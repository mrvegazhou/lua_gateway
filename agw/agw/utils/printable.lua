-- A metatable for pretty printing a table with key=value properties
--
-- Example:
--   {hello = "world", foo = "bar", baz = {"hello", "world"}}
-- Output:
--   "hello=world foo=bar, baz=hello,world"

local utils = require "agw.utils.utils"

local printable_mt = {}

function printable_mt:__tostring()
  local t = {}
  for k, v in pairs(self) do
    if type(v) == "table" then
      if utils.is_array(v) then
        v = table.concat(v, ",")
      else
        setmetatable(v, printable_mt)
      end
    end

    table.insert(t, (type(k) == "string" and k.."=" or "")..tostring(v))
  end
  return table.concat(t, " ")
end

function printable_mt.print_r( t ) 
    local print_r_cache={}
    local res_str = ""
    local function sub_print_r(t,indent)
        if (print_r_cache[tostring(t)]) then
            res_str = res_str .. indent.."*"..tostring(t)
        else
            print_r_cache[tostring(t)]=true
            if (type(t)=="table") then
                for pos,val in pairs(t) do
                    if (type(val)=="table") then
                        res_str = res_str .. indent.."["..pos.."] => "..tostring(t).." {"
                        sub_print_r(val,indent..string.rep(" ",string.len(pos)+8))
                        res_str = res_str .. indent..string.rep(" ",string.len(pos)+6).."}"
                    elseif (type(val)=="string") then
                        res_str = res_str .. indent.."["..pos..'] => "'..val..'"'
                    else
                        res_str = res_str .. indent.."["..pos.."] => "..tostring(val)
                    end
                end
            else
                res_str = res_str .. indent..tostring(t)
            end
        end
    end
    if (type(t)=="table") then
        res_str = res_str .. tostring(t).." {"
        sub_print_r(t," ")
        res_str = res_str .. "}"
    else
        sub_print_r(t," ")
    end
    return res_str
end


function printable_mt.__concat(a, b)
  if getmetatable(a) == printable_mt then
    return tostring(a)..b
  else
    return a..tostring(b)
  end
end

return printable_mt