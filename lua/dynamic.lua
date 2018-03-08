local _M = {
  _VERSION = "1.8.7"
}

local function check_throw(result, err)
  if not result then
    ngx.status = ngx.HTTP_BAD_REQUEST
    ngx.say(err)
    ngx.exit(ngx.HTTP_BAD_REQUEST)
  end
  return result
end

local function set_peer(upstream, peer, fun)
  check_throw(upstream and peer, "upstream and peer arguments required")
  fun(upstream, ngx.unescape_uri(peer))
end

local function set_ip(ip, fun)
  fun(ip)
end

local function set_upstream(upstream_name, upstream_fun, fun)
  check_throw(upstream_name, "upstream argument required")
  local ok, peers, err = upstream_fun(upstream_name)
  check_throw(ok, err)
  lib.foreachi(peers, function(peer)
    fun(upstream_name, peer.name)
  end)
end

local function set_upstream_primary(mod, name, fun)
  set_upstream(name, mod.get_primary_peers, fun)
end

local function set_upstream_backup(mod, name, fun)
  set_upstream(name, mod.get_backup_peers, fun)
end

local function make_mod(mod)
  return {
    enable_peer = function(upstream, peer)
      set_peer(upstream, peer, mod.healthcheck.enable_peer)
    end,
    disable_peer = function(upstream, peer)
      set_peer(upstream, peer, mod.healthcheck.disable_peer)
    end,
    enable_primary_peers = function(upstream)
      set_upstream_primary(mod.upstream, upstream, mod.healthcheck.enable_peer)
    end,
    disable_primary_peers = function(upstream)
      set_upstream_primary(mod.upstream, upstream, mod.healthcheck.disable_peer)
    end,
    enable_backup_peers = function(upstream)
      set_upstream_backup(mod.upstream, upstream, mod.healthcheck.enable_peer)
    end,
    disable_backup_peers = function(upstream)
      set_upstream_backup(mod.upstream, upstream, mod.healthcheck.disable_peer)
    end,
    enable_upstream = function(upstream)
      set_upstream_primary(mod.upstream, upstream, mod.healthcheck.enable_peer)
      set_upstream_backup(mod.upstream, upstream, mod.healthcheck.enable_peer)
    end,
    disable_upstream = function(upstream)
      set_upstream_primary(mod.upstream, upstream, mod.healthcheck.disable_peer)
      set_upstream_backup(mod.upstream, upstream, mod.healthcheck.disable_peer)
    end,
    enable_ip = mod.healthcheck.enable_ip,
    disable_ip = mod.healthcheck.disable_ip
  }
end

_M.http = make_mod {
  healthcheck = require "resty.upstream.dynamic.healthcheck.http",
  upstream = require "ngx.dynamic_upstream"
}
_M.stream = make_mod {
  healthcheck = require "resty.upstream.dynamic.healthcheck.stream",
  upstream = require "ngx.dynamic_upstream.stream"
}

return _M