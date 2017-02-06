local _M = {
  _VERSION = "1.2.0"
}

local CONFIG = ngx.shared.config

function _M.preprocess_uri_simple(uri)
  return uri:gsub("/%d+[^/]+%d+", "/xxx")
            :gsub("/%d+",         "/xxx")
end

function _M.preprocess_uri_stub(uri)
  return uri
end

function _M.config()
  CONFIG:set("http.stat.collect_time_min", 1)
  CONFIG:set("http.stat.collect_time_max", 7200)
  CONFIG:set("http.stat.preprocess_uri", "sysconfig.01-stat.preprocess_uri_stub")
end

return _M
