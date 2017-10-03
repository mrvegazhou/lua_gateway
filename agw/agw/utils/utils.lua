-- general utility functions.
local uuid = require("agw.lib.uuid")
local date = require("agw.lib.date")
local pl_stringx = require "pl.stringx"
local type = type
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local table_sort = table.sort
local table_concat = table.concat
local table_insert = table.insert
local string_gsub = string.gsub
local string_find = string.find
local string_format = string.format
local string_byte    = string.byte
local string_sub     = string.sub
local re_find    = ngx.re.find
local ceil = math.ceil

local _M = {}

--分页计算
function _M.show_pager(total, page, limit)
    local page_count = ceil(tonumber(total)/tonumber(limit))
    local next_page = tonumber(page)+1
    local last_page = tonumber(page)-1
    next_page = next_page<=page_count and next_page or page_count
    last_page = last_page>0 and last_page or 1
    return page_count, last_page, next_page
end

_M.split = pl_stringx.split
_M.strip = pl_stringx.strip

function _M.now()
    local n = date()
    local result = n:fmt("%Y-%m-%d %H:%M:%S")
    return result
end

function _M.trim(s) 
  return (string.gsub(s, "^%s*(.-)%s*$", "%1")) 
end

function _M.current_timetable()
    local n = date()
    local yy, mm, dd = n:getdate()
    local h = n:gethours()
    local m = n:getminutes()
    local s = n:getseconds()
    local day = yy .. "-" .. mm .. "-" .. dd
    local hour = day .. " " .. h
    local minute = hour .. ":" .. m
    local second = minute .. ":" .. s
    
    return {
        Day = day,
        Hour = hour,
        Minute = minute,
        Second = second
    }
end

function _M.current_second()
    local n = date()
    local result = n:fmt("%Y-%m-%d %H:%M:%S")
    return result
end

function _M.current_minute()
    local n = date()
    local result = n:fmt("%Y-%m-%d %H:%M")
    return result
end

function _M.current_hour()
    local n = date()
    local result = n:fmt("%Y-%m-%d %H")
    return result
end

function _M.current_day()
    local n = date()
    local result = n:fmt("%Y-%m-%d")
    return result
end

function _M.table_is_array(t)
    if type(t) ~= "table" then return false end
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then return false end
    end
    return true
end

--- Retrieves the hostname of the local machine
-- @return string  The hostname
function _M.get_hostname()
    local f = io.popen ("/bin/hostname")
    local hostname = f:read("*a") or ""
    f:close()
    hostname = string_gsub(hostname, "\n$", "")
    return hostname
end


--- Generates a random unique string
-- @return string  The random string (a uuid without hyphens)
function _M.random_string()
    return uuid():gsub("-", "")
end

function _M.new_id()
    return uuid()
end


--- Calculates a table size.
-- All entries both in array and hash part.
-- @param t The table to use
-- @return number The size
function _M.table_size(t)
    local res = 0
    if t then
        for _ in pairs(t) do
            res = res + 1
        end
    end
    return res
end

--- Merges two table together.
-- A new table is created with a non-recursive copy of the provided tables
-- @param t1 The first table
-- @param t2 The second table
-- @return The (new) merged table
function _M.table_merge(t1, t2)
    local res = {}
    for k,v in pairs(t1) do res[k] = v end
    for k,v in pairs(t2) do res[k] = v end
    return res
end

--- Checks if a value exists in a table.
-- @param arr The table to use
-- @param val The value to check
-- @return Returns `true` if the table contains the value, `false` otherwise
function _M.table_contains(arr, val)
    if arr then
        for _, v in pairs(arr) do
            if v == val then
                return true
            end
        end
    end
    return false
end

--- Checks if a table is an array and not an associative array.
-- *** NOTE *** string-keys containing integers are considered valid array entries!
-- @param t The table to check
-- @return Returns `true` if the table is an array, `false` otherwise
function _M.is_array(t)
    if type(t) ~= "table" then return false end
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil and t[tostring(i)] == nil then return false end
    end
    return true
end

--- Deep copies a table into a new table.
-- Tables used as keys are also deep copied, as are metatables
-- @param orig The table to copy
-- @return Returns a copy of the input table
function _M.deep_copy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[_M.deep_copy(orig_key)] = _M.deep_copy(orig_value)
        end
        setmetatable(copy, _M.deep_copy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

function _M.table_dup(ori_tab)
    if type(ori_tab) ~= "table" then
        return ori_tab
    end
    local new_tab = {}
    for k, v in pairs(ori_tab) do
        if type(v) == "table" then
            new_tab[k] = _M.table_dup(v)
        else
            new_tab[k] = v
        end
    end
    return new_tab
end

local err_list_mt = {}

--- Add an error message to a key/value table.
-- If the key already exists, a sub table is created with the original and the new value.
-- @param errors (Optional) Table to attach the error to. If `nil`, the table will be created.
-- @param k Key on which to insert the error in the `errors` table.
-- @param v Value of the error
-- @return The `errors` table with the new error inserted.
function _M.add_error(errors, k, v)
    if not errors then errors = {} end

    if errors and errors[k] then
        if getmetatable(errors[k]) ~= err_list_mt then
            errors[k] = setmetatable({errors[k]}, err_list_mt)
        end

        table_insert(errors[k], v)
    else
        errors[k] = v
    end

    return errors
end

--- Try to load a module.
-- Will not throw an error if the module was not found, but will throw an error if the
-- loading failed for another reason (eg: syntax error).
-- @param module_name Path of the module to load (ex: kong.plugins.keyauth.api).
-- @return success A boolean indicating wether the module was found.
-- @return module The retrieved module.
function _M.load_module_if_exists(module_name)
    local status, res = pcall(require, module_name)
    if status then
        return true, res
        -- Here we match any character because if a module has a dash '-' in its name, we would need to escape it.
    elseif type(res) == "string" and string_find(res, "module '"..module_name.."' not found", nil, true) then
        return false
    else
        error(res)
    end
end

--获取服务器主机名
function _M.get_addr(socket_dns, hostname)
    if socket_dns then
        local ip, resolved = socket_dns.toip(hostname)
        local list_tab = {}
        for k, v in ipairs(resolved.ip) do
            table.insert(list_tab, v)
        end
        return list_tab
    else
        return nil
    end
end

--
local uuid_regex = "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
function _M.is_valid_uuid(str)
  if type(str) ~= 'string' or #str ~= 36 then return false end
  return re_find(str, uuid_regex, 'ioj') ~= nil
end

----- Checks whether a request is https or was originally https (but already terminated).
-- It will check in the current request (global `ngx` table). If the header `X-Forwarded-Proto` exists
-- with value `https` then it will also be considered as an https connection.
-- @param allow_terminated if truthy, the `X-Forwarded-Proto` header will be checked as well.
-- @return boolean or nil+error in case the header exists multiple times
function _M.check_https(allow_terminated)
    if ngx.var.scheme:lower() == "https" then
        return true
    end

    if not allow_terminated then
        return false
    end

    local forwarded_proto_header = ngx.req.get_headers()["x-forwarded-proto"]
    if tostring(forwarded_proto_header):lower() == "https" then
        return true
    end

    if type(forwarded_proto_header) == "table" then
        -- we could use the first entry (lower security), or check the contents of each of them (slow). So for now defensive, and error
        -- out on multiple entries for the x-forwarded-proto header.
        return nil, "Only one X-Forwarded-Proto header allowed"
    end

    return false
end


---------------------------------------------------------------------------balencer bengin---------------------------------------------------------------------------------------
function _M.null(e)
    return  e == nil or e == ngx.null
end

function _M.filename(filename)
    -- no "."
    if not string_find(filename, ".", 1, true) then
        return filename
    end

    -- ends with "."
    if string_byte(filename, -1) == string_byte(".") then
        return string_sub(filename, 1, -2)
    end

    return filename:match"(.*)%.(.+)"
end

function _M.basename(path)
    local dir, file = path:match"(.*/)(.*)"
    if #file == 0 then
        return dir
    end
    return dir, file
end

function _M.sorted_pairs(t, order)
    local keys = {}
    for k in pairs(t) do
        table_insert(keys, k)
    end

    if order then
        table_sort(keys, function(a, b) return order(t, a, b) end)
    else
        table_sort(keys)
    end

    local i = 0
    return function()
        i = i + 1
        if keys[i] then return keys[i], t[keys[i]] end
    end
end

function _M.check_is_chinese(s)
    local flag = false
    for k = 1, #s do
        local c = string.byte(s,k) 
        if c>127 then
           return true
        end
    end
    return flag
end

return _M
