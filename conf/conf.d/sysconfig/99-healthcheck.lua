local _M = {
  _VERSION = "1.0.0"
}

local CONFIG = ngx.shared.config

function _M.config()
  CONFIG:set("healthcheck.uri", "/")
  CONFIG:set("healthcheck.interval", 5)
  CONFIG:set("healthcheck.timeout", 1000)
  CONFIG:set("healthcheck.fall", 2)
  CONFIG:set("healthcheck.rise", 2)

  CONFIG:set("healthcheck.debug", false)

  -- Turn on healthchecks for all peers
  -- otherwise depends on server healthcheck parameters
  -- if parameters are missing - no healthchecks
  CONFIG:safe_set("healthcheck.all", false)
end

return _M
