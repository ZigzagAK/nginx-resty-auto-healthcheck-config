local _M = {
  _VERSION = "1.0.0"
}

local cjson = require "cjson"

local function decode(value)
  if value then
    return cjson.decode(value)
  end
  return nil
end

local shdict_class = {}

function shdict_class:get(key)
  return self.shm:get(key)
end

function shdict_class:object_get(key)
  local value, flags = self.shm:get(key)
  return decode(value), flags
end

function shdict_class:get_stale(key)
  return self.shm:get_stale(key)
end

function shdict_class:object_get_stale(key)
  local value, flags, stale = self.shm:get_stale(key)
  return decode(value), flags, stale
end

function shdict_class:set(key, value, exptime, flags)
  return self.shm:set(key, value, exptime, flags)
end

function shdict_class:object_set(key, value, exptime, flags)
  return self.shm:set(key, cjson.encode(value), exptime, flags)
end

function shdict_class:set_safe(key, value, exptime, flags)
  return self.shm:set_safe(key, value, exptime, flags)
end

function shdict_class:object_set_safe(key, value, exptime, flags)
  return self.shm:set_safe(key, cjson.encode(value), exptime, flags)
end

function shdict_class:add(key, value, exptime, flags)
  return self.shm:add(key, value, exptime, flags)
end

function shdict_class:object_add(key, value, exptime, flags)
  return self.shm:add(key, cjson.encode(value), exptime, flags)
end

function shdict_class:safe_add(key, value, exptime, flags)
  return self.shm:safe_add(key, value, exptime, flags)
end

function shdict_class:object_safe_add(key, value, exptime, flags)
  return self.shm:safe_add(key, cjson.encode(value), exptime, flags)
end

function shdict_class:replace(key, value, exptime, flags)
  return self.shm:replace(key, value, exptime, flags)
end

function shdict_class:object_replace(key, value, exptime, flags)
  return self.shm:replace(key, cjson.encode(value), exptime, flags)
end

function shdict_class:delete(key)
  return self.shm:delete(key)
end

function shdict_class:incr(key, value, init)
  return self.shm:incr(key, value, init)
end

function shdict_class:lpush(key, value)
  return self.shm:lpush(key, value)
end

function shdict_class:object_lpush(key, value)
  return self.shm:lpush(key, cjson.encode(value))
end

function shdict_class:rpush(key, value)
  return self.shm:rpush(key, value)
end

function shdict_class:object_rpush(key, value)
  return self.shm:rpush(key, cjson.encode(value))
end

function shdict_class:lpop(key)
  return self.shm:lpop(key)
end

function shdict_class:object_lpop(key)
  local value, err = self.shm:lpop(key)
  return decode(value), err
end

function shdict_class:rpop(key)
  return self.shm:rpop(key)
end

function shdict_class:object_rpop(key)
  local value, err = self.shm:rpop(key)
  return decode(value), err
end

function shdict_class:llen(key)
  return self.shm:llen(key)
end

function shdict_class:flush_all()
  return self.shm:flush_all()
end

function shdict_class:flush_expired()
  return self.shm:flush_expired()
end

function shdict_class:get_keys(max_count)
  return self.shm:get_keys(max_count)
end

function shdict_class:get_values(max_count)
  local keys = self.shm:get_keys(max_count)
  local r = {}
  local v, f
  for i=1,math.min(#keys, max_count)
  do
    v, f = self.shm:get(keys[i])
    table.insert(r, { value = v, flags = f })
  end
  return r
end

function shdict_class:get_objects(max_count)
  local keys = self.shm:get_keys(max_count)
  local r = {}
  local v, f
  for i=1,math.min(#keys, max_count)
  do
    v, f = self.shm:get(keys[i])
    table.insert(r, { object = decode(v), flags = f })
  end
  return r
end

function shdict_class:fun(key, fun)
  return self.shm:fun(key, fun)
end

function shdict_class:object_fun(key, fun)
  local value, flags = self.shm:fun(key, function(value, flags)
    local object, new_flags = fun(decode(value), flags)
    if object then
      return cjson.encode(object), new_flags
    end
    return nil, new_flags
  end)
  return decode(value), flags
end

function _M.new(dict)
  local dict = {
    shm = ngx.shared[dict]
  }
  if not dict.shm then
    return nil, "no dictionary"
  end
  return setmetatable(dict, { __index = shdict_class } )
end

return _M
