local _M = {
  _VERSION = "1.0.0"
}

local system = require "system"

local function init_sysconfig(typ)
  local files = system.getfiles("conf/conf.d/sysconfig", ".+%.lua$")
  for _, file in pairs(files)
  do
    local name = file:match("(.+)%.lua$")
    local ok, r = pcall(require, "sysconfig." .. name)
    if r and (r._MODULE_TYPE or "http") ~= typ then
      package.loaded[name] = nil
      goto continue
    end
    ngx.log(ngx.INFO, "Configuring " .. name .. " ...")
    if ok then
      ok, r = pcall(r.config)
    end
    if not ok then
      ngx.log(ngx.ERR, "Error configuring " .. name .. ", ERR: " .. r)
    end
::continue::
  end
end

local function initd(typ)
  local files = system.getfiles("lua/initd/startup", ".+%.lua$")
  for _, file in pairs(files)
  do
    local name = file:match("(.+)%.lua$")
    local ok, r = pcall(require, "initd.startup." .. name)
    if r and (r._MODULE_TYPE or "http") ~= typ then
      package.loaded[name] = nil
      goto continue
    end
    ngx.log(ngx.INFO, "Startup " .. name .. " ...")
    if ok then
      ok, r = pcall(r.startup)
    end
    if not ok then
      ngx.log(ngx.ERR, "Error starting " .. name .. ", ERR: " .. r)
    end
::continue::
  end
end

function _M.make(typ)
  ngx.log(ngx.INFO, "Configure " .. typ .. " modules begin")
  init_sysconfig(typ)
  ngx.log(ngx.INFO, "Configure " .. typ .. " modules end")
  ngx.log(ngx.INFO, "Startup " .. typ .. " modules begin")
  initd(typ)
  ngx.log(ngx.INFO, "Startup " .. typ .. " modules end")
end

return _M