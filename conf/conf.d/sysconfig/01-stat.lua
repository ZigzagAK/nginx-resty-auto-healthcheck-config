local _M = {
  _VERSION = "1.0.0"
}

local CONFIG = ngx.shared.config

function _M.process_uri(uri)
  return uri:gsub("/%d+[^/]+%d+",  "/XXX")
            :gsub("/%d+",          "/XXX")
            :gsub("/msisdn:[^/]+", "/msisdn:XXX")
            :gsub("/msisdn%d+",    "/msisdnXXX")
            :gsub("C%d+D%d+I%d+",  "XXX")
            :gsub("/login:[^/]+",  "/login:XXX")
end

function _M.config()
  CONFIG:set("http.stat.interval", 60)
  CONFIG:set("http.stat.gsub_uri", "sysconfig.01-stat.process_uri")
end

return _M
