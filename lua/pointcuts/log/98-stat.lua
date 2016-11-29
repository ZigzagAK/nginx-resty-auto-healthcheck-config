local _M = {
  _VERSION = "1.0.0"
}

local upstream = require "ngx.dynamic_upstream"
local cjson = require "cjson"

local STAT   = ngx.shared.stat
local CONFIG = ngx.shared.config

local gsub_uri = CONFIG:get("http.stat.gsub_uri")

if gsub_uri then
  local gsub_mod_name, gsub_mod_func = gsub_uri:match("(.+)%.(.+)$")
  local ok, gsub_mod = pcall(require, gsub_mod_name)
  if ok then
    gsub_uri = gsub_mod[gsub_mod_func]
  end
  if not gsub_uri then
    ngx.log(ngx.ERR, CONFIG:get("http.stat.gsub_uri") .. " is not found")
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
  local upstream_status = ngx.var.upstream_status:match("(%d+)$")  -- get last from chain
  local upstream_response_time = ngx.var.upstream_response_time

  if not upstream_status then
    upstream_status = 499
    upstream_response_time = 0
  end

  local key = u .. "|" .. upstream_status .. "|" .. upstream_addr

  STAT:incr("upstream_n:" .. key, 1, 0)                              -- upstream request count by status
  STAT:incr("upstream_t:" .. key, upstream_response_time, 0) -- upstream total latency by status
end

local function accum_uri_stat()
  local uri = ngx.var.uri

  if gsub_uri then
    uri = gsub_uri(uri)
  end

  local key = "none|" .. ngx.var.status .. "|" .. uri

  STAT:incr("uri_n:" .. key, 1, 0)                    -- uri request count by status
  STAT:incr("uri_t:" .. key, ngx.var.request_time, 0) -- uri request total latency by status
end

function _M.process()
  STAT:safe_add("time_start", ngx.now()) -- register start accumulate time (if exists - not added)
  accum_upstream_stat()
  accum_uri_stat()
end

return _M