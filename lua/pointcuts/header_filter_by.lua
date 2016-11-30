local _M = {
  _VERSION = "1.0.0"
}

local pointcuts = {}
local system = require "system"

function _M.make()
  local files = system.getfiles("lua/pointcuts/header_filter", ".+%.lua$")
  for _, file in pairs(files)
  do
    local name = file:match("(.+)%.lua$")
    local ok, r = pcall(require, "pointcuts.header_filter." .. name)
    if not ok  then
      ngx.log(ngx.WARN, "Loading header_filter pointcut " .. name .. " error:" .. r)
      goto continue
    end
    table.insert(pointcuts, { name = name, m = r })
    ngx.log(ngx.INFO, "Loaded header_filter pointcut " .. name .. " ...")
::continue::
  end
end

function _M.process()
  for _, pointcut in ipairs(pointcuts)
  do
    local ok, err = pcall(pointcut.m.process)
    if not ok then
      ngx.log(ngx.ERR, "Log header_filter " .. pointcut.name .. " error : " .. err)
    end
  end
end

return _M
