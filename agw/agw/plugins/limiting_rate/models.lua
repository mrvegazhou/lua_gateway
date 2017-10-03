local utils = require("agw.utils.utils")
local CONST = require("agw.constants")
local cjson = require("cjson")
local table_insert = table.insert
local len = string.len
local sub = string.sub
local agw_config = ngx.shared.agw_config
local redis_store = require("agw.store.redis_store")(cjson.decode(agw_config:get("agw_config")))
local BaseModel = require "agw.base_model"
local printable = require "agw.utils.printable"

local _M = BaseModel:extend()

local tbl_fields = "`id`, `condition_value`, `period`, `period_count`, `rule_id`, `condition`, `type`, `create_time`"
local tbl_fields_arr = {'id', 'condition_value', 'period', 'period_count', 'rule_id', 'condition', 'type', 'create_time'}

function _M:get_limiting_rate_config_by_id(store, rule_id)
	local config_info = redis_store:get_json(redis_store:get_limiting_rate_config(rule_id))
	if not config_info then
		local sql = "SELECT `id`,`key`,`value`,`op_time` FROM "..CONST.TABLES.LIMITING_RATE..' WHERE id=?'
		config_info = store:query({sql=sql, params={rule_id}})
		if config_info and #config_info>0 then
			redis_store:set_json(redis_store:get_limiting_rate_config(rule_id), config_info[1])
		else
			return false
		end
	end
	return config_info
end

function _M:get_limiting_rate_config(store, find_args, page, limit)
	local offset = ''
	if page and limit then
		offset = " LIMIT "..(tonumber(page)-1)*limit..", "..limit
	end
	local sql = "SELECT `id`,`key`,`value`,`op_time` FROM "..CONST.TABLES.LIMITING_RATE
	local sql, params = BaseModel:sql_args(sql, find_args)
	sql = sql.." ORDER BY id DESC "..offset
	local res, err = store:query({sql=sql, params=params})
	if not res then
		return nil, err
	end
	-- 解析json格式
	local tbl_res = {}
	local i = 1
	for k, v in ipairs(res) do
		local ok, val = pcall(cjson.decode, v.value)
		if not ok then
			ngx.log(ngx.ERR, err)
		end
		tbl_res[i] = {
						enable = val.enable,
						time = val.time,
						log = val.handle.log,
						code = val.handle.code,
						op_time = v.op_time,
						global_limit = val.handle.global_limit,
						key = v.key,
						id = v.id
					}
		i = i + 1
	end
	return tbl_res
end

function _M:get_limiting_rate_total(store, find_args)
	local sql = "SELECT COUNT(*) as total FROM "..CONST.TABLES.LIMITING_RATE
	local sql, params = BaseModel:sql_args(sql, find_args)
	local res, err = store:query({sql=sql, params=params})
	if not res then
		return 0
	end
	return res[1]['total']
end

function _M:update_limiting_rate_config(store, rule_id, key, rule, now_time)
	if not rule then
		return nil, 'update limiting_rate rule error'
	end
	if not rule_id then
		return nil, 'rule_id is null'
	end
	rule = cjson.encode(rule)
	local update_result = store:update({ sql = "update "..CONST.TABLES.LIMITING_RATE.." set `key`=?, `value`=?, `op_time`=? where `id`=?",
							             params = { key, rule, now_time, rule_id }
							          })
	if not update_result then
        return false, "update limiting_rate rules error when modifing"
    end
    redis_store:del(redis_store:get_limiting_rate_config(rule_id))
    redis_store:set_json(redis_store:get_limiting_rate_config(rule_id), {id=rule_id, key=key, value=rule, op_time=now_time})
    return update_result
end

function _M:save_limiting_rate_config(store, key, rule)
	if type(rule) ~= "table" then
		return false, 'rule is not table type'
	end
	if next(rule)==nil then
		return false, 'rule is null'
	end
	if not key then
		return false, 'key is null'
	end
	if not rule.handle.global_limit then
		return false, 'global limit is null'
	end
	local now_time = utils.now()
	local add_res = store:insert({
					sql = "INSERT INTO "..CONST.TABLES.LIMITING_RATE.."(`key`, `value`, `op_time`) VALUES( ?, ?, ?)",
					params = { key, cjson.encode(rule), now_time}
				})
	if not add_res then
		return false, 'add rule error'
	end
	redis_store:del(redis_store:get_limiting_rate_config(add_res))
    redis_store:set_json(redis_store:get_limiting_rate_config(add_res), {id=add_res, key=key, value=cjson.encode(rule), op_time=now_time})
	return rule
end

function _M:del_limiting_rate_config(store, rule_id)
	redis_store:del(redis_store:get_limiting_rate_config(rule_id))
	return store:delete({
                sql = "delete from "..CONST.TABLES.LIMITING_RATE.." where `id`=?",
                params = { rule_id }
    })
end

function _M:get_limiting_rate_by_identifier(store, find_args, page, limit)
	local offset = ''
	if page and limit then
		offset = " LIMIT "..(tonumber(page)-1)*limit..", "..limit
	end
	local sql = "SELECT "..tbl_fields.." FROM "..CONST.TABLES.LIMITING_RATE_IDENTIFIER
	local sql, params = BaseModel:sql_args(sql, find_args)
	sql = sql.." ORDER BY id DESC "..offset
	local res, err = store:query({sql=sql, params=params})
	if not res then
		return nil, err
	end
	return res
end

function _M:get_limiting_rate_by_identifier_total(store, find_args)
	local sql = "SELECT COUNT(1) as total FROM "..CONST.TABLES.LIMITING_RATE_IDENTIFIER
	local sql, params = BaseModel:sql_args(sql, find_args)
	local res, err = store:query({sql=sql, params=params})
	if #res==0 then
		return 0
	end
	return res[1]['total']
end

function _M:del_limiting_rate_list(store, args)
	local sql = "DELETE FROM "..CONST.TABLES.LIMITING_RATE_IDENTIFIER
	local sql, params = BaseModel:sql_args(sql, args)
	return store:delete({sql = sql, params = params})
end

function _M:update_limiting_rate_list(store, update_args, where_args)
	local sql = "UPDATE "..CONST.TABLES.LIMITING_RATE_IDENTIFIER
	local sql, update_params = BaseModel:update_args(sql, update_args)
	local sql, where_params = BaseModel:sql_args(sql, where_args)
	local params = BaseModel:merge_params(update_params, where_params)
	return store:update({sql = sql, params = params})
end

function _M:get_limit_types()
	--{1:consumer,2:credential,3:ip,4:URI,5:Query,6:Header,7:UserAgent,8:Method,9:Referer,10:host}
	return {'consumer', 'credential', 'ip', 'uri', 'query', 'header', 'useragent', 'method', 'referer', 'host'}
end

function _M:save_limiting_rate_identifier(store, datas)
	local sql_keys, sql_marks, sql_params = BaseModel:save_fields_to_tbl(datas, tbl_fields_arr)
	return store:insert({
							sql = "INSERT INTO "..CONST.TABLES.LIMITING_RATE_IDENTIFIER.."("..sql_keys..") VALUES( "..sql_marks.." )",
							params = sql_params
						})
end

return _M

