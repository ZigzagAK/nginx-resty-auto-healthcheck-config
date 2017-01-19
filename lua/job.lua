local _M = {
  _VERSION = "1.0.0"
}

local lock  = require "resty.lock"

local JOBS = ngx.shared.jobs

local main

local function run_job(delay, obj, ...)
  if not ngx.worker.exiting() then
    local ok, err = ngx.timer.at(delay, main, obj, ...)
    if not ok then
      ngx.log(ngx.ERR, obj.key .. " failed to add timer: ", err)
      obj:stop()
      obj:clean()
    end
    return
  end
  obj:finish()
end

main = function(premature, self, ...)
  if premature then
    self:finish()
    return
  end

  if not self:running() then
    return
  end

  for _,other in ipairs(self.wait_others)
  do
    if not other:completed() then
      run_job(0.1, self, ...)
      return
    end
  end

  local mtx = lock:new("jobs", { timeout = 0.1, exptime = 600 })

  local remains, err = mtx:lock(self.key .. ":mtx")
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

  ngx.update_time()

  if ngx.now() >= self:get_next_time() then
    local counter = JOBS:incr(self.key .. ":counter", 1, -1)
    local ok, err = pcall(self.callback, { counter = counter,
                                           hup = self.pid == nil }, ...)
    if not self.pid then
      self.pid = ngx.worker.pid()
    end
    if not ok then
      ngx.log(ngx.WARN, self.key, ": ", err)
    end
    self:set_next_time()
  end

  mtx:unlock()

  ngx.update_time()

  run_job(self:get_next_time() - ngx.now(), self, ...)
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
    ngx.log(ngx.INFO, "job ", self.key, " start")
    JOBS:set(self.key .. ":running", 1)
    self:set_next_time()
    return run_job(0, self, ...)
  end
  ngx.log(ngx.INFO, "job ", self.key, " already completed")
  return nil, "completed"
end

function job:suspend()
  ngx.log(ngx.INFO, "job ", self.key, " suspended")
  JOBS:set(self.key .. ":suspended", 1)
end

function job:resume()
  ngx.log(ngx.INFO, "job ", self.key, " resumed")
  JOBS:del(self.key .. ":suspended")
end

function job:stop()
  ngx.log(ngx.INFO, "job ", self.key, " stopped")
  JOBS:delete(self.key .. ":running")
  JOBS:set(self.key .. ":completed", 1)
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

function job:finish()
  if self.finish_fn then
    self.finish_fn()
  end
end

function job:wait_for(other)
  table.insert(self.wait_others, other)
end

function job:set_next_time()
  ngx.update_time()
  JOBS:set(self.key .. ":next", ngx.now() + self.interval)
end

function job:get_next_time()
  return JOBS:get(self.key .. ":next")
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