local _M = {
  _VERSION = "1.2.0"
}

local pointcuts = {}
local system = require "system"

function _M.make()
  local files = system.getfiles("lua/pointcuts/access", ".+%.lua$")
  for _, file in ipairs(files)
  do
    local name = file:match("(.+)%.lua$")
    local ok, r = pcall(require, "pointcuts.access." .. name)
    if not ok  then
      ngx.log(ngx.WARN, "Loading access pointcut ", name, ": ", r)
      goto continue
    end
    table.insert(pointcuts, { name = name, m = r })
    ngx.log(ngx.INFO, "Loaded access pointcut ", name, " ...")
::continue::
  end
  table.sort(pointcuts, function(l, r) return l.name < r.name end)
end

function _M.process()
  for _, pointcut in ipairs(pointcuts)
  do
    local ok, err = pcall(pointcut.m.process)
    if not ok then
      ngx.log(ngx.ERR, "Access pointcut ", pointcut.name, ": ", err)
    end
  end
end

return _M