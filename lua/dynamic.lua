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
  set_upstream(name, mod.get_primary_peers, fun)
end

local function set_upstream_backup(mod, name, fun)
  set_upstream(name, mod.get_backup_peers, fun)
end

local function disable_peer(mod, b)
  return function(upstream, peer)
    return mod.disable_host(peer, b, upstream)
  end
end

local function disable(mod, b)
  return function(upstream)
    return mod.disable(upstream, b)
  end
end

local function disable_ip(mod, b)
  return function(ip)
    for u, groups in pairs(assert(mod.status()))
    do
      for peer, status in pairs(groups.primary)
      do
        if peer:match("^" .. ip) then
          mod.disable_host(peer, b, u)
        end
      end
      if groups.backup then
      for peer, status in pairs(groups.backup)
        do
          if peer:match("^" .. ip) then
            mod.disable_host(peer, b, u)
          end
        end
      end
    end
  end
end

local function make_mod(mod)
  return {
    enable_peer = function(upstream, peer)
      set_peer(upstream, peer, disable_peer(mod.healthcheck, false))
    end,
    disable_peer = function(upstream, peer)
      set_peer(upstream, peer, disable_peer(mod.healthcheck, true))
    end,
    enable_primary_peers = function(upstream)
      set_upstream_primary(mod.upstream, upstream, disable_peer(mod.healthcheck, false))
    end,
    disable_primary_peers = function(upstream)
      set_upstream_primary(mod.upstream, upstream, disable_peer(mod.healthcheck, true))
    end,
    enable_backup_peers = function(upstream)
      set_upstream_backup(mod.upstream, upstream, disable_peer(mod.healthcheck, false))
    end,
    disable_backup_peers = function(upstream)
      set_upstream_backup(mod.upstream, upstream, disable_peer(mod.healthcheck, true))
    end,
    enable_upstream = function(upstream)
      mod.healthcheck.disable(upstream, false)
    end,
    disable_upstream = function(upstream)
      mod.healthcheck.disable(upstream, true)
    end,
    enable_ip = disable_ip(mod.healthcheck, false),
    disable_ip = disable_ip(mod.healthcheck, true)
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