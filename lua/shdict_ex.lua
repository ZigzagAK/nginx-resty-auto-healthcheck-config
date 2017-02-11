local _M = {
  _VERSION= "1.3.0"
}

local shdict = require "shdict"

local function get_local(dict, key, fun)
  local cache = dict.__local_cache
  local now = ngx.now()

  local item = cache[key]
  if item and item.expired > now then
    return item.val, item.flags
  end

  cache[key] = nil

  item = {}
  item.val, item.flags = fun(dict, key)

  if item.val then
    item.expired = now + dict.__ttl
    cache[key] = item
  end

  return item.val, item.flags
end

local shdict2_class = {}

function shdict2_class:get(key)
  return get_local(self, key, self.dict_get)
end

function shdict2_class:object_get(key)
  return get_local(self, key, self.dict_object_get)
end

function _M.new(name, ttl)
  local dict = shdict.new(name)

  if not ttl or ttl == 0 then
    return dict
  end

  local mt = {}

  for n,f in pairs(getmetatable(dict).__index)
  do
    mt[n] = f
  end

  dict.__local_cache = {}
  dict.__ttl = ttl

  mt.dict_get        = dict.get
  mt.dict_object_get = dict.object_get
  mt.get             = shdict2_class.get
  mt.object_get      = shdict2_class.object_get

  return setmetatable(dict, { __index = mt })
end

return _M