package.path = '/usr/local/luarocks/share/lua/5.1/?.lua;'
package.cpath = '/usr/local/luarocks/lib/lua/5.1/?.so;'

local http = require("socket.http")
local ltn12 = require("ltn12")
local cjson = require "cjson"
domain = 'http://101.201.239.159/'
path = domain.."api/oauth2/refresh_token"
access_token = "Bearer ffb9383f4052964c353849b8eef6a496d51a2915fbe95df2ce35e9e14c8d2a9c"
refresh_token = '0a916117f3e94987a1abf8296f0f3599'
client_id = 'e584cc62649ffc9ae10208740dc69b3d'
client_secret = '09855637-fb6c-45cb-b4b5-9d1d30aed0c9'
username = 'csdn_test'
pwd = 'QYbbemjf'

request = function()
	wrk.method = "POST"
    wrk.body = "grant_type=refresh_token&client_secret="..client_secret..'&client_id='..client_id..'&refresh_token='..refresh_token
    wrk.headers["Content-Type"] = "application/x-www-form-urlencoded"
    return wrk.format('POST', path)
end

response = function(status, headers, body)
	local res_body = cjson.decode(body)
	if status==400 and (res_body['error']=='invalid_token' or res_body['error']=='invalid_request') then
		local request_body = string.format("client_id=%s&client_secret=%s&username=%s&password=%s&grant_type=authorization_code", client_id, client_secret, username, pwd)
		local response_body = {}
		local res, code, response_headers, code_status = http.request{
	      url = domain.."api/oauth2/access_token",
	      method = "POST",
	      headers =
	        {
	            ["Content-Type"] = "application/x-www-form-urlencoded",
	            ["Content-Length"] = #request_body,
	        },
	        source = ltn12.source.string(request_body),
	        sink = ltn12.sink.table(response_body)
  		}
  		if type(response_body)=="table" and code==200 then
  			print('---------------take token---------------')
  			local res_response_body = cjson.decode(response_body[1])
    		access_token = 'Bearer '..res_response_body['access_token']
    		refresh_token = res_response_body['refresh_token']
    	else
    		print('---------------error---------------')
    		os.exit()
    	end
    else
    	print('------------refresh token ok------------')
	end
end

function done(summary, latency, requests)
  print(latency.min/1000 .. "," .. latency.max/1000 .. "," .. latency.mean/1000 .. "," .. latency.stdev/1000 .. "," .. latency:percentile(50.0)/1000 .. "," .. latency:percentile(90.0)/1000 .. "," .. latency:percentile(95.0)/1000 .. "," .. latency:percentile(99.0)/1000 .. "," .. summary.duration/1000000 .. "," .. summary.requests .. "," .. summary.bytes .. "," .. summary.errors.connect.. "," .. summary.errors.read.. "," .. summary.errors.write.. "," .. summary.errors.status.. "," .. summary.errors.timeout .. "," .. summary.requests/(summary.duration/1000000) .. "," .. (summary.bytes/1024)/(summary.duration/1000000))
end