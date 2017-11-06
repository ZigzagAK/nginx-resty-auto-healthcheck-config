local _M = {
  _VERSION = "1.8.5"
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

local function lua_pcall(f, ...)
  local ok, result, err = pcall(f, ...)
  return ok and result or nil, ok and err or result
end

local function lua_xpcall(f, ...)
  local ok, result, err = xpcall(f, function(err)
    ngx_log(ERR, traceback())
    return err
  end, ...)
  return ok and result or nil, ok and err or result
end

local function foreach_v(t, f)
  for _,v in pairs(t) do f(v) end
end

local function foreach(t, f)
  for k,v in pairs(t) do f(k, v) end
end

local function foreachi(t, f)
  for _,v in ipairs(t) do f(v) end
end

local function find_if(t, f)
  for k,v in pairs(t) do
    if f(k,v) then
      return k, v
    end
  end
end

local function find_if_i(t, f)
  for i,v in ipairs(t) do
    if f(v) then
      return { v, i }
    end
  end
end

local function load_modules(path, opts)
  local modules = system.getmodules(path, MOD_TYPE)
  local result = {}
  foreachi(modules, function(m)
    local short_name, name = unpack(m)
    local mod, err = lua_xpcall(require, name)
    if not mod then
      opts.logfun(ERR, short_name, "error: ", err)
    else
      local fun = opts.getfun(mod)
      if fun then
        tinsert(result, { short_name, fun })
        opts.logfun(INFO, short_name, "success")
      else
        package.loaded[name] = nil
      end
    end
  end)
  return result
end

local function process_modules(modules, logfun, logall)
  foreachi(modules, function(mod)
    local name, fun = unpack(mod)
    local _,err = lua_xpcall(fun)
    if err then
      logfun(ERR, name, "error: ", err)
    elseif logall then
      logfun(INFO, name, "success")
    end
  end)
end

local function module_type()
  assert(MOD_TYPE, "MOD_TYPE is nil")
  return MOD_TYPE
end

function _M.init(mod_type)
  assert(not MOD_TYPE, "MOD_TYPE already initialized")
  MOD_TYPE = mod_type
end

lib = lib or {}

lib.pcall = lua_pcall
lib.xpcall = lua_xpcall
lib.foreach = foreach
lib.foreachi = foreachi
lib.foreach_v = foreach_v
lib.find_if = find_if
lib.find_if_i = find_if_i
lib.load_modules = load_modules
lib.process_modules = process_modules
lib.module_type = module_type

return _M