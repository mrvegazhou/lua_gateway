local cjson  = require "cjson.safe"
local BasePlugin = require "agw.plugins.base"
local upstreams_api = require "agw.plugins.balancer.upstreams.api"
local lib_consul = require "agw.store.consul"
local balancer_load = require "agw.plugins.balancer.load"
local error    = error
local state      = ngx.shared.state
local printable    = require "agw.utils.printable"

local BalancerHandler = BasePlugin:extend()
BalancerHandler.PRIORITY = 99999

function BalancerHandler:new(store)
  BalancerHandler.super.new(self, "balancer")
  self.balancer_config = {}
  self.store = store
end

function BalancerHandler:init(config)
	if not config or type(config)~="table" then
		ngx.log(ngx.ERR, "Load balancer plugin configuration data error", nil)
		error("Load balancer plugin configuration data error")
	end
	local balancer_config = {upstreams=config.upstreams, consul=config.consul}
	balancer_config.exit = function(err)
		--用此变量标识response headers是否已发送
		if ngx.headers_sent then
	        return ngx.exit(ngx.status)
	    end
	    local status, discard_body_err = pcall(ngx.req.discard_body)
	    if not status then
	        ngx.log(ngx.ERR, "discard_body err:", discard_body_err)
	    end

	    local code = err.code
	    if ngx.var.x_error_code then
	        ngx.var.x_error_code = code
	    end

	    -- standard http code, exit as usual
	    if code >= 200 and code < 1000 then
	        return ngx.exit(code)
	    end

	    local httpcode = err.httpcode
	    ngx.status = httpcode

	    local req_headers = ngx.req.get_headers()
	    ngx.header["X-Error-Code"] = code
    	ngx.header["Content-Type"] = "application/json"
    	
    	local body = cjson.encode({
	        code = code,
	        msg = err.msg,
	    })
    	ngx.header["Content-Length"] = #body

    	ngx.print(body)
    	return ngx.exit(httpcode)
	end

	--local is_need_consul = balancer_config.upstreams.is_need_consul
	-- 从consul里拉取upstreams列表
	local ok, init_ok = pcall(lib_consul.init, balancer_config)
	--local ok = lib_consul.init(balancer_config)
	if not ok then
        error("Init config failed, " .. init_ok .. ", aborting !")
    end

	-- setmetatable(balancer_config, {
	--     __index = lib_consul.load_config,
	-- })
	self.balancer_config = balancer_config
end

function BalancerHandler:init_worker(conf)
  BalancerHandler.super.init_worker(self)
  upstreams_api.prepare_upstreams(self.balancer_config)
  -- 心跳检测反向代理服务器
  upstreams_api.create_upstreams()
  -- balancer_load.create_load_syncer()
  upstreams_api.get_new_upstreams_from_consul(self.balancer_config)
end

return BalancerHandler


--[[
	nginx缓存有几个地方：
		状态信息的key规则是： str_format("%s:%d", srv.host, srv.port)
		保存负载信息的skeys： base.SKEYS_KEY 存储dyconfig _gen_shd_key方法格式化后的skey
		保存负载节点的： _gen_shd_key(skey)

		锁信息：

--]]