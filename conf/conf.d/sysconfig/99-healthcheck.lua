local _M = {
  _VERSION = "1.10.0"
}

function _M.config()
  local CONFIG = ngx.shared.config

  CONFIG:add("healthcheck.uri", "/")
  CONFIG:add("healthcheck.interval", 10)
  CONFIG:add("healthcheck.timeout", 1000)
  CONFIG:add("healthcheck.fall", 2)
  CONFIG:add("healthcheck.rise", 2)
  CONFIG:add("healthcheck.keepalive_requests", 1)

  CONFIG:set("healthcheck.debug", false)

  -- Turn on healthchecks for all peers
  -- otherwise depends on server healthcheck parameters
  -- if parameters are missing - no healthchecks
  CONFIG:add("healthcheck.all", false)
end

return _M