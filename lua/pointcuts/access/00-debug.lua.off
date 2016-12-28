local _M = {
  _VERSION = "1.0.0"
}

function _M.process()
  local debug = ngx.req.get_headers().debug

  if not debug or not debug:match("^[1yY]$") then
    return
  end

  local ok, r = pcall(require, "rmdebug")
  
  if not ok then
    ngx.log(ngx.WARN, "rmdebug load failed: " .. r)
    return
  end

  ngx.ctx.DEBUG = {
    start = r.start,
    on    = r.on,
    off   = r.off,
    stop  = r.stop
  }

  ngx.ctx.DEBUG.start()
end

return _M