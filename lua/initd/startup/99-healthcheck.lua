local _M = {
  _VERSION = "1.0.0"
}

local healthcheck       = require "resty.upstream.dynamic.healthcheck"
local dynamic_upstream  = require "ngx.dynamic_upstream"
local stream_upstream   = require "ngx.upstream.stream"

local CONFIG      = ngx.shared.config
local HEALTHCHECK = "healthcheck"

local function get_upstreams(mod)
  local ok, upstreams, error = mod.get_upstreams()
  if not ok then
    ngx.log(ngx.ERR, "failed to get upstreams: ", err)
    return nil
  end
  return upstreams
end

local function startup_healthcheck(premature, mod, opts)
  if premature then
    return
  end

  local upstreams = get_upstreams(mod)
  if not upstreams then
    return
  end

  opts.shm         = HEALTHCHECK;
  opts.interval    = CONFIG:get("healthcheck.interval");
  opts.timeout     = CONFIG:get("healthcheck.timeout")
  opts.fall        = CONFIG:get("healthcheck.fall")
  opts.rise        = CONFIG:get("healthcheck.rise")
  opts.concurrency = 100

  for _, service in pairs(upstreams)
  do
    ngx.log(ngx.DEBUG, "starting healthchecks for upstream: " .. service)

    opts.upstream = service;
    opts.http_req = opts.get_ping_req(service);

    local ok, err = healthcheck.spawn_checker(opts)
    if not ok then
      ngx.log(ngx.ERR, "failed to spawn health checker: ", err)
    end
  end
end

local function start_job(delay, f, ...)
  local ok, err = ngx.timer.at(delay, f, ...)
  if not ok then
    ngx.log(ngx.ERR, "failed to create the startup job: ", err)
  end
end

local _set_peer_down = { http = function(upstream, peer)
                                  return dynamic_upstream.set_peer_down(upstream, peer.name)
                                end,
                         stream = function(upstream, peer)
                                    local ok, err = stream_upstream.set_peer_down(upstream, peer.is_backup, peer.id, true)
                                    return ok, nil, err
                                  end
                       }

local _get_upstreams = { http = dynamic_upstream.get_upstreams,
                         stream = function()
                                    return true, stream_upstream.get_upstreams(), nil
                                  end
                       }

local _get_servers   = { http = dynamic_upstream.get_servers,
                         stream = function(upstream)
                                    local peers = {}
                                    local pp = stream_upstream.get_primary_peers(upstream)
                                    local bp = stream_upstream.get_backup_peers(upstream)
                                    if pp then
                                      for _, peer in pairs(pp)
                                      do
                                        peer.is_backup = false
                                        table.insert(peers, peer)
                                      end
                                    end
                                    if bp then
                                      for _, peer in pairs(bp)
                                      do
                                        peer.is_backup = true
                                        table.insert(peers, peer)
                                      end
                                    end
                                    return true, peers, nil
                                  end
                       }

local http_module = { set_peer_down = _set_peer_down.http,
                      get_upstreams = _get_upstreams.http,
                      get_servers   = _get_servers.http
                    }

local stream_module = { set_peer_down = _set_peer_down.stream,
                        get_upstreams = _get_upstreams.stream,
                        get_servers   = _get_servers.stream
                      }

local function set_peers_down(module)
  local ok, upstreams, error = module.get_upstreams()
  if not ok then
    ngx.log(ngx.ERR, "failed to get upstreams: ", err)
    return
  end

  for _, service in pairs(upstreams)
  do
    local ok, servers, err = module.get_servers(service)
    if ok then
      for _, server in pairs(servers)
      do
        module.set_peer_down(service, server)
      end
    else
      ngx.log(ngx.ERR, "failed to get servers: ", err)
    end
  end
end

function _M.startup()
  local id = ngx.worker.id()
  if id ~= 0 then
    return
  end

  ngx.log(ngx.INFO, "Setup healthcheck job worker #" .. id)

  set_peers_down(http_module)
  set_peers_down(stream_module)

  start_job(0, startup_healthcheck, { get_upstreams = http_module.get_upstreams },
                                    { type = "http",
                                      get_ping_req = function(service)
                                        return "GET /" .. service .. "/heartbeat HTTP/1.0\r\n\r\n"
                                      end,
                                      valid_statuses = { 200, 201, 203, 204 }
                                    })

  start_job(0, startup_healthcheck, { get_upstreams = stream_module.get_upstreams },
                                    { type = "tcp",
                                      get_ping_req = function(service)
                                        return nil
                                      end
                                    })
end

return _M
