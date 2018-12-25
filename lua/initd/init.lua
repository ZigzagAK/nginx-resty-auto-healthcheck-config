local _M = {
  _VERSION = "2.1.0"
}

local load_modules = lib.load_modules
local process_modules = lib.process_modules

local module_type = lib.module_type()

local ngx_log = ngx.log
local INFO = ngx.INFO

local function init_globals()
  ngx_log(INFO, "[", module_type ,"] globals")

  local modules = load_modules("lua/globals", {
    logfun = function(level, name, ...)
      ngx_log(level, "[", module_type ,"] loading ", name, " ", ...)
    end
  })

  ngx_log(INFO, "[", module_type ,"]", " init globals finish")
end

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
  init_globals()
  init_sysconfig()
end

function _M.make()
  initd()
end

return _M