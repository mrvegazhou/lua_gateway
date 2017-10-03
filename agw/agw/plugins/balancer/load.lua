local cjson         = require "cjson.safe"
local consul = require "agw.store.consul"
local utils    = require "agw.utils.utils"
local printable    = require "agw.utils.printable"

local setmetatable  = setmetatable
local getfenv       = getfenv
local setfenv       = setfenv
local require       = require
local loadfile      = loadfile
local pcall         = pcall
local loadstring    = loadstring
local next          = next
local pairs         = pairs
local ipairs        = ipairs
local type          = type
local str_find      = string.find
local str_format    = string.format
local str_sub       = string.sub
local tab_insert    = table.insert
local localtime     = ngx.localtime
local timer_at      = ngx.timer.at
local md5           = ngx.md5
local log           = ngx.log
local ERR           = ngx.ERR
local INFO          = ngx.INFO
local WARN          = ngx.WARN
local load_dict     = ngx.shared.load

local SKEYS_KEY     = "lua:skeys"
local VERSION_KEY   = "lua:version"
local TIMER_DELAY   = 1
local CODE_PREFIX   = "update:"
local version_dict  = {}
local global_version

local _M = {}

local function load_syncer(premature)
	if premature then
        return
    end
    local version = load_dict:get(VERSION_KEY)
    if version and version ~= global_version then
    	local skeys = load_dict:get(SKEYS_KEY)
    	if skeys then
            skeys = cjson.decode(skeys)
        else
            skeys = {}
        end

        for key in pairs(version_dict) do
            if not skeys[key] then
                log(INFO, key, " unload from package")
                version_dict[key] = nil
                package.loaded[key] = nil
            end
        end

        for skey, sh_value in pairs(skeys) do
            local worker_version
            if type(version_dict[skey]) == "table" then
                worker_version = version_dict[skey]["version"]
            end
            if package.loaded[skey] and worker_version ~= sh_value.version then
                log(INFO, skey, " version changed")
                version_dict[skey] = nil
                package.loaded[skey] = nil
            end
        end

        global_version = version
    end

    local ok, err = timer_at(TIMER_DELAY, load_syncer)
    if not ok then
        log(ERR, "failed to create timer: ", err)
    end
end

function _M.create_load_syncer()
	global_version = load_dict:get(VERSION_KEY)
	local ok, err = timer_at(TIMER_DELAY, load_syncer)
	if not ok then
        log(ERR, "failed to create load_lua timer: ", err)
        return
    end
end

return _M