local _M = {
  _VERSION = "1.0.0";
}

local CONFIG = ngx.shared.config

function _M.config()
  CONFIG:set("healthcheck.interval", 5000)
  CONFIG:set("healthcheck.timeout", 5000)
  CONFIG:set("healthcheck.fall", 2)
  CONFIG:set("healthcheck.rise", 2)
end

return _M
