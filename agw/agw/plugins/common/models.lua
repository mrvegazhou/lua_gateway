local utils = require "agw.utils.utils"
local CONST = require("agw.constants")
local cjson = require("cjson")
local agw_config = ngx.shared.agw_config
local redis_store = require("agw.store.redis_store")(cjson.decode(agw_config:get("agw_config")))
local socket = require "socket"
local table_insert = table.insert
local sub  = string.sub
local len  = string.len
local str = require("resty.string")
local printable = require "agw.utils.printable"
local sub  = string.sub

local _M = {}

function _M:get_meta_config(store, name)
	local res = store:query({
                sql = "SELECT `id`,`key`,`value`,`op_time` FROM "..CONST.TABLES.META.." WHERE `key`=?", params={name..'.enable'}
            })
	if not res then
		return nil
	else
		return res[1]
	end
end

--停用和启动
function _M:update_meta_enable(store, name, enable)
	local update_result = store:update({
        sql = "UPDATE "..CONST.TABLES.META.." SET `value`=? WHERE `key`=?",
        params = { enable, name..".enable" }
    })

    if update_result then
        local res = redis_store:set(name..".enable", tonumber(enable)==1)
        if not res then
        	return false, "update "..name..".enable on redis store error"
        end
    else
        return false, "update "..name..".enable on mysql store error"
    end
    return true
end

function _M:get_metas(store)
    local enables, err = store:query({
        sql = "select `key`, `value` from meta where `key` like \"%.enable\""
    })
    return enables, err
end

function _M:get_all_plugins(store, plugin)
    local rules, err = store:query({
                sql = "select `value` from " .. plugin .. " order by id asc"
            })
    return rules, err
end

function _M:save_configs_in_redis(store, name)
    local rules, err = self:get_all_plugins(store, name)
    if err then
        ngx.log(ngx.ERR, "Load Plugin Rules Data error: ", err)
        os.exit(1)
    end

    if rules and type(rules) == "table" and #rules > 0 then
        local format_rules = {}
        for i, v in ipairs(rules) do
            table_insert(format_rules, cjson.decode(v.value))
        end
        redis_store:set_json(name .. ".rules", format_rules)
    end
end

return _M