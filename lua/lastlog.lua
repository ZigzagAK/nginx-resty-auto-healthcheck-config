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
  foreach_v(buffer.reqs or {}, function(uri)
    foreach(uri, function(status, ports)
      foreach(ports, function(port, stat)  
        start_time = min(stat.first, start_time)
        end_time = max(stat.last, end_time)
        ports[port] = tconcat( { stat.first, stat.last, stat.latency / stat.count, stat.count }, "|")
      end)
    end)
  end)

  -- upstream statistic
  foreach_v(buffer.ups or {}, function(upstream)
    foreach_v(upstream, function(addr)
      foreach(addr, function(status, stat)
        addr[status] = tconcat( { stat.first, stat.last, stat.latency / stat.count, stat.count }, "|")
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
  local t = { reqs = {}, ups = {}, reqs_by_port = {} }
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

  -- request statistic

  local http_x = {}

  local sum_latency = 0
  local sum_rps = 0
  local count = 0

  foreach(t.reqs.requests, function(uri, uri_data)
    local req_count = 0
    foreach(uri_data, function(status, ports)
      if not http_x[status] then
        http_x[status] = {}
      end
      local c = 0
      foreach(ports, function(port, stat)
        stat.latency = (stat.latency or 0) / stat.recs
        if not http_x[status][port] then
          http_x[status][port] = {}
        end
        http_x[status][port][uri] = stat
        count = count + stat.count
        c = c + stat.count
        sum_rps = sum_rps + stat.current_rps
        sum_latency = sum_latency + stat.latency * stat.count
      end)
      req_count = req_count + c
      ports.count = c
    end)
    uri_data.count = req_count
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

  return t.reqs, t.ups, http_x, now, now + period
end

-- public api

function _M.collapse_ports(requests, http_x)
  local noports = {
    requests = {},
    http_x = {}
  }
  local now = ngx.now()

  foreach(requests, function(uri, ports)
    local agg = {
      first = now,
      last = 0,
      latency = 0,
      count = 0,
      recs = 0,
      current_rps = 0
    }
    local ports_n = 0
    foreach_v(ports, function(list)
      if type(list) == "table" then
        foreach_v(list, function(stat)
          if type(stat) == "table" then
            agg.first = min(agg.first, stat.first)
            agg.last = max(agg.last, stat.last)
            agg.latency = agg.latency + stat.latency
            agg.count = agg.count + stat.count
            agg.recs = agg.recs + stat.recs
            agg.current_rps = agg.current_rps + stat.current_rps
          end
        end)
        ports_n = ports_n + 1
      end
    end)
    if ports_n ~= 0 then
      agg.latency = agg.latency / ports_n;
      noports.requests[uri] = agg
    end
  end)

  -- sort by latency desc
  foreach_v(noports.requests, function(by_uri)
    tsort(by_uri, function(l, r) return l.latency > r.latency end)
  end)

  foreach(http_x, function(status, ports)
    local agg = {}
    local ports_n = 0
    foreach_v(ports, function(by_uri)
      if type(by_uri) == "table" then
        foreach(by_uri, function(uri, stat)
          local agg_by_uri = agg[uri]
          if not agg_by_uri then
            agg_by_uri = {
              first = now,
              last = 0,
              latency = 0,
              count = 0,
              recs = 0,
              current_rps = 0
            }
            agg[uri] = agg_by_uri
          end
          agg_by_uri.first = min(agg_by_uri.first, stat.first)
          agg_by_uri.last = max(agg_by_uri.last, stat.last)
          agg_by_uri.latency = agg_by_uri.latency + stat.latency
          agg_by_uri.count = agg_by_uri.count + stat.count
          agg_by_uri.recs = agg_by_uri.recs + stat.recs
          agg_by_uri.current_rps = agg_by_uri.current_rps + stat.current_rps
        end)
        ports_n = ports_n + 1
      end
    end)
    if ports_n ~= 0 then
      noports.http_x[status] = agg
    end
  end)

  -- sort by latency desc
  foreach_v(noports.http_x, function(by_status)
    tsort(by_status, function(l, r) return l.latency > r.latency end)
  end)

  return noports.requests, noports.http_x
end

function _M.get_statistic(period, backward, withports)
  update_time()
  local reqs, ups, http_x, from, to = get_statistic_impl(now() - (backward or 0) - (period or 60), period or 60)
  if not withports then
    reqs.requests, http_x = _M.collapse_ports(reqs.requests, http_x)
  end
  return reqs, ups, http_x, from, to
end

function _M.get_statistic_from(start_time, period, withports)
  local reqs, ups, http_x, from, to = get_statistic_impl(start_time, period or (now() - start_time))
  if not withports then
    reqs.requests, http_x = _M.collapse_ports(reqs.requests, http_x)
  end
  return reqs, ups, http_x, from, to
end

function _M.get_statistic_table(period, portion, backward, withports)
  local t = {}

  update_time()

  for time = now() - (backward or 0) - (period or 60), now() - (backward or 0), portion or 60
  do
    local reqs, ups, http_x, _, _ = get_statistic_impl(time, portion or 60)
    if not withports then
      reqs.requests, http_x = _M.collapse_ports(reqs.requests, http_x)
    end
    tinsert(t, { requests_statistic = reqs,
                 upstream_staistic = ups,
                 http_x = http_x,
                 time = time } )
  end
  return t
end

function _M.get_statistic_table_from(start_time, period, portion, withports)
  local t = {}

  for time = start_time, start_time + (period or now() - start_time), portion or 60
  do
    local reqs, ups, http_x, _, _ = get_statistic_impl(time, portion or 60)
    if not withports then
      reqs.requests, http_x = _M.collapse_ports(reqs.requests, http_x)
    end
    tinsert(t, { requests_statistic = reqs,
                 http_x = http_x,
                 upstream_staistic = ups,
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
      local uri, status, start_time, request_time, port = req:match("(.+)|(.+)|(.+)|(.+)|(.+)")
      add_stat(gett(buffer.reqs, uri, status, port),
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
  local port = ngx.var.server_port
  rpush(req_queue, tconcat( { port, uri, status, start_time, request_time }, "|" ))
  add_stat(gett(buffer.reqs, uri, status, port),
           start_time, request_time)
end

function _M.add_ups_stat(upstream, status, addr, start_time, response_time)
  rpush(ups_queue, tconcat( { upstream, status, addr, start_time, response_time }, "|" ))
  add_stat(gett(buffer.ups, upstream, addr, status),
           start_time, response_time)
end

return _M