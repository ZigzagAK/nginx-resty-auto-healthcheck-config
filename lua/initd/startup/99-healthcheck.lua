local _M = {
  _VERSION = "1.8.7"
}

function _M.startup()
  local healtcheck = require "healthcheck"
  healtcheck.start()
end

return _M
