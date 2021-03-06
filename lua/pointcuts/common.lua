local _M = {
  _VERSION = "2.1.0"
}

local system = require "system"

local ipairs, pairs = ipairs, pairs
local pcall, xpcall = pcall, xpcall
local traceback = debug.traceback
local tinsert = table.insert
local unpack = unpack
local assert = assert

local ngx_log = ngx.log
local INFO, ERR = ngx.INFO, ngx.ERR

-- setup in init()
local MOD_TYPE

--- @field #table lib
lib = lib or {}

function lib.fake(...)
  return ...
end

function lib.pcall(f, ...)
  local ok, result = pcall(function(...)
    return { f(...) }
  end, ...)
  if ok then
    return unpack(result)
  end
  return nil, result
end

function lib.xpcall(f, ...)
  local ok, result = xpcall(function(...)
    return { f(...) }
  end, function(err)
    ngx_log(ERR, err, "\n", traceback())
    return err
  end, ...)
  if ok then
    return unpack(result)
  end
  return nil, result
end

function lib.foreach_v(t, f)
  for _,v in pairs(t) do f(v) end
end

function lib.foreach(t, f)
  for k,v in pairs(t) do f(k, v) end
end

function lib.foreachi(t, f)
  for i=1,#t do f(t[i], i) end
end

function lib.find_if(t, f)
  for k,v in pairs(t) do
    if f(k,v) then
      return k, v
    end
  end
end

function lib.find_if_i(t, f)
  local v
  for i=1,#t do
    v = t[i]
    if f(v, i) then
      return { v, i }
    end
  end
end

function lib.load_modules(path, opts)
  local modules = system.getmodules(path)
  local result = {}
  lib.foreachi(modules, function(m)
    local short_name, name = unpack(m)
    local mod, err = lib.xpcall(require, name)
    if not mod then
      opts.logfun(ERR, short_name, "error: ", err)
    else
      if opts.getfun then
        local fun = opts.getfun(mod)
        if fun then
          tinsert(result, { short_name, fun })
          opts.logfun(INFO, short_name, "success")
        else
          package.loaded[name] = nil
        end
      else
        opts.logfun(INFO, short_name, "success")
      end
    end
  end)
  return result
end

function lib.process_modules(modules, logfun, logall)
  lib.foreachi(modules, function(mod)
    local name, fun = unpack(mod)
    local _,err = lib.xpcall(fun)
    if err then
      logfun(ERR, name, "error: ", err)
    elseif logall then
      logfun(INFO, name, "success")
    end
  end)
end

function lib.module_type()
  assert(MOD_TYPE, "MOD_TYPE is nil")
  return MOD_TYPE
end

function lib.path2lua_module(path)
  return path:gsub("^lua/", "")
             :gsub("^conf/conf.d/", "")
             :gsub("/", ".")
end

function _M.init(mod_type)
  assert(not MOD_TYPE, "MOD_TYPE already initialized")
  MOD_TYPE = mod_type
end

return _M