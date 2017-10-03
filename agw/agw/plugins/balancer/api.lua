local printable = require "agw.utils.printable"
local cjson = require "cjson"

local upstreams_api  = require "agw.plugins.balancer.upstreams.api"
local base           = require "agw.plugins.balancer.upstreams.base"
local lib_consul     = require "agw.store.consul" 

local model = require("agw.plugins.balancer.models")
local utils = require("agw.utils.utils")
local common_model = require("agw.plugins.common.models")
local get_body_data = ngx.req.get_body_data
local table_insert = table.insert
local state        = ngx.shared.state

local API = {}

local limit = 20

local hostname = require "agw.lib.get_host_name"

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

local function get_request_host_name(res, store, bid)
    local balancer_info = model:get_balancer_by_id(store, bid)
    if not balancer_info then
        return return_res(res, nil, "cann't find balancer data")
    end
    local host_name = cjson.decode(balancer_info[1]['value'])
    if not host_name['handle']['host'] then
        return return_res(res, nil, "cann't find balancer host name")
    end
    return host_name
end

local function save_updated_upstreams(conf, host_name)
    local lock
    lock, err = base.get_lock(base.UPDATED_CONSUL)
    if not lock then
        log(WARN, "failed to acquire the lock: ", err)
        return false, err
    end
    local updated_vals = lib_consul.get_updated_upstreams(conf, hostname)
    if updated_vals and type(updated_vals)=='table' then
        local flag = utils.table_contains(updated_vals, host_name)
        if not flag then
            table_insert(updated_vals, host_name)
        end
    else
        updated_vals = {host_name}
    end

    local update_consul_res, err = lib_consul.put_server_by_key(conf, "updated_upstreams/"..hostname, cjson.encode(updated_vals))
    base.release_lock(lock)
    return updated_vals
end

API["/api/upstreams/:upstream_name"] = {
	GET = function(store, conf)
        return function(req, res, next)
        	local upstream_name = req.params.upstream_name
        end
    end,

    POST = function(store, conf)
		return function(req, res, next)
			local upstream_name = req.params.upstream_name
			local body = get_body_data()
			if not body then
        		return res:json({success = false, msg = "body to big"})
    		end
    		body = cjson.decode(body)
    		if not body then
        		return res:json({success = false, msg = "decode body error"})
    		end
    		local ok, err = upstreams_api.update_upstream(upstream_name, {{ servers = body.servers}})
    		if not ok then
        		return ngx.HTTP_BAD_REQUEST, err
    		end

    		local callback = function(host, port)
		        local res = ngx.location.capture("/" .. port)
		        ngx.say(res.body)
		        return 1
		    end

    		local ok, err = upstreams_api.ready_ok(upstream_name, callback)
    		res:json({
                success = true,
                data = {}
            })
		end
	end,

	DELETE = function(store, conf)
		return function(req, res, next)
			local upstream_name = req.params.upstream_name
			local ok, err = upstreams_api.delete_upstream(upstream_name)
			if not ok then
		        res:json({
	                success = false,
	                data = {req=ngx.HTTP_BAD_REQUEST, err=err}
	            })
		    end
		    res:json({
                success = true,
                data = ngx.HTTP_OK
            })
		end
	end
}

-- 展示负载路由列表
API["/upstreams"] = {
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
            local total = model:get_balancers_total(store, args)
            data.total = total
            data.page = 1
            data.url = "/api/balancer/list"
            local page_count = math.ceil(tonumber(total)/tonumber(limit))
            data.page_count = page_count
            res:render("balancer/upstreams", data)
        end
    end
}

--停用和启用
API["/api/balancer/enable"] = {
    POST = function(store, conf)
        return function(req, res, next)
            local enable = req.body.enable
            if enable == "1" then enable = true else enable = false end

            local result = false

            local can_enable = "0"
            if enable then can_enable = "1" end

            local update_res = common_model:update_meta_enable(store, 'balancer', can_enable)
            if update_res then
                return_res(res, (enable == true and "开启路由负载成功" or "关闭路由负载成功"))
            else
                return_res(res, nil, (enable == true and "开启路由负载失败" or "关闭路由负载失败"))
            end
        end
    end
}

-- 获取consul中的服务列表
API["/api/balancer/consul_infos"] = {
    POST = function(store, conf)
        return function(req, res, next)
            local data = {}
            local services = lib_consul.get_consul_catalog_services(conf)
            local services_list = {}
            table_insert(services_list, ngx.var.server_addr)
            table_insert(services_list, ngx.var.hostname)
            for k, v in pairs(services) do
                if not string.find(k, "consul") then
                    local info = lib_consul.get_consul_catalog_services(conf, k)
                    table_insert(services_list, k..'--- Address:'..info[1].Address..', ServicePort:'..info[1].ServicePort..', ServiceID:'..info[1].ServiceID)
                end
            end
            data.services_list = services_list
            return res:json({success = true, data = data})
        end
    end
}

API["/api/balancer/list"] = {
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
            local enable = common_model:get_meta_config(store, 'balancer')
            data.enable = tonumber(enable.value)==1 and true or false
            -- 获取
            local args = {}
            if not key_name then
                args = {}
            else
                args = {{'key like %?%', key_name}}
            end
            local upstreams = model:get_balancers(store, args, page, limit)
            data.upstreams = upstreams
            return res:json({success = true, data = data})
        end
    end
}

API["/api/balancer/urls"] = {
    GET = function(store, conf)
        return function(req, res, next)
            local data = {}
            local page = req.query.page
            if not page then
                page = 1
            end
            data.page = page
            local bid = req.query.bid
            if not bid then
                return return_res(res, nil, "query params is error")
            end
            -- 获取page总数
            local total = model:get_balancer_urls_total(store, bid)
            local page_count, last_page, next_page = utils.show_pager(total, page, limit)
            data.page_count = page_count
            data.next_page = next_page
            data.last_page = last_page
            data.url = "/api/balancer/urls?bid="..bid..'&page='
            data.bid = bid
            -- 获取host
            local host_info = model:get_balancer_by_id(store, bid)
            if not host_info or #host_info==0 then
                res:render("404", {return_url='/upstreams', return_name='负载均衡反向代理信息列表'})
                return ngx.exit(ngx.OK)
            end
            local host_name = cjson.decode(host_info[1]['value'])
            host_name = host_name['handle']['host']
            local res_list, err = model:get_balancer_urls(store, bid, page, limit)
            for k, v in ipairs(res_list) do
                local status_name = '未知'
                if state then
                    local status_key = base.PEER_STATUS_PREFIX .. host_name..':'..v['host']..':'..v['port']
                    local state_val = state:get(status_key)
                    if state_val then
                        state_val = cjson.decode(state_val)
                        state_val = state_val['status']
                    end                    
                    if state_val==base.STATUS_OK then
                        status_name = '正常'
                    elseif state_val==base.STATUS_UNSTABLE then
                        status_name = '不稳定'
                    elseif state_val==base.STATUS_ERR then
                        status_name = '异常'
                    end
                end
                res_list[k]['status'] = status_name
            end
            data.res_list = res_list
            res:render("balancer/upstreams_list", data)
        end
    end,
    PUT = function(store, conf)
        return function(req, res, next)
            local url_id = req.body.url_id
            if not url_id then
                return return_res(res, nil, "query params is error")
            end
            -- 获取旧数据
            local old_url_info = model:get_balancer_url_info(store, url_id)
            if not old_url_info then
                return return_res(res, nil, "cann't find old data")
            end
            -- 获取host name
            local host_name = get_request_host_name(res, store, old_url_info[1]['b_id'])
            host_name = host_name['handle']['host']
            local tmp = {}
            local host = req.body.tmp_host
            local port = req.body.tmp_port
            local weight = req.body.tmp_weight
            local max_fails = req.body.tmp_max_fails
            local fail_timeout = req.body.tmp_fail_timeout
            local down = req.body.tmp_down
            local backup = req.body.tmp_backup
            if host then
                tmp['host'] = host
            end
            if port then
                tmp['port'] = tonumber(port)
            end
            if weight then
                tmp['weight'] = tonumber(weight)
            end
            if max_fails then
                tmp['max_fails'] = tonumber(max_fails)
            end
            if fail_timeout then
                tmp['fail_timeout'] = tonumber(fail_timeout)
            end
            if down==1 then
                tmp['down'] = 1
            end
            if backup==1 then
                tmp['backup'] = 1
            end

            -- 通过host和port判断是否重复
            local checked = model:get_balancer_url_info_by_args(store, {{'host=?', tmp['host']}, {'port=?', tmp['port']}})
            if next(checked) then
                return return_res(res, nil, "不能添加重复的url，请检查host和port")
            end

            local update_res = model:update_balancer_info_by_id(store, url_id, tmp)
            if not update_res then
                return return_res(res, nil, "update error")
            end
       
            -- 获取是否在consul中存在
            local flag, result = lib_consul.get_servers_by_key(conf, "upstreams/"..host_name, "upstreams")
            if not result then
                -- 如果没有key就创建空值key
                local create_flag, err = lib_consul.create_server_key(conf, "upstreams/"..host_name)

                if not create_flag then
                    return return_res(res, nil, "please check consul key :".."upstreams/"..host_name)
                end
            end

            local checked_on_consul = false
            if result['servers'] and #result['servers']>0 then
                for k, v in pairs(result['servers']) do
                    if v['host']==old_url_info[1]['host'] and v['port']==old_url_info[1]['port'] then
                        result['servers'][k] = tmp
                        checked_on_consul = true
                    end
                end
            end

            -- 如果consul不存在则添加进去
            if not checked_on_consul then
                if not result['servers'] then
                    result = {enable=true, servers={}}
                end
                table_insert(result['servers'], tmp)
            end

            -- 更新consul
            local consul_res, err = lib_consul.put_server_by_key(conf, "upstreams/"..host_name, cjson.encode(result))
            save_updated_upstreams(conf, host_name)
            --
            return return_res(res, tmp, nil)
        end
    end,
    POST = function(store, conf)
        return function(req, res, next)
            local url_id = req.body.url_id
            local data = {}
            local info = model:get_balancer_url_info(store, url_id)
            data.info = info
            return return_res(res, data, nil)
        end
    end,
    DELETE = function(store, conf)
        return function(req, res, next)
            local url_id = req.body.url_id
            if not url_id then
                return return_res(res, nil, "query params is error")
            end
            -- 数据库
            local balancer_url_info = model:get_balancer_url_info(store, url_id)
            if #balancer_url_info==0 then
                return return_res(res, nil, "url info is null")
            end
            local bid = balancer_url_info[1]['b_id']
            local res_del = model:del_balancer_info_by_id(store, url_id)
            if not res_del then
                return return_res(res, nil, "delete failed")
            else
                -- 获取host name
                local host_name = get_request_host_name(res, store, balancer_url_info[1]['b_id'])
                host_name = host_name['handle']['host']

                -- 获取是否在consul中存在
                if not conf then
                    return return_res(res, nil, "consul config is error")
                end
                local flag, result = lib_consul.get_servers_by_key(conf, "upstreams/"..host_name, "upstreams")
                if not result then
                    return return_res(res, nil, "consul has no key")
                else
                    for k, v in pairs(result['servers']) do
                        if v['host']==balancer_url_info[1]['host'] and v['port']==balancer_url_info[1]['port'] then
                            result['servers'][k] = nil
                        end
                    end
                    -- 更新consul
                    lib_consul.put_server_by_key(conf, "upstreams/"..host_name, cjson.encode(result))
                end
                save_updated_upstreams(conf, host_name)
                --
                return res:json({success = true})
            end
        end
    end
}

API["/api/balancer/addurl"] = {
    POST = function(store, conf)
        return function(req, res, next)
            -- 添加到内存的url信息
            local ngx_server_url_info = {}
            -- 查询负载规则的信息是否存在
            local bid = req.body.bid
            local balancer_info = model:get_balancer_by_id(store, tonumber(bid))
            local host_name
            if not balancer_info then
                return return_res(res, nil, "负载规则信息不存在")
            else
                local balancer_info_value = cjson.decode(balancer_info[1]['value'])
                if not balancer_info_value['handle']['host'] then
                    return return_res(res, nil, "cann't find balancer host name")
                end
                host_name = balancer_info_value['handle']['host']

                local host = req.body.tmp_host
                local port = tonumber(req.body.tmp_port)
                local weight = tonumber(req.body.tmp_weight)
                local max_fails = tonumber(req.body.tmp_max_fails)
                local fail_timeout = tonumber(req.body.tmp_fail_timeout)
                local down = req.body.tmp_down
                local backup = req.body.tmp_backup
                if not host then
                    return return_res(res, nil, "host不能为空")
                elseif not port then
                    return return_res(res, nil, "端口不能为空")
                elseif not weight then
                    weight = 0
                elseif not max_fails then
                    max_fails = 0
                elseif not fail_timeout then
                    fail_timeout = 0
                elseif not down then
                    down = 0
                elseif not backup then
                    backup = 0
                end
                -- 通过host和port判断是否重复
                local checked = model:get_balancer_url_info_by_args(store, {{'host=?', host}, {'port=?', port}})
                if #checked>0 then
                    return return_res(res, nil, "不能添加重复的url，请检查host和port")
                end
                
                ngx_server_url_info['host'] = host
                ngx_server_url_info['port'] = tonumber(port)
                if weight~=0 and type(weight)=='number' then
                    ngx_server_url_info['weight'] = weight
                end
                if max_fails~=0 and type(max_fails)=='number' then
                    ngx_server_url_info['max_fails'] = max_fails
                end
                if fail_timeout~=0 and type(fail_timeout)=='number' then
                    ngx_server_url_info['fail_timeout'] = fail_timeout
                end
                if down==1 then
                    ngx_server_url_info['down'] = 1
                end
                if backup==1 then
                    ngx_server_url_info['backup'] = 1
                end

                local tmp = {host=host, port=port, weight=weight, max_fails=max_fails, fail_timeout=fail_timeout, down=down, backup=backup, b_id=bid, created_time=math.floor(ngx.now())}
                local add_res = model:add_balancer_url_info(store, tmp)
                if not add_res then
                    return return_res(res, nil, "添加失败")
                end
                
                -- 获取是否在consul中存在
                if not conf['consul'] then
                    return return_res(res, nil, "consul config is error")
                end
                -- 获取consul的数据
                local flag, result = lib_consul.get_servers_by_key(conf, "upstreams/"..host_name, "upstreams")
                if not result then
                    -- 如果没有key就创建空值key
                    lib_consul.create_server_key(conf, "upstreams/"..host_name)
                    local result = {enable=true, servers={ngx_server_url_info} }
                    local flag = lib_consul.put_server_by_key(conf, "upstreams/"..host_name, cjson.encode(result))
                    if not flag then
                        return return_res(res, nil, "添加到consul失败")
                    end
                else
                    if not result['servers'] then
                        result = {enable=true, servers={}}
                    end
                    table_insert(result['servers'], ngx_server_url_info)
                    -- 更新consul
                    lib_consul.put_server_by_key(conf, "upstreams/"..host_name, cjson.encode(result))
                end
                -- 保存更新的host到consul的updated_upstreams值里
                save_updated_upstreams(conf, host_name)
                --
                return_res(res, {data = tmp})
            end
        end
    end
}


API["/api/balancer/configs"] = {
    PUT = function(store, conf)
        return function(req, res, next)
            local rule = req.body.rule
            rule = cjson.decode(rule)
            if not rule.id then
                return_res(res, nil, "update balancer to db error")
            end
            --获取旧数据
            local old_balancer_info = model:get_balancer_by_id(store, rule.id)
            if not old_balancer_info then
                return_res(res, nil, "balancer info is null")
            end
            local old_balancer_val = cjson.decode(old_balancer_info[1]['value'])
            local old_balancer_host = old_balancer_val['handle']['host']

            local new_rules = {handle={balancer_type={}}}
            local new_host_name
            local now_time = utils.now()
            local redis_tmp_enables = {}
            for i, v in pairs(rule) do
                if i=='enable' then
                    new_rules[i] = v
                elseif i=="balancer_type" or i=="host" or i=="code" or i=="log" then
                    if i=="balancer_type" then
                        for i2, v2 in pairs(v) do
                            new_rules['handle']['balancer_type'][i2] = v2
                        end
                    elseif i=='host' then
                        new_host_name = v
                        new_rules['handle']['host'] = v
                    else
                        new_rules['handle'][i] = v
                    end
                end
                --
            end

            --
            local update_res = model:update_balancer_config(store, rule.id, rule['key'], new_rules, now_time)
            if not update_res then
                return_res(res, nil, "update balancer to db error")
            end
            
            -- 更新规则列表缓存
            common_model:save_configs_in_redis(store, 'balancer')

            if new_host_name then
                local create_flag
                -- 转移url负载列表
                local flag, balancer_urls = lib_consul.get_servers_by_key(conf, "upstreams/"..old_balancer_host, "upstreams")
                if (type(balancer_urls)=='table' and #balancer_urls['servers']==0) or balancer_urls==false then
                    create_flag = lib_consul.create_server_key(conf, "upstreams/"..new_host_name)
                elseif type(balancer_urls)=='table' and #balancer_urls['servers']>0 then
                    create_flag = lib_consul.put_server_by_key(conf, "upstreams/"..new_host_name, balancer_urls)
                end
               
                if not create_flag then
                    return return_res(res, nil, "please check consul key :".."upstreams/"..new_host_name)
                end

                -- 删除balancer
                if new_host_name~=old_balancer_host then
                    lib_consul.del_servers_by_key(conf, old_balancer_host)
                end

                -- 删除updated_upstreams 旧key换新的
                local updated_vals = lib_consul.get_updated_upstreams(conf, hostname)
                local tmp_updated_vals = {}
                for key, val in pairs(updated_vals) do
                    if val~=new_host_name then
                        table_insert(tmp_updated_vals, val)
                    end
                end
                table_insert(tmp_updated_vals, new_host_name)
                local update_upstreams_res = lib_consul.put_server_by_key(conf, "updated_upstreams/"..hostname, cjson.encode(tmp_updated_vals))
            end

            return_res(res, {rules = new_rules})
        end
    end,
    
    POST = function(store, conf)
        return function(req, res, next)
            local rule = req.body.rule
            if not rule then
                return return_res(res, nil, "bad argument error")
            end
            rule = cjson.decode(rule)
            if not rule.key then
                return return_res(res, nil, "key is null error")
            end
            local new_rules = {handle={balancer_type={}}}
            local new_host_name
            local key = rule.key
            -- 判断是否有重复的key
            local add_info = model:get_balancers(store, {{'`key`=?', key}})
            if add_info and #add_info>0 then
                return return_res(res, nil, "添加相同的规则名称")
            end

            for i, v in pairs(rule) do
                if i=='enable' then
                    new_rules[i] = v
                elseif i=="balancer_type" or i=="host" or i=="code" or i=="log" then
                    if i=="balancer_type" then
                        for i2, v2 in pairs(v) do
                            new_rules['handle']['balancer_type'][i2] = v2
                        end
                    elseif i=='host' then
                        new_host_name = v
                        new_rules['handle']['host'] = v
                    else
                        new_rules['handle'][i] = v
                    end
                end
            end
            --
            local add_res = model:add_balancer_info(store, key, new_rules)
            if not add_res then
                return return_res(res, nil, "添加新规则失败")
            end
            -- 添加新的upstreams key到consul
            local add_consol_res = lib_consul.create_server_key(conf, "upstreams/"..new_host_name)
            if not add_consol_res then
                return return_res(res, nil, "添加新规则到consul失败")
            end
            return_res(res, {rule_id = add_res})
        end
    end,

    DELETE = function(store, conf)
        return function(req, res, next)
            local rule_id = req.body.rule_id
            if not rule_id then
                return return_res(res, nil, "请求参数错误")
            end
            -- 获取旧balancer信息
            local old_balancer_info = model:get_balancer_by_id(store, rule_id)
            local host_name = nil
            if not old_balancer_info or #old_balancer_info==0 then
                return return_res(res, nil, "请求参数错误")
            else
                old_balancer_info = cjson.decode(old_balancer_info[1]['value'])
                host_name = old_balancer_info['handle']['host']
            end
            
            local del_res = model:del_balancer_info(store, rule_id)
            if not del_res then
                return return_res(res, nil, "删除失败")
            else

                -- 删除url列表
                local del_urls_res = model:del_balancer_info_by_bid(store, rule_id)
                if not del_urls_res then
                    return return_res(res, nil, "删除urls失败")
                end

                -- 删除balancer
                lib_consul.del_servers_by_key(conf, host_name)

                -- 删除updated_upstreams key
                local updated_vals = lib_consul.get_updated_upstreams(conf, hostname)
                local tmp_updated_vals = {}
                for key, val in pairs(updated_vals) do
                    if val~=host_name then
                        table_insert(tmp_updated_vals, val)
                    end
                end
                lib_consul.put_server_by_key(conf, "updated_upstreams/"..hostname, cjson.encode(tmp_updated_vals))

                -- delete ngx share dict
                local dyconfig = require "agw.plugins.balancer.upstreams.dyconfig"
                dyconfig.do_delete_upstream(host_name)
            end
            return_res(res, {rule_id = rule_id})
        end
    end
}

-- 同步服务器信息到consul
API["/api/balancer/sync_servers"] = {
    POST = function(store, conf)
        return function(req, res, next)
            local servers_list = model:get_balancer_servers(store)
            local res_servers = {}
            local hostnames = {}
            for k, v in pairs(servers_list) do
                table_insert(res_servers, v['host_name'].."-"..v['ip'])
                table_insert(hostnames, v['host_name'])
            end
            local put_result = lib_consul.put_server_by_key(conf, "updated_upstream_servers",  cjson.encode(hostnames))
            if not put_result then
                return return_res(res, nil, "添加服务器信息到consul失败")
            else
                return return_res(res, {servers = table.concat(res_servers, '<br/>')})
            end
        end
    end
}

-- 同步服务器信息到consul
API["/api/balancer/clear_servers"] = {
    POST = function(store, conf)
        return function(req, res, next)
            local servers_list = model:get_balancer_servers(store)
            local servers_keys = lib_consul.get_upstream_keys(conf, "updated_upstreams")
            local delete_servers = {}
            local hostnames = {}
            for k, v in pairs(servers_keys) do
                for _, v1 in pairs(servers_list) do
                    if v~="config/balancer/updated_upstreams/"..v1['host_name'] then
                        table_insert(delete_servers, v1['host_name'])
                    end
                end
            end
            if #delete_servers>0 then
                for k, v in pairs(delete_servers) do
                    local delete_res = lib_consul.del_servers_by_key(conf, v, "updated_upstreams")
                    if not delete_res then
                        return return_res(res, nil, "删除失败~")
                    end
                end
            end
            return return_res(res, {servers = table.concat(delete_servers, '<br/>')})
        end
    end
}

return API