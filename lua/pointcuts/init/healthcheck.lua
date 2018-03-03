local _M = {
  _VERSION = "1.8.7"
}

function _M.process()
  local healtcheck = require "healthcheck"
  healtcheck.init()
end

return _M
