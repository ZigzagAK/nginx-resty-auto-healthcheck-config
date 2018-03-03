local _M = {
  _VERSION = "1.8.7"
}

local CONFIG = ngx.shared.config

local healthchecks = {}

local function init_healthcheck(mod, opts)
  assert(opts.type, "type required")

  opts.shm = "healthcheck"
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

  return assert(mod.new(opts))
end

function _M.init()
  local debug_enabled = CONFIG:get("healthcheck.debug")

  if debug_enabled then
    local common = require "resty.upstream.dynamic.healthcheck.common"
    common.enable_debug()
  end

  healthchecks.http = init_healthcheck(require "resty.upstream.dynamic.healthcheck.http", {
    type = "http",
    healthcheck = {
      command = {
        uri = CONFIG:get("healthcheck.uri") or "/",
        method = "GET",
        headers = {},
        body = nil,
        expected = {
          codes = { 200, 201, 202, 203, 204 },
          body = nil -- pcre
        }
      }
    }
  })

  healthchecks.stream = init_healthcheck(require "resty.upstream.dynamic.healthcheck.stream", {
    type = "tcp"
  })
end

function _M.start()
  assert(healthchecks.http:start())
  assert(healthchecks.stream:start())
end

return _M
