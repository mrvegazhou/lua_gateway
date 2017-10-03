local BasePlugin = require "agw.plugins.base"
local policies = require "agw.plugins.limiting_rate.policies"
local utils_condition = require "agw.utils.condition"
local timestamp = require "agw.lib.timestamp"
local cjson = require "cjson"
local agw_config = ngx.shared.agw_config
local redis_store = require("agw.store.redis_store")(cjson.decode(agw_config:get("agw_config")))
local model = require("agw.plugins.limiting_rate.models")

local printable = require "agw.utils.printable"

local ngx_log = ngx.log
local pairs = pairs
local tostring = tostring
local tonumber = tonumber
local ngx_timer_at = ngx.timer.at

local RATELIMIT_LIMIT = "X-RateLimit-Limit"
local RATELIMIT_REMAINING = "X-RateLimit-Remaining"

local LimitingRateHandler = BasePlugin:extend()
LimitingRateHandler.PRIORITY = 1003

local function get_limit_type(period)
    if not period then return nil end
    if period == 1 then
        return "Second"
    elseif period == 60 then
        return "Minute"
    elseif period == 3600 then
        return "Hour"
    elseif period == 86400 then
        return "Day"
    else
        return nil
    end
end

local function get_limit_types()
	return {'consumer', 'credential', 'ip', 'url', 'query', 'header', 'useragent', 'method', 'referer', 'host'}
end

local function get_usage(limit_type, identifier, period, period_count)
	local usage
  	local stop
	if limit_type then
		local current_usage, err = policies["redis"].usage(identifier, get_limit_type(period))
		if err then
	      return nil, nil, err
	    end
	    local remaining = period_count - current_usage
	    if remaining<=0 then
	    	stop = true
	    end
	    return remaining, stop
	end
	return nil, nil
end

local function judge_identifier(store)
	-- 判断各种限速类型
	local identifier
	local identifier_value
	local types = get_limit_types()
	for i=1, #(types) do
		if types[i]=='consumer' then
			identifier = ngx.ctx.authenticated_consumer and ngx.ctx.authenticated_consumer.id
		elseif types[i]=='credential' then
			identifier = ngx.ctx.authenticated_credential and ngx.ctx.authenticated_credential.id
		else
			identifier = utils_condition:judge_type(types[i])
		end
		if identifier then
			identifier_value = redis_store:get_json(redis_store:get_limiting_rate_condition_value(i, identifier))
			if identifier_value then
				local operator = identifier_value['condition']
				local expected = identifier_value['condition_value']
				local period = tonumber(identifier_value['period'])
				local period_count = identifier_value['period_count']
				-- 获取rule_id判断规则配置是否开启限速 and 判断配置是否为全局
				local rule_id = identifier_value['rule_id']
				local rule_info = model:get_limiting_rate_config_by_id(store, rule_id)
				if rule_info then
					local rule_info_value = cjson.decode(rule_info['value'])
					if rule_info_value['enable']==true and rule_info_value.handle.global_limit==false then
						local pass = utils_condition:judge_condition(identifier, operator, expected)
						if pass then
							-- 判断频率是否超出
							local limit_type = get_limit_type(period)
							local remaining, stop, err = get_usage(limit_type, identifier, period, period_count)
							ngx.header["X-RateLimit-Limit" .. "-" ..limit_type ] = period_count
							if stop then
								if rule_info_value.handle.log==true then
	                            	ngx.log(ngx.INFO, "[RateLimiting-Forbidden-Rule] ", " uri:", ngx_var_uri, " limit:", period_count, " remaining:", remaining)
	                           	end
	                           	ngx.header["X-RateLimit-Remaining" .. "-" .. limit_type] = 0
	                           	ngx.exit(429)
	                           	return true
	                        else
	                        	ngx.header["X-RateLimit-Remaining" .. "-" .. limit_type] = remaining - 1
	                        	policies["redis"].increment(identifier, limit_type, 1)
							end
						end
					end
				end
			end
		end
	end
	return false
end

function LimitingRateHandler:new(store)
	LimitingRateHandler.super.new(self, "limiting_rate")
	self.store = store
end

function LimitingRateHandler:access(conf)
	LimitingRateHandler.super.access(self)
	local stop = judge_identifier(self.store)
	--ngx.log(ngx.ERR, '\n\n\n===stop======='..printable.print_r(stop)..'============\n\n\n')
	if stop then -- 不再执行此插件其他逻辑
        return
    end
end

return LimitingRateHandler