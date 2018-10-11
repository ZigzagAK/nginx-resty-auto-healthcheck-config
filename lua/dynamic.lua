local _M = {
  _VERSION = "2.0.0"
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

local function set_upstream(upstream_name, upstream_fun, fun)
  check_throw(upstream_name, "upstream argument required")
  local ok, peers, err = upstream_fun(upstream_name)
  check_throw(ok, err)
  lib.foreachi(peers, function(peer)
    fun(upstream_name, peer.name)
  end)
end

local function set_upstream_primary(mod, name, fun)
  set_upstream(name, mod.upstream.get_primary_peers, fun)
end

local function set_upstream_backup(mod, name, fun)
  set_upstream(name, mod.upstream.get_backup_peers, fun)
end

local function disable_peer(mod, b)
  return function(upstream, peer)
    local dynamic = mod.healthcheck.get(upstream)
    if dynamic then
      mod.healthcheck.disable_host(peer, b, upstream)
    end
    if b then
      mod.upstream.set_peer_down(upstream, peer)
    else
      if not dynamic then
        mod.upstream.set_peer_up(upstream, peer)
      end
    end
  end
end

local function disable(mod, b)
  return function(upstream)
    local dynamic = mod.healthcheck.get(upstream)
    if dynamic then
      mod.healthcheck.disable(upstream, b)
    end
    set_upstream(upstream, mod.upstream.get_peers, function(upstream, peer)
      if b then
        mod.upstream.set_peer_down(upstream, peer)
      else
        if not dynamic then
          mod.upstream.set_peer_up(upstream, peer)
        end
      end
    end)
  end
end

local function disable_ip(mod, b)
  return function(ip)
    local ok, upstreams, err = mod.upstream.get_upstreams()
    assert(ok, err)
    for _,u in ipairs(upstreams)
    do
      local ok, peers, err = mod.upstream.get_peers(u)
      assert(ok, err)
      for _, peer in ipairs(peers)
      do
        if peer.name:match("^" .. ip) then
          disable_peer(mod, b)(u, peer.name)
        end
      end
    end
  end
end

local function make_mod(mod)
  return {
    enable_peer = function(upstream, peer)
      set_peer(upstream, peer, disable_peer(mod, false))
    end,
    disable_peer = function(upstream, peer)
      set_peer(upstream, peer, disable_peer(mod, true))
    end,
    enable_primary_peers = function(upstream)
      set_upstream_primary(mod.upstream, upstream, disable_peer(mod, false))
    end,
    disable_primary_peers = function(upstream)
      set_upstream_primary(mod.upstream, upstream, disable_peer(mod, true))
    end,
    enable_backup_peers = function(upstream)
      set_upstream_backup(mod.upstream, upstream, disable_peer(mod, false))
    end,
    disable_backup_peers = function(upstream)
      set_upstream_backup(mod.upstream, upstream, disable_peer(mod, true))
    end,
    enable_upstream = function(upstream)
      disable(mod, false)(upstream)
    end,
    disable_upstream = function(upstream)
      disable(mod, true)(upstream)
    end,
    enable_ip = disable_ip(mod, false),
    disable_ip = disable_ip(mod, true)
  }
end

_M.http = make_mod {
  healthcheck = require "ngx.healthcheck",
  upstream = require "ngx.dynamic_upstream"
}
_M.stream = make_mod {
  healthcheck = require "ngx.healthcheck.stream",
  upstream = require "ngx.dynamic_upstream.stream"
}

return _M