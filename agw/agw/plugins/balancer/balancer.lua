-- 可以查看https://github.com/openresty/lua-resty-core/blob/master/lib/ngx/balancer.md
local checkups  = require "agw.plugins.balancer.upstreams.api"
--local balancer  = require "agw.lib.ngx_balancer"
local balancer  = require "ngx.balancer"
--local printable    = require "agw.utils.printable"

local get_last_failure = balancer.get_last_failure
local set_current_peer = balancer.set_current_peer
local set_more_tries = balancer.set_more_tries


local skey = ngx.var.host
if not skey then
    ngx.log(ngx.ERR, "request host is null")
    return
end

-- 检测出失效的负载节点
local status, code = get_last_failure()

if status == "failed" then
    local last_peer = ngx.ctx.last_peer
    -- 反馈节点状态
    checkups.feedback_status(skey, last_peer.host, last_peer.port, true)
end

-- 通过算法进行负载均衡
local peer, ok, err
peer, err = checkups.select_peer(skey)
if not peer then
    ngx.log(ngx.ERR, "select peer failed, ", err)
    return
end

ngx.ctx.last_peer = peer
ok, err = set_current_peer(peer.host, peer.port)
if not ok then
    ngx.log(ngx.ERR, "set_current_peer failed, ", err)
    return
end

ok, err = set_more_tries(1)
if not ok then
    ngx.log(ngx.ERR, "set_more_tries failed, ", err)
    return
end
