local _M = {
  _VERSION = "1.8.5"
}

local lock  = require "resty.lock"

local JOBS = ngx.shared.jobs

local ipairs = ipairs
local update_time = ngx.update_time
local ngx_now = ngx.now
local worker_exiting = ngx.worker.exiting
local timer_at = ngx.timer.at
local ngx_log = ngx.log
local INFO, ERR, WARN = ngx.INFO, ngx.ERR, ngx.WARN
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

local function set_next_time(self)
  JOBS:incr(self.key .. ":next", self.interval, now())
end

local function get_next_time(self)
  return JOBS:get(self.key .. ":next")
end

local function run_job(delay, self, ...)
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
      return run_job(0.1, self, ...)
    end
  end

  local mtx = lock:new("jobs", { timeout = 0.1, exptime = 600 })

  local remains = mtx:lock(self.key .. ":mtx")
  if not remains then
    if self:running() then
      run_job(0.1, self, ...)
    end
    return
  end

  if self:suspended() then
    run_job(0.1, self, ...)
    mtx:unlock()
    return
  end

  if not self:running() then
    mtx:unlock()
    return self:finish(...)
  end

  if now() >= get_next_time(self) then
    local counter = JOBS:incr(self.key .. ":counter", 1, -1)
    local ok, err = pcall(self.callback, { counter = counter,
                                           hup = self.pid == nil }, ...)
    if not self.pid then
      self.pid = worker_pid()
    end
    if not ok then
      ngx_log(WARN, self.key, ": ", err)
    end
    set_next_time(self)
  end

  mtx:unlock()

  run_job(get_next_time(self) - now() + random(0, workers - 1) / 10, self, ...)
end

local job = {}

-- public api

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

function job:run(...)
  if not self:completed() then
    ngx_log(INFO, "job ", self.key, " start")
    JOBS:set(self.key .. ":running", 1)
    set_next_time(self)
    return assert(run_job(0, self, ...))
  end
  ngx_log(INFO, "job ", self.key, " already completed")
  return nil, "completed"
end

function job:suspend()
  if not self:suspended() then
    ngx_log(INFO, "job ", self.key, " suspended")
    JOBS:set(self.key .. ":suspended", 1)
  end
end

function job:resume()
  if self:suspended() then
    ngx_log(INFO, "job ", self.key, " resumed")
    JOBS:delete(self.key .. ":suspended")
  end
end

function job:stop()
  JOBS:delete(self.key .. ":running")
  JOBS:set(self.key .. ":completed", 1)
  ngx_log(INFO, "job ", self.key, " stopped")
end

function job:completed()
  return JOBS:get(self.key .. ":completed") == 1
end

function job:running()
  return JOBS:get(self.key .. ":running") == 1
end

function job:suspended()
  return JOBS:get(self.key .. ":suspended") == 1
end

function job:finish(...)
  if self.finish_fn then
    self.finish_fn(...)
  end
  return true
end

function job:wait_for(other)
  tinsert(self.wait_others, other)
end


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