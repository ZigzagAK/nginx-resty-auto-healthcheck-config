_M = {
  _VERSION = "1.0.0",

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

local function scandir(dirname)
   if type(dirname) ~= 'string' then
     error("dirname not a string:", dirname)
   end

   local dir = C.opendir(dirname)
   if dir == nil then
     return {}
   end

   local entries = {}
   local dirent = C.readdir(dir)

   while dirent ~= nil do
      table.insert(entries, ffi.string(dirent.d_name))
      dirent = C.readdir(dir)
   end

   C.closedir(dir);

   return entries
end

function _M.getfiles(directory, mask)
  local t = {}
  for _, file in pairs(scandir(directory))
  do
    if file:match(mask) then
      table.insert(t, file)
    end
  end
  table.sort(t, function(l, r) return l < r end)
  return t
end

return _M
