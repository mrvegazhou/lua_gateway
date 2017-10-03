local Object = require "agw.lib.classic"
local len = string.len
local sub = string.sub
local ipairs = ipairs
local pairs = pairs
local str_rep = string.rep
local table_insert = table.insert
local BaseModel = Object:extend()
local printable = require "agw.utils.printable"

function BaseModel:save_fields_to_tbl(datas, fields)
    local revtab = {}
    local sql_keys = ''
    local sql_params = {}
    for k, v in ipairs(fields) do
        revtab[v] = true
    end
    for k, v in pairs(datas) do
        if revtab[k] then
            sql_keys = sql_keys..'`'..k..'`,'
            table_insert(sql_params, v)
        end
    end
    if sql_keys then
        sql_keys = sub(sql_keys, 0, #sql_keys-1)
    end
    local sql_marks = str_rep('?,', #sql_params)
    sql_marks = sub(sql_marks, 0, #sql_marks-1)
    return sql_keys, sql_marks, sql_params
end

function BaseModel:sql_args(sql, find_args)
	local params = {}
	if #find_args>0 then
		sql = sql.." WHERE "
		for key, value in ipairs(find_args) do
			sql = sql..value[1]..(#value~=3 and " AND " or value[3])
			table_insert(params, value[2])
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	return sql, params
end

function BaseModel:update_args(sql, args)
    local params = {}
    if #args>0 then
        sql = sql.." SET "
        for key, value in ipairs(args) do
            sql = sql..value[1]..","
            table_insert(params, value[2])
        end
        sql = sub(sql, 0, len(sql)-1)
    end
    return sql, params
end

function BaseModel:merge_params(param1, param2)
    local merge_tbl = {}
    for k, v in ipairs(param1) do table_insert(merge_tbl, v) end
    for k, v in ipairs(param2) do table_insert(merge_tbl, v) end
    return merge_tbl
end

return BaseModel