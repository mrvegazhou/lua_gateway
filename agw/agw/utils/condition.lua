local type = type
local string_format = string.format
local string_find = string.find
local string_lower = string.lower
local ngx_re_find = ngx.re.find
local _M = {}

function _M:judge_condition(real, operator, expected)
    if not real then
        ngx.log(ngx.ERR, string_format("assert_condition error: %s %s %s", real, operator, expected))
        return false
    end

    if operator == 'match' then
        if ngx_re_find(real, expected, 'isjo') ~= nil then
            return true
        end
    elseif operator == 'not_match' then
        if ngx_re_find(real, expected, 'isjo') == nil then
            return true
        end
    elseif operator == "=" then
        if type(real) == 'number' then
            expected = tonumber(expected)
        end
        if real == expected then
            return true
        end
    elseif operator == "!=" then
        if real ~= expected then
            return true
        end
    elseif operator == '>' then
        if real ~= nil and expected ~= nil then
            expected = tonumber(expected)
            real = tonumber(real)
            if real and expected and real > expected then
                return true
            end
        end
    elseif operator == '>=' then
        if real ~= nil and expected ~= nil then
            expected = tonumber(expected)
            real = tonumber(real)
            if real and expected and real >= expected then
                return true
            end
        end
    elseif operator == '<' then
        if real ~= nil and expected ~= nil then
            expected = tonumber(expected)
            real = tonumber(real)
            if real and expected and real < expected then
                return true
            end
        end
    elseif operator == '<=' then
        if real ~= nil and expected ~= nil then
            expected = tonumber(expected)
            real = tonumber(real)
            if real and expected and real <= expected then
                return true
            end
        end
    end

    return false
end

function _M:judge_type(condition_type, condition_value)
    if not condition_type then
        return false
    end

    local real

    if condition_type == "url" then
        real = ngx.var.uri
    elseif condition_type == "query" then
        local query = ngx.req.get_uri_args()
        if condition_value and string.find(condition_value, "=") then
            local t = {}
            for w in string.gmatch(condition_value, "([^'=']+)") do
                table.insert(t, w) 
            end
            real = query[t[1]]
        end
    elseif condition_type == "header" then
        local headers = ngx.req.get_headers()
        if condition_value and string.find(condition_value, "=") then
            local t = {}
            for w in string.gmatch(condition_value, "([^'=']+)") do
                table.insert(t, w) 
            end
            real = headers[t[1]]
        end
    elseif condition_type == "ip" then
        real = ngx.var.remote_addr
    elseif condition_type == "useragent" then
        real = ngx.var.http_user_agent
    elseif condition_type == "method" then
        local method = ngx.req.get_method()
        method = string_lower(method)
        -- if not expected or type(expected) ~= "string" then
        --     expected = ""
        -- end
        -- expected = string_lower(expected)
        real = method
    elseif condition_type == "referer" then
        real =  ngx.var.http_referer
    elseif condition_type == "host" then
        real =  ngx.var.host
    end

    return real
end

return _M
