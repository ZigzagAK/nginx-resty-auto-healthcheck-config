local _M = {
  _VERSION = "1.0.0"
}

local STAT = ngx.shared.stat

function _M.process()
  ngx.update_time()
  ngx.ctx.start_request_time = ngx.now()
end

return _M