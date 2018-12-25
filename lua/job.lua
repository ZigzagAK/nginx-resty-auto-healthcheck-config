local _M = {
  _VERSION = "1.9.0"
}

local lock  = require "resty.lock"
local shdict = require "shdict"

local JOBS = shdict.new("jobs")

local ipairs = ipairs
local update_time = ngx.update_time
local ngx_now = ngx.now
local worker_exiting = ngx.worker.exiting
local timer_at = ngx.timer.at
local ngx_log = ngx.log
local INFO, ERR, WARN, DEBUG = ngx.INFO, ngx.ERR, ngx.WARN, ngx.DEBUG
local xpcall, setmetatable = xpcall, setmetatable
local worker_pid = ngx.worker.pid
local tinsert = table.insert
local assert = assert
local random = math.random

local workers = ngx.worker.count()

local function now()
  update_time()
  return ngx_now()
end

local main

local function make_key(self, key)
  return self.key .. "$" .. key
end

local function set_next_time(self, interval)
  local next_time = now() + (interval or self.interval)
  JOBS:set(make_key(self, "next"), next_time)
  return next_time
end

local function get_next_time(self)
  local next_time = JOBS:get(make_key(self, "next"))
  if not next_time then
    next_time = now()
    JOBS:set(make_key(self, "next"), next_time)
  end
  return next_time
end

--- @param #Job self
local function run_job(self, delay, ...)
  if worker_exiting() then
    return self:finish(...)
  end

  local ok, err = timer_at(delay, main, self, ...)
  if not ok then
    ngx_log(ERR, self.key .. " failed to add timer: ", err)
    self:stop()
    self:clean()
    return false
  end

  return true
end

local function wait_others(self)
  local wait_others = self.wait_others
  for i=1,#wait_others
  do
    if not wait_others[i]:completed(true) then
      return false
    end
  end
  self.wait_others = {}
  return true
end

main = function(premature, self, ...)
  if premature or not self:running() then
    return self:finish(...)
  end

  if not wait_others(self) then
    return run_job(self, 1, ...)
  end

  local remains = self.mutex:lock(make_key(self, "mtx"))
  if not remains then
    return run_job(self, 0.2, ...)
  end

  if self:suspended() then
    self.mutex:unlock()
    return run_job(self, 1, ...)
  end

  if not self:running() then
    self.mutex:unlock()
    return self:finish(...)
  end

  local next_time = get_next_time(self)

  if now() >= next_time then
    local counter = JOBS:incr(make_key(self, "counter"), 1, -1)
    local ok, err = xpcall(self.callback, function(err)
      ngx.log(ngx.ERR, debug.traceback())
      return err
    end, { counter = counter, hup = self.pid == nil }, ...)

    if not self.pid then
      self.pid = worker_pid()
    end
    if not ok then
      ngx_log(WARN, "job ", self.key, ": ", err)
    end

    local new_next_time = get_next_time(self)
    if new_next_time == next_time then
      next_time = set_next_time(self)
    else
      -- next time changed from outside
      next_time = new_next_time
    end
  end

  local delay = next_time - now() + random(0, workers - 1) / 10

  run_job(self, delay, ...)

  self.mutex:unlock()
end

--- @type Job
local job = {}

-- public api

--- @return #Job
function _M.new(name, callback, interval, finish)
  local j = {
    callback    = callback,
    finish_fn   = finish,
    interval    = interval,
    key         = name,
    wait_others = {},
    pid         = nil,
    cached      = {},
    mutex       = lock:new("jobs", { timeout = 0.2, exptime = 600, step = 0.2 })
  }
  return setmetatable(j, { __index = job })
end

--- @param #Job self
function job:run(...)
  if not self:completed(true) then
    if not self:running(true) then
      ngx_log(INFO, "job ", self.key, " start")
      JOBS:set(make_key(self, "running"), 1)
    end
    self:running(true)
    return assert(run_job(self, 0, ...))
  end
  ngx_log(DEBUG, "job ", self.key, " already completed")
  return nil, "completed"
end

--- @param #Job self
function job:set_next(interval)
  return set_next_time(self, interval)
end

--- @param #Job self
function job:suspend()
  if not self:suspended() then
    ngx_log(INFO, "job ", self.key, " suspended")
    JOBS:set(make_key(self, "suspended"), 1)
  end
end

--- @param #Job self
function job:resume()
  if self:suspended() then
    ngx_log(INFO, "job ", self.key, " resumed")
    JOBS:delete(make_key(self, "suspended"))
  end
end

--- @param #Job self
function job:stop()
  JOBS:delete(make_key(self, "running"))
  JOBS:set(make_key(self, "completed"), 1)
  ngx_log(INFO, "job ", self.key, " stopped")
end

local function check_cached(self, flag, nocache)
  local sec = now()
  local c = self.cached[flag]
  if not c or nocache or sec - c.last > 1 then
    if not c then
      c = {}
      self.cached[flag] = c
    end
    c.b = JOBS:get(make_key(self, flag)) == 1
    c.last = sec
  end
  return c.b
end

--- @param #Job self
function job:completed(nocache)
  return check_cached(self, "completed", nocache)
end

--- @param #Job self
function job:running(nocache)
  return check_cached(self, "running", nocache)
end

--- @param #Job self
function job:suspended(nocache)
  return check_cached(self, "suspended", nocache)
end

--- @param #Job self
function job:finish(...)
  if self.finish_fn then
    self.finish_fn(...)
  end
  return true
end

--- @param #Job self
function job:wait_for(other)
  tinsert(self.wait_others, other)
end

--- @param #Job self
function job:clean()
  if not self:running(true) then
    JOBS:delete(make_key(self, "running"))
    JOBS:delete(make_key(self, "completed"))
    JOBS:delete(make_key(self, "suspended"))
    return true
  end
  return false
end

return _M
