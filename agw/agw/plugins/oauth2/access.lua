local url = require "socket.url"
local http = require "resty.http"
local json = require "cjson"
local ngx_md5 = ngx.md5
local utils = require "agw.utils.utils"
local CONST = require "agw.constants"
local pl_stringx = require "pl.stringx"
local Multipart = require "multipart"
local timestamp = require "agw.lib.timestamp"
local model = require "agw.plugins.oauth2.models"
local responses = require "agw.lib.responses"
local printable = require "agw.utils.printable"

local agw_config = ngx.shared.agw_config
local redis_store = require("agw.store.redis_store")(json.decode(agw_config:get("agw_config")))

local tonumber = tonumber

local string_find = string.find
local req_get_headers = ngx.req.get_headers
local check_https = utils.check_https
local table_insert = table.insert

local CONTENT_LENGTH = "content-length"
local CONTENT_TYPE = "content-type"
local CREDENTIAL = 'credential'
local RESPONSE_TYPE = "response_type"
local STATE = "state"
local CODE = "code"
local TOKEN = "token"
local REFRESH_TOKEN = "refresh_token"
local SCOPE = "scope"
local CLIENT_ID = "client_id"
local CLIENT_SECRET = "client_secret"
local CONSUMER = 'consumer'
local USERNAME = 'username'
local PASSWORD = 'password'
local REDIRECT_URI = "redirect_uri"
local ACCESS_TOKEN = "access_token"
local GRANT_TYPE = "grant_type"
local GRANT_AUTHORIZATION_CODE = "authorization_code"
local GRANT_CLIENT_CREDENTIALS = "client_credentials"
local GRANT_REFRESH_TOKEN = "refresh_token"
local GRANT_PASSWORD = "password"
local ERROR = "error"
local AUTHENTICATED_USERID = "authenticated_userid"
local RULE_ID = "rule_id"

local _M = {}


local function retrieve_parameters()
  ngx.req.read_body()
  -- OAuth2 parameters could be in both the querystring or body
  local body_parameters
  local content_type = req_get_headers()[CONTENT_TYPE]
  
  local ngx_body_data = ngx.req.get_body_data()
  if not ngx_body_data then
    ngx_body_data = {}
  end
  if content_type and string_find(content_type:lower(), "multipart/form-data", nil, true) then
    if #ngx_body_data~=0 or next(ngx_body_data)~=nil then
      local func = Multipart(ngx_body_data, content_type):get_all()
      local ok, body_parameters = pcall(func, nil)
      if not ok then
        return {}
      end
    else
      return {}
    end
  elseif content_type and string_find(content_type:lower(), "application/json", nil, true) then
    local ok, body_parameters = pcall(json.decode, ngx_body_data)
    if not ok then
      return {}
    end
  else
    body_parameters = ngx.req.get_post_args()
  end
  return utils.table_merge(ngx.req.get_uri_args(), body_parameters)
end

--通过client_id获取oauth2_credentials信息
local function get_redirect_uri(store, client_id)
  local client
  if client_id then
    local credential = model:get_oauth2_credentials(store, client_id)
    if credential and #credential>0 then
      client = credential[1]
    else
      return nil, nil
    end
  else
    return nil, nil
  end
  return client and client.redirect_uri or nil, client
end

function _M:authorize(store, params)
  local response_params = {}
  local parameters = retrieve_parameters()
  if params then
    parameters = utils.table_merge(parameters, params)
  end
  local conf = model:load_oauth2_plugin_info(store, parameters[RULE_ID])
  if not conf then
    response_params = {[ERROR] = "access_denied", error_description = "Invalid parameter" }
    return response_params
  end
  
  local state = parameters[STATE]
  local allowed_redirect_uris, client, redirect_uri, parsed_redirect_uri
  --local is_implicit_grant

  local is_https, err = check_https(conf.accept_http_if_already_terminated)
  is_https = true -----------------------------------------------------------------------------------------------------删除掉
  if not is_https then
    response_params = {[ERROR] = "access_denied", error_description = err or "You must use HTTPS"}
  else

    if conf.provision_key ~= parameters.provision_key then
      response_params = {[ERROR] = "invalid_provision_key", error_description = "Invalid API provision_key"}
    elseif not parameters.authenticated_userid or utils.strip(parameters.authenticated_userid.."") == "" then
      response_params = {[ERROR] = "invalid_authenticated_userid", error_description = "Missing authenticated_userid parameter"}
    else
      local response_type = parameters[RESPONSE_TYPE]
      --  需要验证response_type          1
      if not ((response_type == CODE and conf.enable_authorization_code) or (conf.enable_implicit_grant and response_type == TOKEN)) then -- Authorization Code Grant (http://tools.ietf.org/html/rfc6749#section-4.1.1)
        response_params = {[ERROR] = "unsupported_response_type", error_description = "Invalid "..RESPONSE_TYPE}
      end
      --  需要验证scopes        2
      
      --  验证 client_id and redirect_uri   3
      allowed_redirect_uris, client = get_redirect_uri(store, parameters[CLIENT_ID])
      --  这里应该判断allowed_redirect_uris，但是api项目没有redirect_uri参数，后期会修补
      if not client then
        response_params = {[ERROR] = "invalid_client", error_description = "Invalid client authentication" }
      else
        response_params.client_secret = client.client_secret
        --redirect_uri = parameters[REDIRECT_URI] and parameters[REDIRECT_URI] or allowed_redirect_uris[1]
      end

      -- If there are no errors, keep processing the request
      if not response_params[ERROR] then
        if response_type == CODE then
          local authorization_code, err = model:save_oauth2_authorization_codes(store, client.id, parameters[AUTHENTICATED_USERID], params['scope'] or 'all')
          if not authorization_code then
            return nil, err
          end
          response_params.code = authorization_code.code
        else
          -- Implicit grant, override expiration to zero

        end
      else
        return nil, response_params[ERROR]
      end
    end
  end   --https
  -- Adding the state if it exists. If the state == nil then it won't be added
  -- 用于请求阶段和回调阶段之间的状态保持
  -- client app 在第一步骤中获取 authorization code 时向 OAuth2 Server 传递并由 OAuth2 Server 返回的随机哈希参数
  response_params.state = state
  return response_params
end

-- 通过两种方式（get header）获取client_id, client_secret
local function retrieve_client_credentials(parameters)
  local client_id, client_secret, from_authorization_header
  local authorization_header = ngx.req.get_headers()["authorization"]
  if parameters[CLIENT_ID] then
    client_id = parameters[CLIENT_ID]
    client_secret = parameters[CLIENT_SECRET]
  elseif authorization_header then
    from_authorization_header = true
    local iterator, iter_err = ngx.re.gmatch(authorization_header, "\\s*[Bb]asic\\s*(.+)")
    if not iterator then
      ngx.log(ngx.ERR, iter_err)
      return
    end
    local m, err = iterator()
    if err then
      ngx.log(ngx.ERR, err)
      return
    end

    if m and table.getn(m) > 0 then
      local decoded_basic = ngx.decode_base64(m[1])
      if decoded_basic then
        local basic_parts = utils.split(decoded_basic, ":")
        client_id = basic_parts[1]
        client_secret = basic_parts[2]
      end
    end
  end

  return client_id, client_secret, from_authorization_header
end


--
--oauth2_plugin_info  oauth2配置信息
--credential          
--
local function generate_token(store, oauth2_plugin_info, credential, authenticated_userid, scope, state, expiration, is_refresh, delete_id, token_id)
  local token_expiration = tonumber(expiration) or tonumber(oauth2_plugin_info.token_expiration)
  local refresh_token = utils.random_string()
  if is_refresh==false then
    -- local del_res = model:delete_oauth2_token(store, token.credential_id) -- Delete old token
    -- if not del_res then
    --   response_params = {[ERROR] = "invalid_request", error_description = "Delete old access token fail"}
    -- end
    flag = true
  else
    -- 删除 authorization code
    -- local del_auth_code = model:delete_oauth2_code(store, authorization_code.id) --删除oauth2_authorization_codes信息，避免token重复利用
    -- if not del_auth_code then
    --   response_params = {[ERROR] = "invalid_request", error_description = "server_error"}
    -- end
    flag = false
  end
  local token, err = model:transaction_del_save_token(store, flag, delete_id, credential.id, authenticated_userid, token_expiration, refresh_token, scope, token_id)
  if not token then
    return {[ERROR] = "invalid_request", error_description = "server_error"}
  end
  return {
    access_token = token.access_token,
    token_type = "bearer",
    expires_in = token_expiration > 0 and token.expires_in or nil,
    refresh_token = refresh_token,
    state = state -- If state is nil, this value won't be added
  }
end

--[[
  oauth2错误返回规范：
    1.ASCII编码的 error code，其值意义包括
        invalid_request
        unauthorized_client
        access_denied
        unsupported_response_type
        invalid_scope、server_error
        temporarily_unavailable；（必选）
    2.error_description：对错误的描述（可选）
    3.error_uri：对于错误的附加信息，比如出现了这个错误，然后指向错误的帮助页面（可选）
    4.state（可选）
--]]
function _M:issue_token(store, parameters)
  local response_params = {}
  local invalid_client_properties = {}
  -- local parameters
  -- if params then
  --   parameters = utils.table_merge(retrieve_parameters(), params)
  -- else
  --   parameters = retrieve_parameters()
  -- end

  local client_id, client_secret, from_authorization_header = retrieve_client_credentials(parameters)

  -- 从redis获取权限配置
  local conf = model:load_oauth2_plugin_info_by_client_id(store, parameters[CLIENT_ID])
  if not conf then
    return {[ERROR] = "invalid_request", error_description = "server_error"}
  end

  local state = parameters[STATE]
  local is_https, err = check_https(conf.accept_http_if_already_terminated or false)
  is_https = true
  if not is_https then
    response_params = {[ERROR] = "access_denied", error_description = err or "You must use HTTPS"}
  else
    local grant_type = parameters[GRANT_TYPE]
    --(conf.enable_client_credentials and grant_type == GRANT_CLIENT_CREDENTIALS) or (conf.enable_password_grant and grant_type == GRANT_PASSWORD)
    --判断grant_type是否有值, 并且判断是否为刷新token和授权码模式
    if not (grant_type == GRANT_AUTHORIZATION_CODE or
            grant_type == GRANT_REFRESH_TOKEN) then
      response_params = {[ERROR] = "unsupported_grant_type", error_description = "Invalid "..GRANT_TYPE}
    end

    -- 检查client_id and redirect_uri
    -- 空的后续修改验证redirect_uri
    allowed_redirect_uris, client = get_redirect_uri(store, client_id)
    if client and client.client_secret ~= client_secret then
      response_params = {[ERROR] = "invalid_client", error_description = "Invalid client authentication"}
      if from_authorization_header then
        invalid_client_properties = { status = 401, www_authenticate = "Basic realm=\"OAuth2.0\""}
      end
    end
    
    if not response_params[ERROR] then
      if grant_type == GRANT_AUTHORIZATION_CODE then
        local code = parameters[CODE]
        --通过auth code获取oauth2_authorization_codes表的信息 然后验证oauth2_authorization_codes表里的credential_id是否与oauth2_credentials表的主键相等
        local authorization_code = code and model:get_oauth2_authorization_codes(store, {code = code})[1]
        
        if not authorization_code then
          response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..CODE}
        elseif authorization_code.credential_id ~= client.id then
          response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..CODE}
        else
          response_params = generate_token(store, conf, client, authorization_code.authenticated_userid, authorization_code.scope, state, nil, false, authorization_code.id, nil)
          
    --elseif grant_type == GRANT_CLIENT_CREDENTIALS then
        --
    --elseif grant_type == GRANT_PASSWORD then
        --
        end
      elseif grant_type == GRANT_REFRESH_TOKEN then
          local refresh_token = parameters[REFRESH_TOKEN]
          --此处没使用缓存，为了使数据直接从mysql更精准
          local token
          if refresh_token then
            local token_tmp = model:get_oauth2_tokens_by_args(store, {refresh_token = refresh_token})
            if not token_tmp then
              response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..REFRESH_TOKEN}
            else
              token = token_tmp[1]
            end
          end

          if not token then
            response_params = {[ERROR] = "invalid_request", error_description = "Invalid "..REFRESH_TOKEN}
          else
            response_params = generate_token(store, conf, client, token.authenticated_userid, token.scope, state, nil, true, token.credential_id, token.id)
          end
      end
    end
  end
  -- 如果state存在就添加
  response_params.state = state
  return response_params, invalid_client_properties
end

--返回ACCESS_TOKEN
local function parse_access_token(store, retrieve_parameters)
  local found_in = {}
  local result = retrieve_parameters[ACCESS_TOKEN]
  
  local client_id
  if not result then
    local head_res = ngx.req.get_headers()
    local authorization = head_res["authorization"]
    client_id = head_res["api-key"]
    if not client_id and retrieve_parameters[CLIENT_ID] then
      client_id = retrieve_parameters[CLIENT_ID]
    end
    if not client_id then
      return false, 'client id is error'
    end

    if authorization then
      local parts = {}
      for v in authorization:gmatch("%S+") do
        table_insert(parts, v)
      end
      if #parts == 2 and (parts[1]:lower() == "token" or parts[1]:lower() == "bearer") then
        result = parts[2]
        found_in.authorization_header = true
      end
    end
  end

  local conf = model:load_oauth2_plugin_info_by_client_id(store, client_id)
  if not conf then
    return false, 'get oauth2 config info error'
  end
  if conf.hide_credentials then
    if found_in.authorization_header then
      ngx.req.clear_header("authorization")
    else
      -- Remove from querystring
      local parameters = ngx.req.get_uri_args()
      parameters[ACCESS_TOKEN] = nil
      ngx.req.set_uri_args(parameters)
      if ngx.req.get_method() ~= "GET" then
        ngx.req.read_body()
        parameters = ngx.req.get_post_args()
        parameters[ACCESS_TOKEN] = nil
        local encoded_args = ngx.encode_args(parameters)  --将table编码为一个参数字符串
        ngx.req.set_header(CONTENT_LENGTH, string.len(encoded_args))
        ngx.req.set_body_data(encoded_args)
      end
    end
  end
  return result, client_id
end

local function retrieve_token(store, client_id)
  local token
  if client_id then
    local credentials, err = model:get_oauth2_tokens_by_token(store, client_id, false, 7200)
    if err then
      return nil
    elseif #credentials > 0 then
      token = credentials[1]
    end
    return token
  end
end

function _M.execute(store, agw_conf)
  -- 先判断是否开启鉴权开关
  if redis_store:get('oauth2.enable')=='true' then
    local retrieve_parameters = retrieve_parameters()

    local access_token, client_id = parse_access_token(store, retrieve_parameters)
    if not access_token then
      return responses.send_HTTP_UNAUTHORIZED({[ERROR] = "invalid_request", error_description = "The access token is missing"}, {["WWW-Authenticate"] = 'Bearer realm="service"'})
    end

    if not client_id then
      return responses.send_HTTP_UNAUTHORIZED({[ERROR] = "invalid_request", error_description = "The api key is missing"}, {["WWW-Authenticate"] = 'Bearer realm="service"'})
    end

    local token = retrieve_token(store, client_id)
    if not token then
      return responses.send_HTTP_UNAUTHORIZED({[ERROR] = "invalid_token", error_description = "The access token is invalid or has expired"}, {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"'})
    else
      if token.access_token~=access_token then
        return responses.send_HTTP_UNAUTHORIZED({[ERROR] = "invalid_token", error_description = "The access token is invalid"}, {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token is invalid"'})
      end
    end
    
    -- Check expiration date
    if token.expires_in and token.expires_in > 0 then -- zero means the token never expires
      local now = math.floor(ngx.now())
      if (now - token.created_time) > token.expires_in then
        return responses.send_HTTP_UNAUTHORIZED({[ERROR] = "invalid_token", error_description = "The access token has expired"}, {["WWW-Authenticate"] = 'Bearer realm="service" error="invalid_token" error_description="The access token is invalid or has expired"'})
      end
    end

    -- Retrive the credential from the token
    local credential = model:get_oauth2_credentials_by_args(store, {id = token.credential_id})
    -- Retrive the consumer from the credential
    local consumer, err = model:get_consumers_by_args(store, {id = credential[1]['consumer_id']}, nil, nil, true)
    if not consumer then
      return responses.send_HTTP_INTERNAL_SERVER_ERROR(err)
    end

    ngx.req.set_header(CONST.HEADERS.CONSUMER_ID, token.authenticated_userid)
    ngx.req.set_header(CONST.HEADERS.CONSUMER_USERNAME, consumer[1]['username'])
    ngx.req.set_header(CONST.HEADERS.AUTHENTICATED_SCOPE, token.scope)
    ngx.req.set_header(CONST.HEADERS.AUTHENTICATED_USERID, consumer[1]['id'])
    ngx.ctx.authenticated_credential = credential[1]
    ngx.ctx.authenticated_consumer = consumer[1]
  end
end

function _M.refresh_token(store, agw_conf)
  local response_params = {}
  local parameters = retrieve_parameters()
  if parameters[GRANT_TYPE]~='refresh_token' then
    response_params = {[ERROR] = "unsupported_grant_type", error_description = "Invalid "..GRANT_TYPE}
  elseif not parameters[CLIENT_ID] then
    response_params = {[ERROR] = "invalid_client", error_description = "Invalid client id"}
  elseif not parameters[CLIENT_SECRET] then
    response_params = {[ERROR] = "invalid_client", error_description = "Invalid client client_secret"}
  elseif not parameters[REFRESH_TOKEN] then
    response_params = {[ERROR] = "invalid_refresh_token", error_description = "Invalid "..REFRESH_TOKEN}
  end
  response_params, invalid_client_properties = _M:issue_token(store, parameters)
  -- Sending response in JSON format
  return responses.send(response_params[ERROR] and (invalid_client_properties and invalid_client_properties.status or 400)
                        or 200, response_params, {
    ["cache-control"] = "no-store",
    ["pragma"] = "no-cache",
    ["www-authenticate"] = invalid_client_properties and invalid_client_properties.www_authenticate
  })
end

local resolver = require "resty.dns.resolver"


function _M.access_token(store, agw_conf)
  local parameters = retrieve_parameters()
  local client_id = parameters[CLIENT_ID]
  local response_params = nil
  if not client_id then
    response_params = {[ERROR] = "invalid_client_id", error_description = "Invalid "..CLIENT_ID}
  end

  local client_secret = parameters[CLIENT_SECRET]
  if not client_secret then
    response_params = {[ERROR] = "invalid_client_secret", error_description = "Invalid "..CLIENT_SECRET}
  end

  local username = parameters[USERNAME]
  if not username then
    response_params = {[ERROR] = "invalid_username", error_description = "Invalid "..USERNAME}
  end

  local password = parameters[PASSWORD]
  if not password then
    response_params = {[ERROR] = "invalid_password", error_description = "Invalid "..PASSWORD}
  end

  local grant_type = parameters[GRANT_TYPE]
  if grant_type~=GRANT_AUTHORIZATION_CODE then
    response_params = {[ERROR] = "unsupported_grant_type", error_description = "Invalid "..GRANT_TYPE}
  end
  local credential = model:get_oauth2_credentials(store, client_id)
  if not credential or credential[1]['client_secret']~=client_secret then
    response_params = {[ERROR] = "invalid_client_secret", error_description = "Invalid "..CLIENT_SECRET}
  end
  
  local consumer_id = credential[1]['consumer_id']
  local consumer_info
  local httpc = http.new()
  local res, err = httpc:request_uri( CONST.VCG_HTTP_URLS.VCG_USER_GET.."&loginName="..username )

  if not res then
    response_params = {[ERROR] = "invalid_request", error_description = "Invalid Request"}
  else
    local body = json.decode(res.body)
    if body.data==json.null then
      response_params = {[ERROR] = "invalid_username", error_description = "Invalid "..USERNAME}
    else
      consumer_info = model:get_consumers_by_args(store, {id=consumer_id})
      if #consumer_info==0 then
        response_params = {[ERROR] = "invalid_consumer", error_description = "Invalid "..CONSUMER}
      end
      if body.data.userId~=consumer_info[1]['custom_id'] then
        response_params = {[ERROR] = "invalid_username_id", error_description = "Invalid "..USERNAME}
      end
      if body.data.password~=ngx_md5(password) then
        response_params = {[ERROR] = "invalid_password", error_description = "Invalid "..PASSWORD}
      end
    end
  end

  if not response_params then
    redis_store:del(redis_store:get_oauth2_token_by_tokencode(credential[1]['id']))
    local token_info = redis_store:get_json(redis_store:get_oauth2_token_by_tokencode(credential[1]['id']))
    if not token_info or #token_info==0 then
      token_info = model:get_oauth2_tokens_by_args(store, {credential_id=credential[1]['id']})
    end

    if not token_info or #token_info==0 then
      response_params = {[ERROR] = "invalid_credential", error_description = "Invalid "..CREDENTIAL}
    else
      --判断是否过期
      local datas
      local now = math.floor(ngx.now())
      local remain_expires = now - token_info[1]['created_time']
      if remain_expires < token_info[1]['expires_in'] then
        datas = {
          access_token = token_info[1]['access_token'],
          token_type = "bearer",
          expires_in = token_info[1]['expires_in']-remain_expires,
          refresh_token = token_info[1]['refresh_token']
        }
      else
        --过期则删除并生成新的token
        -- 删除token在redis的缓存
        redis_store:del(redis_store:get_oauth2_token_by_tokencode(credential[1]['id']))

        local token_res, err = model:update_oauth2_tokens(store, token_info)
        if not token_res then
          response_params = {[ERROR] = "invalid_credential", error_description = "Invalid "..CREDENTIAL}
        else
          datas = {
            access_token = token_res.access_token,
            token_type = "bearer",
            expires_in = token_info[1]['expires_in'],
            refresh_token = token_res.refresh_token
          }
        end
      end
      return responses.send(200, datas, {
            ["cache-control"] = "no-store",
            ["pragma"] = "no-cache",
            ["www-authenticate"] = 'Basic realm="OAuth2.0"'
          })
    end
  end

  return responses.send_HTTP_UNAUTHORIZED(response_params, {["WWW-Authenticate"] = 'Basic realm="OAuth2.0"'})
end


return _M