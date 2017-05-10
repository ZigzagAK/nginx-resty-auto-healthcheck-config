local _M = {
  _VERSION = "1.6.0"
}

local HEALTHCHECK = ngx.shared.healthcheck

local function set_peer(upstream, peer, fun)
  if not upstream or not peer then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say("upstream and peer arguments required")
    ngx.exit(ngx.status)
  end
  fun(HEALTHCHECK, upstream, peer)
end

local function set_upstream(upstream, upstream_name, upstream_fun, fun)
  if not upstream_name then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say("upstream argument required")
    ngx.exit(ngx.status)
  end
  local ok, peers, err = upstream_fun(upstream_name)
  if ok then
    for i=1,#peers
    do
      fun(HEALTHCHECK, upstream_name, peers[i].name)
    end
  else
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say(err)
    ngx.exit(ngx.status)
  end
end

local function set_upstream_primary(upstream, name, fun)
  set_upstream(upstream, name, upstream.get_primary_peers, fun)
end

local function set_upstream_backup(upstream, name, fun)
  set_upstream(upstream, name, upstream.get_backup_peers, fun)
end

local http = require "resty.upstream.dynamic.healthcheck.http"
local stream = require "resty.upstream.dynamic.healthcheck.stream"

local upstream_http = require "ngx.dynamic_upstream"
local upstream_stream = require "ngx.dynamic_upstream.stream"

_M.http = {
  enable_peer = function(upstream, peer)
    set_peer(upstream, peer, http.enable_peer)
  end,
  disable_peer = function(upstream, peer)
    set_peer(upstream, peer, http.disable_peer)
  end,
  enable_primary_peers = function(upstream)
    set_upstream_primary(upstream_http, upstream, http.enable_peer)
  end,
  disable_primary_peers = function(upstream)
    set_upstream_primary(upstream_http, upstream, http.disable_peer)
  end,
  enable_backup_peers = function(upstream)
    set_upstream_backup(upstream_http, upstream, http.enable_peer)
  end,
  disable_backup_peers = function(upstream)
    set_upstream_backup(upstream_http, upstream, http.disable_peer)
  end,
  enable_upstream = function(upstream)
    set_upstream_primary(upstream_http, upstream, http.enable_peer)
    set_upstream_backup(upstream_http, upstream, http.enable_peer)
  end,
  disable_upstream = function(upstream)
    set_upstream_primary(upstream_http, upstream, http.disable_peer)
    set_upstream_backup(upstream_http, upstream, http.disable_peer)
  end
}

_M.stream = {
  enable_peer = function(upstream, peer)
    return set_peer(upstream, peer, stream.enable_peer)
  end,
  disable_peer = function(upstream, peer)
    return set_peer(upstream, peer, stream.disable_peer)
  end,
  enable_primary_peers = function(upstream)
    set_upstream_primary(upstream_stream, upstream, stream.enable_peer)
  end,
  disable_primary_peers = function(upstream)
    set_upstream_primary(upstream_stream, upstream, stream.disable_peer)
  end,
  enable_backup_peers = function(upstream)
    set_upstream_backup(upstream_stream, upstream, stream.enable_peer)
  end,
  disable_backup_peers = function(upstream)
    set_upstream_backup(upstream_stream, upstream, stream.disable_peer)
  end,
  enable_upstream = function(upstream)
    set_upstream_primary(upstream_stream, upstream, stream.enable_peer)
    set_upstream_backup(upstream_stream, upstream, stream.enable_peer)
  end,
  disable_upstream = function(upstream)
    set_upstream_primary(upstream_stream, upstream, stream.disable_peer)
    set_upstream_backup(upstream_stream, upstream, stream.disable_peer)
  end
}

return _M