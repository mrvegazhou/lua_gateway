local ngx_log = ngx.log
local timestamp = require("agw.lib.timestamp")
local utils = require("agw.utils.utils")
local cjson = require("cjson")
local agw_config = ngx.shared.agw_config
local agw_config_tbl = cjson.decode(agw_config:get("agw_config"))
local redis_store = require("agw.store.redis_store")(agw_config_tbl)

local pairs = pairs
local fmt = string.format
local printable = require "agw.utils.printable"

local get_local_key = function(identifier, period_date)
  return fmt("ratelimit:%s:%s", identifier, period_date)
end

local EXPIRATIONS = {
  Second = 1,
  Minute = 60,
  Hour = 3600,
  Day = 86400
}

return {
	["redis"] = {
		increment = function(identifier, limit_type, value)
			local red, err = redis_store:connect(agw_config_tbl.store_redis.timeout)
			if not red and err then
				ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
        		return
			end

			if agw_config_tbl.store_redis.connect_config.redis_password and agw_config_tbl.store_redis.connect_config.redis_password ~= "" then
		        local ok, err = red:auth(agw_config_tbl.store_redis.connect_config.redis_password)
		        if not ok then
		          ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
		          return
		        end
		    end

			local current_timetable = utils.current_timetable()
			local time_key = current_timetable[limit_type]
			local cache_key = get_local_key(identifier, time_key)

			local exists, err = red:exists(cache_key)
			if err then
	          ngx_log(ngx.ERR, "failed to query Redis: ", err)
	          return
	        end
	        -- 参数n 近似的指定添加到命令队列中的数量，这个参数可以少许提高性能
	        red:init_pipeline((not exists or exists == 0) and 2 or 1)
	        red:incrby(cache_key, value)
	        if not exists or exists == 0 then
	          red:expire(cache_key, EXPIRATIONS[limit_type])
	        end
	        local _, err = red:commit_pipeline()
	        if err then
	          ngx_log(ngx.ERR, "failed to commit pipeline in Redis: ", err)
	          return
	        end

			local ok, err = red:set_keepalive(10000, 100)
		    if not ok then
		    	ngx_log(ngx.ERR, "failed to set Redis keepalive: ", err)
		    	return
		    end
		end,
		usage = function(identifier, limit_type)
			local red, err = redis_store:connect(agw_config_tbl.store_redis.timeout)
			if not red then
	        	ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
	        	return
	    	end
	    	
	    	if agw_config_tbl.store_redis.connect_config.redis_password and agw_config_tbl.store_redis.connect_config.redis_password ~= "" then
		        local ok, err = red:auth(agw_config_tbl.store_redis.connect_config.redis_password)
		        if not ok then
		          ngx_log(ngx.ERR, "failed to connect to Redis: ", err)
		          return
		        end
		    end

	    	local current_timetable = utils.current_timetable()
			local time_key = current_timetable[limit_type]
	    	local cache_key = get_local_key(identifier, time_key)

	    	local current_metric, err = red:get(cache_key)
	    	if err then
		       return nil, err
		    end
		    if current_metric == ngx.null then
        		current_metric = nil
      		end
      		
      		return current_metric and current_metric or 0
		end
	}
}