local _M = {
  _VERSION = "1.0.0"
}

local upstream = require "ngx.dynamic_upstream"

local STAT   = ngx.shared.stat
local CONFIG = ngx.shared.config

local cache = {}

local gsub_uri = CONFIG:get("http.stat.gsub_uri")

if gsub_uri then
  local package, func = gsub_uri:match("(.+)%.(.+)$")
  local ok, mod = pcall(require, package)
  if ok then
    gsub_uri = mod[func]
  end
  if not gsub_uri then
    ngx.log(ngx.ERR, CONFIG:get("http.stat.gsub_uri") .. " is not found")
  end
end

local ok, upstreams, err = upstream.get_upstreams()
if not ok then
  ngx.log(ngx.WARN, "Can't get upstream list")
end

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
    upstream_addr = upstream_addr:match("(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?%:%d%d?%d?%d?%d?)$")
  end

  if not upstream_addr then
    return
  end

  local u = get_upstream(upstream_addr)

  local key = u .. ":" .. ngx.var.upstream_status .. ":" .. upstream_addr

  STAT:incr("upstream_status:"  .. key, 1, 0)                              -- upstream request count by status
  STAT:incr("upstream_latency:" .. key, ngx.var.upstream_response_time, 0) -- upstream total latency by status
end

local function accum_uri_stat()
  local uri = ngx.var.uri

  if gsub_uri then
    uri = gsub_uri(uri)
  end

  local key = ngx.var.status .. ":" .. uri

  STAT:incr("uri_count:"   .. key, 1, 0)                    -- uri request count by status
  STAT:incr("uri_latency:" .. key, ngx.var.request_time, 0) -- uri request total latency by status
end

function _M.process()
  STAT:safe_add("time_start", ngx.now()) -- register start accumulate time (if exists - not added)
  accum_upstream_stat()
  accum_uri_stat()
end

return _M