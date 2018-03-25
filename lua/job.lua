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
local pcall, setmetatable = pcall, setmetatable
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

local function set_next_time(self, interval)
  interval = interval or self.interval
  JOBS:set(self.key .. ":next", now() + interval)
end

local function get_next_time(self)
  local next_time = JOBS:get(self.key .. ":next")
  if not next_time then
    next_time = now()
    JOBS:set(self.key .. ":next", next_time)
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

main = function(premature, self, ...)
  if premature or not self:running() then
    return self:finish(...)
  end

  for _,other in ipairs(self.wait_others)
  do
    if not other:completed() then
      return run_job(self, 0.1, ...)
    end
  end

  local mtx = lock:new("jobs", { timeout = 0.1, exptime = 600 })

  local remains = mtx:lock(self.key .. ":mtx")
  if not remains then
    if self:running() then
      run_job(self, 0.1, ...)
    end
    return
  end

  if self:suspended() then
    run_job(self, 0.1, ...)
    mtx:unlock()
    return
  end

  if not self:running() then
    mtx:unlock()
    return self:finish(...)
  end

  local next_time = get_next_time(self)

  if now() >= next_time then
    local counter = JOBS:incr(self.key .. ":counter", 1, -1)
    local ok, err = pcall(self.callback, { counter = counter,
                                           hup = self.pid == nil }, ...)
    if not self.pid then
      self.pid = worker_pid()
    end
    if not ok then
      ngx_log(WARN, self.key, ": ", err)
    end
    if get_next_time(self) == next_time then
      -- next time may be changed from outside
      set_next_time(self)
    end
  end

  mtx:unlock()

  run_job(self, get_next_time(self) - now() + random(0, workers - 1) / 10, ...)
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
    pid         = nil
  }
  return setmetatable(j, { __index = job })
end

--- @param #Job self
function job:run(...)
  if not self:completed() then
    if not self:running() then
      ngx_log(INFO, "job ", self.key, " start")
      JOBS:set(self.key .. ":running", 1)
    end
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
    JOBS:set(self.key .. ":suspended", 1)
  end
end

--- @param #Job self
function job:resume()
  if self:suspended() then
    ngx_log(INFO, "job ", self.key, " resumed")
    JOBS:delete(self.key .. ":suspended")
  end
end

--- @param #Job self
function job:stop()
  JOBS:delete(self.key .. ":running")
  JOBS:set(self.key .. ":completed", 1)
  ngx_log(INFO, "job ", self.key, " stopped")
end

--- @param #Job self
function job:completed()
  return JOBS:get(self.key .. ":completed") == 1
end

--- @param #Job self
function job:running()
  return JOBS:get(self.key .. ":running") == 1
end

--- @param #Job self
function job:suspended()
  return JOBS:get(self.key .. ":suspended") == 1
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
  if not self:running() then
    JOBS:delete(self.key .. ":running")
    JOBS:delete(self.key .. ":completed")
    JOBS:delete(self.key .. ":suspended")
    return true
  end
  return false
end

return _M