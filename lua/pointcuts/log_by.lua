local _M = {
  _VERSION = "1.8.5"
}

local load_modules = lib.load_modules
local process_modules = lib.process_modules

local ngx_log = ngx.log
local INFO = ngx.INFO

local modules = {}

function _M.make()
  ngx_log(INFO, "[http] loading log pointcuts")

  modules = load_modules("lua/pointcuts/log", {
    getfun = function(mod)
      return mod.process
    end,
    logfun = function(level, name, ...)
      ngx_log(level, "[http] loading log pointcut ", name, " ", ...)
    end
  })

  ngx_log(INFO, "[http] loading log pointcuts finish")
end

function _M.process()
  process_modules(modules, function(level, name, ...)
    ngx_log(level, "[http] log pointcut ", name, " ", ...)
  end)
end

return _M