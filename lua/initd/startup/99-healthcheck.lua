local _M = {
  _VERSION = "1.0.0"
}

local http_hc   = require "resty.upstream.dynamic.healthcheck.http"
local stream_hc = require "resty.upstream.dynamic.healthcheck.stream"

local CONFIG      = ngx.shared.config
local HEALTHCHECK = "healthcheck"

local function startup_healthcheck(premature, mod, opts)
  if premature then
    return
  end

  opts.shm          = HEALTHCHECK;
  opts.interval     = CONFIG:get("healthcheck.interval");
  opts.timeout      = CONFIG:get("healthcheck.timeout")
  opts.fall         = CONFIG:get("healthcheck.fall")
  opts.rise         = CONFIG:get("healthcheck.rise")
  opts.concurrency  = 100
  opts.get_ping_req = opts.get_ping_req

  local hc = mod.new(opts)
  if hc then
    local ok, err = hc:start()
    if not ok then
      ngx.log(ngx.ERR, "failed to the startup [" .. hc:upstream_type() .. "] healthchecks: ", err)
    end
  else
    ngx.log(ngx.ERR, "failed to the create checker")
  end
end

local function start_job(delay, f, ...)
  local ok, err = ngx.timer.at(delay, f, ...)
  if not ok then
    ngx.log(ngx.ERR, "failed to create the startup job: ", err)
  end
end

function _M.startup()
  local id = ngx.worker.id()
  if id ~= 0 then
    return
  end

  ngx.log(ngx.INFO, "Setup healthcheck job worker #" .. id)

  start_job(0, startup_healthcheck, http_hc,
                                    { typ = "http",
                                      get_ping_req = function(u)
                                        return "GET /" .. u .. "/heartbeat HTTP/1.0\r\n\r\n"
                                      end,
                                      valid_statuses = { 200, 201, 203, 204 }
                                    })

  start_job(0, startup_healthcheck, stream_hc,
                                    { typ = "tcp",
                                      get_ping_req = function(service)
                                        return nil
                                      end
                                    })
end

return _M
