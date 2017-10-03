local utils = require "agw.utils.utils"
local url = require "socket.url"
local http = require "resty.http"
local CONST = require("agw.constants")
local cjson = require("cjson")
local agw_config = ngx.shared.agw_config
local redis_store = require("agw.store.redis_store")(cjson.decode(agw_config:get("agw_config")))
local socket = require "socket"
local md5 = require "md5"
local aes = require "resty.aes"
local uuid = require("agw.lib.uuid")
local table_insert = table.insert
local sub  = string.sub
local len  = string.len
local resty_sha256 = require("resty.sha256")
local str = require("resty.string")
local printable = require "agw.utils.printable"
local sub  = string.sub
local tonumber = tonumber

local iv = CONST.AES.IV
local key = CONST.AES.KEY

local function encode(s)
    local sha256 = resty_sha256:new()
    sha256:update(s)
    local digest = sha256:final()
    return str.to_hex(digest)
end

local function generate_client_id()
	local hostname = socket.dns.gethostname()
  	local uuid = uuid.gen20()
  	return md5.sumhexa(uuid..hostname)
end

local function generate_code()
	return utils.random_string()
end

local function generate_client_secret()
	return uuid()
end

local function validate_uris(v, t, column)
  if v then
    if #v < 1 then
      return false, "at least one URI is required"
    end
    for _, uri in ipairs(v) do
      local parsed_uri = url.parse(uri)
      if not (parsed_uri and parsed_uri.host and parsed_uri.scheme) then
        return false, "cannot parse '"..uri.."'"
      end
      if parsed_uri.fragment ~= nil then
        return false, "fragment not allowed in '"..uri.."'"
      end
    end
  end
  return true, nil
end

---------------------------------------------------------------------------------------分割线-----------------------------------------------------------------------------------

local _M = {}

function _M:get_meta_config(store)
	local res = store:query({
                sql = "SELECT `id`,`key`,`value`,`op_time` FROM "..CONST.TABLES.META.." WHERE `key`='oauth2.enable'", params={}
            })
	if not res then
		return nil
	else
		return res[1]
	end
end

function _M:get_oauth2_config(store, find_args)
	local sql = "SELECT `id`,`key`,`value`,`op_time` FROM "..CONST.TABLES.OAUTH2
	local params = {}
	if find_args and #find_args>0 then
		sql = sql.." WHERE "
		for key, value in ipairs(find_args) do
			sql = sql..value[1].." AND "
			table_insert(params, value[2])
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	sql = sql.." ORDER BY id ASC"
	return store:query({sql=sql, params=params})
end

--通过rule id获取配置信息
function _M:get_oauth2_config_by_id(store, rule_id)
	local res = store:query({
			sql = "SELECT `id`,`key`,`value`,`op_time` FROM "..CONST.TABLES.OAUTH2.." WHERE id=?",
			params={rule_id}
		})
	if not res then
		return nil
	else
		res[1]['value'] = cjson.decode(res[1]['value'])
		return res[1]
	end
end

--删除oauth2规则
function _M:del_oauth2_config(store, rule_id)
	return store:delete({
                sql = "delete from "..CONST.TABLES.OAUTH2.." where `id`=?",
                params = { rule_id }
    })
end

--update oauth2 config
function _M:update_oauth2_config(store, rule_id, rule, now_time)
	if not rule then
		return false, 'update oauth2 rule error'
	end
	rule.handle.credentials.provision_key = generate_code()
	local update_result = store:update({
                sql = "update "..CONST.TABLES.OAUTH2.." set `value`=?,`op_time`=? where `id`=?",
                params = { cjson.encode(rule), now_time, rule_id }
            })

	if not update_result then
        return false, "update oauth2 rules error when modifing"
    end
    return update_result
end

function _M:save_oauth2_config(store, rule)
	if type(rule) ~= "table" then
		return false, 'rule is not table type'
	end
	if next(rule)==nil then
		return false, 'rule is null'
	end
	if not rule.name then
		return false, 'name is null'
	end
	if not rule.handle.credentials then
		return false, 'credentials is null'
	end
	rule.handle.credentials.provision_key = generate_code()
	local add_res = store:insert({
					sql = "INSERT INTO "..CONST.TABLES.OAUTH2.."(`key`, `value`) VALUES( ?, ? )",
					params = { rule.name, cjson.encode(rule) }
				})
	if not add_res then
		return false, 'add rule error'
	end
	return rule
end

-- first del then update oauth2 rules to redis store
function _M:update_oauth2_redis_store_by_del(store, rule_id)
	local delete_result = self:del_oauth2_config(store, rule_id)
	if delete_result then

        local enable = self:get_meta_config(store)
        if not enable then
        	return false, "get oauth2 enable error"
        end
        --删除相关配置信息的账户
        --事务处理需要删除的账户授权信息
        local c_infos = store:query({sql="SELECT * FROM consumers WHERE rule_id=?", params={rule_id}})
        local consumer_keys = ''
        if c_infos and next(c_infos)~=nil then
	        for i, v in pairs(c_infos) do
	        	consumer_keys = consumer_keys..','..v['id']..','
	        end
	        consumer_keys = string.sub(consumer_keys, 0, string.len(consumer_keys)-1)
    	end

        local credential_keys = ''
        local client_ids = {}
        if consumer_keys then
        	local credential_infos = store:query({sql="SELECT id, client_id FROM oauth2_credentials WHERE consumer_id IN ("..consumer_keys..")"})
        	if credential_infos and next(credential_infos)~=nil  then
		        for i, v in pairs(credential_infos) do
		        	credential_keys = credential_keys..','..v['id']..','
		        	table_insert(client_ids, v['client_id'])
		        end
		        credential_keys = string.sub(credential_keys, 0, string.len(credential_keys)-1)
	    	end
        end

        local tokens = {}
        if credential_keys then
	        local token_infos = store:query({sql="SELECT credential_id, access_token FROM oauth2_tokens WHERE credential_id IN ("..credential_keys..")"})
			if token_infos and next(token_infos)~=nil  then
		        for i, v in pairs(token_infos) do
		        	table_insert(tokens, {access_token=v['access_token'], credential_id=v['credential_id']})
		        end
	    	end
	    end

        local t_sql = 'set autocommit=0;START TRANSACTION;'
        if consumer_keys then
        	t_sql = t_sql..'DELETE FROM consumers WHERE rule_id='..tonumber(rule_id)..'; DELETE FROM oauth2_credentials WHERE consumer_id IN ('..consumer_keys..');'
        end
        if credential_keys then
        	t_sql = t_sql..'DELETE FROM oauth2_tokens WHERE credential_id IN ('..credential_keys..');'
        end
        t_sql = t_sql..' COMMIT;set autocommit=1;'
        store:query({sql=t_sql})

        -- 删除缓存 表oauth2_credentials 键包含client_id的数据 涉及到access类的get_oauth2_credentials操作
        for _, client_id in pairs(client_ids) do
        	redis_store:del(redis_store:get_oauth2_credentials_by_clientid(client_id))
        end

        -- 删除缓存 表oauth2_token 键包含 redis_store:get_oauth2_token_by_tokencode(credential_id), 涉及到access类的
        for _, t in pairs(tokens) do
        	redis_store:del(redis_store:get_oauth2_token_by_tokencode(t['credential_id']))	--t['access_token']
        end

        return new_rules, enable.value
	else
		return false, "delete rule from db error"
	end
end

--停用和启动oauth2 **********************************
function _M:update_oauth2_enable(store, enable)
	local update_result = store:update({
        sql = "UPDATE "..CONST.TABLES.META.." SET `value`=? WHERE `key`=?",
        params = { enable, "oauth2.enable" }
    })

    if update_result then
    	-- agw.lua加载插件时会使用缓存
        local res = redis_store:set("oauth2.enable", tonumber(enable)==1)
        if not res then
        	return false, "update oauth2.enable on redis store error"
        end
    else
        return false, "update oauth2.enable on mysql store error"
    end
    return true
end
------------------------------------------------------------------------------------分割线----------------------------------------------------------------------------------
-- 注意redis只缓存rule_id或id的数据，否则redis添加维护很麻烦
function _M:get_consumers_by_args(store, find_args, page, limit, is_cache)
	local res
	local offset = ''
	if page and limit then
		offset = " LIMIT "..(tonumber(page)-1)*limit..", "..limit
	end

	local sql = "SELECT id, username, showname, custom_id, rule_id, init_password, create_time FROM "..CONST.TABLES.CONSUMERS..' '
	local params = {}
	local count = 0
	if find_args then
		sql = sql.." WHERE "
		for key, value in pairs(find_args) do
			sql = sql..key.."=? AND "
			table_insert(params, value)
			count = count + 1
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	--table.sort(find_args)
	local redis_key
	if count==1 and find_args['rule_id'] then
		redis_key = ':rule_id:'..find_args['rule_id']
	elseif count==1 and find_args['id'] then
		redis_key = ':id:'..find_args['id']
	end

	if redis_key and is_cache then
		--redis_store:del(redis_store:get_oauth2_consumers_by_args(redis_keys))
		res = redis_store:get_json(redis_store:get_oauth2_consumers_by_args(redis_key))
	end
	
	if not res then
		sql = sql.." ORDER BY id DESC "..offset
		res = store:query({sql=sql, params=params})
		if not res then
			return false, 'get oauth2 consumers error'
		else
			if redis_key and is_cache then
				redis_store:set_json(redis_store:get_oauth2_consumers_by_args(redis_key), res)
			end
		end
	end
	return res
end

function _M:del_consumer_and_credential(store, consumer_id, credential_id, client_id) 
	local del_cons_res = store:delete({
			sql = "delete from "..CONST.TABLES.CONSUMERS.." where `id`=?",
				params = { consumer_id }
		})
	if not del_cons_res then
    	return return_res(res, nil, "删除CONSUMERS失败")
    else
    	redis_store:del(redis_store:get_oauth2_consumers_by_args(':id:'..consumer_id))
    end
    local del_cre_res = store:delete({
			sql = "delete from "..CONST.TABLES.OAUTH2_CREDENTIALS.." where `consumer_id`=?",
				params = { consumer_id }
		})
    if not del_cre_res then
    	return return_res(res, nil, "删除CREDENTIAL失败")
    else
    	-- 删除缓存内的数据
    	local del_res = redis_store:del(redis_store:get_oauth2_credentials_by_args(":client_id:"..client_id))
    	if not del_res then ngx.log(ERR, "delete redis key"..":client_id:"..client_id..' error!') end
    	local del_res = redis_store:del(redis_store:get_oauth2_credentials_by_args(":consumer_id:"..consumer_id))
    	if not del_res then ngx.log(ERR, "delete redis key"..":consumer_id:"..consumer_id..' error!') end
    	local del_res = redis_store:del(redis_store:get_oauth2_credentials_by_args(":id:"..credential_id))
    	if not del_res then ngx.log(ERR, "delete redis key"..":id:"..credential_id..' error!') end
    end
end

-- 管理consumers表的redis缓存数据 添加，修改
function _M:update_consumers_redis(key, key_val, value, op)
	local redis_key
	if key=='id' then
		redis_key = redis_store:get_oauth2_consumers_by_args(':id:'..key_val)
		redis_store:set_json(redis_store:get_oauth2_consumers_by_args(redis_key), value)
	elseif key=='rule_id' then
		redis_key = redis_store:get_oauth2_consumers_by_args(':rule_id:'..key_val)
		local consumers = redis_store:get_json(redis_key)
		if op=='update' then
			local tmp = utils.table_dup(consumers)
			for k, v in pairs(tmp) do
				if v.id==key_val then
					consumers[k] = nil
				end
			end
			table_insert(consumers, value)
		elseif op=='add' then
			table_insert(consumers, value)
		end
	end
	redis_store:set_json(redis_key, value)
end

--获取总数
function _M:get_consumers_count(store, find_args)
	local sql = "SELECT count(*) as total FROM "..CONST.TABLES.CONSUMERS
	local params = {}
	if find_args then
		sql = sql.." WHERE "
		for key, value in pairs(find_args) do
			sql = sql..key.."=? AND "
			table_insert(params, value)
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	local res = store:query({sql=sql, params=params})
	if res then
		return res[1]['total']
	end
	return 0
end

function _M:save_consumer_oauth2(store, user_name, redirect_uri, name, rule_id, showname)

	if not rule_id or not user_name then
		return nil, 'params is null, please check them'
	end
	if showname==nil then
		showname = ''
	end
	local username = utils.trim(user_name)
	local res_info = store:query({
                sql = "SELECT `id`,`username`,`custom_id`,`rule_id` FROM `"..CONST.TABLES.CONSUMERS.."` WHERE `username`=?",
                params = { username }
            })
	local consumer_id
	local custom_id
	local query_execution_time = 0
	local reg_execution_time = 0

	if res_info==nil or next(res_info)==nil then
		--查看是否存在用户在vcg
		local httpc = http.new()

		local start_time = ngx.now()
		local res, err = httpc:request_uri( CONST.VCG_HTTP_URLS.VCG_USER_GET.."&loginName="..username )

		local end_time = ngx.now()
		query_execution_time = end_time-start_time
		if not res then
			return nil, "request user center fail:"..err
		end
		local body = cjson.decode(res.body)
		--进行注册
		if body.status=='200' and body.data==cjson.null then
			--{"password":"string", "status":0, "userFrom":"api", "userName":"string", "userType":0}
			local password = uuid.gen8()

			local start_time = ngx.now()
			local res_reg, err_reg = httpc:request_uri( CONST.VCG_HTTP_URLS.VCG_USER_REGISTER, 
														{ 	method="POST", 
															body="{\"password\":\""..password.."\", \"userFrom\":30, \"userType\":1, \"userName\":\""..username.."\"}",
															headers = {["Content-Type"] = "application/json"}
														}
													)
			local end_time = ngx.now()
			reg_execution_time = end_time-start_time
			--判断注册到用户中心是否有问题
			if res_reg==nil or err_reg then
				return nil, "register new user fail:"..err_reg
			end
			local res_reg_body = cjson.decode(res_reg.body)
			if res_reg.status ~= 200 then
				return nil, 'register user error:'..err_reg
			elseif not res_reg_body.error and res_reg_body.userId then
				local aes_128_cbc_with_iv = assert(aes:new(key, nil, aes.cipher(128, "cbc"), {iv=iv, method=nil}))
				password = ngx.encode_base64(aes_128_cbc_with_iv:encrypt(password))	--aes_128_cbc_with_iv:decrypt(ngx.decode_base64(encrypted)) 解密

				custom_id = res_reg_body.userId
				
				--添加用户信息到consumer
				local res_consumer, err = store:insert({ 
					sql = "INSERT INTO "..CONST.TABLES.CONSUMERS.."(`username`, `custom_id`, `rule_id`, `init_password`, `showname`) VALUES( ?, ?, ?, ?, ? )",
					params = { username, custom_id, rule_id,  password, showname}
				})
				if res_consumer then
					consumer_id = res_consumer.insert_id
				end
			else
				return nil, 'register user error'
			end
		elseif body.data and body.data.userId then
			custom_id = body.data.userId
			--用户中心存在数据 存储信息到consumers
			local insert_consumer_res = store:insert({
														sql = "INSERT INTO "..CONST.TABLES.CONSUMERS.." (`username`, `custom_id`, `rule_id`, `showname`) VALUES(?, ?, ?, ?) ",
														params = { username, custom_id, rule_id, showname }
													})
			if not insert_consumer_res then
				return nil, 'insert consumers error'
			end
			-- 修改consumers表缓存
			consumer_id = insert_consumer_res.insert_id
		else
			return nil, 'Get from user center fail:'..body.error
		end
		-- 为res_info赋值
		res_info = {{id=consumer_id, custom_id=custom_id, username=username, password=password}}
	else
		consumer_id = res_info[1].id
		custom_id = res_info[1].custom_id
	end
	--添加应用
	local client_id
	local client_secret = generate_client_secret()
	local flag = true
	local i = 0
	repeat
		client_id = generate_client_id()
		--查询client_id是否重复
		local tmp_res = store:query({ 
			sql = "SELECT id, client_id FROM "..CONST.TABLES.OAUTH2_CREDENTIALS.." WHERE client_id=?",
			params = { client_id }
		})
		flag = false
		if not tmp_res then
			flag = false
		end
		i = i + 1
		if i>100 then
			flag = false
		end
	until( flag==false )
	--先判断是否存在consumer_id
	local credential_res = store:query({
                sql = "SELECT `id` FROM `"..CONST.TABLES.OAUTH2_CREDENTIALS.."` WHERE `consumer_id`=?",
                params = { res_info[1].id }
            })
	if credential_res and next(credential_res)~=nil then
		return nil, '已经存在授权用户'
	end

	local res = store:insert({
		sql = "INSERT INTO "..CONST.TABLES.OAUTH2_CREDENTIALS.." (`name`, `consumer_id`, `client_id`, `client_secret`, `redirect_uri`) VALUES(?, ?, ?, ?, ?) ",
		params = { name=='' and 'api' or name, res_info[1].id, client_id, client_secret, redirect_uri }
	})
	if res then
		return { 	credentials_id=res.insert_id, 
					consumer_id=consumer_id, 
					custom_id=custom_id, 
					client_id=client_id, 
					client_secret=client_secret, 
					redirect_uri=redirect_uri,
					query_reg_execution_time=query_execution_time+reg_execution_time
				}
	else
		return nil, "save consumer error"
	end
end 


--	通过client id获取 ********************************************
function _M:get_oauth2_credentials(store, client_id)
	if not client_id then
		return nil, "client_id error"
	end
	local res
	res = redis_store:get_json(redis_store:get_oauth2_credentials_by_args(":client_id:"..client_id))
	if not res or #res==0 then
		res = store:query({
			sql = "SELECT  id, client_id, client_secret, redirect_uri, consumer_id, created_time FROM "..CONST.TABLES.OAUTH2_CREDENTIALS.." WHERE client_id=?",
			params = { client_id }
		})
		if not res or #res==0 then
			return nil
		else
			redis_store:set_json(redis_store:get_oauth2_credentials_by_args(":client_id:"..client_id), res)
		end
	end
	return res
end

-- 只缓存key包含consumer_id和主键id的数据 **************************************
function _M:get_oauth2_credentials_by_args(store, find_args)
	local res
	local sql = "SELECT id, client_id, client_secret, redirect_uri, consumer_id, created_time FROM "..CONST.TABLES.OAUTH2_CREDENTIALS
	local params = {}
	local redis_keys
	local count = 0
	if find_args then
		sql = sql.." WHERE "
		for key, value in pairs(find_args) do
			sql = sql..key.."=? AND "
			table_insert(params, value)
			count = count + 1
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	
	if count==1 and find_args['id'] then
		redis_keys = ":id:"..find_args['id']
	elseif count==1 and find_args['consumer_id'] then
		redis_keys = ":consumer_id:"..find_args['consumer_id']
	end
	if redis_keys then
		res = redis_store:get_json(redis_store:get_oauth2_credentials_by_args(redis_keys))
	end
	if not res then
		res = store:query({sql=sql, params=params})
		if not res then
			return false, 'get oauth2 credentials error'
		else
			if redis_keys then
				redis_store:set_json(redis_store:get_oauth2_credentials_by_args(redis_keys), res)
			end
		end
	end
	return res
end

--通过in查询client id列表
function _M:get_oauth2_credentials_by_in(store, in_args, page, limit)
	if next(in_args)==nil or not in_args['key'] or not in_args['val'] then
		return nil, 'args is error'
	end

	local offset = ''
	if page and limit then
		offset = " LIMIT "..(tonumber(page)-1)*limit..", "..page
	end
	local in_str = ''
	for k, v in pairs(in_args['val']) do
		in_str = in_str..tonumber(v)..','
	end
	
	in_str = sub(in_str, 1, -2)

	local res = store:query({
				sql="SELECT id, client_id, client_secret, redirect_uri, consumer_id, name, created_time FROM "..CONST.TABLES.OAUTH2_CREDENTIALS.." WHERE "..in_args['key'].." IN ("..in_str..") ".." ORDER BY id DESC "..offset,
	})
	if not res then
		return nil, "list is null"
	end
	local res_list = {}
	for k, v in pairs(res) do
		res_list[v.id] = v
	end 
	return res_list
end

function _M:save_oauth2_authorization_codes(store, credential_id, authenticated_userid, scope)
	local consumer_res = store:query({
		sql = "SELECT id FROM "..CONST.TABLES.CONSUMERS.." WHERE custom_id=?",
		params = { authenticated_userid }
	})
	if not consumer_res then
		return nil, "authenticated_userid error"
	end
	local code = encode(generate_code())
	local res = store:insert({
		sql = "INSERT INTO "..CONST.TABLES.OAUTH2_AUTHORIZATION_CODE.." (`code`, `credential_id`, `authenticated_userid`, `scope`) VALUES(?, ?, ?, ?) ",
		params = { code, credential_id, authenticated_userid, scope~='' and scope or "all" }
	})
	if not res then
		return nil, 'save authorization code error' 
	end
	return { id=res.insert_id, code=code, authenticated_userid=authenticated_userid, credential_id=credential_id }
end

function _M:get_oauth2_authorization_codes(store, find_args)
	local sql = "SELECT id,code,authenticated_userid,credential_id,scope,created_time FROM "..CONST.TABLES.OAUTH2_AUTHORIZATION_CODE
	local params = {}
	if find_args then
		sql = sql.." WHERE "
		for key, value in pairs(find_args) do
			sql = sql..key.."=? AND "
			table_insert(params, value)
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	local res = store:query({sql=sql, params=params})
	if not res then
		return nil, 'get oauth2 authorization code error'
	else
		return res
	end
end

function _M:update_oauth2_tokens(store, old_token)
	if not old_token or #old_token==0 then
		return false, "update oauth2 token error when modifing"
	end
	
	local access_token = encode(utils.random_string())
	old_token[1]['access_token'] = access_token

	local refresh_token = utils.random_string()
	old_token[1]['refresh_token'] = refresh_token

	local created_time = math.floor(ngx.now())
	old_token[1]['created_time'] = created_time

	local update_result = store:update({
                sql = "update "..CONST.TABLES.OAUTH2_TOKENS.." set `access_token`=?, `refresh_token`=?, `created_time`=? where `id`=?",
                params = { access_token, refresh_token, created_time, old_token[1]['id'] }
            })

	if not update_result then
        return false, "update oauth2 token error when modifing"
    end
    --缓存
    redis_store:set_json(redis_store:get_oauth2_token_by_tokencode(old_token[1]['credential_id']), old_token, 7200)
    return old_token[1]
end

--在生成refresh token和access token的时候会调用事物处理
function _M:transaction_del_save_token(store, is_authorization_code, delete_id, credential_id, authenticated_userid, expires_in, refresh_token, scope, token_id)
	if (is_authorization_code==nil) or (delete_id==nil) or (not credential_id) or (not authenticated_userid) or (not refresh_token) or (not expires_in) then
		return false, "error"
	end
	local access_token = encode(utils.random_string())
	local now_time = math.floor(ngx.now())
	local token_type = "bearer"
	if is_authorization_code==true then
		local params_tbl = {}
		local t_sql = 'set autocommit=0;START TRANSACTION;'
		t_sql = t_sql.." delete from "..CONST.TABLES.OAUTH2_AUTHORIZATION_CODE.." where `id`=?;"
		table_insert(params_tbl, delete_id)

		t_sql = t_sql.."INSERT INTO "..CONST.TABLES.OAUTH2_TOKENS.." (`credential_id`, `access_token`, `token_type`, `refresh_token`, `expires_in`, `authenticated_userid`, `scope`, `created_time`) VALUES(?, ?, ?, ?, ?, ?, ?, ?);"
		table_insert(params_tbl, credential_id)
		
		table_insert(params_tbl, access_token)
		table_insert(params_tbl, token_type)
		table_insert(params_tbl, refresh_token)
		table_insert(params_tbl, expires_in)
		table_insert(params_tbl, authenticated_userid)
		table_insert(params_tbl, scope~='' and scope or 'all')
		table_insert(params_tbl, now_time)

		t_sql = t_sql..' COMMIT;set autocommit=1;'
		store:query({sql=t_sql, params=params_tbl})
	else
		--如果是刷新token操作
		local update_result = store:update({
                sql = "update "..CONST.TABLES.OAUTH2_TOKENS.." set `refresh_token`=?,`access_token`=?,`created_time`=?  where `credential_id`=?",
                params = { refresh_token, access_token, now_time, delete_id }
        })
        if update_result then
        	--更新缓存
        	redis_store:set_json(redis_store:get_oauth2_token_by_tokencode(delete_id), {
        		{	expires_in=expires_in, 
        			authenticated_userid=authenticated_userid, 
        			id=token_id, 
        			credential_id=credential_id, 
        			refresh_token=refresh_token, 
        			access_token=access_token,
        			created_time=now_time,
        			scope=scope,
        			token_type=token_type
        		}
        	})
        end
	end
	
	return { 	credential_id=credential_id, 
				access_token=access_token, 
				token_type=token_type,
				refresh_token=refresh_token, 
				expires_in=expires_in, 
				authenticated_userid=authenticated_userid, 
				scope=scope or 'all'	}
end

function _M:save_oauth2_tokens(store, credential_id, authenticated_userid, expires_in, refresh_token, scope)
	if not refresh_token then
		refresh_token = utils.random_string()
	end
	local access_token = encode(utils.random_string())
	local res = store:insert({
		sql = "INSERT INTO "..CONST.TABLES.OAUTH2_TOKENS.." (`credential_id`, `access_token`, `token_type`, `refresh_token`, `expires_in`, `authenticated_userid`, `scope`, `created_time`) VALUES(?, ?, ?, ?, ?, ?, ?, ?) ",
		params = { 	credential_id, 
					access_token, 
					"bearer", 
					refresh_token, 
					expires_in, 
					authenticated_userid, 
					scope~='' and scope or 'all',
					math.floor(ngx.now()) }
	})

	if not res then
		return nil, 'save oauth2 token error'
	end
	return { 	id=res, 
				credential_id=credential_id, 
				access_token=access_token, 
				token_type="bearer",
				refresh_token=refresh_token, 
				expires_in=expires_in, 
				authenticated_userid=authenticated_userid, 
				scope=scope or 'all'	}
end

function _M:delete_oauth2_code(store, id)
	return store:delete({
					sql = "delete from "..CONST.TABLES.OAUTH2_AUTHORIZATION_CODE.." where `id`=?",
  					params = { id }
  	})
end

--删除token  并删除redis缓存，包括token为key的缓存 ***************************
function _M:delete_oauth2_token(store, credential_id)
	if not credential_id then
		return false, 'delete token error'
	end
	local del_res = store:delete({
					sql = "delete from "..CONST.TABLES.OAUTH2_TOKENS.." where `credential_id`=?",
  					params = { credential_id }
  	})
  	if del_res then
  		redis_store:del(redis_store:get_oauth2_token_by_tokencode(credential_id))	--token_info.access_token
  	end
  	return del_res
end

function _M:get_oauth2_config_by_rule_id(store, rule_id)
	res = store:query({
				sql="SELECT `id`, `key`, `value`, `op_time` FROM `"..CONST.TABLES.OAUTH2.."` WHERE `id`=?", 
				params={ rule_id }
			})
	if next(res)==nil then
		return false, "cann't find result from OAUTH2 table"
	end
	
	local tmp_rule = {}
	res[1]['value'] = cjson.decode(res[1]['value'])
	for key, val in pairs(res[1]) do
		if key=='id' or key=='key' or key=='op_time' then
			tmp_rule[key] = val
		elseif key=='value' then
			for i, v in pairs(val) do
				if i=='name' or i=='enable' then
					tmp_rule[i] = v
				elseif i=="handle" then
					for i2, v2 in pairs(v) do
						if i2=="log" or i2=="code" then
							tmp_rule[i2] = v2
						elseif i2=="credentials" then
							for i3, v3 in pairs(v2) do
								if i3=="enable_authorization_code" or i3=="enable_client_credentials" or i3=="enable_implicit_grant" or i3=="enable_password_grant" 
									or i3=="token_expiration" or i3=="accept_http_if_already_terminated" or i3=="hide_credentials" or i3=='provision_key' then
									tmp_rule[i3] = v3
								end
							end
						end
					end
				end
			end
		end
	end
	return tmp_rule
end

function _M:update_config_info(store, rule_id)
	local tmp_rule = self:get_oauth2_config_by_rule_id(store, rule_id)
	redis_store:set_json(redis_store:oauth2_rule_by_ruleid(rule_id), tmp_rule)
end

--从插件表中载入信息
--获取的结果为一维的数据
function _M:load_oauth2_plugin_info(store, rule_id)
	local res
	--redis_store:del(redis_store:oauth2_rule_by_ruleid(rule_id))
	res = redis_store:get_json(redis_store:oauth2_rule_by_ruleid(rule_id))
	if not res or #res==0 or next(res)==nil then
		local tmp_rule = self:get_oauth2_config_by_rule_id(store, rule_id)
		redis_store:set_json(redis_store:oauth2_rule_by_ruleid(rule_id), tmp_rule)
		return tmp_rule
	else
		return res
	end
end

function _M:load_oauth2_plugin_info_by_client_id(store, client_id)
	local credentials_info = self:get_oauth2_credentials(store, client_id)
	if not credentials_info or #credentials_info==0 then
		return false, "get client credentials error"
	end
	local consumer_id = credentials_info[1].consumer_id
	local consumer_info = self:get_consumers_by_args(store, {id=consumer_id}, nil, nil, true)
	if next(consumer_info)==nil then
		return false, "get consumer error"
	end
	local rule_id = consumer_info[1].rule_id
	return self:load_oauth2_plugin_info(store, rule_id)
end

--通过access_token获取oauth2_tokens信息
function _M:get_oauth2_tokens_by_token(store, client_id, not_set_redis, ttl)
	if not client_id then
		return nil, "client_id is null"
	end
	local credential_info = _M:get_oauth2_credentials(store, client_id)
	if not credential_info or #credential_info==0 then
		return nil, "can't find credential info"
	end

	local res = nil
	if not not_set_redis then
		res = redis_store:get_json(redis_store:get_oauth2_token_by_tokencode(credential_info[1]['id']))	--access_token
	end
	if not res or #res==0 then
		res = store:query({
					sql="SELECT id, credential_id, access_token, token_type, refresh_token, expires_in, authenticated_userid, scope, created_time FROM "..CONST.TABLES.OAUTH2_TOKENS.." WHERE credential_id=?", 
					params={credential_info[1]['id']}
				})
		if not res or #res==0 then
			return false, 'get oauth2 token error'
		else
			if not not_set_redis then
				redis_store:set_json(redis_store:get_oauth2_token_by_tokencode(credential_info[1]['id']), res, ttl)	--access_token
			end
		end
	end
	
	return res, nil
end

--
function _M:get_oauth2_tokens_by_args(store, find_args)
	local sql = "SELECT id,credential_id,access_token,token_type,refresh_token,expires_in,authenticated_userid,scope,created_time FROM "..CONST.TABLES.OAUTH2_TOKENS
	local params = {}
	if find_args then
		sql = sql.." WHERE "
		for key, value in pairs(find_args) do
			sql = sql..key.."=? AND "
			table_insert(params, value)
		end
		sql = sub(sql, 0, len(sql)-4)
	end
	sql = sql.." ORDER BY id DESC "
	local res = store:query({sql=sql, params=params})
	if not res then
		return nil, 'get OAUTH2 TOKENS error'
	else
		return res
	end
end

function _M:get_oauth2_tokens_by_in(store, in_args, page, limit)
	if type(in_args)~="table" or not in_args or next(in_args)==nil then
		return nil, 'args is error'
	end
	if not in_args['key'] or not in_args['val'] then
		return nil, 'args key or val is error'
	end
	local offset = ''
	if page and limit then
		offset = " LIMIT "..(tonumber(page)-1)*limit..", "..page
	end
	local in_str = ''
	for k, v in pairs(in_args['val']) do
		in_str = in_str..v..','
	end
	in_str = sub(in_str, 1, -2)
	local res = store:query({
				sql="SELECT `id`, `credential_id`, `access_token`, `token_type`, `refresh_token`, `expires_in`, `authenticated_userid`, `scope`, `created_time` FROM "..CONST.TABLES.OAUTH2_TOKENS.." WHERE "..in_args['key'].." IN ("..in_str..") ".." ORDER BY id DESC "..offset,
	})
	if not res then
		return nil, "list is null"
	end
	local res_list = {}
	for k, v in pairs(res) do
		res_list[v.id] = v
	end 
	return res_list
end

return _M
