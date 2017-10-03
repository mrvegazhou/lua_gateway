local sleep = ngx.sleep
local log = ngx.log
local ERR = ngx.ERR
local math = require "math"
local setmetatable = setmetatable
local tonumber = tonumber
local error = error
local socket = require "socket"

local min = math.min
local ipairs = ipairs
local table_insert = table.insert
local utils = require "agw.utils.utils"
local redis = require("resty.redis")

local Object = require "agw.lib.classic"
local redlock = Object:extend()

local clock_drift_factor = 0.01
local instances = {}

function redlock:new(servers, retry_delay, retry_count)
	self.servers = servers
    self.retry_delay = retry_delay or 200
    self.retry_count = retry_count or 3
    self.quorum = min(#servers, ((#servers)/2+1))
    self.instances = instances
end

function redlock:initInstances()
	if #self.instances==0 then
		for i, v in ipairs(self.servers) do
			local red = redis:new()
			red:set_timeout(v.timeout)
			local ok, err = red:connect(v.host, v.port)
			if ok then
				table_insert(self.instances, red)
			end
		end
	end
end

function redlock:lock(resource, ttl)
	self:initInstances()
	token = utils.random_string()
	retry = self.retry_count
	repeat
		local n = 0
		local start_time = socket.gettime()*1000
		for i, instance in ipairs(self.instances) do
			if self:lockInstance(instance, resource, token, ttl) then
				n = n+1
			end
		end
		--偏移时间
		local drift = (ttl * clock_drift_factor) + 2
		--锁对象的有效时间=锁自动释放时间-(当前时间-开始时间)-偏移时间
		local validity_time = ttl - (socket.gettime() * 1000 - start_time) - drift
		if n>=self.quorum and validity_time>0 then
			return {validity=validity_time, resource=resource, token=token}
		else
			for i_tmp, instance_tmp in ipairs(self.instances) do
				self:unlockInstance(instance, resource, token)
			end
		end
		local delay = math.random(math.floor(self.retry_delay/2), self.retry_delay)
		log(ERR, "------------WAITING FOR LOCK---------")
		sleep(delay/1000)
		retry = retry - 1
	until(retry<=0)
	return false
end

function redlock:unlock(lock)
	self:initInstances()
	local resource = lock['resource']
	local token = lock['token']
	for i, instance in ipairs(self.instances) do
		self:unlockInstance(instance, resource, token)
	end
end

function redlock:lockInstance(instance, resource, token, ttl)
	return instance:set(resource, token, 'PX', ttl, 'NX');
end

function redlock:unlockInstance(instance, resource, token)
	script = [[
		if redis.call("GET", KEYS[1]) == ARGV[1] then
            return redis.call("DEL", KEYS[1])
        else
            return 0
        end
	]]
	local ans, err = instance:eval(script, 1, resource, token)
	if not ans then
        return nil, err
    end
    return ans
end

return redlock