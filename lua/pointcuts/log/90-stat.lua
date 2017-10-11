local _M = {
  _VERSION = "1.8.0"
}

local upstream = require "ngx.dynamic_upstream"
local lastlog  = require "lastlog"

local tinsert = table.insert

local CONFIG = ngx.shared.config

local preprocess_uri = CONFIG:get("http.stat.preprocess_uri")

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

local function split(s)
  local t = {}
  for p in s:gmatch("([^%s,]+)")
  do
    tinsert(t, p)
  end
  return t
end

local function accum_upstream_stat(start_request_time)
  local ok, u = upstream.current_upstream()
  if not ok or not u then
    u = "proxypass"
  end

  local upstream_addr = ngx.var.upstream_addr
  if not upstream_addr then
    return
  end

  local addrs, codes, times =
    split(upstream_addr), split(ngx.var.upstream_status), split(ngx.var.upstream_response_time) or 0

  for i=1,#addrs
  do
    local upstream_addr = addrs[i]
    if upstream_addr == u then
      -- error query
      upstream_addr = "ERROR"
    end

    lastlog.add_ups_stat(u,
                         codes[i] or "???",
                         upstream_addr,
                         start_request_time,
                         times[i])
  end
end

local function accum_uri_stat()
  local orig_uri = ngx.var.request_uri or "/"
  local uri = orig_uri:sub(orig_uri:find("[^%?]+"))
  local ok, transformed

  if preprocess_uri then
    ok, transformed = pcall(preprocess_uri, uri)
    if ok then
      uri = transformed
      ngx.ctx.uri = transformed
    end
  end

  local start_request_time, request_time = get_request_time()

  lastlog.add_uri_stat(uri or "/",
                       ngx.var.status or "???",
                       start_request_time,
                       request_time)

  return start_request_time
end

function _M.process()
  ngx.update_time()
  local ok, start_request_time, err = pcall(accum_uri_stat)
  if ok then
    ok, err = pcall(accum_upstream_stat, start_request_time)
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
