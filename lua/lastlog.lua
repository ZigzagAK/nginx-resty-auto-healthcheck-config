local _M = {
  _VERSION = "1.8.0"
}

local cjson  = require "cjson"
local shdict = require "shdict"
local job    = require "job"

local STAT = shdict.new("stat")
local STAT_BUFFER = shdict.new("stat_buffer")

local CONFIG = ngx.shared.config

local collect_time_min = CONFIG:get("http.stat.collect_time_min") or 1
local collect_time_max = CONFIG:get("http.stat.collect_time_max") or 7200

local id = ngx.worker.id()
local req_queue, ups_queue, buffer_key = "r:" .. id, "u:" .. id, "b:" .. id

local buffer = {
  reqs = {}, ups = {}
}

local tinsert, tconcat = table.insert, table.concat

local function pull_statistic()
  if not next(buffer.reqs) then
    return
  end

  local start_time, end_time = ngx.now(), 0

  -- request statistic
  for _, uri_data in pairs(buffer.reqs or {})
  do
    for _, stat in pairs(uri_data)
    do
      start_time = math.min(stat.first, start_time)
      end_time = math.max(stat.last, end_time)
      if stat.latency and stat.count then
        stat.latency = stat.latency / stat.count
      end
    end
  end

  -- upstream statistic
  for _, upstream_data in pairs(buffer.ups or {})
  do
    for _, addr_data in pairs(upstream_data)
    do
      for _, stat in pairs(addr_data)
      do
        if stat.latency and stat.count then
          stat.latency = stat.latency / stat.count
        end
      end
    end
  end

  local r = buffer

  buffer = {
    reqs = {}, ups = {}
  }

  STAT:delete(buffer_key)
  STAT_BUFFER:delete(req_queue)
  STAT_BUFFER:delete(ups_queue)

  return start_time, end_time, r
end

local function purge()
  local j, count = CONFIG:get("collector:j") - 1800, 0
  for i=j,0,-1
  do
    STAT:fun(i, function(value, flags)
      if not value then
        i = 0
      end
      return nil, 0
    end)
    if i ~= 0 then
      count = count + 1
    end
  end
  ngx.log(ngx.WARN, "stat collector: purge count=", count)
end

local function do_collect()
  local start_time, end_time, stat = pull_statistic()
  if not start_time or not end_time then
    return
  end

  STAT:flush_expired()

  local j = CONFIG:incr("collector:j", 1, 0)

  for i=1,2
  do
    local ok, err = STAT:object_set(j, { start_time = start_time,
                                         end_time   = end_time,
                                         stat       = stat },
                                    collect_time_max)
    if ok then
      break
    end

    ngx.log(ngx.ERR, "stat collector: increase [lua_shared_dict stat] or decrease [http.stat.collect_time_max]: ", err)

    purge()
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
      if k == "latency" then
        l.latency = (l.latency or 0) + v
      elseif k == "count" then
        l.count = (l.count or 0) + v
      elseif k == "first" then
        l.first = math.min(l[k] or v, v)
      elseif k == "last" then
        l.last = math.max(l[k] or v, v)
        l.recs = (l.recs or 0) + 1
      end
    end
  end
end

local function get_statistic_impl(now, period)
  local t = { reqs = {}, ups = {} }
  local current_rps = 0

  for j = CONFIG:get("collector:j") or 0, 0, -1
  do
    local stat_j = STAT:object_get(j)
    if not stat_j then
      break
    end

    if not stat_j.stat then
      goto continue
    end

    if stat_j.start_time > now + period then
      goto continue
    end

    if stat_j.end_time < now then
      break
    end

    if stat_j.stat.reqs then
      merge(t.reqs, stat_j.stat.reqs)
    end

    if stat_j.stat.ups then
      merge(t.ups, stat_j.stat.ups)
    end
:: continue ::
  end

  t = { ups  = { upstreams = t.ups, stat = {} },
        reqs = { requests = t.reqs, stat = {} } }

  local http_x = {}

  -- request statistic

  local sum_latency = 0
  local sum_rps = 0
  local count = 0

  for uri, data in pairs(t.reqs.requests)
  do
    local req_count = 0
    for status, stat in pairs(data)
    do
      stat.latency = (stat.latency or 0) / stat.recs
      local p = stat.last - stat.first
      if p > 0 and stat.last > ngx.now() - collect_time_min then
        stat.current_rps = stat.count / p
      else
        stat.current_rps = 0
      end
      if not http_x[status] then
        http_x[status] = {}
      end
      tinsert(http_x[status], { uri = uri or "?", stat = stat })
      count = count + stat.count
      req_count = req_count + stat.count
      sum_rps = sum_rps + stat.current_rps
      sum_latency = sum_latency + stat.latency * stat.count
    end
    data.count = req_count
  end

  if count ~= 0 then
    t.reqs.stat.average_latency = sum_latency / count
  end
  t.reqs.stat.average_rps = count / period
  t.reqs.stat.current_rps = sum_rps

  -- upstream statistic
  for u, peers in pairs(t.ups.upstreams)
  do
    sum_latency = 0
    sum_rps = 0
    count = 0
    for peer, data in pairs(peers)
    do
      for status, stat in pairs(data)
      do
        stat.latency = (stat.latency or 0) / stat.recs
        local p = stat.last - stat.first
        if p > 0 and stat.last > ngx.now() - collect_time_min then
          stat.current_rps = stat.count / p
        else
          stat.current_rps = 0
        end
        count = count + stat.count
        sum_latency = sum_latency + stat.latency * stat.count
        sum_rps = sum_rps + stat.current_rps
      end
    end
    if count ~= 0 then
      t.ups.stat[u] = {}
      t.ups.stat[u].average_latency = sum_latency / count
    end
    t.ups.stat[u].average_rps = count / period
    t.ups.stat[u].current_rps = sum_rps
  end

  -- sort by latency desc
  for status, reqs in pairs(http_x)
  do
    table.sort(reqs, function(l, r) return l.stat.latency > r.stat.latency end)
  end

  return t.reqs, t.ups, http_x, now, now + period
end

-- public api

function _M.get_statistic(period, backward)
  ngx.update_time()
  return get_statistic_impl(ngx.now() - (backward or 0) - (period or 60), period or 60)
end

function _M.get_statistic_from(start_time, period)
  return get_statistic_impl(start_time, period or (ngx.now() - start_time))
end

function _M.get_statistic_table(period, portion, backward)
  local t = {}
  local now

  ngx.update_time()
  now = ngx.now()

  for time = now - (backward or 0) - (period or 60), now - (backward or 0), portion or 60
  do
    local reqs, ups, http_x, _, _ = get_statistic_impl(time, portion or 60)
    tinsert(t, { requests_statistic = reqs,
                 upstream_staistic = ups,
                 http_x = http_x,
                 time = time } )
  end
  return t
end

function _M.get_statistic_table_from(start_time, period, portion)
  local t = {}

  for time = start_time, start_time + (period or ngx.now() - start_time), portion or 60
  do
    local reqs, ups, http_x, _, _ = get_statistic_impl(time, portion or 60)
    tinsert(t, { requests_statistic = reqs,
                 upstream_staistic = ups,
                 http_x = http_x,
                 time = time } )
  end
  return t
end

local function gett(t, ...)
  local n = select("#",...)
  for i=1,n
  do
    local k = select(i,...)
    local p = t[k]
    if not p then
      p = {}
      t[k] = p
    end
    t = p
  end
  return t
end

local check_point = ngx.now()

local function try_check_point()
  local now = ngx.now()
  if check_point > now then
    return
  end

  STAT:object_set(buffer_key, buffer)

  STAT_BUFFER:delete(req_queue)
  STAT_BUFFER:delete(ups_queue)

  check_point = now + 1
end

local function add_stat(t, start_time, latency)
  latency = tonumber(latency) or 0
  if next(t) then
    t.first, t.last, t.count, t.latency = math.min(t.first, start_time), math.max(t.last, start_time), t.count + 1, t.latency + latency
  else
    t.first, t.last, t.count, t.latency = start_time, start_time, 1, latency
  end
  try_check_point()
end

function _M.spawn_collector()
  buffer = STAT:object_get(buffer_key) or {
    reqs = {}, ups = {}
  }

  repeat
    local req = STAT_BUFFER:lpop(req_queue)
    if req then
      local uri, status, start_time, request_time = req:match("(.+)%|(.+)%|(.+)%|(.+)")
      add_stat(gett(buffer.reqs, uri, status),
               start_time, request_time)
    end
  until not req

  repeat
    local req = STAT_BUFFER:lpop(ups_queue)
    if req then
      local upstream, status, addr, start_time, response_time = req:match("(.+)%|(.+)%|(.+)%|(.+)%|(.+)")
      add_stat(gett(buffer.ups, upstream, addr, status),
               start_time, response_time)
    end
  until not req

  STAT:object_set(buffer_key, buffer)

  job.new("Stat collector worker #=" .. id, do_collect, collect_time_min):run()
end

function _M.purge()
  purge()
end

function _M.add_uri_stat(uri, status, start_time, request_time)
  STAT_BUFFER:rpush(req_queue, tconcat( { uri, status, start_time, request_time }, "|" ))
  add_stat(gett(buffer.reqs, uri, status),
           start_time, request_time)
end

function _M.add_ups_stat(upstream, status, addr, start_time, response_time)
  STAT_BUFFER:rpush(ups_queue, tconcat( { upstream, status, addr, start_time, response_time }, "|" ))
  add_stat(gett(buffer.ups, upstream, addr, status),
           start_time, response_time)
end

return _M
