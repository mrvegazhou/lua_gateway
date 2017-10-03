local cjson = require "cjson.safe"
local str_format = string.format

local consistent_hash = require "agw.plugins.balancer.upstreams.consistent_hash"
local round_robin= require "agw.plugins.balancer.upstreams.round_robin"
local heartbeat  = require "agw.plugins.balancer.upstreams.heartbeat"
local dyconfig   = require "agw.plugins.balancer.upstreams.dyconfig"
local base       = require "agw.plugins.balancer.upstreams.base"
local utils    = require "agw.utils.utils"
local lib_consul    = require "agw.store.consul"
local printable    = require "agw.utils.printable"
local host_name = require "agw.lib.get_host_name"

local localtime  = ngx.localtime
local mutex      = ngx.shared.mutex
local shd_config = ngx.shared.config
local state      = ngx.shared.state
local log        = ngx.log
local now        = ngx.now
local ERR        = ngx.ERR
local WARN       = ngx.WARN
local INFO       = ngx.INFO
local worker_id  = ngx.worker.id
local get_phase  = ngx.get_phase
local tab_insert = table.insert

local _M = {
    STATUS_OK = base.STATUS_OK, STATUS_UNSTABLE = base.STATUS_UNSTABLE, STATUS_ERR = base.STATUS_ERR
}

_M.reset_round_robin_state = round_robin.reset_round_robin_state
_M.try_cluster_round_robin = round_robin.try_cluster_round_robin

function _M.prepare_upstreams(conf)
	local config = {upstreams=conf.upstreams, consul=conf.consul}

	base.upstream.start_time = localtime()
    base.upstream.conf_hash = config.upstreams.conf_hash
    base.upstream.checkup_timer_interval = config.upstreams.checkup_timer_interval or 5
    base.upstream.checkup_timer_overtime = config.upstreams.checkup_timer_overtime or 60
    base.upstream.checkups = {}
    base.upstream.ups_status_sync_enable = config.upstreams.ups_status_sync_enable
    base.upstream.ups_status_timer_interval = config.upstreams.ups_status_timer_interval or 5
    --base.upstream.checkup_shd_sync_enable = config.upstreams.checkup_shd_sync_enable
    base.upstream.shd_config_timer_interval = config.upstreams.shd_config_timer_interval or base.upstream.checkup_timer_interval
    base.upstream.default_heartbeat_enable = config.upstreams.default_heartbeat_enable
    local skeys = {}
    local phase = get_phase()

    for skey, ups in pairs(conf) do
        -- consul的配置信息
    	if type(ups)=="table" and type(ups.cluster)=="table" then
    		base.upstream.checkups[skey] = utils.table_dup(ups)
    		--解析配置文件中的consul项 skey=consul
    		for level, cls in pairs(base.upstream.checkups[skey].cluster) do
                -- 获取配置文件中的负载服务器列表 并缓存到cls.servers和peer_id_dict表里
                -- 刚开始加载的时候为空
    			base.extract_servers_from_upstream(skey, cls)
                -- 通过rr算法获取gcd max_weight weight_sum等参数
    			_M.reset_round_robin_state(cls)
    		end

    		if shd_config and worker_id then
                if phase == "init" or phase == "init_worker" and worker_id() == 0 then
                    -- consul信息也会保存在shd_config
                    local key = dyconfig._gen_shd_key(skey)
                    shd_config:set(key, cjson.encode(base.upstream.checkups[skey].cluster))
                end
                skeys[skey] = 1
            else
                log(ERR, "no shd_config nor worker_id found.")
            end 
    	end
    end
    if shd_config and worker_id then

        -- 如果在init_worker阶段并且worker=0 执行更新shm操作
        if phase == "init" or phase == "init_worker" and worker_id() == 0 then
            shd_config:set(base.SHD_CONFIG_VERSION_KEY, 0)
            shd_config:set(base.SKEYS_KEY, cjson.encode(skeys))
        end
        base.upstream.shd_config_version = 0
    end
    base.upstream.initialized = true
end

function _M.create_upstreams()
    if not base.upstream.initialized then
        log(ERR, "create checker failed, call prepare_checker in init_by_lua")
        return
    end
    -- 同步负载均衡的配置文件到共享内存
    if base.upstream.shd_config_version then
        dyconfig.create_shd_config_syncer()
    end

    local ckey = base.CHECKUP_TIMER_KEY
    local val, err = mutex:get(ckey)
    if val then
        return
    end
    if err then
        log(WARN, "failed to get key from shm: ", err)
        return
    end

    -- 在init_worker阶段加锁 timeout nil默认是5秒 0是立即返回结果 
    local lock_timeout = get_phase() == "init_worker" and 0 or nil
    local lock = base.get_lock(ckey, lock_timeout)  
    if not lock then
        log(WARN, "failed to acquire the lock: ", err)
        return
    end

    -- 防止回调递归
    val, err = mutex:get(ckey)
    if val then
        base.release_lock(lock)
        return
    end

    -- 激活checkup定时器
    local ok, err = ngx.timer.at(0, heartbeat.active_checkup)
    if not ok then
        log(WARN, "failed to create timer: ", err)
        base.release_lock(lock)
        return
    end

    local overtime = base.upstream.checkup_timer_overtime
    local ok, err = mutex:set(ckey, 1, overtime)
    if not ok then
        log(WARN, "failed to update shm: ", err)
    end
    base.release_lock(lock)
end

-- 从consul更新nginx的反向负载均衡
function _M.get_new_upstreams_from_consul(config)
    if not base.upstream.initialized then
        log(ERR, "create checker failed, call prepare_checker in init_by_lua")
        return
    end
    -- 获取shm.state和consul的state对比
    if get_phase()=="init_worker" and worker_id()==0 then
        local ok, err = ngx.timer.at(0, _M.check_consul_upstreams, config)
        if not ok then
            log(WARN, "failed to create timer: ", err)
            return
        end
    end
end

function _M.check_consul_upstreams(premature, config)
    local lock

    -- 从consul获取已经更新过的host
    local updated_upstreams = lib_consul.get_updated_upstreams(config, host_name)
    if #updated_upstreams>0 then
        local has_updated_upstreams = {}

        lock, err = base.get_lock(base.UPDATED_CONSUL)
        state:set(base.CHECKUP_LAST_CHECK_TIME_KEY, localtime())

        for k, v in ipairs(updated_upstreams) do
            local flag, result = lib_consul.get_servers_by_key(config, v)
            -- 当servers不存在的时候删除nginx的负载均衡
            if not result['servers'] or #result['servers']==0 then
                _M.delete_upstream(v)
            else
                if result['servers'] then
                    local ok, err = _M.update_upstream(v, {{servers = result['servers']}})
                    if ok then
                        tab_insert(has_updated_upstreams, v)
                    end
                end
            end
            if not ok then
                -- 这里可以发送日志
            end
        end

        -- 如果更新成功删除config/balancer/updated_upstreams
        if #has_updated_upstreams>0 then
            for k, v in pairs(updated_upstreams) do
                for k1, v1 in pairs(has_updated_upstreams) do
                    if v==v1 then
                        -- 删除
                        table.remove(updated_upstreams, k)
                    end
                end
            end
            lib_consul.put_server_by_key(config, "updated_upstreams/"..host_name, #updated_upstreams==0 and '' or cjson.encode(updated_upstreams))
        end
        base.release_lock(lock)
    end

    local interval = base.upstream.checkup_timer_interval

    local ok, err = ngx.timer.at(interval, _M.check_consul_upstreams, config)
    if not ok then
        log(WARN, "failed to create timer: ", err)
        local ok, err = mutex:set(ckey, nil)
        base.release_lock(lock)
        if not ok then
            log(WARN, "failed to update shm: ", err)
        end
        return
    end
end

function _M.get_status()
    local all_status = {}
    for skey in pairs(base.upstream.checkups) do
        all_status["upstream-balancer:" .. skey] = base.get_upstream_status(skey)
    end

end

-- 动态设置负载url
function _M.update_upstream(skey, upstream)
	if not upstream or not next(upstream) then
        return false, "can not set empty upstream"
    end
    local ok, err
    for level, cls in pairs(upstream) do
    	if not cls or not next(cls) then
            return false, "can not update empty level"
        end

        local servers = cls.servers
        if not servers or not next(servers) then
            return false, "can not update empty servers"
        end

        for _, srv in ipairs(servers) do
        	-- 检测负载配置信息的参数是否正确
            ok, err = dyconfig.check_update_server_args(skey, level, srv)
            if not ok then
                return false, err
            end
        end
    end

    local lock
    lock, err = base.get_lock(base.SKEYS_KEY)
    if not lock then
        log(WARN, "failed to acquire the lock: ", err)
        return false, err
    end
    -- 把配置信息保存到共享内存中ngx.shared.config
    ok, err = dyconfig.do_update_upstream(skey, upstream)
    
    base.release_lock(lock)

    return ok, err
end

function _M.delete_upstream()
	local lock, ok, err
	lock, err = base.get_lock(base.SKEYS_KEY)
	if not lock then
        log(WARN, "failed to acquire the lock: ", err)
        return false, err
    end
    ok, err = dyconfig.do_delete_upstream(skey)
    base.release_lock(lock)
	return ok, err
end

local function try_cluster(skey, ups, cls, callback, opts, try_again)
    local mode = ups.mode
    local args = opts.args or {}
    -- 暂时rr算法
    return round_robin.try_cluster_round_robin_(skey, ups, cls, callback, args, try_again)
end

function _M.ready_ok(skey, callback, opts)
	opts = opts or {}
	local ups = base.upstream.checkups[skey]

	if not ups then
        return nil, "unknown skey " .. skey
    end

	local res, err, cont, try_again

    for level, cls in ipairs(ups.cluster) do
        res, cont, err = try_cluster(skey, ups, cls, callback, opts, try_again)
        if res then
            return res, err
        end
        -- 如果有try次数，继续下一次尝试
        if not cont then 
            break 
        end

        if type(cont) == "number" then
            if cont < 1 then
                break
            else
                try_again = cont
            end
        end
    end

    return nil, err or "no upstream available"
end

-- 当节点失败时修改次节点的状态
function _M.feedback_status(skey, host, port, failed)
    local ups = base.upstream.checkups[skey]

    if not ups then
        return nil, "unknown skey " .. skey
    end

    local srv
    for level, cls in pairs(ups.cluster) do
        for _, s in ipairs(cls.servers) do
            if s.host == host and s.port == port then
                srv = s
                break
            end
        end
    end

    if not srv then
        return nil, "unknown host:port" .. host .. ":" .. port
    end
    -- 修改失败节点状态
    base.set_srv_status(skey, srv, failed)
    return 1
end

-- 选取正常的节点进行负载
function _M.select_peer(skey)
    return _M.ready_ok(skey, function(host, port)
        return { host=host, port=port }
    end)
end

return _M 