local cjson     = require "cjson.safe"
local cmsgpack  = require "cmsgpack"
local http      = require "resty.http"
local http_sock = require "socket.http"
local ltn12     = require "ltn12"
local httpipe   = require "agw.lib.httpipe"
local shcache   = require "agw.lib.shcache"
local printable = require "agw.utils.printable"

local tab_insert = table.insert
local tab_concat = table.concat
local str_format = string.format
local str_sub    = string.sub

local _M = {}

local function parse_body(body)
    local data = cjson.decode(body)
    if not data then
        ngx.log(ngx.ERR, "json decode body failed, ", body)
        return
    end
    return data
end

local function connect_by_conf(conf)
    if not conf.host or not conf.port then
        return nil, nil
    end
    local httpc = http.new()

    if conf.connect_timeout then
        httpc:set_timeout(connect_timeout)
    end

    local ok, err = httpc:connect(conf.host, conf.port)
    if not ok then
        return nil, err
    end
    return httpc
end

local function build_uri(key, opts)
    local uri = "/v1"..key
    if opts then
        if opts.wait then
            opts.wait = opts.wait.."s"
        end
        local params = ngx.encode_args(opts)
        if #params > 0 then
            uri = uri.."?"..params
        end
    end
    return uri
end

-- 创建一个value为空的key
function _M.create_server_key(config, key)
    if not key then
        return false
    end
    local consul = config.consul or {}
    local key_prefix = consul.config_key_prefix or ""
    local consul_cluster = consul.cluster or {}
    for _, cls in pairs(consul_cluster) do
        for _, srv in pairs(cls.servers) do
            local url = str_format("http://%s:%s/v1/kv/%s", srv.host, srv.port, key_prefix..key)
            local httpc = http.new()
            local res, err = httpc:request_uri(url, {method = "PUT", body=""})
            if 200~=res.status then
                return nil, err
            else
                return res['body'], err
            end
        end
    end
    return true
end

local function get_http_request(url, cluster)
    local res_code, res_body
    if ngx.get_phase()=='init' then
        local status, code = http_sock.request(url)
        res_code = code
        res_body = status
    else
        local httpc = http.new()
        local res, err = httpc:request_uri(url, {method = "GET"})
        res_code = res.status
        res_body = res.body
    end
    if res_code==200 then
        return res_body, 200
    else
        return false, false
    end
end

local function get_servers(cluster, key)
    -- try all the consul servers
    for _, cls in pairs(cluster) do
        for _, srv in pairs(cls.servers) do
            local url = str_format("http://%s:%s/v1/kv/%s", srv.host, srv.port, key)
            local res_body, code = get_http_request(url, cluster)
            if not res_body or #res_body==0 then
                return {}
            else
                return parse_body(res_body)
            end
        end
    end
end

-- 获取consul的更新状态, init_work阶段执行resty http
function _M.get_updated_upstreams(config, hostname)
    if not config.consul then
        return false
    end
    local consul = config.consul
    local key_prefix = consul.config_key_prefix or ""
    for _, cls in pairs(consul.cluster) do
        for _, srv in pairs(cls.servers) do
            local url = str_format("http://%s:%s/v1/kv/%s", srv.host, srv.port, key_prefix.."updated_upstreams/"..hostname.."?raw")
            local res_body = get_http_request(url)
            if not res_body or #res_body==0 then
                return {}
            else
                return parse_body(res_body)
            end
        end
    end
end

-- function _M.get_script_blocking(cluster, key, need_raw)
--     -- try all the consul servers
--     for _, cls in pairs(cluster) do
--         for _, srv in pairs(cls.servers) do
--             local httpc = http.new()
--             local url = str_format("http://%s:%s/v1/kv/%s", srv.host, srv.port, key)
--             local res, err = httpc:request_uri(url, {method='GET'})
--             if res.status == 404 then
--                 return nil
--             elseif res.status == 200 and res.body then
--                 if need_raw then
--                     return body
--                 else
--                     return parse_body(res.body)
--                 end
--             else
--                 ngx.log(ngx.ERR, str_format("get config from %s failed", url))
--             end
--         end
--     end
-- end

local function check_servers(servers)
    if not servers or type(servers) ~= "table" or not next(servers) then
        return false
    end
    for _, srv in pairs(servers) do
        if not srv.host or not srv.port then
            return false
        end

        if srv.weight and type(srv.weight) ~= "number" or
            srv.max_fails and type(srv.max_fails) ~= "number" or
            srv.fail_timeout and type(srv.fail_timeout) ~= "number" then
            return false
        end
    end

    return true
end

function _M.have_consuls(config)
    local consul = config.consul or {}
    local key_prefix = consul.config_key_prefix or ""
    local consul_cluster = consul.cluster or {}
    return key_prefix, consul_cluster
end

-- 获取name为key的值然后返回是否存在和name的值
function _M.get_servers_by_key(config, name, prefix_name)
    local key_prefix, consul_cluster = _M.have_consuls(config)
    if not prefix_name then
        prefix_name = "upstreams"
    end
    local upstream_keys = get_servers(consul_cluster, key_prefix .. prefix_name .. "?keys")
    if not upstream_keys then
        return false, false
    end
    local flag = false
    local result = {}
    name = key_prefix..prefix_name.."/"..name
    for _, key in pairs(upstream_keys) do
        if key~=name then
            flag = false
        else
            result = get_servers(consul_cluster, key.."?raw")
            flag = true
        end
    end
    return flag, result
end

function _M.get_upstream_keys(config, name)
    local key_prefix, consul_cluster = _M.have_consuls(config)
    if not name then
        name = 'upstreams'
    end 
    return get_servers(consul_cluster, key_prefix .. name .. "?keys") 
end

-- 通过name删除key
function _M.del_servers_by_key(config, name, prefix_name)
    if not name then
        return false, 'name is null'
    end
    if not prefix_name then
        prefix_name = "upstreams/"
    end
    local key_prefix, consul_cluster = _M.have_consuls(config)
    for _, cls in pairs(consul_cluster) do
        for _, srv in pairs(cls.servers) do
            local url = str_format("http://%s:%s/v1/kv/%s?recurse", srv.host, srv.port, key_prefix..prefix_name..name.."?raw")
            local httpc = http.new()
            local res, err = httpc:request_uri(url, {method = "DELETE"})
            if not res then
                return false, err
            end
        end
    end
    return true
end

-- 获取consul的catalog services
function _M.get_consul_catalog_services(config, key)
    if not config then
        return false
    end
    local _, consul_cluster = _M.have_consuls(config)

    for _, cls in pairs(consul_cluster) do
        for _, srv in pairs(cls.servers) do
            local url
            if not key then
                url = str_format("http://%s:%s/v1/catalog/services", srv.host, srv.port)
            else
                url = str_format("http://%s:%s/v1/catalog/service/%s", srv.host, srv.port, key)
            end
            local httpc = http.new()
            local res, err = httpc:request_uri(url, {method = "GET"})
            if 200~=res.status then
                return nil, err
            else
                return parse_body(res.body), err
            end
        end
    end
end

-- 不管cosnul是否存在key的值都去替换
function _M.put_server_by_key(config, name, value)
    if not value then
        return false
    end
    local body_in
    if type(value) == "table" or type(value) == "boolean" then
        body_in = cjson.encode(value)
    else
        body_in = value
    end

    local consul = config.consul or {}
    local key_prefix = consul.config_key_prefix or ""
    local consul_cluster = consul.cluster or {}
    for _, cls in pairs(consul_cluster) do
        for _, srv in pairs(cls.servers) do
            -- 不同的服务器进行连接
            -- 判断不同阶段请求
            local url = str_format("http://%s:%s/v1/kv/%s", srv.host, srv.port, key_prefix..name)
            local res
            if ngx.get_phase()=='init' then
                local reqbody = body_in
                local respbody = {} 
                res, code, response_headers = http_sock.request{
                                                                        url = url,
                                                                        method = "PUT",
                                                                        headers = {["Content-Type"] = "application/json"},
                                                                        source = ltn12.source.string(reqbody),
                                                                        sink = ltn12.sink.table(respbody),
                                                                      }
            else
                local httpc = http.new()
                res, err = httpc:request_uri(url, {method = "PUT", body = body_in})
            end

            if "true"==res['body'] then
                return res, nil
            else
                return nil, err
            end
        end
    end
    return true, nil
end
--[[
consul的存储格式：
{"enable": true, "servers": [{"host": "127.0.0.1","port": 8001,"weight": 1,"max_fails": 6,"fail_timeout": 30}], "keepalive": 10, "try": 2}
--]]
function _M.init(config)
    local consul = config.consul or {}
    local key_prefix = consul.config_key_prefix or ""
    local consul_cluster = consul.cluster or {}

    local upstream_keys = get_servers(consul_cluster, key_prefix .. "upstreams?keys")
    if not upstream_keys then
        return false
    end

    for _, key in ipairs(upstream_keys) do repeat
        local skey = str_sub(key, #key_prefix + 11)
        if #skey == 0 then
            break
        end
        -- upstream already exists in agw.conf
        if config[skey] then
            break
        end

        local servers = get_servers(consul_cluster, key .. "?raw")
        
        if not servers or not next(servers) then
            return false
        end

        if not check_servers(servers["servers"]) then
            return false
        end

        local cls = {
            servers = servers["servers"],
            keepalive = tonumber(servers["keepalive"]),
            try =  tonumber(servers["try"]),
        }

        config[skey] = {
            cluster = { cls },
        }

        -- fit agw.conf format
        for k, v in pairs(servers) do
            -- copy other values
            if k ~= "servers" and k ~= "keepalive" and k ~= "try" then
                config[skey][k] = v
            end
        end

    until true end

    return true
end

local function get_value(cluster, key, http_callback)
    local hp, err = httpipe:new()
    if not hp then
        ngx.log(ngx.ERR, "failed to new httpipe: ", err)
        return
    end

    hp:set_timeout(5 * 1000)
    local req = {
        method = "GET",
        path = "/v1/kv/" .. key,
    }

    local callback = function(host, port)
        return hp:request(host, port, req)
    end

    if type(http_callback)~='function' then
    	return 
    end

    local res, err = http_callback("consul", callback)

    if not res or res.status ~= 200 then
        ngx.log(ngx.ERR, "failed to get config from consul: ", err or res.status)
        hp:close()
        return
    end
    hp:set_keepalive()

    return parse_body(res.body)
end

function _M.load_config(config, key)
    local consul = config.consul or {}
    local cache_label = "consul_config"

    local _load_config = function()
        local consul_cluster = consul.cluster or {}
        local key_prefix = consul.config_key_prefix or ""
        local key = key_prefix .. key .. "?raw"

        ngx.log(ngx.INFO, "get config from consul, key: " .. key)
 
        return  get_value(consul_cluster, key)
    end

    if consul.config_cache_enable == false then
        return _load_config()
    end

    local config_cache = shcache:new(
        ngx.shared.cache,
        { 
            external_lookup = _load_config,
            encode = cmsgpack.pack,
            decode = cmsgpack.unpack,
        },
        { 
            positive_ttl = consul.config_positive_ttl or 30,
            negative_ttl = consul.config_negative_ttl or 3,
            name = cache_label,
        }
    )

    local data, _ = config_cache:load(cache_label .. ":" .. key)

    return data
end

local DEFAULT_HOST    = "127.0.0.1"
local DEFAULT_PORT    = 8500
local DEFAULT_TIMEOUT = 60*1000

function _M.new(_, opts)
    local self = {
        host            = opts.host            or DEFAULT_HOST,
        port            = opts.port            or DEFAULT_PORT,
        connect_timeout = opts.connect_timeout or DEFAULT_TIMEOUT,
        read_timeout    = opts.read_timeout    or DEFAULT_TIMEOUT
    }
    return setmetatable(self, mt)
end

local function connect(self)
    local httpc = http.new()

    local connect_timeout = self.connect_timeout
    if connect_timeout then
        httpc:set_timeout(connect_timeout)
    end

    local ok, err = httpc:connect(self.host, self.port)
    if not ok then
        return nil, err
    end
    return httpc
end

local function _get(httpc, key, opts)
    local uri = build_uri(key, opts)
    local res, err = httpc:request({path = uri})
    if not res then
        return nil, err
    end
    local status = res.status
    if not status then
        return nil, "No status from consul"
    elseif status~=200 then
        if status == 404 then
            return nil, "Key not found"
        else
            return nil, "Consul returned: HTTP "..status
        end
    end

    local body, err = res:read_body()
    if not body then
        return nil, err
    end

    local headers = res.headers
    local response = {}
    if headers.content_type == 'application/json' then
        response = cjson.decode(body)
    end

    return response, headers["X-Consul-Lastcontact"], headers["X-Consul-Knownleader"], headers["X-Consul-Index"]
end

function _M.get(self, key, opts)
    local httpc, err = connect(self)
    if not httpc then
        return nil, err
    end

    if opts and (opts.wait or opts.index) then
        -- Blocking request, increase timeout
        local timeout = 10 * 60 * 1000 -- Default timeout is 10m
        if opts.wait then
            timeout = opts.wait * 1000
        end
        httpc:set_timeout(timeout)
    else
        httpc:set_timeout(self.read_timeout)
    end

    local res, lastcontact_or_err, knownleader, consul_index = _get(httpc, key, opts)
    httpc:set_keepalive()
    if not res then
        return nil, lastcontact_or_err
    end
    return res, {lastcontact_or_err or false, knownleader or false, consul_index or false}
end

function _M.put(self, key, value, opts)
    if not opts then
        opts = {}
    end

    local httpc, err = connect(self)
    if not httpc then
        return nil, err
    end

    local uri = build_uri(key, opts)

    local body_in
    if type(value) == "table" or type(value) == "boolean" then
        body_in = cjson.encode(value)
    else
        body_in = value
    end

    local res, err = httpc:request({
        method = "PUT",
        path = uri,
        body = body_in
    })
    if not res then
        return nil, err
    end

    if not res.status then
        return nil, "No status from consul"
    end

    local body, err = res:read_body()
    if not body then
        return nil, err
    end

    httpc:set_keepalive()

    if res.status ~= 200 then
        return nil, err
    elseif body and #body > 0 then
        local ok, json = pcall(cjson.decode, body)
        if ok then
            return json
        else
            ngx.log(ngx.ERR, json)
        end
    else
        return true
    end
end

function _M.get_servers_url(self, cluster, key)
    local servers = {}
    if not cluster then
        tab_insert(servers, { servers={host=self.host, port=self.port} })
    else
        servers = cluster
    end
    return get_servers(cluster, key)
end

return _M