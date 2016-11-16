local _M = {
  _VERSION= "1.0.0"
}

local debugger = require "mobdebug"
local dbg_addr

function _M.init(addr)
  dbg_addr = addr
end

function _M.start()
  if not dbg_addr then
    dbg_addr = ngx.var.remote_addr
  end
  debugger.start(dbg_addr)
end

function _M.on()
  debugger.on()
end

function _M.off()
  debugger.off()
end

function _M.stop()
  debugger.done()
end

return _M
