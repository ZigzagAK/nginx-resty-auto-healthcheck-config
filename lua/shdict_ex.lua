local _M = {
  _VERSION= "1.9.0"
}

local shdict = require "shdict"
local lrucache = require "resty.lrucache"

local ngx_now = ngx.now

local make_key = shdict.make_key

local function get_local(dict, key, fun)
  local cache = dict.__local_cache
  local now = ngx_now()

  local item = cache:get(key)
  if item and item.expired > now then
    return item.val, item.flags
  end

  if item then
    cache:delete(key)
  end

  item = {}
  item.val, item.flags = fun(dict, key)

  if item.val then
    item.expired = now + dict.__ttl
    cache:set(key, item, dict.__ttl)
  end

  return item.val, item.flags
end

--- @type ShDict2
--  @extends shdict#ShDict
local shdict2_class = {}

--- @param #ShDict2 self
function shdict2_class:get(key)
  key = make_key(key)
  return get_local(self, key, self.dict_get)
end

--- @param #ShDict2 self
function shdict2_class:object_get(key)
  key = make_key(key)
  return get_local(self, key, self.dict_object_get)
end

--- @param #string name
--  @param #number ttl
--  @param #number count
--  @return #ShDict2
function _M.new(name, ttl, count)
  local dict = shdict.new(name)

  if not ttl or ttl == 0 then
    return dict
  end

  local mt = {}

  for n,f in pairs(getmetatable(dict).__index)
  do
    mt[n] = f
  end

  local err
  dict.__local_cache, err = assert(lrucache.new(count or 10000))
  dict.__ttl = ttl

  mt.dict_get        = dict.get
  mt.dict_object_get = dict.object_get
  mt.get             = shdict2_class.get
  mt.object_get      = shdict2_class.object_get

  return setmetatable(dict, { __index = mt })
end

return _M