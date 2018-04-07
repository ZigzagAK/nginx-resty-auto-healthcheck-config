local _M = {
  _VERSION = "1.9.0"
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
local min, max, floor = math.min, math.max, math.floor
local type = type
local tonumber, tostring = tonumber, tostring
local update_time = ngx.update_time
local ngx_now = ngx.now

local ngx_log = ngx.log
local WARN, ERR, DEBUG = ngx.WARN, ngx.ERR, ngx.DEBUG

local foreach, foreach_v = lib.foreach, lib.foreach_v

local function normalizeOffset(offset)
  return floor(offset / collect_time_min) * collect_time_min
end

local function now()
  return normalizeOffset(ngx_now())
end

local function pull_statistic()
  if not next(buffer.reqs) then
    return
  end

  local offset_min = now()
  local offset_max = 0

  -- request statistic
  foreach(buffer.reqs or {}, function(off, reqs)
    off = tonumber(off)
    offset_min = min(offset_min, off)
    offset_max = max(offset_max, off)
    foreach_v(reqs, function(uri)
      foreach(uri, function(status, ports)
        foreach(ports, function(port, stat)
          ports[port] = tconcat( { stat.latency / stat.count, stat.count }, "|")
        end)
      end)
    end)
  end)

  -- upstream statistic
  foreach(buffer.ups or {}, function(off, ups)
    off = tonumber(off)
    offset_min = min(offset_min, off)
    offset_max = max(offset_max, off)
    foreach_v(ups, function(upstream)
      foreach_v(upstream, function(addr)
        foreach(addr, function(status, stat)
          addr[status] = tconcat( { stat.latency / stat.count, stat.count }, "|")
        end)
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

  r.offset_min = offset_min
  r.offset_max = offset_max

  return r
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
  local stat = pull_statistic()
  if not stat then
    return
  end

  local j = CONFIG:incr("$stat:last", 1, 0)

  while not STAT:object_add(j, stat, collect_time_max)
  do
    purge()
  end

  STAT:flush_expired()
end

local function merge(l, r, offset)
  local curr_offset = now()
  foreach(r or {}, function(k, v)
    local lk = l[k]
    if type(v) == "table" then
      if not lk then
        lk = {}
        l[k] = lk
      end
      merge(lk, v, offset)
    else
      if not lk then
        lk = {
          latency = 0,
          count = 0,
          recs = 0,
          current_rps = 0,
          average_rps = 0
        }
        l[k] = lk
      end
      local latency, count = v:match("(.+)|(.+)")
      lk.latency = lk.latency + tonumber(latency)
      lk.count = lk.count + tonumber(count)
      lk.recs = lk.recs + 1
      if offset >= curr_offset - collect_time_min then
        lk.current_rps = lk.current_rps + tonumber(count) / collect_time_min
      end
    end
  end)
end

local function get_statistic_impl(from, period)
  local t = { reqs = {}, ups = {} }
  local miss = 0
  local offset_min = now()
  local offset_max = 0

  period = tonumber(period)

  ngx_log(DEBUG, from, ":", period)

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

    if stat_j.offset_max < from then
      break
    end

    if stat_j.offset_min >= from + period then
      goto continue
    end

    ngx_log(DEBUG, stat_j.offset_min, "-", stat_j.offset_max)

    foreach(stat_j.reqs, function(off, stat)
      off = tonumber(off)
      if from <= off and off < from + period then
        merge(t.reqs, stat, off)
        offset_min = min(off, offset_min)
        offset_max = max(off, offset_max)
      end
    end)

    foreach(stat_j.ups, function(off, stat)
      off = tonumber(off)
      if from <= off and off < from + period then
        merge(t.ups, stat, off)
        offset_min = min(off, offset_min)
        offset_max = max(off, offset_max)
      end
    end)

:: continue ::
  end

  period = offset_max - offset_min + collect_time_min

  -- request statistic

  local reqs = {
    requests = t.reqs,
    stat = {
      average_rps = 0,
      current_rps = 0
    }
  }

  local http_x = {}

  local sum_latency, count = 0, 0

  foreach(reqs.requests, function(uri, uri_data)
    local uri_count = 0
    foreach(uri_data, function(status, ports)
      if not http_x[status] then
        http_x[status] = {}
      end
      local count = 0
      foreach(ports, function(port, stat)
        stat.latency = stat.latency / stat.recs
        stat.average_rps = stat.count / period
        if not http_x[status][port] then
          http_x[status][port] = {}
        end
        http_x[status][port][uri] = stat
        reqs.stat.current_rps = reqs.stat.current_rps + stat.current_rps
        reqs.stat.average_rps = reqs.stat.average_rps + stat.average_rps
        count = count + stat.count
        sum_latency = sum_latency + stat.latency
      end)
      ports.count = count
      uri_count = uri_count + count
    end)
    uri_data.count = uri_count
  end)

  if count ~= 0 then
    reqs.stat.average_latency = sum_latency / count
  end

  -- upstream statistic

  local ups = { upstreams = t.ups, stat = {} }
  
  foreach(ups.upstreams, function(u, peers)
    local sum_latency, count = 0, 0
    local ustat = { current_rps = 0, average_rps = 0 }
    foreach_v(peers, function(data)
      foreach_v(data, function(stat)
        stat.latency = stat.latency / stat.recs
        stat.average_rps = stat.count / period
        count = count + stat.count
        sum_latency = sum_latency + stat.latency * stat.count
        ustat.current_rps = ustat.current_rps + stat.current_rps
        ustat.average_rps = ustat.average_rps + stat.average_rps
      end)
    end)
    if count ~= 0 then
      ustat.average_latency = sum_latency / count
    end
    ups.stat[u] = ustat
  end)

  return reqs, ups, http_x, offset_min, period
end

-- public api

function _M.collapse_ports(requests, http_x)
  local noports = {
    requests = {},
    http_x = {}
  }

  foreach(requests, function(uri, ports)
    local agg = {
      latency = 0,
      count = 0,
      recs = 0,
      current_rps = 0,
      average_rps = 0
    }
    local ports_n = 0
    foreach_v(ports, function(list)
      if type(list) == "table" then
        foreach_v(list, function(stat)
          if type(stat) == "table" then
            agg.latency = agg.latency + stat.latency
            agg.count = agg.count + stat.count
            agg.recs = agg.recs + stat.recs
            agg.current_rps = agg.current_rps + stat.current_rps
            agg.average_rps = agg.average_rps + stat.average_rps
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
              latency = 0,
              count = 0,
              recs = 0,
              current_rps = 0,
              average_rps = 0
            }
            agg[uri] = agg_by_uri
          end
          agg_by_uri.latency = agg_by_uri.latency + stat.latency
          agg_by_uri.count = agg_by_uri.count + stat.count
          agg_by_uri.recs = agg_by_uri.recs + stat.recs
          agg_by_uri.current_rps = agg_by_uri.current_rps + stat.current_rps
          agg_by_uri.average_rps = agg_by_uri.average_rps + stat.average_rps
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

function _M.get_statistic(interval, backward, withports)
  update_time()
 
  local curr_offset = now()  

  backward = backward or 0
  interval = interval or 60

  local reqs, ups, http_x, offset, period = get_statistic_impl(curr_offset - backward - interval, interval)
  if not withports then
    reqs.requests, http_x = _M.collapse_ports(reqs.requests, http_x)
  end
  return reqs, ups, http_x, offset, period
end

function _M.get_statistic_from(from, interval, withports)
  from = normalizeOffset(from)
  local reqs, ups, http_x, offset, period = get_statistic_impl(from, interval or now() - from)
  if not withports then
    reqs.requests, http_x = _M.collapse_ports(reqs.requests, http_x)
  end
  return reqs, ups, http_x, offset, period
end

function _M.get_statistic_table(period, portion, backward, withports)
  update_time()

  local t = {}
  local curr_offset = now()

  backward = backward or 0
  period = period or 60
  portion = portion or 60

  update_time()

  for from = curr_offset - backward - period, curr_offset - backward, portion
  do
    local reqs, ups, http_x, offset = get_statistic_impl(from, portion)
    if not withports then
      reqs.requests, http_x = _M.collapse_ports(reqs.requests, http_x)
    end
    tinsert(t, { requests_statistic = reqs,
                 upstream_staistic = ups,
                 http_x = http_x,
                 time = offset } )
  end
  return t
end

function _M.get_statistic_table_from(from, period, portion, withports)
  update_time()

  local t = {}
  local curr_offset = now()

  from = normalizeOffset(from)
  portion = portion or 60

  for time = from, from + (period or curr_offset - from), portion
  do
    local reqs, ups, http_x, offset = get_statistic_impl(time, portion)
    if not withports then
      reqs.requests, http_x = _M.collapse_ports(reqs.requests, http_x)
    end
    tinsert(t, { requests_statistic = reqs,
                 http_x = http_x,
                 upstream_staistic = ups,
                 time = offset } )
  end

  return t
end

local function gett(t, ...)
  local n = select("#",...)
  for i=1,n
  do
    local k = tostring(select(i,...))
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

local function add_stat(t, latency)
  latency = tonumber(latency) or 0
  if next(t) then
    t.count, t.latency = t.count + 1, t.latency + latency
  else
    t.count, t.latency = 1, latency
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
      local uri, status, offset, request_time, port = req:match("(.+)|(.+)|(.+)|(.+)|(.+)")
      add_stat(gett(offset, buffer.reqs, uri, status, port),
               request_time)
    end
  until not req

  repeat
    local req = STAT_BUFFER:lpop(ups_queue)
    if req then
      local upstream, status, addr, offset, response_time = req:match("(.+)|(.+)|(.+)|(.+)|(.+)")
      add_stat(gett(offset, buffer.ups, upstream, addr, status),
               response_time)
    end
  until not req

  STAT:object_set(buffer_key, buffer)

  job.new("lastlog worker #" .. id, do_collect, 1):run()
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

function _M.add_uri_stat(uri, status, offset, request_time)
  local port = ngx.var.server_port
  offset = normalizeOffset(offset)
  rpush(req_queue, tconcat( { port, uri, status, offset, request_time }, "|" ))
  add_stat(gett(buffer.reqs, offset, uri, status, port),
           request_time)
end

function _M.add_ups_stat(upstream, status, addr, offset, response_time)
  offset = normalizeOffset(offset)
  rpush(ups_queue, tconcat( { upstream, status, addr, offset, response_time }, "|" ))
  add_stat(gett(buffer.ups, offset, upstream, addr, status),
           response_time)
end

return _M