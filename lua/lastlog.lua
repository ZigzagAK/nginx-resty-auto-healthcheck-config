local _M = {
  _VERSION = "1.8.5"
}

local shdict = require "shdict"
local job = require "job"

local STAT = shdict.new("stat")

local ok, STAT_BUFFER = pcall(shdict.new, "stat_buffer")
if not ok then
  -- disable stat buffer
  STAT_BUFFER = setmetatable({}, { __index = {
    delete = function() end,
    lpop = function() end,
    rpush = function() return 0 end
  }})
end

local CONFIG = ngx.shared.config

local collect_time_min = CONFIG:get("http.stat.collect_time_min") or 1
local collect_time_max = CONFIG:get("http.stat.collect_time_max") or 7200

local worker_id = ngx.worker.id

local id = worker_id()
local req_queue, ups_queue, buffer_key = "r:" .. id, "u:" .. id, "b:" .. id

local buffer = {
  reqs = {}, ups = {}
}

local tinsert, tconcat, tsort = table.insert, table.concat, table.sort
local pairs, ipairs, next, select = pairs, ipairs, next, select
local min, max = math.min, math.max
local type = type
local tonumber = tonumber
local update_time = ngx.update_time
local now = ngx.now

local ngx_log = ngx.log
local WARN, ERR = ngx.WARN, ngx.ERR

local foreach, foreach_v = lib.foreach, lib.foreach_v

local function pull_statistic()
  if not next(buffer.reqs) then
    return
  end

  local start_time, end_time = now(), 0

  -- request statistic
  foreach_v(buffer.reqs or {}, function(uri_data)
    foreach(uri_data, function(status, stat)
      start_time = min(stat.first, start_time)
      end_time = max(stat.last, end_time)
      uri_data[status] = tconcat( { stat.first, stat.last, stat.latency / stat.count, stat.count }, "|")
    end)
  end)

  -- upstream statistic
  foreach_v(buffer.ups or {}, function(upstream_data)
    foreach_v(upstream_data, function(addr_data)
      foreach(addr_data, function(status, stat)
        addr_data[status] = tconcat( { stat.first, stat.last, stat.latency / stat.count, stat.count }, "|")
      end)
    end)
  end)

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
  local oldest, last = CONFIG:get("$stat:oldest") or 0, CONFIG:get("$stat:last") or 0
  local count = 0

  ngx_log(WARN, "lastlog: please increase [lua_shared_dict stat] or decrease [http.stat.collect_time_max]: no memory")

  for j=oldest,last
  do
    STAT:fun(j, function(val)
      count = count + (val and 1 or 0)
      return nil, 0
    end)
    oldest = oldest + 1
    if count == 100 then
      break
    end
  end

  CONFIG:set("$stat:oldest", oldest)

  ngx_log(WARN, "lastlog: purge count=", count)

  STAT:flush_expired()
end

local function do_collect()
  local start_time, end_time, stat = pull_statistic()
  if not start_time or not end_time then
    return
  end

  local j = CONFIG:incr("$stat:last", 1, 0)

  while not STAT:object_add(j, { start_time = start_time,
                                         end_time   = end_time,
                                         stat       = stat },
                                    collect_time_max)
  do
    purge()
  end

  STAT:flush_expired()
end

local function merge(l, r)
  foreach(r or {}, function(k, v)
    local lk = l[k]
    if type(v) == "table" then
      if not lk then
        lk = {}
        l[k] = lk
      end
      merge(lk, v)
    else
      if not lk then
        lk = {
          latency = 0,
          count = 0,
          recs = 0,
          first = now(),
          last = 0,
          current_rps = 0
        }
        l[k] = lk
      end
      local first, last, latency, count = v:match("(.+)|(.+)|(.+)|(.+)")
      lk.first = min(lk.first, first)
      lk.last = max(lk.last, last)
      lk.latency = lk.latency + tonumber(latency)
      lk.count = lk.count + tonumber(count)
      lk.recs = lk.recs + 1
      local p = tonumber(last) - tonumber(first)
      if p > 0 and tonumber(last) >= now() - collect_time_min then
        lk.current_rps = lk.current_rps + tonumber(count) / p
      end
    end
  end)
end

local function get_statistic_impl(now, period)
  local t = { reqs = {}, ups = {} }
  local miss = 0

  for j = CONFIG:get("$stat:last") or 0, 0, -1
  do
    local stat_j = STAT:object_get(j)
    if not stat_j then
      miss = miss + 1
      if miss == 100 then
        break
      end
      goto continue
    end

    miss = 0

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

  foreach(t.reqs.requests, function(uri, data)
    local req_count = 0
    foreach(data, function(status, stat)
      stat.latency = (stat.latency or 0) / stat.recs
      if not http_x[status] then
        http_x[status] = {}
      end
      tinsert(http_x[status], { uri = uri or "?", stat = stat })
      count = count + stat.count
      req_count = req_count + stat.count
      sum_rps = sum_rps + stat.current_rps
      sum_latency = sum_latency + stat.latency * stat.count
    end)
    data.count = req_count
  end)

  if count ~= 0 then
    t.reqs.stat.average_latency = sum_latency / count
  end
  t.reqs.stat.average_rps = count / period
  t.reqs.stat.current_rps = sum_rps

  -- upstream statistic
  foreach(t.ups.upstreams, function(u, peers)
    sum_latency = 0
    sum_rps = 0
    count = 0
    foreach_v(peers, function(data)
      foreach_v(data, function(stat)
        stat.latency = (stat.latency or 0) / stat.recs
        count = count + stat.count
        sum_latency = sum_latency + stat.latency * stat.count
        sum_rps = sum_rps + stat.current_rps
      end)
    end)
    if count ~= 0 then
      t.ups.stat[u] = {}
      t.ups.stat[u].average_latency = sum_latency / count
    end
    t.ups.stat[u].average_rps = count / period
    t.ups.stat[u].current_rps = sum_rps
  end)

  -- sort by latency desc
  foreach_v(http_x, function(reqs)
    tsort(reqs, function(l, r) return l.stat.latency > r.stat.latency end)
  end)

  return t.reqs, t.ups, http_x, now, now + period
end

-- public api

function _M.get_statistic(period, backward)
  update_time()
  return get_statistic_impl(now() - (backward or 0) - (period or 60), period or 60)
end

function _M.get_statistic_from(start_time, period)
  return get_statistic_impl(start_time, period or (now() - start_time))
end

function _M.get_statistic_table(period, portion, backward)
  local t = {}

  update_time()

  for time = now() - (backward or 0) - (period or 60), now() - (backward or 0), portion or 60
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

  for time = start_time, start_time + (period or now() - start_time), portion or 60
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

local check_point = now()

local function try_check_point()
  if check_point > now() then
    return
  end

  while not STAT:object_set(buffer_key, buffer)
  do
    purge()
  end

  STAT_BUFFER:delete(req_queue)
  STAT_BUFFER:delete(ups_queue)

  check_point = now() + 1
end

local function add_stat(t, start_time, latency)
  latency = tonumber(latency) or 0
  if next(t) then
    t.first, t.last, t.count, t.latency =
      min(t.first, start_time), max(t.last, start_time), t.count + 1, t.latency + latency
  else
    t.first, t.last, t.count, t.latency = start_time, start_time, 1, latency
  end
  try_check_point()
end

function _M.spawn_collector()
  buffer = STAT:object_get(buffer_key) or {
    reqs = {}, ups = {}
  }

  id = worker_id()
  req_queue, ups_queue, buffer_key = "r:" .. id, "u:" .. id, "b:" .. id

  repeat
    local req = STAT_BUFFER:lpop(req_queue)
    if req then
      local uri, status, start_time, request_time = req:match("(.+)|(.+)|(.+)|(.+)")
      add_stat(gett(buffer.reqs, uri, status),
               start_time, request_time)
    end
  until not req

  repeat
    local req = STAT_BUFFER:lpop(ups_queue)
    if req then
      local upstream, status, addr, start_time, response_time = req:match("(.+)|(.+)|(.+)|(.+)|(.+)")
      add_stat(gett(buffer.ups, upstream, addr, status),
               start_time, response_time)
    end
  until not req

  STAT:object_set(buffer_key, buffer)

  job.new("lastlog worker #" .. id, do_collect, collect_time_min):run()
end

function _M.purge()
  purge()
end

local function rpush(key, ...)
  local len
  repeat
    len = STAT_BUFFER:rpush(key, ...)
    if not len then
      -- no memory
      STAT_BUFFER:lpop(key)
    end
  until len
end

function _M.add_uri_stat(uri, status, start_time, request_time)
  rpush(req_queue, tconcat( { uri, status, start_time, request_time }, "|" ))
  add_stat(gett(buffer.reqs, uri, status),
           start_time, request_time)
end

function _M.add_ups_stat(upstream, status, addr, start_time, response_time)
  rpush(ups_queue, tconcat( { upstream, status, addr, start_time, response_time }, "|" ))
  add_stat(gett(buffer.ups, upstream, addr, status),
           start_time, response_time)
end

return _M