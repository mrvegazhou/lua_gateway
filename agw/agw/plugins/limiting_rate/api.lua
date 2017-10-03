local API = {}
local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs
local type = type
local tostring = tostring
local tonumber = tonumber
local cjson = require("cjson")
local utils = require("agw.utils.utils")
local model = require("agw.plugins.limiting_rate.models")
local CONST = require("agw.constants")
local common_model = require("agw.plugins.common.models")
local agw_config = ngx.shared.agw_config
local redis_store = require("agw.store.redis_store")(cjson.decode(agw_config:get("agw_config")))

local printable = require "agw.utils.printable"

local limit = 20

local function return_res(res, data, msg)
	if data then
    	return res:json({
            success = true,
            data = data
        })
    else
    	return res:json({
            success = false,
            msg = msg
        })
    end
end

API["/limiting_rate"] = {
	GET = function(store, conf)
		return function(req, res, next)
			local data = {}
            -- 获取总条数
            local key_name = req.query.key_name or nil
            if not key_name then
                args = {}
            else
                args = {{'key like %?%', key_name}}
            end
            local total = model:get_limiting_rate_total(store, args)
            data.total = total
            data.page = 1
            data.url = "/api/limiting_rate/configs"
            local page_count = math.ceil(tonumber(total)/tonumber(limit))
            data.page_count = page_count
            res:render("limiting_rate/limiting_rate", data)
		end
	end
}

API["/api/limiting_rate/configs"] = {
	GET = function(store, conf)
        return function(req, res, next)
        	local data = {}
            local page = req.query.page
            if not page then
                page = 1
            end
            data.page = page
            -- key search
            local key_name = req.query.key_name or nil
            local enable = common_model:get_meta_config(store, 'limiting_rate')
            data.enable = tonumber(enable.value)==1 and true or false
            local args = {}
            if not key_name then
                args = {}
            else
                args = {{'key like %?%', key_name}}
            end
        	local limiting_rates = model:get_limiting_rate_config(store, args, page, limit)
        	data.rules = limiting_rates
            return res:json({success = true, data = data})
        end
    end,
	POST = function(store, conf)
		return function(req, res, next)
			local rule = req.body.rule
			if not rule then
				return return_res(res, nil, "add rule to db error")
			end
			rule = cjson.decode(rule)
			local tmp_rule = {handle={}}
			local key
			for i, v in pairs(rule) do
				if i=='enable' then
					tmp_rule[i] = v
				elseif i=='key' then
					if not v then
						return return_res(res, nil, "规则名称不能为空！")
					end
					key = v
				elseif i=="handle" then
					for i2, v2 in pairs(v) do
						if i2=="log" or i2=="code" or i2=='global_limit' then
							tmp_rule['handle'][i2] = v2
						end
					end
				end
			end
			local check_duplicate, err = model:get_limiting_rate_config(store, {{'`key`=?', key}})
			if #check_duplicate>0 then
				return return_res(res, nil, "规则名称不能重复！")
			end
			tmp_rule.time = utils.now()
			local add_res, err = model:save_limiting_rate_config(store, key, tmp_rule)
			if not add_res then
				return return_res(res, nil, err)
			end
			return return_res(res, {rule_id = add_res})
		end
	end,
	DELETE = function(store, conf)
		return function(req, res, next)
			local rule_id = req.body.rule_id
			if not rule_id then
                return return_res(res, nil, "请求参数错误")
            end
            local del_res = model:del_limiting_rate_config(store, rule_id)
            if not del_res then
                return return_res(res, nil, "删除失败")
            end
            return_res(res, {rule_id = rule_id})
		end
	end,
    PUT = function(store, conf)
		return function(req, res, next)
			local rule = req.body.rule
            rule = cjson.decode(rule)
            if not rule.id then
                return_res(res, nil, "update limiting_rate to db error")
            end
            local old_limiting_rate_info = model:get_limiting_rate_config(store, {{'id=?', rule.id}})
            if not old_limiting_rate_info then
                return return_res(res, nil, "原始数据不存在")
            end
            local tmp_rule = {}
            local key
            for i, v in pairs(rule) do
            	if i=='enable' then
					tmp_rule[i] = v
				elseif i=='key' then
					key = v
				elseif i=="handle" then
					tmp_rule['handle'] = {}
					for i2, v2 in pairs(v) do
						if i2=="log" or i2=="code" then
							tmp_rule['handle'][i2] = v2
						elseif i2=="global_limit" then
							tmp_rule['handle'][i2] = v2
						end
					end
				end
            end
            local now_time = utils.now()
            tmp_rule.time = now_time
            local update_res = model:update_limiting_rate_config(store, rule.id, key, tmp_rule, now_time)
            if not update_res then
				return return_res(res, nil, "修改限速配置失败")
			end
			return_res(res, {rules = tmp_rule})
		end
	end
}

--停用和启用
API["/api/limiting_rate/enable"] = {
	POST = function(store, conf)
        return function(req, res, next)
        	local enable = req.body.enable
            if enable == "1" then enable = true else enable = false end

            local result = false

            local can_enable = "0"
            if enable then can_enable = "1" end

            local update_res = common_model:update_meta_enable(store, 'limiting_rate', can_enable)
            if update_res then
                return return_res(res, (enable == true and "开启限速成功" or "关闭限速成功"))
            else
                return return_res(res, nil, (enable == true and "开启限速失败" or "关闭限速失败"))
            end
        end
    end
}

API["/api/limiting_rate/list"] = {
	GET = function(store, conf)
		return function(req, res, next)
			local data = {}
			local rid = req.query.rid
			local page = req.query.page
			if not page then
				page = 1
			end
			
			data.rid = rid
            -- 获取总条数
            local key_name = req.query.key or nil
            local args = {{'rule_id=?', rid}}
            if key_name then
                args = {{'rule_id=?', rid}, {'key like %?%', key_name}}
            end
            local total = model:get_limiting_rate_by_identifier_total(store, args)
            data.total = total
            data.page = page
            local page_count, last_page, next_page = utils.show_pager(total, page, limit)
            data.page_count = page_count
            data.next_page = next_page
			data.last_page = last_page
			data.url = "/api/limiting_rate/list?rid="..rid.."&page="
            data.res_list = model:get_limiting_rate_by_identifier(store, args, page, limit)
            res:render("limiting_rate/limiting_rate_list", data)
		end
	end,
	DELETE = function(store, conf)
		return function(req, res, next)
			local rate_list_id = req.body.rate_id
			if not rate_list_id then
				return return_res(res, nil, "参数不正确")
			end
			-- 获取type和condition_value
			local rate_info = model:get_limiting_rate_by_identifier(store, {{'id=?', rate_list_id}})
			if not rate_info or #rate_info==0 then
				return return_res(res, nil, "限速信息不存在")
			end
			local del_res = model:del_limiting_rate_list(store, {{'id=?', tonumber(rate_list_id)}})
			if not del_res then
				return return_res(res, nil, "删除失败")
			end
			--删除redis缓存
			redis_store:del(redis_store:get_limiting_rate_condition_value(rate_info[1]['type'], rate_info[1]['condition_value']))
			return return_res(res, {rate_id=rate_list_id})
		end
	end,
	PUT = function(store, conf)
		return function(req, res, next)
			local rate_list_id = req.body.rate_list_id
			local rid = req.body.rid
			-- 判断是否存在
			local rate_info = model:get_limiting_rate_by_identifier(store, {{'id=?', tonumber(rate_list_id)}})
			if not rate_info or #rate_info==0 then
				return return_res(res, nil, "限速列表信息不存在")
			end
			local datas = {}
			local update_datas = {}

			local tmp_type = req.body.tmp_type
			update_datas['type'] = tmp_type
			table_insert(datas, {"`type`=?", tmp_type})

			local tmp_period_count = req.body.tmp_period_count
			update_datas['period_count'] = tmp_period_count
			table_insert(datas, {"`period_count`=?", tmp_period_count})

			local tmp_period = req.body.tmp_period
			update_datas['period'] = tmp_period
			table_insert(datas, {"`period`=?", tmp_period})

			local tmp_condition = req.body.tmp_condition
			update_datas['condition'] = tmp_condition
			table_insert(datas, {"`condition`=?", tmp_condition})

			local tmp_condition_value = req.body.tmp_condition_value
			update_datas['condition_value'] = tmp_condition_value
			table_insert(datas, {"`condition_value`=?", tmp_condition_value})

			update_datas['rule_id'] = rid
			update_datas['id'] = rate_list_id

			local update_res = model:update_limiting_rate_list(store, datas, {{"id=?", rate_list_id}})
			if not update_res then
				return return_res(res, nil, "限速列表信息修改失败")
			end
			-- 先删除限速判断缓存
			redis_store:del(redis_store:get_limiting_rate_condition_value(rate_info[1]['type'], rate_info[1]['condition_value']))
			redis_store:set_json(redis_store:get_limiting_rate_condition_value(tmp_type, tmp_condition_value), update_datas)
			redis_store:persist(redis_store:get_limiting_rate_condition_value(tmp_type, tmp_condition_value))
			return return_res(res, update_datas)
		end
	end,
	POST = function(store, conf)
		return function(req, res, next)
			local datas = {}
			local tmp_type = req.body.tmp_type
			datas['type'] = tmp_type

			local tmp_period_count = req.body.tmp_period_count
			datas['period_count'] = tmp_period_count
			
			local tmp_period = req.body.tmp_period
			datas['period'] = tmp_period
			
			local tmp_condition = req.body.tmp_condition
			datas['condition'] = tmp_condition
			
			local tmp_condition_value = req.body.tmp_condition_value
			datas['condition_value'] = tmp_condition_value
			
			local rid = req.body.rid
			datas['rule_id'] = rid
			
			-- 判断限速规则是否存在
			local check_rate_config = model:get_limiting_rate_config(store, {{'id=?', tonumber(rid)}})
			if not check_rate_config or #check_rate_config==0 then
				return return_res(res, nil, "限速配置信息不存在")
			end
			-- 判断限速列表是否存在 限速类型+类型值+限速条件+条件值
			local search_condition = {{'type=?', tmp_type}, {'condition=?', tmp_condition}}
			local check_duplicate_list_info = model:get_limiting_rate_by_identifier(store, search_condition)
			if check_duplicate_list_info then
				return return_res(res, nil, "限速列表信息已经存在，请检查添加条件")
			end

			local add_res = model:save_limiting_rate_identifier(store, datas)
			if not add_res then
				return return_res(res, nil, "添加限速列表失败")
			end
			datas['id'] = add_res
			-- 添加到redis缓存 type+condition_val
			redis_store:set_json(redis_store:get_limiting_rate_condition_value(tmp_type, tmp_condition_value), datas)
			redis_store:persist(redis_store:get_limiting_rate_condition_value(tmp_type, tmp_condition_value))
			return return_res(res, datas)
		end
	end
}

API["/api/limiting_rate/info"] = {
	POST = function(store, conf)
		return function(req, res, next)
			local info_id = req.body.info_id
			if not info_id then
				return return_res(res, nil, "id参数为空")
			end
			local info = model:get_limiting_rate_by_identifier(store, {{'id=?', info_id}}) 
			if not info or #info==0 then
				return return_res(res, nil, "获取信息失败")
			end
			return return_res(res, {info=info[1]})
		end
	end
}


return API