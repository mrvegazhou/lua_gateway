local cjson = require("cjson")
local redis = require("resty.redis")
local store = require("agw.store.base")
local redis_store = store:extend()
local config_loader = require("agw.utils.config_loader")
local ngx_log = ngx.log
local resty_lock = require "resty.lock"

local printable = require("agw.utils.printable")

local CACHE_KEYS = {
  APIS = "apis",
  
  OAUTH2_RULE = "oauth2.rule",
  OAUTH2_CREDENTIAL = "oauth2_credentials",
  OAUTH2_CREDENTIAL_CLIENT_ID = "oauth2_credentials.clientid",
  OAUTH2_CONSUMERS_BY_ARGS = "oauth2_consumers_by_args",
  OAUTH2_TOKEN_BY_TOKENCODE = "oauth2_token_by_tokencode",
  OAUTH2_TOKEN = "oauth2_token",
  CONSUMERS = "oauth2_consumers",
  OAUTH2_CREDENTIALS_BY_ARGS = "oauth2_credentials.args",

  BALANCER_LIST = "balancer_list",
  BALANCER_URL = "balancer_url",

  LIMITING_RATE_CONDITION_VALUE = "l_rate",
  LIMITING_RATE_CONFIG = "l_rate_conf",

  PLUGINS = "plugins",
  BASICAUTH_CREDENTIAL = "basicauth_credentials",
  HMACAUTH_CREDENTIAL = "hmacauth_credentials",
  KEYAUTH_CREDENTIAL = "keyauth_credentials",
  JWTAUTH_CREDENTIAL = "jwtauth_credentials",
  ACLS = "acls",
  SSL = "ssl",
  REQUESTS = "requests",
  AUTOJOIN_RETRIES = "autojoin_retries",
  TIMERS = "timers",
  ALL_APIS_BY_DIC = "ALL_APIS_BY_DIC",
  LDAP_CREDENTIAL = "ldap_credentials",
  BOT_DETECTION = "bot_detection"
}


-------------------------------------------return oauth2 keys-----------------------------------------------------------------------
function redis_store:oauth2_token_key(access_token)
  return CACHE_KEYS.OAUTH2_TOKEN..":"..access_token
end

function redis_store:oauth2_credential_key(client_id)
  return CACHE_KEYS.OAUTH2_CREDENTIAL..":"..client_id
end

function redis_store:oauth2_rule_by_ruleid(rule_id)
  return CACHE_KEYS.OAUTH2_RULE..'.'..rule_id
end

function redis_store:get_oauth2_token_by_tokencode(credential_id) --token_code
  return CACHE_KEYS.OAUTH2_TOKEN_BY_TOKENCODE..":"..credential_id --..":"..token_code
end

function redis_store:get_oauth2_consumers_by_args(args)
  return CACHE_KEYS.OAUTH2_CONSUMERS_BY_ARGS..args
end

function redis_store:get_delete_all_oauth2_consumers()
  return "oauth2_consumers*"
end

function redis_store:get_delete_all_oauth2_tokens()
  return "oauth2_token*"
end

function redis_store:get_delete_all_oauth2_credentials()
  return "oauth2_credentials*"
end

function redis_store:get_oauth2_credentials_by_args(args)
  return CACHE_KEYS.OAUTH2_CREDENTIALS_BY_ARGS.."."..args
end

-------------------------------------------return balancer keys-----------------------------------------------------------------------
function redis_store:get_balancer_list()
  return CACHE_KEYS.BALANCER_LIST
end

function redis_store:get_balancer_url_by_bid(bid)
  return CACHE_KEYS.BALANCER_URL.."."..bid
end
-------------------------------------------return limiting_rate------------------------------------------------------------------------
function redis_store:get_limiting_rate_condition_value(type, condition_value)
  return CACHE_KEYS.LIMITING_RATE_CONDITION_VALUE..':'..type..':'..condition_value
end

function redis_store:get_limiting_rate_config(rule_id)
  return CACHE_KEYS.LIMITING_RATE_CONFIG..":"..rule_id
end
---------------------------------------------------------------------------------------------------------------------------------------

function redis_store:get_cache_keys()
  return CACHE_KEYS
end

-------------------------------------------return keys end------------------------------------------------------------------------------

function redis_store:new(config, redis_host, redis_port, redis_password)
    -- local instance = {}
    -- instance.config = config
    -- if config then
    -- 	instance.redis_host = config.store_redis.connect_config.redis_host
    -- 	instance.redis_port = config.store_redis.connect_config.redis_port
    -- 	instance.redis_password = ""
    -- else
    -- 	instance.redis_host = "127.0.0.1"
    -- 	instance.redis_port = "6379"
    -- 	instance.redis_password = ""
    -- end
    -- return setmetatable(instance, { __index = redis_store})
  if redis_host==nil or redis_port==nil then
    self.redis_host = "r-2ze82ef8b4cb5a74.redis.rds.aliyuncs.com"
    self.redis_port = "6379"
  	self.redis_password = "Visualchina123"
  else
    if not config then
      error("config is null")
    end
    self.redis_host = config.store_redis.connect_config.redis_host
    self.redis_port = config.store_redis.connect_config.redis_port
    self.redis_password = config.store_redis.connect_config.redis_password
  end
  self.config = config
end

function redis_store:connect(exptime)
  local conf = self.config
  if conf and conf.store_redis.enable==false then
    return nil
  end
	local red = redis:new()
  red:set_timeout(exptime or 2000)
  if (not self.redis_host) or (not self.redis_port) then
  	error("failed to connect to Redis, nil host or port")
  end

  local ok, err = red:connect(self.redis_host, self.redis_port)
	if not ok then
		self:finish(red)
		error("failed to connect to Redis: "..err)
	end
  local count
  count, err = red:get_reused_times()
  if 0 == count then
      ok, err = red:auth(self.redis_password)
      if not ok then
          error("failed to connect to Redis: "..err)
          return
      end
  elseif err then
      error("failed to get reused times: "..err)
      return nil, err
  end

	return red, nil
end

function redis_store:finish(red, pool_max_idle_time, pool_size)
	red:set_keepalive(pool_max_idle_time or 10000, pool_size or 200)
end

function redis_store:get(key)
	local red = self:connect()
	local res, err = red:get(key)
	if res==cjson.null then
	    return nil
	end
	self:finish(red)
	return res, err
end

function redis_store:set(key, value, ttl, exptime)
	local red = self:connect(exptime or nil)
	local ok, err = red:set(key, value)
  if ttl then
    red:expire(key, ttl)
  end
	if not ok then
      ngx_log(ngx.ERR, "redis failed to set: "..err)
      return nil
  end
  self:finish(red)
  return ok
end

function redis_store:sadd_json(key, value, ttl, exptime)
  local red = self:connect(exptime or nil)
  local ok, err = red:sadd(key, cjson.encode(value))
  if ttl then
    red:expire(key, ttl)
  end
  if not ok then
      ngx_log(ngx.ERR, "redis failed to sadd: "..err)
      return nil
  end
  self:finish(red)
  return ok
end

function redis_store:smembers_json(key)
  local red = self:connect()
  local res, err = red:smembers(key)
  if err then
    return false, "smembers_json error"
  end
  if not res or res==cjson.null then
      return false, 'smembers null error'
  end
  res = cjson.decode(res)
  return res, err
end

function redis_store:srem(val)
  local red = self:connect()
  local res, err = red:srem(val)
  if err then
    return false, "srem error"
  end
  return res
end

function redis_store:get_or_set(key, cb, ttl, exptime)
  local red = self:connect(exptime or nil)
	-- Try to get the value from the cache
  -- self:del(key)
  local value, err = red:get(key)
  if value~=ngx.null then
    return cjson.decode(value), err 
  end

  local lock, err = resty_lock:new("locks", {
    exptime = 10,
    timeout = 5
  })
  if not lock then
    ngx_log(ngx.ERR, "could not create lock: ", err)
    return
  end

	-- The value is missing, acquire a lock
	local elapsed, err = lock:lock(key)
	if not elapsed then
		ngx_log(ngx.ERR, "failed to acquire cache lock: ", err)
	end

	-- Lock acquired. Since in the meantime another worker may have
  	-- populated the value we have to check again
  value = red:get(key)
  if value==ngx.null then
    -- Get from closure
    value = cb()
    if value then
      local ok, err = red:set(key, cjson.encode(value))
      if ttl then
        red:expire(key, ttl)
      end
      if not ok then
        ngx_log(ngx.ERR, err)
      end
    end
  end

  local ok, err = lock:unlock()
  if not ok and err then
    ngx_log(ngx.ERR, "failed to unlock: ", err)
  end

  self:finish(red)
  return value
end

function redis_store:set_json(key, value, ttl)
    if value then
        value = cjson.encode(value)
    else
    	return nil
    end
    return self:set(key, value, ttl)
end

function redis_store:get_json(key)
    local value, err = self:get(key)
    if err then
    	return false, "get_json error"
    end
    if not value or value==cjson.null then
        return false, 'get null error'
    end
    value = cjson.decode(value)
    return value, err
end

function redis_store:persist(key)
    if not key then
      return nil, "key is null"
    end
    local red = self:connect(exptime or nil)
    local ok, err = red:PERSIST(key)
    self:finish(red)
    return ok, err
end

function redis_store:incr(key, value, exptime)
    local red = self:connect(exptime or nil)
  	local ok, err = red:incr(key, value)
  	if not ok and err then
  		ngx_log(ngx.ERR, "failed to delete: ", err)
  		return nil, err
  	end
  	self:finish(red)
  	return ok, err
end

-- 获取keys
function redis_store:get_keys(key)
  local red = self:connect()
  local ok, err = red:keys(key)
  if not ok and err then
    ngx_log(ngx.ERR, "failed to get keys: ", err)
    return nil
  end
  self:finish(red)
  return ok, err
end

function redis_store:batch_del(key)
  local red = self:connect()
  local keys, err = red:keys(key)
  if not keys and err then
    ngx_log(ngx.ERR, "failed to get keys: ", err)
    return nil
  end
  for k, v in pairs(keys) do
    red:del(v)
  end
  self:finish(red)
end

function redis_store:check_ttl(key)
  local red = self:connect()
  local ok, err = red:ttl(key)
  if not ok and err then
    ngx_log(ngx.ERR, "failed to check ttl: ", err)
    return nil
  end
  return ok
end

function redis_store:del(key)
	local red = self:connect()
	local ok, err = red:del(key)
	if not ok and err then
		ngx_log(ngx.ERR, "failed to delete: ", err)
		return nil
	end
	self:finish(red)
	return ok, err
end


return redis_store