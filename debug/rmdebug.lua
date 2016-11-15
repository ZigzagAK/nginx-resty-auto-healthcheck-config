local _M = {
  _VERSION= "1.0.0"
}

local debugger = require "mobdebug"
local addr

function _M.init(addr)
  addr = addr
end

function _M.start()
  if not addr then
    addr = ngx.var.remote_addr
  end
  debugger.start(addr)
end

function _M.stop()
  debugger.done()
end

return _M