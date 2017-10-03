local utils = require "agw.utils.utils"
local url = require "socket.url"
local http = require "resty.http"
local CONST = require "agw.constants"
local cjson = require "cjson"
local agw_config = ngx.shared.agw_config
local redis_store = require("agw.store.redis_store")(cjson.decode(agw_config:get("agw_config")))
local log           = ngx.log
local ERR           = ngx.ERR
local WARN          = ngx.WARN
local socket = require "socket"
local table_insert = table.insert
local str_sub    = string.sub
local sub  = string.sub
local len  = string.len
local str = require "resty.string"
local sub  = string.sub
local tonumber = tonumber
local tab_concat = table.concat
local printable = require "agw.utils.printable"


---------------------------------------------------------------------------------------分割线-----------------------------------------------------------------------------------

local _M = {}

local tbl_balancer_url_fields = "id, host, down, weight, max_fails, fail_timeout, backup, b_id, port, created_time"

-- 获取各账户下的负载信息total
function _M:get_balancers_total(store, find_args)
	local sql = "SELECT COUNT(*) as total FROM "..CONST.TABLES.BALANCER
	if #find_args>0 then
		sql = sql.." WHERE "
		for key, value in ipairs(find_args) do
			sql = sql..value[1].." AND "
			table_insert(params, value[2])
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	local res = store:query({sql=sql, params=params})
	if not res then
		return 0
	end
	return res[1]['total']
end

-- 获取各账户下的负载信息
function _M:get_balancers(store, find_args, page, limit)
	local offset = ''
	local params = {}
	if page and limit then
		offset = " LIMIT "..(tonumber(page)-1)*limit..", "..limit
	end
	local sql = "SELECT `id`,`key`,`value`,`op_time` FROM "..CONST.TABLES.BALANCER
	if #find_args>0 then
		sql = sql.." WHERE "
		for key, value in ipairs(find_args) do
			sql = sql..value[1].." AND "
			table_insert(params, value[2])
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	sql = sql.." ORDER BY id DESC "..offset
	local res = store:query({sql=sql, params=params})
	if not res then
		return nil, 'upstreams balancer is null' 
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
						balancer_type = val.handle.balancer_type,
						code = val.handle.code,
						op_time = v.op_time,
						host = val.handle.host,
						key = v.key,
						id = v.id
					}
		i = i + 1
	end
	return tbl_res
end

-- 通过账号获取
function _M:get_balancer_urls(store, bid, page, limit)
	local offset = ''
	if page and limit then
		offset = " LIMIT "..(tonumber(page)-1)*limit..", "..limit
	end
	local res = store:query({sql = "SELECT "..tbl_balancer_url_fields.." FROM "
									..CONST.TABLES.BALANCER_URL.." WHERE b_id=?".." ORDER BY id DESC "..offset, 
							 params = {tonumber(bid)} })
	if not res then
		return nil, 'balancer url is null' 
	end
	return res
end

-- function _M:get_balancers_urls_for_consul(store, bid)
-- 	local all_urls = self:get_balancer_urls(store, bid)
-- 	local return_res = {}
-- 	for k,v in pairs(all_urls) do

-- 	end
-- end

-- 获取url总数
function _M:get_balancer_urls_total(store, bid)
	if not bid then
		return nil, "params is null"
	end
	local res = store:query({sql = "SELECT COUNT(*) AS total FROM "
									..CONST.TABLES.BALANCER_URL.." WHERE b_id=?", params = {bid}})
	return res[1]['total']
end

function _M:get_balancer_url_info_by_args(store, find_args)
	local params = {}
	local sql = "SELECT "..tbl_balancer_url_fields.." FROM "..CONST.TABLES.BALANCER_URL
	if #find_args>0 then
		sql = sql.." WHERE "
		for key, value in ipairs(find_args) do
			sql = sql..value[1].." AND "
			table_insert(params, value[2])
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	sql = sql.." ORDER BY id DESC "
	local res = store:query({sql=sql, params=params})
	if not res then
		return nil
	end
	return res
end

--获取url详情
function _M:get_balancer_url_info(store, url_id)
	if not url_id then
		return nil, "params is null"
	end
	return store:query({sql="SELECT "..tbl_balancer_url_fields.." FROM "..CONST.TABLES.BALANCER_URL.." WHERE id=?", params={url_id}})
end

function _M:update_balancer_info_by_id(store, url_id, datas)
	if not url_id then
		return nil, "params is null"
	end
	local val_datas = {}
	sql = "UPDATE "..CONST.TABLES.BALANCER_URL.." SET "
	for k, v in pairs(datas) do
		sql = sql..k..'=?, '
		table_insert(val_datas, v)
	end
	sql = sub(sql, 0, len(sql)-2)
	sql = sql..' WHERE id=?'
	table_insert(val_datas, tonumber(url_id))
	return store:update({
		sql = sql,
        params = val_datas
	})
end

function _M:del_balancer_info_by_id(store, url_id)
	return store:delete({
		sql = "DELETE FROM "..CONST.TABLES.BALANCER_URL.." WHERE id=?",
		params = {url_id}
	})
end

function _M:del_balancer_info_by_bid(store, bid)
	return store:delete({
		sql = "DELETE FROM "..CONST.TABLES.BALANCER_URL.." WHERE b_id=?",
		params = {bid}
	})
end

-- 通过key获取负载详情
function _M:get_balancer_by_id(store, id)
	local info = store:query({sql = "SELECT `id`,`key`,`value`,`op_time` FROM "..CONST.TABLES.BALANCER.." WHERE id=?", params = {id} })
	if not info then
		return nil, "get balancer by id is null"
	end
	return info
end

-- 添加账户下的负载信息
function _M:add_balancer_info(store, key, value)
	if not key or not value then
		return false, 'bad argument'
	end
	local add_res = store:insert({
						sql = "INSERT INTO "..CONST.TABLES.BALANCER.."(`key`, `value`) VALUES( ?, ? )",
						params = { key, cjson.encode(value) }
					})
	if not add_res then
		return false, 'add balancer info error'
	end
	return add_res
end

function _M:add_balancer_url_info(store, datas)
	local sql_keys = ''
	local sql_params = {}
	for k, v in pairs(datas) do
		if k=='host' then
			sql_keys = sql_keys..'`host`,'
			table_insert(sql_params, v)
		elseif k=='port' then
			sql_keys = sql_keys..'`port`,'
			table_insert(sql_params, v)
		elseif k=='down' then
			--v = v==false and 0 or 1
			sql_keys = sql_keys..'`down`,'
			table_insert(sql_params, tonumber(v))
		elseif k=='weight' then
			sql_keys = sql_keys..'`weight`,'
			table_insert(sql_params, v)
		elseif k=='max_fails' then
			sql_keys = sql_keys..'`max_fails`,'
			table_insert(sql_params, v)
		elseif k=='fail_timeout' then
			sql_keys = sql_keys..'`fail_timeout`,'
			table_insert(sql_params, v)
		elseif k=='backup' then
			sql_keys = sql_keys..'`backup`,'
			table_insert(sql_params, tonumber(v))
		elseif k=='b_id' then
			sql_keys = sql_keys..'`b_id`,'
			table_insert(sql_params, v)
		elseif k=='created_time' then
			sql_keys = sql_keys..'`created_time`,'
			table_insert(sql_params, v)
		end
	end
	if sql_keys then
		sql_keys = str_sub(sql_keys, 0, #sql_keys-1)
	end
	local sql_marks = string.rep('?,', #sql_params)
	sql_marks = str_sub(sql_marks, 0, #sql_marks-1)
	return store:insert({
						sql = "INSERT INTO "..CONST.TABLES.BALANCER_URL.."("..sql_keys..") VALUES( "..sql_marks.." )",
						params = sql_params
					})
end

-- 修改balancer info
function _M:update_balancer_info(store, key, value)
	-- 修改数据库
	local update_result = store:update({
        sql = "UPDATE "..CONST.TABLES.BALANCER.." SET `value`=? WHERE `key`=?",
        params = { cjson.encode(value), key }
    })
	if not update_result then
		return nil, "update balancer error by key="..key
	end
	return update_result
end

-- 删除balancer info
function _M:del_balancer_info(store, id)
	return store:delete({
                sql = "delete from "..CONST.TABLES.BALANCER.." where `id`=?",
                params = { id }
    }) 
end

-- 从consul获取路由信息
function _M:get_urls_from_consul(host, port)
	local parse_url = str_format("http://%s:%s/v1/catalog/services", host, port)
	local httpc = http.new()
	local res, err = httpc:request_uri(parse_url)
	if not res then
        log(ERR, "request consul services", err)
        return
    end
    local data = cjson.decode(res)
    if not data then
        log(ERR, "json decode body failed, ", res)
        return
    end
    return data
end

-- 
function _M:update_balancer_config(store, rule_id, key, rule, now_time)
	if not rule or not rule_id then
		return false, 'update balancer rule error'
	end
	return store:update({ sql = "update "..CONST.TABLES.BALANCER.." set `key`=?, `value`=?,`op_time`=? where `id`=?",
						  params = { key, cjson.encode(rule), now_time, rule_id }
						})
end


-------------------------------------------balancer_servers-----------------------------------------------------

function _M:get_balancer_servers(store)
	return store:query({ sql = "SELECT id, ip, host_name, create_time FROM "..CONST.TABLES.BALANCER_SERVERS, params = {} })
end


return _M