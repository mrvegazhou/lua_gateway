local ipairs = ipairs
local pairs = pairs
local type = type
local pcall = pcall
local string_lower = string.lower
local printable = require "agw.utils.printable"
local lor = require("lor.index")

local function load_plugin_api(plugin, dashboard_router, store, conf)
    local plugin_api_path = "agw.plugins." .. plugin .. ".api"
    -- local ok, plugin_api = pcall(require, plugin_api_path)
    -- if not ok or not plugin_api or type(plugin_api) ~= "table" then
    --     ngx.log(ngx.ERR, "[plugin's api load error], plugin_api_path:", plugin_api_path)
    --     return
    -- end
    local plugin_api = require(plugin_api_path)
    for uri, api_methods in pairs(plugin_api) do
        if type(api_methods) == "table" then
            for method, func in pairs(api_methods) do
                local m = string_lower(method)
                if m == "get" or m == "post" or m == "put" or m == "delete" then
                    dashboard_router[m](dashboard_router, uri, func(store, conf))
                end
            end
        end
    end
end

return function(config, store)
    local dashboard_router = lor:Router()
    local redis_store = require("agw.store.redis_store")(config)

    --local redis_store = redis_db:new(config)
    dashboard_router:get("/", function(req, res, next)
        --- 全局信息
        -- 当前加载的插件，开启与关闭情况
        -- 每个插件的规则条数等
        local data = {}
        local plugins = config.plugins
        data.plugins = plugins

        local plugin_configs = {}
        for i, v in ipairs(plugins) do
            local tmp = {
                enable = redis_store:get(v .. ".enable"),
                name = v,
                active_rule_count = 0,
                inactive_rule_count = 0
            }
            local plugin_rules = redis_store:get_json(v .. ".rules")
            if type(plugin_rules) == "table" then
                if plugin_rules then
                    for j, r in ipairs(plugin_rules) do
                        if r.enable == true then
                            tmp.active_rule_count = tmp.active_rule_count + 1
                        else
                            tmp.inactive_rule_count = tmp.inactive_rule_count + 1
                        end
                    end
                end
            end
            plugin_configs[v] = tmp
        end
        data.plugin_configs = plugin_configs
        res:render("index", data)
    end)

    dashboard_router:get("/status", function(req, res, next)
        res:render("status")
    end)

    dashboard_router:get("/oauth2", function(req, res, next)
        res:render("oauth2/oauth2")
    end)

    --- 加载其他"可用"插件API
    local available_plugins = config.plugins
    if not available_plugins or type(available_plugins) ~= "table" or #available_plugins<1 then
        ngx.log(ngx.ERR, "no available plugins, maybe you should check `orange.conf`.")
    else
        for _, p in ipairs(available_plugins) do
            load_plugin_api(p, dashboard_router, store, config)
        end
    end

    return dashboard_router
end


