local _M = {
  _VERSION = "1.0.0"
}

local upstream = require "ngx.dynamic_upstream"
local cjson = require "cjson"

local STAT   = ngx.shared.stat
local CONFIG = ngx.shared.config

local preprocess_uri = CONFIG:get("http.stat.preprocess_uri")

if preprocess_uri then
  local gsub_mod_name, gsub_mod_func = preprocess_uri:match("(.+)%.(.+)$")
  local ok, gsub_mod = pcall(require, gsub_mod_name)
  if ok then
    preprocess_uri = gsub_mod[gsub_mod_func]
  end
  if not preprocess_uri then
    ngx.log(ngx.ERR, CONFIG:get("http.stat.preprocess_uri") .. " is not found")
  end
end

local ok, upstreams, err = upstream.get_upstreams()
if not ok then
  ngx.log(ngx.WARN, "Can't get upstream list")
end

local cache = {}

local function get_upstream(addr)
  local u = cache[addr]
  if u then
    return u
  end

  for _, u in ipairs(upstreams)
  do
    local ok, peers, err = upstream.get_peers(u)
    if not ok then
      ngx.log(ngx.WARN, "Can't get upstream list")
      break
    end
    for _, p in ipairs(peers)
    do
      if p.name == addr then
        cache[addr] = u
        return u
      end
    end
  end

  cache[addr] = addr
  return addr
end

local function accum_upstream_stat()
  local upstream_addr = ngx.var.upstream_addr

  if upstream_addr then
    upstream_addr = upstream_addr:match("(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?%:%d%d?%d?%d?%d?)$") -- get last from chain
  end

  if not upstream_addr then
    return
  end

  local u = get_upstream(upstream_addr)

  local upstream_status        = ngx.var.upstream_status:match("(%d+)$")            -- get last from chain
  local upstream_response_time = ngx.var.upstream_response_time:match("([%d%.]+)$") -- get last from chain

  if not upstream_status then
    upstream_status = 499
  end

  if not upstream_response_time then
    upstream_response_time = 0
  end

  local key = u .. "|" .. upstream_status .. "|" .. upstream_addr
  local start_request_time = ngx.ctx.start_request_time

  STAT:safe_add("first_request_time:" .. key, start_request_time, 0) -- first request start time
  STAT:set("last_request_time:" .. key, start_request_time, 0)       -- last request start time
  STAT:incr("count:" .. key, 1, 0)                                   -- upstream request count by status
  STAT:incr("latency:" .. key, upstream_response_time, 0)            -- upstream total latency by status

  ngx.log(ngx.DEBUG, "stat pointcut: key=" .. key ..
                     ", start_request_time=" .. start_request_time ..
                     ", upstream_response_time=" .. upstream_response_time)
end

local function accum_uri_stat()
  local uri = ngx.var.uri

  if preprocess_uri then
    ok, transformed = pcall(preprocess_uri(uri))
    if ok then
      uri = transformed
    end
  end

  local key = "none|" .. (ngx.var.status or 499) .. "|" .. uri
  local start_request_time = ngx.ctx.start_request_time

  STAT:safe_add("first_request_time:" .. key, start_request_time, 0) -- first request start time
  STAT:set("last_request_time:" .. key, start_request_time, 0)       -- last request start time
  STAT:incr("count:" .. key, 1, 0)                                   -- uri request count by status
  STAT:incr("latency:" .. key, ngx.now() - start_request_time, 0)    -- uri request total latency by status

  ngx.log(ngx.DEBUG, "stat pointcut: key=" .. key ..
                     ", start_request_time=" .. start_request_time ..
                     ", latency=" .. ngx.now() - start_request_time)
end

function _M.process()
  pcall(accum_upstream_stat)
  pcall(accum_uri_stat)
end

return _M