local _M = {
  _VERSION = "1.2.0"
}

local upstream = require "ngx.dynamic_upstream"
local cjson    = require "cjson"
local lastlog  = require "lastlog"
local shdict  = require "shdict"

local STAT   = shdict.new("stat")
local CONFIG = ngx.shared.config

local preprocess_uri = CONFIG:get("http.stat.preprocess_uri")

local debug_enabled = false

local function debug(...)
  if debug_enabled then
    ngx.log(ngx.DEBUG, ...)
  end
end

if preprocess_uri then
  local gsub_mod_name, gsub_mod_func = preprocess_uri:match("(.+)%.(.+)$")
  local ok, gsub_mod = pcall(require, gsub_mod_name)
  if ok then
    preprocess_uri = gsub_mod[gsub_mod_func]
  end
  if not preprocess_uri then
    ngx.log(ngx.ERR, CONFIG:get("http.stat.preprocess_uri"), " is not found")
  end
end

local function get_request_time()
  local now = ngx.now()
  local request_time = ngx.var.request_time or 0
  return now - request_time, request_time
end

local function accum_upstream_stat()
  local ok, u, err = upstream.current_upstream()
  if not u then
    u = "proxypass"
  end

  local upstream_addr = ngx.var.upstream_addr
  if not upstream_addr then
    return
  end

  upstream_addr = upstream_addr:match("([^%s,]+)$") -- get last from chain

  if u == upstream_addr then
    -- error query
    upstream_addr = "ERROR"
  end

  local upstream_status        = ngx.var.upstream_status:match("(%d+)$")                           -- get last from chain
  local upstream_response_time = tonumber(ngx.var.upstream_response_time:match("([%d%.]+)$") or 0) -- get last from chain

  local key = u .. "|" .. (upstream_status or 499) .. "|" .. upstream_addr
  local start_request_time = ngx.now() - upstream_response_time

  ok, err = STAT:add("first:"    .. key, start_request_time)        -- first request start time
  ok, err = STAT:set("last:"     .. key, start_request_time)        -- last request start time
  ok, err = STAT:incr("count:"   .. key, 1, 0)                      -- upstream request count by status
  ok, err = STAT:incr("latency:" .. key, upstream_response_time, 0) -- upstream total latency by status

  if not ok then
    error(err)
  end

  debug("stat pointcut: key=", key, " start_request_time=", start_request_time, " upstream_response_time=", upstream_response_time)
end

local function accum_uri_stat()
  local uri = ngx.var.uri
  local ok, transformed

  if preprocess_uri then
    ok, transformed = pcall(preprocess_uri, uri)
    if ok then
      uri = transformed
      ngx.ctx.uri = transformed
    end
  end

  local key = "none|" .. (ngx.var.status or 499) .. "|" .. (uri or "/")
  local start_request_time, request_time = get_request_time()

  local err

  ok, err = STAT:add("first:"    .. key, start_request_time) -- first request start time
  ok, err = STAT:set("last:"     .. key, start_request_time) -- last request start time
  ok, err = STAT:incr("count:"   .. key, 1, 0)               -- uri request count by status
  ok, err = STAT:incr("latency:" .. key, request_time, 0)    -- uri request total latency by status

  if not ok then
    error(err)
  end

  debug("stat pointcut: key=", key, " start_request_time=", start_request_time, " latency=", request_time)
end

function _M.process()
  ngx.update_time()
  local ok, err = pcall(accum_upstream_stat)
  if ok then
    ok, err = pcall(accum_uri_stat)
  end
  if not ok then
    if err == "no memory" then
      lastlog.purge()
      err = "stat pointcut: increase [lua_shared_dict stat] or decrease [http.stat.collect_time_max]"
    end
    error(err)
  end
end

return _M
