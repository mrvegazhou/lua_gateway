local ffi = require "ffi"
local C = ffi.C

ffi.cdef[[
int gethostname(char *name, size_t len);
]]

local function get_host_name()
	local size = 50
	local buf = ffi.new("unsigned char[?]", size)

	local res = C.gethostname(buf, size)
	if res == 0 then
	    local hostname = ffi.string(buf, size)

	    local host = string.gsub(hostname, "%z+$", "")

	    return host
	end

	local f = io.popen("/bin/hostname", "r")
	if f then
	    local host = f:read("*l")
	    f:close()

	    return host
	end
end

return get_host_name()