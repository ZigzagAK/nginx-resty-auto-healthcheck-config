local _M = {
  _VERSION = "1.4.0"
}

local HEALTHCHECK = ngx.shared.healthcheck

local function set_peer(upstream, peer, fun)
  if not upstream or not peer then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say("upstream and peer arguments required")
    ngx.exit(ngx.HTTP_BAD_REQUEST)
  end
  fun(HEALTHCHECK, upstream, peer)
  ngx.say("OK")
end

local http = require "resty.upstream.dynamic.healthcheck.http"
local stream = require "resty.upstream.dynamic.healthcheck.stream"

_M.http = {
  enable_peer = function(upstream, peer)
    return set_peer(upstream, peer, http.enable_peer)
  end,
  disable_peer = function(upstream, peer)
    return set_peer(upstream, peer, http.disable_peer)
  end
}

_M.stream = {
  enable_peer = function(upstream, peer)
    return set_peer(upstream, peer, stream.enable_peer)
  end,
  disable_peer = function(upstream, peer)
    return set_peer(upstream, peer, stream.disable_peer)
  end
}

return _M