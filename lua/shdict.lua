local _M = {
  _VERSION = "1.9.0"
}

local cjson = require "cjson"

local json_decode = cjson.decode
local json_encode = cjson.encode

local foreach, foreachi = lib.foreach, lib.foreachi
local tinsert, tsort, tconcat = table.insert, table.sort, table.concat
local type, next, null = type, next, ngx.null

local function decode(value)
  return value and json_decode(value) or nil
end

local function make_key(key)
  if type(key) ~= "table" then
    return key
  end

  local tmp = {}
  foreach(key, function(k,v)
    tinsert(tmp, k.."="..(v ~= null and v or "null"))
  end)

  tsort(tmp)

  return tconcat(tmp, "&")
end

local function parse_key(key)
  if key then
    local key_object = {}
    for k,v in key:gmatch("([^=]+)=([^&]+)&?")
    do
      key_object[k] = v ~= "null" and v or null
    end
    return next(key_object) and key_object or key
  end
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

--- @type ShDict
local shdict_class = {}

--- @param #ShDict self
function shdict_class:get(key)
  key = make_key(key)
  return self.shard(key):get(key)
end

--- @param #ShDict self
function shdict_class:object_get(key)
  key = make_key(key)
  local value, flags = self.shard(key):get(key)
  return decode(value), flags
end

--- @param #ShDict self
function shdict_class:get_stale(key)
  key = make_key(key)
  return self.shard(key):get_stale(key)
end

--- @param #ShDict self
function shdict_class:object_get_stale(key)
  key = make_key(key)
  local value, flags, stale = self.shard(key):get_stale(key)
  return decode(value), flags, stale
end

--- @param #ShDict self
function shdict_class:set(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):set(key, value, exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:object_set(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):set(key, json_encode(value), exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:safe_set(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):safe_set(key, value, exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:object_safe_set(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):safe_set(key, json_encode(value), exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:add(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):add(key, value, exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:object_add(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):add(key, json_encode(value), exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:safe_add(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):safe_add(key, value, exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:object_safe_add(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):safe_add(key, json_encode(value), exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:replace(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):replace(key, value, exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:object_replace(key, value, exptime, flags)
  key = make_key(key)
  return self.shard(key):replace(key, json_encode(value), exptime or 0, flags or 0)
end

--- @param #ShDict self
function shdict_class:delete(key)
  key = make_key(key)
  return self.shard(key):delete(key)
end

--- @param #ShDict self
function shdict_class:incr(key, value, init)
  key = make_key(key)
  return self.shard(key):incr(key, value, init or 0)
end

--- @param #ShDict self
function shdict_class:lpush(key, value)
  key = make_key(key)
  return self.shard(key):lpush(key, value)
end

--- @param #ShDict self
function shdict_class:object_lpush(key, value)
  key = make_key(key)
  return self.shard(key):lpush(key, json_encode(value))
end

--- @param #ShDict self
function shdict_class:rpush(key, value)
  key = make_key(key)
  return self.shard(key):rpush(key, value)
end

--- @param #ShDict self
function shdict_class:object_rpush(key, value)
  key = make_key(key)
  return self.shard(key):rpush(key, json_encode(value))
end

--- @param #ShDict self
function shdict_class:lpop(key)
  key = make_key(key)
  return self.shard(key):lpop(key)
end

--- @param #ShDict self
function shdict_class:object_lpop(key)
  key = make_key(key)
  local value, err = self.shard(key):lpop(key)
  return decode(value), err
end

--- @param #ShDict self
function shdict_class:rpop(key)
  key = make_key(key)
  return self.shard(key):rpop(key)
end

--- @param #ShDict self
function shdict_class:object_rpop(key)
  key = make_key(key)
  local value, err = self.shard(key):rpop(key)
  return decode(value), err
end

--- @param #ShDict self
function shdict_class:llen(key)
  key = make_key(key)
  return self.shard(key):llen(key)
end

--- @param #ShDict self
function shdict_class:ttl(key)
  key = make_key(key)
  return self.shard(key):ttl(key)
end

--- @param #ShDict self
function shdict_class:zset(key, zkey, value, exptime)
  key = make_key(key)
  return self.shard(key):zset(key, make_key(zkey), value, exptime)
end

--- @param #ShDict self
function shdict_class:object_zset(key, zkey, value, exptime)
  key = make_key(key)
  return self.shard(key):zset(key, make_key(zkey),
                              value and json_encode(value) or nil,
                              exptime)
end

function shdict_class:zadd(key, zkey, value, exptime)
  key = make_key(key)
  return self.shard(key):zadd(key, make_key(zkey), value, exptime)
end

--- @param #ShDict self
function shdict_class:object_zadd(key, zkey, value, exptime)
  key = make_key(key)
  return self.shard(key):zadd(key, make_key(zkey),
                              value and json_encode(value) or nil,
                              exptime)
end

--- @param #ShDict self
function shdict_class:zget(key, zkey)
  key = make_key(key)
  local zkey, value = self.shard(key):zget(key, make_key(zkey))
  return parse_key(zkey),          -- zkey
         zkey and value or nil,    -- value
         not zkey and value or nil -- err
end

--- @param #ShDict self
function shdict_class:object_zget(key, zkey)
  key = make_key(key)
  local zkey, value = self.shard(key):zget(key, make_key(zkey))
  return parse_key(zkey),               -- zkey
         zkey and decode(value) or nil, -- object
         not zkey and value or nil      -- err
end

--- @param #ShDict self
function shdict_class:zgetall(key)
  key = make_key(key)
  local items, err = self.shard(key):zgetall(key)
  foreachi(items or {}, function(item)
    item[1] = parse_key(item[1])
  end)
  return items, err
end

--- @param #ShDict self
function shdict_class:object_zgetall(key)
  key = make_key(key)
  local items, err = self.shard(key):zgetall(key)
  foreachi(items or {}, function(item)
    item[1], item[2] = parse_key(item[1]), decode(item[2])
  end)
  return items, err
end

--- @param #ShDict self
function shdict_class:zrem(key, zkey)
  key = make_key(key)
  return self.shard(key):zrem(key, make_key(zkey))
end

--- @param #ShDict self
function shdict_class:object_zrem(key, zkey)
  key = make_key(key)
  local val, err = self.shard(key):zrem(key, make_key(zkey))
  return decode(val), err
end

--- @param #ShDict self
function shdict_class:zcard(key)
  key = make_key(key)
  return self.shard(key):zcard(key)
end

--- @param #ShDict self
function shdict_class:zscan(key, fun, lbound)
  key = make_key(key)
  return self.shard(key):zscan(key, function(zkey, value)
    return fun(parse_key(zkey), value)
  end, lbound)
end

--- @param #ShDict self
function shdict_class:object_zscan(key, fun, lbound)
  key = make_key(key)
  return self.shard(key):zscan(key, function(zkey, value)
    return fun(parse_key(zkey), decode(value))
  end, lbound)
end

--- @param #ShDict self
function shdict_class:expire(key, exptime)
  key = make_key(key)
  return self.shard(key):expire(key, exptime)
end

--- @param #ShDict self
function shdict_class:capacity()
  local total = 0
  foreachi(self.__caches.data, function(shard)
    total = total + shard:capacity()
  end)
  return total
end

--- @param #ShDict self
function shdict_class:free_space()
  local total = 0
  foreachi(self.__caches.data, function(shard)
    total = total + shard:free_space()
  end)
  return total
end

--- @param #ShDict self
function shdict_class:flush_all()
  foreachi(self.__caches.data, function(shard)
    shard:flush_all()
  end)
end

--- @param #ShDict self
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

--- @param #ShDict self
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

--- @param #ShDict self
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

--- @param #ShDict self
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

--- @param #ShDict self
function shdict_class:fun(key, fun, exptime)
  key = make_key(key)
  return self.shard(key):fun(key, fun, exptime or 0)
end

--- @param #ShDict self
function shdict_class:object_fun(key, fun, exptime)
  key = make_key(key)
  local value, flags = self.shard(key):fun(key, function(value, flags)
    local object, new_flags = fun(decode(value), flags)
    return object and json_encode(object) or nil, new_flags
  end, exptime or 0)
  return decode(value), flags
end

--- @param #string name
--  @return #ShDict
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

function _M.make_key(key)
  return make_key(key)
end

return _M
