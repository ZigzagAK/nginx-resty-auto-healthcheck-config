local _M = {
  _VERSION = "1.0.0"
}

local STAT = ngx.shared.stat

local function sett(t, ...)
  local n = select("#",...)
  for i=1,n
  do
    local k = select(i,...)
    if i == n - 1 then
      local v = select(n,...)
      if type(v) == "number" then
        t[k] = (t[k] or 0) + v
      else
        if not t[k] then
          t[k] = v
        end
      end
      return
    end
    if not t[k] then
      t[k] = {}
    end
    t = t[k]
  end
end

function _M.get_statistic()
  local t = {}
  local keys = STAT:get_keys()

  for _, key in pairs(keys)
  do
    local typ, u, status, arg = key:match("^(.+):(.+)|(.+)|(.+)$")

    if not arg then
      goto continue
    end
    
    local v = STAT:get(key)

    sett(t, u, arg, status, typ, v)
::continue::
  end

  STAT:set("time_start", ngx.now())
  STAT:flush_all()

  local reqs = t["none"]
  t["none"] = nil

  local http_x = {}

  -- request statistic
  for uri, data in pairs(reqs)
  do
    for status, stat in pairs(data)
    do
      if stat.uri_t and stat.uri_n and stat.uri_n ~= 0 then
        data[status] = { count = stat.uri_n, latency = stat.uri_t / stat.uri_n }
        sett(http_x, status, {})
        table.insert(http_x[status], { uri = uri, stat = data[status] })
      end
    end
  end

  -- upstream statistic
  for uri, peers in pairs(t)
  do
    for _, data in pairs(peers)
    do
      for status, stat in pairs(data)
      do
        if stat.upstream_t and stat.upstream_n and stat.upstream_n ~= 0 then
          data[status] = { count = stat.upstream_n, latency = stat.upstream_t / stat.upstream_n }
        end
      end
    end
  end

  -- sort by latency desc
  for status, reqs in pairs(http_x)
  do
    table.sort(reqs, function(l, r) return l.stat.latency > r.stat.latency end)
  end

  return reqs, t, http_x
end

return _M