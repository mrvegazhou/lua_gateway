local BasePlugin = require "agw.plugins.base"
local access = require "agw.plugins.oauth2.access"
local str_sub = string.sub

local OAuthHandler = BasePlugin:extend()
OAuthHandler.PRIORITY = 1009

function OAuthHandler:new(store)
  OAuthHandler.super.new(self, "oauth2")
  self.store = store
end

function OAuthHandler:access(conf)
  OAuthHandler.super.access(self)
  if "/api/oauth2/refresh_token"==ngx.var.request_uri then
  	access.refresh_token(self.store, conf)
  elseif "/api/oauth2/access_token"==ngx.var.request_uri then
  	access.access_token(self.store, conf)
  else
  	access.execute(self.store, conf)
  end
end

return OAuthHandler