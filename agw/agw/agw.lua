local config_loader = require("agw.utils.config_loader")
local utils = require("agw.utils.utils")
local logger = require("agw.utils.logger")
local printable = require("agw.utils.printable")
local redis_store = nil
local cjson = require("cjson")
local agw_config = ngx.shared.agw_config
local require = require
local ipairs = ipairs
local type = type
local pcall = pcall
local tostring = tostring
local table_insert = table.insert
local table_sort = table.sort

local common_model
local loaded_plugins = {}
-- 加载插件
local function load_node_plugins(config, store)
	ngx.log(ngx.DEBUG, "Discovering used plugins")
	local sorted_plugins = {}
	local plugins = config.plugins
	for _, v in ipairs(plugins) do
		local loaded, plugin_handler = utils.load_module_if_exists("agw.plugins." .. v .. ".handler")
		if not loaded then
            error("The following plugin is not installed: " .. v)
        else
        	ngx.log(ngx.DEBUG, "Loading plugin: " .. v)
        	table_insert(sorted_plugins, {
                name = v,
                handler = plugin_handler(store)
            })
        end
	end

	table_sort(sorted_plugins, function(a, b)
        local priority_a = a.handler.PRIORITY or 0
        local priority_b = b.handler.PRIORITY or 0
        return priority_a > priority_b
    end)

    return sorted_plugins, balancer_plugin
end

--- load data for agw and its plugins from MySQL
-- ${plugin}.enable
-- ${plugin}.rules
local function load_data_by_mysql(store, config)
	-- 查找enable --------------------------------------------------------------------优化
	local enables, err = common_model:get_metas(store)
    if err then
        ngx.log(ngx.ERR, "Load Meta Data error: ", err)
        os.exit(1)
    end
    if enables and type(enables) == "table" and #enables > 0 then
        for i, v in ipairs(enables) do
            redis_store:set(v.key, tonumber(v.value) == 1)
        end
    end

    local available_plugins = config.plugins
    for i, v in ipairs(available_plugins) do
    	if v ~= "stat" then
            common_model:save_configs_in_redis(store, v)
    	end
    end
end

-- ms 
local function now()
    return ngx.now() * 1000
end

-- ########################### Agw #############################
local Agw = {}

-- 执行过程:
-- 加载配置
-- 实例化存储store
-- 加载插件
-- 插件排序
function Agw.init(options)
	options = options or {}
	local store, config
	local status, err = pcall(
		function()
	        local conf_file_path = options.config
	        config = config_loader.load(conf_file_path)
	        store = require("agw.store.mysql_store")(config.store_mysql)
            --保存配置文件到共享内存agw_config, 在实在不能从参数中获取的全局配置文件，可以从全局变量中获取
            if agw_config then
                agw_config:set("agw_config", cjson.encode(config))
            end
	        loaded_plugins = load_node_plugins(config, store)
	        ngx.update_time()
	        config.agw_start_at = ngx.now()
	    end
	)
    
	if not status or err then
        ngx.log(ngx.ERR, "Startup error: " .. err)
        os.exit(1)
    end

    -- 给redis对象传递构造参数
    redis_store = require("agw.store.redis_store")(config)

    for _, plugin in ipairs(loaded_plugins) do
        if plugin.handler.init then
            plugin.handler:init(config)
        end
    end

    Agw.data = {
        store = store,
        config = config
    }
    return config, store
end

function Agw.init_worker(config)
    if not redis_store then
        -- 给redis对象传递构造参数
        redis_store = require("agw.store.redis_store")(config)
    end
    -- 必须放在agw_config被加载之前
    common_model = require("agw.plugins.common.models")
	-- 初始化定时器，清理计数器等
	if Agw.data and Agw.data.store and Agw.data.config.store == "mysql" then
		local worker_id = ngx.worker.id()
        if worker_id == 0 then
            local ok, err = ngx.timer.at(0, 
        									function(premature, store, config)
        										load_data_by_mysql(store, config)
        									end,
        									Agw.data.store, 
                                            Agw.data.config
                                        )
    		if not ok then
                ngx.log(ngx.ERR, "failed to create the timer: ", err)
                return
            end
        end
	end
	for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:init_worker()
    end

end

function Agw.redirect()
	ngx.ctx.AGW_REDIRECT_START = now()
	for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:redirect()
    end
    local now = now()
    ngx.ctx.AGW_REDIRECT_TIME = now - ngx.ctx.AGW_REDIRECT_START
    ngx.ctx.AGW_REDIRECT_ENDED_AT = now
end

function Agw.rewrite()
    ngx.ctx.AGW_REWRITE_START = now()

    for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:rewrite()
    end

    local now = now()
    ngx.ctx.AGW_REWRITE_TIME = now - ngx.ctx.AGW_REWRITE_START
    ngx.ctx.AGW_REWRITE_ENDED_AT = now
end

function Agw.access()
    ngx.ctx.AGW_ACCESS_START = now()

    for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:access(Agw.data.store)
    end

    local now = now()
    ngx.ctx.AGW_ACCESS_TIME = now - ngx.ctx.AGW_ACCESS_START
    ngx.ctx.AGW_ACCESS_ENDED_AT = now
    ngx.ctx.AGW_PROXY_LATENCY = now - ngx.req.start_time() * 1000
    ngx.ctx.ACCESSED = true
end

function Agw.header_filter()
end

function Agw.body_filter()
end

function Agw.log()
    for _, plugin in ipairs(loaded_plugins) do
        plugin.handler:log()
    end
end


function Agw.test(config)
    local tbl_util = require("agw.utils.tableutil")
    local t1 = {1,2,4}
    local t2 = {4,3,1}
    local tmp = tbl_util.intersections(t1, t2)
    print('\n=====tmp====='..printable.print_r(tmp)..'============\n')
end

return Agw