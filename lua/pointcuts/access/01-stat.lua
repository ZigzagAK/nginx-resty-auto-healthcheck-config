local _M = {
  _VERSION = "1.0.0"
}

function _M.process()
  ngx.log(ngx.INFO, "Request " .. ngx.var.request .. " begin")
end

return _M