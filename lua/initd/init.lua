local _M = {
  _VERSION = "1.8.5"
}

local load_modules = lib.load_modules
local process_modules = lib.process_modules

local module_type = lib.module_type()

local ngx_log = ngx.log
local INFO = ngx.INFO

local function init_sysconfig()
  ngx_log(INFO, "[", module_type ,"] configuring modules")

  local modules = load_modules("conf/conf.d/sysconfig", {
    getfun = function(mod)
      return mod.config
    end,
    logfun = function(level, name, ...)
      ngx_log(level, "[", module_type ,"] loading ", name, " ", ...)
    end
  })

  process_modules(modules, function(level, name, ...)
    ngx_log(level, "[", module_type ,"]", " configuring ", name, " ", ...)
  end, true)

  ngx_log(INFO, "[", module_type ,"]", " configuring modules finish")
end

local function initd()
  ngx_log(INFO, "[", module_type ,"]", " startup modules")

  local modules = load_modules("lua/initd/startup", {
    getfun = function(mod)
      return mod.startup
    end,
    logfun = function(level, name, ...)
      ngx_log(level, "[", module_type ,"] loading ", name, " ", ...)
    end
  })

  process_modules(modules, function(level, name, ...)
    ngx_log(level, "[", module_type ,"] startup ", name, " ", ...)
  end, true)

  ngx_log(INFO, "[", module_type ,"] startup modules finish")
end

function _M.sysconfig()
  init_sysconfig()
end

function _M.make()
  initd()
end

return _M