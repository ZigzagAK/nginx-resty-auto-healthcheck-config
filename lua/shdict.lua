local _M = {
  _VERSION = "1.2.0"
}

local cjson = require "cjson"

local function decode(value)
  if value then
    return cjson.decode(value)
  end
  return nil
end

local function make_cache(cache, prefix)
  local shm = ngx.shared[prefix]
  if shm then
    cache.count = 1
    cache.data[1] = shm
    return
  end

  for i=1,64
  do
    shm = ngx.shared[prefix .. "_" .. i]
    if not shm then
      break
    end
    cache.data[i] = shm
    ngx.log(ngx.DEBUG, prefix .. "_" .. i, " found")
  end

  cache.count = #cache.data

  if cache.count == 0 then
    error("shared memory [", prefix, "] is not defined")
  end
end

local shdict_class = {}

function shdict_class:get(key)
  return self.__caches.get(key):get(key)
end

function shdict_class:object_get(key)
  local value, flags = self.__caches.get(key):get(key)
  return decode(value), flags
end

function shdict_class:get_stale(key)
  return self.__caches.get(key):get_stale(key)
end

function shdict_class:object_get_stale(key)
  local value, flags, stale = self.__caches.get(key):get_stale(key)
  return decode(value), flags, stale
end

function shdict_class:set(key, value, exptime, flags)
  return self.__caches.get(key):set(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_set(key, value, exptime, flags)
  return self.__caches.get(key):set(key, cjson.encode(value), exptime or 0, flags or 0)
end

function shdict_class:safe_set(key, value, exptime, flags)
  return self.__caches.get(key):safe_set(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_safe_set(key, value, exptime, flags)
  return self.__caches.get(key):safe_set(key, cjson.encode(value), exptime or 0, flags or 0)
end

function shdict_class:add(key, value, exptime, flags)
  return self.__caches.get(key):add(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_add(key, value, exptime, flags)
  return self.__caches.get(key):add(key, cjson.encode(value), exptime or 0, flags or 0)
end

function shdict_class:safe_add(key, value, exptime, flags)
  return self.__caches.get(key):safe_add(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_safe_add(key, value, exptime, flags)
  return self.__caches.get(key):safe_add(key, cjson.encode(value), exptime or 0, flags or 0)
end

function shdict_class:replace(key, value, exptime, flags)
  return self.__caches.get(key):replace(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_replace(key, value, exptime, flags)
  return self.__caches.get(key):replace(key, cjson.encode(value), exptime or 0, flags or 0)
end

function shdict_class:delete(key)
  return self.__caches.get(key):delete(key)
end

function shdict_class:incr(key, value, init)
  return self.__caches.get(key):incr(key, value, init or 0)
end

function shdict_class:lpush(key, value)
  return self.__caches.get(key):lpush(key, value)
end

function shdict_class:object_lpush(key, value)
  return self.__caches.get(key):lpush(key, cjson.encode(value))
end

function shdict_class:rpush(key, value)
  return self.__caches.get(key):rpush(key, value)
end

function shdict_class:object_rpush(key, value)
  return self.__caches.get(key):rpush(key, cjson.encode(value))
end

function shdict_class:lpop(key)
  return self.__caches.get(key):lpop(key)
end

function shdict_class:object_lpop(key)
  local value, err = self.__caches.get(key):lpop(key)
  return decode(value), err
end

function shdict_class:rpop(key)
  return self.__caches.get(key):rpop(key)
end

function shdict_class:object_rpop(key)
  local value, err = self.__caches.get(key):rpop(key)
  return decode(value), err
end

function shdict_class:llen(key)
  return self.__caches.get(key):llen(key)
end

function shdict_class:flush_all()
  for i=1,self.__caches.count
  do
    self.__caches.data[i]:flush_all()
  end
end

function shdict_class:flush_expired()
  for i=1,self.__caches.count
  do
    self.__caches.data[i]:flush_expired()
  end
end

local function get_keys(dict, max_count)
  local keys = {}
  local part, total = max_count / dict.__caches.count, 0
  for i=1,dict.__caches.count
  do
    if part ~= 0 and i == dict.__caches.count then
      part = max_count - total
    end
    keys[i] = dict.__caches.data[i]:get_keys(part)
    total = total + #keys[i]
  end
  return keys
end

function shdict_class:get_keys(max_count)
  local parts = get_keys(self, max_count or 0)
  local keys = {}
  for i=1,#parts
  do
    for j=1,#parts[i]
    do
      keys[#keys + 1] = parts[i][j]
    end
  end
  return keys
end

function shdict_class:get_values(max_count)
  local keys = get_keys(self, max_count or 0)
  local r = {}
  local v, f
  for i=1,#keys
  do
    for j=1,#keys[i]
    do
      v, f = self.__caches.data[i]:get(keys[i][j])
      r[#r + 1] = { value = v, flags = f }
    end
  end
  return r
end

function shdict_class:get_objects(max_count)
  local keys = get_keys(self, max_count or 0)
  local r = {}
  local v, f
  for i=1,#keys
  do
    for j=1,#keys[i]
    do
      v, f = self.__caches.data[i]:get(keys[i][j])
      r[#r + 1] = { object = decode(v), flags = f }
    end
  end
  return r
end

function shdict_class:fun(key, fun, exptime)
  return self.__caches.get(key):fun(key, fun, exptime or 0)
end

function shdict_class:object_fun(key, fun, exptime)
  local value, flags = self.__caches.get(key):fun(key, function(value, flags)
    local object, new_flags = fun(decode(value), flags)
    if object then
      return cjson.encode(object), new_flags
    end
    return nil, new_flags
  end, exptime or 0)
  return decode(value), flags
end

function _M.new(name)
  local dict = {
    __caches = {
      count = 0,
      data = {}
    }
  }

  local caches = dict.__caches

  caches.get = function(key)
    if caches.count == 1 then
      return caches.data[1]
    end

    if caches.last_key == key then
      return caches.last_shm
    end

    caches.last_key = key
    caches.last_shm = caches.data[1 + ngx.crc32_short(key) % caches.count]

    return caches.last_shm
  end

  make_cache(caches, name)

  return setmetatable(dict, { __index = shdict_class } )
end

return _M
