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

  opts.shm = HEALTHCHECK
  opts.interval = CONFIG:get("healthcheck.interval") or 10

  if not opts.healthcheck then
    opts.healthcheck = {}
  end

  opts.healthcheck.fall = CONFIG:get("healthcheck.fall") or 2
  opts.healthcheck.rise = CONFIG:get("healthcheck.rise") or 2
  opts.healthcheck.timeout = CONFIG:get("healthcheck.timeout") or 1000
  
  opts.check_all = CONFIG:get("healthcheck.all")
  if opts.check_all == nil then
    opts.check_all = true
  end

  opts.concurrency = 100
  
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
  
  start_job(0, startup_healthcheck, http_hc, { typ = "http", 
                                               healthcheck = {
                                                 command = {
                                                   uri = "/heartbeat",
                                                   headers = {},
                                                   body = nil,
                                                   expected = {
                                                     codes = { 200, 201, 202, 203, 204 },
                                                     body = nil -- pcre
                                                   }
                                                 }
                                               }
                                             })
  
  start_job(0, startup_healthcheck, stream_hc, { typ = "tcp" })

end

return _M
