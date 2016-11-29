local _M = {
  _VERSION = "1.0.0"
}

local cjson = require "cjson"
local lock = require "resty.lock"
  
local STAT = ngx.shared.stat
local CONFIG = ngx.shared.config
local DICT = "stat"

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
  return t
end

function _M.pull_statistic()
  local t = {}
  local keys = STAT:get_keys()

  for _, key in pairs(keys)
  do
    local typ, u, status, arg = key:match("^(.+):(.+)|(.+)|(.+)$")

    if not arg then
      goto continue
    end
    
    local v = STAT:get(key)
    STAT:delete(key)

    sett(t, u, arg, status, typ, v)
::continue::
  end

  STAT:set("time_start", ngx.now())
  local reqs = t["none"] or {}
  t["none"] = nil

  -- request statistic
  for uri, data in pairs(reqs)
  do
    for status, stat in pairs(data)
    do
      if stat.uri_t and stat.uri_n and stat.uri_n ~= 0 then
        data[status] = { count = stat.uri_n, latency = stat.uri_t / stat.uri_n }
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

  return { reqs   = reqs,
           ups    = t }
end

local collect_time_min = CONFIG:get("http.stat.collect_time_min") or 1
local collect_time_max = CONFIG:get("http.stat.collect_time_max") or 600

local function do_collect()
  local j = STAT:incr("collector:j", 1, 0)
  local json = cjson.encode( { time = ngx.now(),
                               stat = _M.pull_statistic() } )
  STAT:set("collector[" .. j .. "]", json, collect_time_max)
--ngx.log(ngx.INFO, "collector: ", json)
end

local collector
collector = function(premature, ctx)
  if (premature) then
    return
  end

  local elapsed, err = ctx.mutex:lock("collector:mutex")

  if elapsed then
    local now = ngx.now()
    if STAT:get("collector:next") <= now then
      STAT:set("collector:next", now + collect_time_min)
      do_collect()
      STAT:flush_expired()
    end
    ctx.mutex:unlock()
  else
    ngx.log(ngx.INFO, "Collector: can't aquire mutex, err: " .. (err or "?"))
  end

  local ok, err = ngx.timer.at(collect_time_min, collector, ctx)
  if not ok then
    ngx.log(ngx.ERR, "failed to continue statistic collector job: ", err)
  end
end

function _M.spawn_collector()
  local ctx = { 
    mutex = lock:new(DICT)
  }
  STAT:safe_set("collector:next", 0)
  local ok, err = ngx.timer.at(0, collector, ctx)
  if not ok then
    ngx.log(ngx.ERR, "failed to create statistic collector job: ", err)
  end
end

local function merge(l, r)
  if not r then
    return
  end
  for k, v in pairs(r)
  do
    if type(v) == "table" then
      if not l[k] then
        l[k] = {}
      end
      merge(l[k], v)
    else
      if type(v) == "number" then
        l[k] = (l[k] or 0) + v
      else
        l[k] = v
      end
    end
  end
end

function _M.get_statistic(period)
  local t = { reqs = {}, ups = {} }
  local now = ngx.now()
  local count_reqs = 0
  local count_ups = 0

  if not period then
    period = 60
  end
  
  for j = (STAT:get("collector:j") or 0), 0, -1
  do
    local json = STAT:get("collector[" .. j .. "]")
    if not json then
      break
    end

    local stat_j = cjson.decode(json)
    
    if stat_j.time < now - period then
      break
    end

    if stat_j.stat.reqs then
      merge(t.reqs, stat_j.stat.reqs)
      count_reqs = count_reqs + 1
    end

    if stat_j.stat.ups then
      merge(t.ups, stat_j.stat.ups)
      count_ups = count_ups + 1
    end
  end
  
  local http_x = {}

  -- request statistic
  for uri, data in pairs(t.reqs)
  do
    for status, stat in pairs(data)
    do
      stat.latency = stat.latency / count_reqs
      if not http_x[status] then
        http_x[status] = {}
      end
      table.insert(http_x[status], { uri = uri, stat = stat })
    end
  end

  -- upstream statistic
  for u, peers in pairs(t.ups)
  do
    for peer, data in pairs(peers)
    do
      for status, stat in pairs(data)
      do
        stat.latency = (stat.latency or 0) / count_ups
      end
    end
  end
  
  -- sort by latency desc
  for status, reqs in pairs(http_x)
  do
    table.sort(reqs, function(l, r) return l.stat.latency > r.stat.latency end)
  end

  return t.reqs, t.ups, http_x
end

return _M