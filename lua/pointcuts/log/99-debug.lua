local _M = {
  _VERSION = "1.0.0"
}

function _M.process()
  if ngx.ctx.DEBUG then
    ngx.ctx.DEBUG.stop()
  end
end

return _M