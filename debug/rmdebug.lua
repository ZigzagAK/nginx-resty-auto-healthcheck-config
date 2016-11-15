local _M = {
  _VERSION= "1.0.0"
}

local debugger = require "mobdebug"

function _M.start(addr)
  debugger.start(addr)
end

function _M.stop()
  debugger.done()
end

return _M