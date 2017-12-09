local _M = {
  _VERSION = "1.8.5",

  signal = {
    SIGHUP  = 1,
    SIGINT  = 2,
    SIGQUIT = 3,
    SIGABRT = 6,
    SIGKILL = 9
  }
}

local ffi = require 'ffi'

local C = ffi.C

ffi.cdef[[
  int getpid (void);
  int getppid (void);
  int kill(int pid, int sig);
  int usleep(unsigned int usec);
]]

function _M.getpid()
  return C.getpid()
end

function _M.getppid()
  return C.getppid()
end

function _M.kill(pid, sig)
  return C.kill(pid, sig)
end

function _M.sleep(sec)
  return C.usleep(sec * 1000000)
end

ffi.cdef[[
  struct DIR *opendir(const char *name);
  int closedir(struct DIR *dirp);

  typedef unsigned long int ino_t;
  typedef long int          off_t;

  struct dirent
  {
    ino_t              d_ino;
    off_t              d_off;
    unsigned short int d_reclen;
    unsigned char      d_type;
    char               d_name[256];
  };
  struct dirent *readdir(struct DIR *dirp);
]]

local assert = assert
local tinsert, tsort = table.insert, table.sort

local function scandir(dirname)
  local dir = C.opendir(dirname)
  if not dir then
    return {}
  end

  local entries = {}
  local dirent = C.readdir(dir)

  while dirent ~= nil do
    tinsert(entries, ffi.string(dirent.d_name))
    dirent = C.readdir(dir)
  end

  C.closedir(dir);

  return entries
end

function _M.getfiles(directory, mask)
  local entries = {}
  lib.foreachi(scandir(directory), function(file)
    if file:match(mask) then
      tinsert(entries, file)
    end
  end)
  tsort(entries, function(l, r) return l < r end)
  return entries
end

function _M.getmodules(directory, type)
  local entries = _M.getfiles(directory, "%.lua$")
  local mod_prefix = lib.path2lua_module(directory)
  local modules = {}
  type = type or lib.module_type()
  lib.foreachi(entries, function(file_name)
    local f = assert(io.open(directory .. "/" .. file_name))
    local content = f:read("*a")
    f:close()
    local mod_type = content:match([[_MODULE_TYPE%s*=%s*["']?([^"']+)["']?]]) or "http"
    if mod_type:lower() == type:lower() then
      local name = file_name:match("(.+)%.lua$")
      tinsert(modules, { name, mod_prefix .. "." .. name })
    end
  end)
  return modules
end

return _M