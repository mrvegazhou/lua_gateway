local cjson         = require "cjson.safe"
local lock          = require "resty.lock"
local printable     = require "agw.utils.printable"

local str_format    = string.format
local str_sub       = string.sub
local lower         = string.lower
local byte          = string.byte
local floor         = math.floor
local sqrt          = math.sqrt
local tab_sort      = table.sort
local tab_concat    = table.concat
local tab_insert    = table.insert
local unpack        = unpack

local log           = ngx.log
local ERR           = ngx.ERR
local WARN          = ngx.WARN
local tcp           = ngx.socket.tcp
local localtime     = ngx.localtime
local re_find       = ngx.re.find
local re_match      = ngx.re.match
local re_gmatch     = ngx.re.gmatch
local mutex         = ngx.shared.mutex
local state         = ngx.shared.state
local shd_config    = ngx.shared.config
local now           = ngx.now

local _M = {
    STATUS_OK = 0, STATUS_UNSTABLE = 1, STATUS_ERR = 2
}

local ngx_upstream

local CHECKUP_TIMER_KEY = "checkups:timer:" .. math.floor(ngx.now())
_M.CHECKUP_TIMER_KEY = CHECKUP_TIMER_KEY
local CHECKUP_LAST_CHECK_TIME_KEY = "checkups:last_check_time"
_M.CHECKUP_LAST_CHECK_TIME_KEY = CHECKUP_LAST_CHECK_TIME_KEY
local CHECKUP_TIMER_ALIVE_KEY = "checkups:timer_alive"
_M.CHECKUP_TIMER_ALIVE_KEY = CHECKUP_TIMER_ALIVE_KEY
local PEER_STATUS_PREFIX = "checkups:peer_status:"
_M.PEER_STATUS_PREFIX = PEER_STATUS_PREFIX
local SHD_CONFIG_VERSION_KEY = "config_version"
_M.SHD_CONFIG_VERSION_KEY = SHD_CONFIG_VERSION_KEY
local SKEYS_KEY = "checkups:skeys"
_M.SKEYS_KEY = SKEYS_KEY
local SHD_CONFIG_PREFIX = "shd_config"
_M.SHD_CONFIG_PREFIX = SHD_CONFIG_PREFIX

local UPDATED_CONSUL = "updated:consul:"..ngx.now()
_M.UPDATED_CONSUL = UPDATED_CONSUL

local upstream = {}
_M.upstream = upstream

local peer_id_dict = {}

local ups_status_timer_created
_M.ups_status_timer_created = ups_status_timer_created

-- 全局状态负载节点信息
local cluster_status = {}
_M.cluster_status = cluster_status


local function _gen_key(skey, srv)
    return str_format("%s:%s:%d", skey, srv.host, srv.port)
end
_M._gen_key = _gen_key

-- 返回服务器host和端口
local function extract_srv_host_port(name)
    local m = re_match(name, [[([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(?::([0-9]+))?]], "jo")
    if not m then
        return
    end
    local host, port = m[1], m[2] or 80
    return host, port
end

function _M.extract_servers_from_upstream(skey, cls)
	local up_key = cls.upstream
    if not up_key then
        return
    end

    cls.servers = cls.servers or {}
    if not ngx_upstream then
    	local ok
    	ok, ngx_upstream = pcall(require, "ngx.upstream")
    	if not ok then
    		log(ERR, "ngx_upstream_lua module required")
            return
    	end
    end
    local ups_backup = cls.upstream_only_backup
    local srvs_getter = ngx_upstream.get_primary_peers
    if ups_backup then
        srvs_getter = ngx_upstream.get_backup_peers
    end
    local srvs, err = srvs_getter(up_key)
    if not srvs and err then
        log(ERR, "failed to get servers in upstream ", err)
        return
    end

    for _, srv in ipairs(srvs) do
    	local host, port = extract_srv_host_port(srv.name)
    	if not host then
            log(ERR, "invalid server name: ", srv.name)
            return
        end
        peer_id_dict[_gen_key(skey, { host = host, port = port })] = {id = srv.id, backup = ups_backup and true or false}
        tab_insert(cls.servers, {host = host, port = port, weight = srv.weight, max_fails = srv.max_fails, fail_timeout = srv.fail_timeout})
    end
end

function _M.get_lock(key, timeout)
    local lock = lock:new("locks", {timeout=timeout})
    local elapsed, err = lock:lock(key)
    if not elapsed then
        log(WARN, "failed to acquire the lock: ", key, ", ", err)
        return nil, err
    end

    return lock
end

function _M.release_lock(lock)
    local ok, err = lock:unlock()
    if not ok then
        log(WARN, "failed to unlock: ", err)
    end
end

function _M.ups_status_checker(premature)
	if premature then
        return
    end
    if not ngx_upstream then
        local ok
        ok, ngx_upstream = pcall(require, "ngx.upstream")
        if not ok then
            log(ERR, "ngx_upstream_lua module required")
            return
        end
    end
    local ups_status = {}
    local names = ngx_upstream.get_upstreams()
    -- get current upstream down status
    for _, name in ipairs(names) do

    	local srvs = ngx_upstream.get_primary_peers(name)
    	for _, srv in ipairs(srvs) do
            ups_status[srv.name] = srv.down and _M.STATUS_ERR or _M.STATUS_OK
        end

        srvs = ngx_upstream.get_backup_peers(name)
        for _, srv in ipairs(srvs) do
            ups_status[srv.name] = srv.down and _M.STATUS_ERR or _M.STATUS_OK
        end

    end

    for skey, ups in pairs(upstream.checkups) do
    	for level, cls in pairs(ups.cluster) do
    		if not cls.upstream then
                break
            end

            for _, srv in pairs(cls.servers) do
            	local peer_key = _gen_key(skey, srv)
                local status_key = PEER_STATUS_PREFIX .. peer_key

                local peer_status, err = state:get(status_key)
                if peer_status then
                	local st = cjson.decode(peer_status)
                	local up_st = ups_status[srv.host .. ':' .. srv.port]
                	local unstable = st.status == _M.STATUS_UNSTABLE
                	if (unstable and up_st == _M.STATUS_ERR) or (not unstable and up_st and st.status ~= up_st) then
                        local up_id = peer_id_dict[peer_key]
                        local down = up_st == _M.STATUS_OK
                        local ok, err = ngx_upstream.set_peer_down(cls.upstream, up_id.backup, up_id.id, down)
                        if not ok then
                        	log(ERR, "failed to set peer down", err)
                        end
                    end
                elseif err then
                	log(WARN, "get peer status error ", status_key, " ", err)
                end
            end
    	end
    end

    local interval = upstream.ups_status_timer_interval
    local ok, err = ngx.timer.at(interval, _M.ups_status_checker)
    if not ok then
        ups_status_timer_created = false
        log(WARN, "failed to create ups_status_checker: ", err)
    end
end

-- 获取节点的状态 并判断失效时间是否大于当前时间
function _M.get_srv_status(skey, srv)
    local server_status = cluster_status[skey]
    if not server_status then
        return _M.STATUS_OK
    end
    local srv_key = str_format("%s:%d", srv.host, srv.port)
    local srv_status = server_status[srv_key]
    local fail_timeout = srv.fail_timeout or 10
    if srv_status and srv_status.lastmodify + fail_timeout > now() then
        return srv_status.status
    end
    return _M.STATUS_OK
end

-- 修改节点状态信息
function _M.set_srv_status(skey, srv, failed)
    local server_status = cluster_status[skey]
    if not server_status then
        server_status = {}
        cluster_status[skey] = server_status
    end

    local max_fails = srv.max_fails or 0
    local fail_timeout = srv.fail_timeout or 10
    if max_fails == 0 then
        return
    end

    local time_now = now()

    local srv_key = str_format("%s:%d", srv.host, srv.port)
    local srv_status = server_status[srv_key]
    -- 第一次设置状态
    if not srv_status then
        srv_status = {
            status = _M.STATUS_OK,
            failed_count = 0,
            lastmodify = time_now
        }
        server_status[srv_key] = srv_status
    -- 失效时间过期后
    elseif srv_status.lastmodify + fail_timeout < time_now then
        srv_status.status = _M.STATUS_OK
        srv_status.failed_count = 0
        srv_status.lastmodify = time_now
    end

    if failed then
        -- 把失败的节点状态修改为ERR
        srv_status.failed_count = srv_status.failed_count + 1

        if srv_status.failed_count >= max_fails then
            local ups = upstream.checkups[skey]
            for level, cls in pairs(ups.cluster) do
                for _, s in ipairs(cls.servers) do
                    local k = str_format("%s:%d", s.host, s.port)
                    local st = server_status[k]
                    if not st or st.status == _M.STATUS_OK and k ~= srv_key then
                        srv_status.status = _M.STATUS_ERR
                        return
                    end
                end
            end
        end
    end
end

function _M.check_res(res, check_opts)
    if res then
        local typ = check_opts.typ

        if typ == "http" and type(res) == "table" and res.status then
            local status = tonumber(res.status)
            local http_opts = check_opts.http_opts
            if http_opts and http_opts.statuses and http_opts.statuses[status]==false then
                return false
            end
        end
        return true
    end

    return false
end

return _M

