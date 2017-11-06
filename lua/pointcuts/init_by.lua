local _M = {
  _VERSION = "1.8.5"
}

local load_modules = lib.load_modules
local process_modules = lib.process_modules

local module_type = lib.module_type()

local ngx_log = ngx.log
local INFO = ngx.INFO

local modules = {}

function _M.make()
  ngx_log(INFO, "[", module_type ,"] loading init pointcuts")

  modules = load_modules("lua/pointcuts/init", {
    getfun = function(mod)
      return mod.process
    end,
    logfun = function(level, name, ...)
      ngx_log(level, "[", module_type ,"] loading init pointcut ", name, " ", ...)
    end
  })

  process_modules(modules, function(level, name, ...)
    ngx_log(level, "[", module_type ,"] process init pointcut ", name, " ", ...)
  end, true)

  ngx_log(INFO, "[", module_type ,"] loading init pointcuts finish")
end

return _M