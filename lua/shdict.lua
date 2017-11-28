local _M = {
  _VERSION = "1.8.5"
}

local cjson = require "cjson"

local json_decode = cjson.decode
local json_encode = cjson.encode

local ipairs = ipairs

local function foreachi(t, f)
  for _,v in ipairs(t) do f(v) end
end

local function decode(value)
  return value and json_decode(value) or nil
end

local function make_cache(cache, prefix)
  local shm = ngx.shared[prefix]
  if shm then
    cache.count = 1
    cache.data[1] = shm
    return 1
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

  assert(cache.count > 0, "shared memory [" .. prefix .. "] is not defined")

  return cache.count
end

local shdict_class = {}

function shdict_class:get(key)
  return self.shard(key):get(key)
end

function shdict_class:object_get(key)
  local value, flags = self.shard(key):get(key)
  return decode(value), flags
end

function shdict_class:get_stale(key)
  return self.shard(key):get_stale(key)
end

function shdict_class:object_get_stale(key)
  local value, flags, stale = self.shard(key):get_stale(key)
  return decode(value), flags, stale
end

function shdict_class:set(key, value, exptime, flags)
  return self.shard(key):set(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_set(key, value, exptime, flags)
  return self.shard(key):set(key, json_encode(value), exptime or 0, flags or 0)
end

function shdict_class:safe_set(key, value, exptime, flags)
  return self.shard(key):safe_set(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_safe_set(key, value, exptime, flags)
  return self.shard(key):safe_set(key, json_encode(value), exptime or 0, flags or 0)
end

function shdict_class:add(key, value, exptime, flags)
  return self.shard(key):add(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_add(key, value, exptime, flags)
  return self.shard(key):add(key, json_encode(value), exptime or 0, flags or 0)
end

function shdict_class:safe_add(key, value, exptime, flags)
  return self.shard(key):safe_add(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_safe_add(key, value, exptime, flags)
  return self.shard(key):safe_add(key, json_encode(value), exptime or 0, flags or 0)
end

function shdict_class:replace(key, value, exptime, flags)
  return self.shard(key):replace(key, value, exptime or 0, flags or 0)
end

function shdict_class:object_replace(key, value, exptime, flags)
  return self.shard(key):replace(key, json_encode(value), exptime or 0, flags or 0)
end

function shdict_class:delete(key)
  return self.shard(key):delete(key)
end

function shdict_class:incr(key, value, init)
  return self.shard(key):incr(key, value, init or 0)
end

function shdict_class:lpush(key, value)
  return self.shard(key):lpush(key, value)
end

function shdict_class:object_lpush(key, value)
  return self.shard(key):lpush(key, json_encode(value))
end

function shdict_class:rpush(key, value)
  return self.shard(key):rpush(key, value)
end

function shdict_class:object_rpush(key, value)
  return self.shard(key):rpush(key, json_encode(value))
end

function shdict_class:lpop(key)
  return self.shard(key):lpop(key)
end

function shdict_class:object_lpop(key)
  local value, err = self.shard(key):lpop(key)
  return decode(value), err
end

function shdict_class:rpop(key)
  return self.shard(key):rpop(key)
end

function shdict_class:object_rpop(key)
  local value, err = self.shard(key):rpop(key)
  return decode(value), err
end

function shdict_class:llen(key)
  return self.shard(key):llen(key)
end

function shdict_class:ttl(key)
  return self.shard(key):ttl(key)
end

function shdict_class:expire(key, exptime)
  return self.shard(key):expire(key, exptime)
end

function shdict_class:capacity()
  local total = 0
  foreachi(self.__caches.data, function(shard)
    total = total + shard:capacity()
  end)
  return total
end

function shdict_class:free_space()
  local total = 0
  foreachi(self.__caches.data, function(shard)
    total = total + shard:free_space()
  end)
  return total
end

function shdict_class:flush_all()
  foreachi(self.__caches.data, function(shard)
    shard:flush_all()
  end)
end

function shdict_class:flush_expired(max_count)
  local part, n = (max_count or 0) / self.__caches.count, 0
  for i=1,self.__caches.count
  do
    if part ~= 0 and i == self.__caches.count then
      part = max_count - n
    end
    local expired = self.__caches.data[i]:flush_expired(part) or 0
    n = n + expired
  end
  return n
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
  return self.shard(key):fun(key, fun, exptime or 0)
end

function shdict_class:object_fun(key, fun, exptime)
  local value, flags = self.shard(key):fun(key, function(value, flags)
    local object, new_flags = fun(decode(value), flags)
    return object and json_encode(object) or nil, new_flags
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

  local data = dict.__caches.data
  local count = make_cache(dict.__caches, name)
  local single = count == 1 and data[1] or nil
  local crc32_short = ngx.crc32_short

  dict.shard = function(key)
    return single and single or data[1 + crc32_short(tostring(key)) % count]
  end

  return setmetatable(dict, { __index = shdict_class } )
end

return _M