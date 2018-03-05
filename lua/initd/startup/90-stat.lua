local _M = {
  _VERSION = "1.8.7"
}

function _M.startup()
  local lastlog = require "lastlog"
  lastlog.spawn_collector()
end

return _M