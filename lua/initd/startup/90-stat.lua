local _M = {
  _VERSION = "1.0.0"
}

local lastlog = require "lastlog"

function _M.startup()
  local id = ngx.worker.id()
  ngx.log(ngx.INFO, "Setup statistic collector job worker #" .. id)
  lastlog.spawn_collector()
end

return _M