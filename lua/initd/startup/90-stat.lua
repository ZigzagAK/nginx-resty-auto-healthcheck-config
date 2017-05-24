local _M = {
  _VERSION = "1.8.0"
}

local lastlog = require "lastlog"

function _M.startup()
  lastlog.spawn_collector()
end

return _M