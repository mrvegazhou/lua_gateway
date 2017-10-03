local API = {}
local table_insert = table.insert
local ipairs = ipairs
local pairs = pairs
local type = type
local tostring = tostring
local cjson = require("cjson")
local utils = require("agw.utils.utils")
local model = require("agw.plugins.oauth2.models")
local access = require("agw.plugins.oauth2.access")
local responses = require("agw.lib.responses")
local utils = require "agw.utils.utils"
local CONST = require("agw.constants")
local agw_config = ngx.shared.agw_config
local redis_store = require("agw.store.redis_store")(cjson.decode(agw_config:get("agw_config")))

local aes = require "resty.aes"
local iv = CONST.AES.IV
local key = CONST.AES.KEY

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

--添加oauth2到plugins插件中 key值指定consumer_id			1
API["/api/oauth2/configs"] = {
	GET = function(store)
        return function(req, res, next)
            local success, data = false, {}
            local enable = model:get_meta_config(store)
            data.enable = tonumber(enable.value)==1 and true or false
            local config_infos = model:get_oauth2_config(store)
            local rules = {}
            for i,v in pairs(config_infos) do
            	local tmp_value = cjson.decode(v.value)
            	tmp_value.id = v.id
            	table_insert(rules, tmp_value)
            end
            data.rules = rules
            success = true
            res:json({
                success = success,
                data = data
            })
        end
    end,
	POST = function(store)
		return function(req, res, next)
			local rule = req.body.rule
			if not rule then
				return return_res(res, nil, "add rule to db error")
			end
			rule = cjson.decode(rule)
			local tmp_rule = {}
			local key
			for i, v in pairs(rule) do
				if i=='name' or i=='enable' then
					tmp_rule[i] = v
					if i=='name' then
						if not v then
							return return_res(res, nil, "规则名称不能为空！")
						end
						key = v
					end
				elseif i=="handle" then
					tmp_rule['handle'] = {}
					for i2, v2 in pairs(v) do
						if i2=="log" or i2=="code" then
							tmp_rule['handle'][i2] = v2
						elseif i2=="credentials" then
							local tmp_credentials = {}
							for i3, v3 in pairs(v2) do
								if i3=="enable_authorization_code" or i3=="enable_client_credentials" or i3=="enable_implicit_grant" or i3=="enable_password_grant" 
									or i3=="token_expiration" or i3=="accept_http_if_already_terminated" or i3=="hide_credentials" then
									tmp_credentials[i3] = v3
								end
							end
							tmp_rule['handle']['credentials'] = tmp_credentials
						end
					end
				end
			end
			--先判断是否存在相同的key
			local check_duplicate, err = model:get_oauth2_config(store, {{'`key`=?', key}})
			if #check_duplicate>0 then
				return return_res(res, nil, "规则名称不能重复！")
			end

			local now_time = utils.now()
			tmp_rule.time = now_time
			local add_res, err = model:save_oauth2_config(store, tmp_rule)
			if not add_res then
				return_res(res, nil, err)
			end
			local enable = model:get_meta_config(store)
			return_res(res, {rule = tmp_rule, enable = enable['value']})
		end
	end,
	DELETE = function(store)
		return function(req, res, next)
			local rule_id = tostring(req.body.rule_id)
			if not rule_id or rule_id == "" then
                return res:json({
                    success = false,
                    msg = "error param: rule id shoule not be null."
                })
            end
            local rules, enable = model:update_oauth2_redis_store_by_del(store, rule_id)
            if not res then
            	res:json({
                    success = false,
                    msg = "delete rule from db error"
                })
            else
	            res:json({
                    success = true,
                    data = {
                        rules = rules,
                        enable = enable
                    }
	            })
        	end
		end
	end,
	-- modify
    PUT = function(store)
		return function(req, res, next)
			local rule = req.body.rule
			rule = cjson.decode(rule)
			if not rule.id then
				return_res(res, nil, "update rule to db error")
			end
			local tmp_rule = {}
			
			for i, v in pairs(rule) do
				if i=='name' or i=='enable' then
					tmp_rule[i] = v
				elseif i=="handle" then
					tmp_rule['handle'] = {}
					for i2, v2 in pairs(v) do
						if i2=="log" or i2=="code" then
							tmp_rule['handle'][i2] = v2
						elseif i2=="credentials" then
							local tmp_credentials = {}
							for i3, v3 in pairs(v2) do
								if i3=="enable_authorization_code" or i3=="enable_client_credentials" or i3=="enable_implicit_grant" or i3=="enable_password_grant" 
									or i3=="token_expiration" or i3=="accept_http_if_already_terminated" or i3=="hide_credentials" then
									tmp_credentials[i3] = v3
								end
							end
							tmp_rule['handle']['credentials'] = tmp_credentials
						end
					end
				end
			end

			local now_time = utils.now()
			tmp_rule.time = now_time
			local update_res = model:update_oauth2_config(store, rule.id, tmp_rule, now_time)
			if not update_res then
				return_res(res, nil, "update rule to db error")
			end
			-- 更新redis缓存
			model:update_config_info(store, rule.id)

			local enable = model:get_meta_config(store)
			return_res(res, {rules = new_rules, enable = enable['value']})
		end
	end
}

--停用和启用
API["/api/oauth2/enable"] = {
	POST = function(store)
        return function(req, res, next)
        	local enable = req.body.enable
            if enable == "1" then enable = true else enable = false end

            local result = false

            local oauth2_enable = "0"
            if enable then oauth2_enable = "1" end

            local update_res = model:update_oauth2_enable(store, oauth2_enable)
            if update_res then
                return_res(res, (enable == true and "开启oauth2成功" or "关闭oauth2成功"))
            else
                return_res(res, nil, (enable == true and "开启oauth2失败" or "关闭oauth2失败"))
            end
        end
    end
}

API["/api/oauth2/reg"] = {
	POST = function(store)
		return function(req, res, next)
			local rule_id = req.body.rule_id
			local data = {}
			--------------------------------------------------1 添加consumers 返回client_id client_secret consumer_id + 添加应用 
			local username = utils.trim(req.body.username)
			local showname = utils.trim(req.body.showname)
			local name = utils.trim(req.body.name)
			local scope = utils.trim(req.body.scope)
			local redirect_uri = utils.trim(req.body.redirect_uri)
			local save_consumer_credentials_res, err = model:save_consumer_oauth2(store, username, redirect_uri, name, rule_id, showname)
			if not save_consumer_credentials_res then
				return return_res(res, nil, err~='' and err or '获取账号信息失败')
			end
			--------------------------------------------------3 获取回调码 
			--获取provision_key 此获取的配置信息是多维的
			local rule_info = model:get_oauth2_config_by_id(store, rule_id)
			if not rule_info and rule_info.value.handle.provision_key then
				return return_res(res, nil, '获取配置信息失败')
			end
			local authorize_params = {	rule_id=rule_id, 
										state="", 
										provision_key=rule_info.value.handle.credentials.provision_key, 
										authenticated_userid=save_consumer_credentials_res.custom_id, 	--这里取自用户中心的id
										response_type='code',
										client_id=save_consumer_credentials_res.client_id,
										scope=scope
									 }
			local authorize_res = access:authorize(store, authorize_params)
			if not authorize_res or not authorize_res.code then
				--删除失败的账号
				model:del_consumer_and_credential(	store, 
													save_consumer_credentials_res.custom_id, 
													save_consumer_credentials_res.credentials_id, 
													save_consumer_credentials_res.client_id
												 )
				return return_res(res, nil, '获取回调码失败:'..authorize_res['error_description'])
			end
			--------------------------------------------------4 获取refresh_token access_token
			authorize_params['client_secret'] = authorize_res.client_secret
			authorize_params['grant_type'] = 'authorization_code'
			authorize_params['code'] = authorize_res.code
			authorize_params['scope'] = scope
			local response_params, _ = access:issue_token(store, authorize_params)
			if response_params.error then
				return return_res(res, nil, '获取access token失败:'..response_params.error)
			end
			res:json({
                    success = true,
                    data = {
                        access_token=response_params.access_token,
                        token_type=response_params.token_type,
                        expires_in=response_params.expires_in,
                        refresh_token=response_params.refresh_token,
                        scope=scope,
                        query_reg_execution_time=save_consumer_credentials_res.query_reg_execution_time
                    }
                })
		end
	end
}

--获取access token相关信息
API["/api/oauth2/check_regs/:rule_id/page/:page"] = {
	GET = function(store)
		return function(req, res, next)
			local data = {}
			--通过rule id获取账户列表
			local rule_id = req.params.rule_id
			local page = req.params.page
			if not page then
				page = 1
			end
			data.page = page
			
			data.url = "/api/oauth2/check_regs/"..rule_id.."/page/"

			--获取账户表的总数
			local total = model:get_consumers_count(store, {rule_id=rule_id})
			local page_count, last_page, next_page = utils.show_pager(total, page, limit)
			data.page_count = page_count
			data.next_page = next_page
			data.last_page = last_page

			local oauth2_consumer_list = model:get_consumers_by_args(store, {rule_id=rule_id}, page, limit)
			local consumers_ids = {}
			for i,v in pairs(oauth2_consumer_list) do
            	table_insert(consumers_ids, v.id)
            end

            local oauth2_credentials_list = model:get_oauth2_credentials_by_in(store, {key="consumer_id", val=consumers_ids})
            local credentials_ids = {}
            local oauth2_credentials_list_tmp = {}
            if oauth2_credentials_list then
	            for i,v in pairs(oauth2_credentials_list) do
	            	table_insert(credentials_ids, v.id)
	            	oauth2_credentials_list_tmp[v.consumer_id..'_c'] = v
	            end
	        end

            local oauth2_token_list = model:get_oauth2_tokens_by_in(store, {key='credential_id', val=credentials_ids})
            local oauth2_token_list_tmp = {}
            if oauth2_token_list then
	            for i,v in pairs(oauth2_token_list) do
	            	oauth2_token_list_tmp[v.credential_id..'_t'] = v
	            end
	        end
			
			local res_list_tmp = {}
			for i,v in pairs(oauth2_consumer_list) do
				local res_list = {}
				res_list.id = v.id
				res_list.username = v.username
				res_list.showname = v.showname
				res_list.create_time = v.create_time
				if oauth2_credentials_list_tmp[v['id']..'_c'] then
					res_list.name = oauth2_credentials_list_tmp[v['id']..'_c']['name']
					res_list.client_secret = oauth2_credentials_list_tmp[v['id']..'_c']['client_secret']
					res_list.client_id = oauth2_credentials_list_tmp[v['id']..'_c']['client_id']
					res_list.redirect_uri = oauth2_credentials_list_tmp[v['id']..'_c']['redirect_uri']

					local key = oauth2_credentials_list_tmp[v['id']..'_c']
					if oauth2_token_list_tmp[ key['id']..'_t' ] then
						res_list.scope = oauth2_token_list_tmp[ key['id']..'_t' ]['scope']
						res_list.expires_in = oauth2_token_list_tmp[ key['id']..'_t' ]['expires_in']
						res_list.refresh_token = oauth2_token_list_tmp[ key['id']..'_t' ]['refresh_token']
						res_list.token_type = oauth2_token_list_tmp[ key['id']..'_t' ]['token_type']
						res_list.access_token = oauth2_token_list_tmp[ key['id']..'_t' ]['access_token']

						if res_list.scope=='all' then
							res_list.scope = '全部'
						elseif res_list.scope=='' then
							res_list.scope = '空'
						end
					end
				end
				table_insert(res_list_tmp, res_list)
			end
            data.res_list = res_list_tmp
            data.res_json = cjson.encode(res_list_tmp)
			res:render("oauth2/oauth2_regs_list", data)
		end
	end
}

--查看账户下的授权信息
API["/api/oauth2/regedit"] = {
	POST = function(store)
        return function(req, res, next)
        	local consumer_id = req.body.consumer_id
        	local data = {}
        	local res_tmp = {}
        	local consumer = model:get_consumers_by_args(store, {id=consumer_id})
        	if not consumer then
        		return return_res(res, nil, '无此账户授权信息')
        	end
        	local credential = model:get_oauth2_credentials_by_args(store, {consumer_id=consumer_id})
        	local credential_id = credential[1]['id']
        	local token = model:get_oauth2_tokens_by_args(store, {credential_id=credential_id})
        	consumer = consumer[1]
        	res_tmp.id = consumer.id
        	res_tmp.username = consumer.username
        	res_tmp.showname = consumer.showname
        	res_tmp.custom_id = consumer.custom_id
        	res_tmp.create_time = consumer.create_time
        	--res_tmp.init_password = consumer.init_password
        	res_tmp.init_password = consumer.init_password==cjson.null and '' or consumer.init_password
        	if credential[1] then
        		credential = credential[1]
        		res_tmp.name = credential.name
	        	res_tmp.client_secret = credential.client_secret
	        	res_tmp.client_id = credential.client_id
	        	res_tmp.redirect_uri = credential.redirect_uri
	        else
	        	res_tmp.name = ''
	        	res_tmp.client_secret= ''
	        	res_tmp.client_id= ''
	        	res_tmp.redirect_uri= ''
        	end
        	if token[1] then
        		token = token[1]
	        	res_tmp.scope = token.scope
	        	res_tmp.expires_in = token.expires_in
	        	res_tmp.refresh_token = token.refresh_token
	        	res_tmp.token_type = token.token_type
	        	res_tmp.access_token = token.access_token
	        else
	        	res_tmp.scope = ''
	        	res_tmp.expires_in = ''
	        	res_tmp.refresh_token = ''
	        	res_tmp.token_type = ''
	        	res_tmp.access_token = ''
	        end
        	data.info = res_tmp
        	return return_res(res, data, nil)
        end
    end
}

API["/api/oauth2/editRegInfo"] = {
	POST = function(store)
		return function(req, res, next)
			local init_password = req.body.init_password
			local showname = req.body.showname
			local client_secret = req.body.client_secret
			local access_token = req.body.access_token
			local redirect_uri = req.body.redirect_uri
			local token_type = req.body.token_type
			local refresh_token = req.body.refresh_token
			local consumers_id = req.body.consumers_id
			local expires_in = req.body.expires_in
			local scope = req.body.scope

			if not consumers_id then
				return return_res(res, nil, "参数不正确")
			end
			if init_password then
				if utils.check_is_chinese(init_password) then
					return return_res(res, nil, "初始密码不能为中文")
				end
				local update_res = store:update({
			        sql = "UPDATE "..CONST.TABLES.CONSUMERS.." SET `init_password`=? WHERE id=?",
			        params = { init_password, consumers_id }
			    })
			    if not update_res then
			    	return return_res(res, nil, "修改账户失败")
			    else
			    	-- 删除redis
			    	redis_store:del(redis_store:get_oauth2_consumers_by_args(':id:'..consumers_id))
			    end
			end

			-- 修改展示名称
			if showname then
				local update_res = store:update({
			        sql = "UPDATE "..CONST.TABLES.CONSUMERS.." SET `showname`=? WHERE id=?",
			        params = { showname, consumers_id }
			    })
			    if not update_res then
			    	return return_res(res, nil, "修改展示名称失败")
			    else
			    	-- 删除redis
			    	redis_store:del(redis_store:get_oauth2_consumers_by_args(':id:'..consumers_id))
			    end
			end

		    local credential_info = store:query({
                sql = "SELECT * FROM `"..CONST.TABLES.OAUTH2_CREDENTIALS.."` WHERE `consumer_id`=? LIMIT 1",
                params = { consumers_id }
            })
            local credential_id = credential_info[1]['id']


		    local update_res, err = store:update({
		        sql = "UPDATE "..CONST.TABLES.OAUTH2_CREDENTIALS.." SET `client_secret`=?, `redirect_uri`=? WHERE consumer_id=?",
		        params = { client_secret, redirect_uri, consumers_id }
		    })
		    if not update_res then
		    	return return_res(res, nil, "修改OAUTH2 CREDENTIAL失败")
		    else
		    	redis_store:del(redis_store:get_oauth2_credentials_by_args(":client_id:"..credential_info[1]['client_id']))
		    	redis_store:del(redis_store:get_oauth2_credentials_by_args(":consumer_id:"..consumers_id))
		    	redis_store:del(redis_store:get_oauth2_credentials_by_args(":id:"..credential_id))
		    end

		    --判断expires_in是否为纯数字
		    local expires_in = tonumber(expires_in)
		    if not expires_in then
		    	return return_res(res, nil, "失效时间必须为数字")
		    end

		    --替换scope中文逗号
		    scope = string.gsub(scope, "，", ",")

		    local update_res = store:update({
		        sql = "UPDATE "..CONST.TABLES.OAUTH2_TOKENS.." SET `access_token`=?, `token_type`=?, `refresh_token`=?, `expires_in`=?, `scope`=?, `created_time`=? WHERE credential_id=?",
		        params = { access_token, token_type, refresh_token, expires_in, scope, math.floor(ngx.now()), credential_id}
		    })
		    if not update_res then
		    	return return_res(res, nil, "修改OAUTH2 TOKEN失败")
		    else
		    	local token_info = model:get_oauth2_tokens_by_args(store, {credential_id=credential_id})
		    	for k, v in ipairs(token_info) do
		    		redis_store:del(redis_store:get_oauth2_token_by_tokencode(v.credential_id))	--v.access_token
		    	end
		    end
		    res:json({ success = true })
		end
	end,

	DELETE = function(store)
		return function(req, res, next)
			local consumer_id = tonumber(req.body.consumer_id)

			local t_sql = 'set autocommit=0;START TRANSACTION;'
			store:query({sql=t_sql})

			local del_cons_res = store:delete({
					sql = "delete from "..CONST.TABLES.CONSUMERS.." where `id`=?",
  					params = { consumer_id }
				})
			if not del_cons_res then
		    	return return_res(res, nil, "删除CONSUMERS失败")
		    else
		    	redis_store:del(redis_store:get_oauth2_consumers_by_args(':id:'..consumer_id))
		    end

		    local credential_info = store:query({
                sql = "SELECT * FROM `"..CONST.TABLES.OAUTH2_CREDENTIALS.."` WHERE `consumer_id`=? LIMIT 1",
                params = { consumer_id }
            })
            if #credential_info>0 then
	            local credential_id = credential_info[1]['id']

			    local del_cre_res = store:delete({
						sql = "delete from "..CONST.TABLES.OAUTH2_CREDENTIALS.." where `consumer_id`=?",
	  					params = { consumer_id }
					})
			    if not del_cre_res then
			    	return return_res(res, nil, "删除CREDENTIAL失败")
			    else
			    	-- 删除缓存内的数据
			    	local del_res = redis_store:del(redis_store:get_oauth2_credentials_by_args(":client_id:"..credential_info[1]['client_id']))
			    	if not del_res then ngx.log(ERR, "delete redis key"..":client_id:"..credential_info[1]['client_id']..' error!') end
			    	local del_res = redis_store:del(redis_store:get_oauth2_credentials_by_args(":consumer_id:"..consumer_id))
			    	if not del_res then ngx.log(ERR, "delete redis key"..":consumer_id:"..consumer_id..' error!') end
			    	local del_res = redis_store:del(redis_store:get_oauth2_credentials_by_args(":id:"..credential_id))
			    	if not del_res then ngx.log(ERR, "delete redis key"..":id:"..credential_id..' error!') end
			    end

			    local token_info = model:get_oauth2_tokens_by_args(store, {credential_id=credential_id})
			    for k, v in pairs(token_info) do 
				    local del_token_res = store:delete({
							sql = "delete from "..CONST.TABLES.OAUTH2_TOKENS.." where `id`=?",
		  					params = { v.id }
						})
				    if not del_token_res then
				    	return return_res(res, nil, "删除TOKEN失败")
				    else
				    	redis_store:del(redis_store:get_oauth2_token_by_tokencode(v.credential_id))	--v.access_token
				    end
				end

			    store:delete({
						sql = "delete from "..CONST.TABLES.OAUTH2_AUTHORIZATION_CODE.." where `credential_id`=?",
	  					params = { credential_id }
					})
			end

		    t_sql = 'COMMIT;set autocommit=1;'
		    store:query({sql=t_sql})

		    res:json({ success = true })
		end
	end
}

---------------------------------------------------------------------------------------分割线----------------------------------------------------------------------------------

--添加应用 判断username是否存在							3
API["/api/oauth2/consumers/:username"] = {
    POST = function(store)
        return function(req, res, next)
        	local result = false
            local name = req.body.name
            if not name then
            	return return_res(res, nil, '账户名称为空')
            end
            local rule_id = req.body.rule_id
            if not rule_id then
            	return return_res(res, nil, '规则id为空')
            end
            local redirect_uri = req.body.redirect_uri
            --consumer id or name
            local username = req.body.username
            --添加开发者帐号+添加应用
            local data = model:save_consumer_oauth2(store, username, redirect_uri, name, rule_id)
            return return_res(res, data, '添加账户失败')
        end
    end
}

--模拟用户授权，获取回调码
API["/api/oauth2/authorize"] = {
	POST = function(store)
		return function(req, res, next)
			-- local response_type = req.body.response_type
			-- local scope = req.body.scope or "all"
			--添加授权的用户
			-- local authenticated_userid = req.body.authenticated_userid
			--Authorization: Basic
			-- local authorization_header = ngx.req.get_headers()["authorization"]
			local response_params = access:authorize(store, nil)
			return return_res(res, response_params, 'get oauth2 code error')
		end
	end
}

--获取两码，完成初次认证 refresh token
-- API["/api/oauth2/refresh_token"] = {
-- 	POST = function(store)
-- 		return function(req, res, next)
-- 			local client_id = req.body.client_id
-- 			local client_secret = req.body.client_secret
-- 			local grant_type = "refresh_token"
-- 			local refresh_token = req.body.refresh_token
-- 			local response_params, invalid_client_properties = access:issue_token(store, {	client_id=client_id, 
-- 																client_secret=client_secret,
-- 																grant_type=grant_type,
-- 																refresh_token=refresh_token})
-- 			-- Sending response in JSON format
-- 		  	return responses.send(
-- 		            response_params[ERROR] and (invalid_client_properties and invalid_client_properties.status or 400) or 200, 
-- 		            response_params, 
-- 		            { ["cache-control"]="no-store", ["pragma"]="no-cache", ["www-authenticate"]=invalid_client_properties and invalid_client_properties.www_authenticate }
-- 		    )
-- 			--return return_res(res, response_params, 'get oauth2 token error')
-- 		end
-- 	end
-- }



return API