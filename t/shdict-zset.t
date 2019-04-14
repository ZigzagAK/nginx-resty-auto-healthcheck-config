# vim:set ft= ts=4 sw=4 et fdm=marker:
use Test::Nginx::Socket::Lua;

repeat_each(2);

plan tests => repeat_each() * (blocks() * 3 + 0);

no_long_string();

run_tests();

__DATA__

=== TEST 1: zset & zget & zrem
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict dogs_1 1m;
    lua_shared_dict dogs_2 1m;
    lua_shared_dict dogs_3 1m;
    lua_shared_dict dogs_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location = /test {
        content_by_lua_block {
            local shdict = require "shdict"
            local dogs = shdict.new("dogs")

            local len, err = dogs:zset("foo", "bar", "hello")
            if len then
                ngx.say("zset ", len)
            else
                ngx.say("szet err: ", err)
            end

            local len, err = dogs:zset("foo", "foo", 999)
            if len then
                ngx.say("zset ", len)
            else
                ngx.say("szet err: ", err)
            end

            local zkey, val = dogs:zget("foo", "bar")
            ngx.say(zkey, " ", val)

            local zkey, val = dogs:zget("foo", "foo")
            ngx.say(zkey, " ", val)

            local val, err = dogs:zrem("foo", "bar")
            if val then
              ngx.say(val)
            else
              ngx.say("zrem err: ", err)
            end

            local val, err = dogs:zrem("foo", "foo")
            if val then
              ngx.say(val)
            else
              ngx.say("zrem err: ", err)
            end

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
zset 1
zset 2
bar hello
foo 999
hello
999
--- no_error_log
[error]


=== TEST 2: exptime
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict dogs_1 1m;
    lua_shared_dict dogs_2 1m;
    lua_shared_dict dogs_3 1m;
    lua_shared_dict dogs_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location = /test {
        content_by_lua_block {
            local shdict = require "shdict"
            local dogs = shdict.new("dogs")

            local len, err = dogs:zset("foo", "bar", "hello", 1)
            if len then
                ngx.say("zset ", len)
            else
                ngx.say("zset err: ", err)
            end

            local zkey, val = dogs:zget("foo", "bar")
            ngx.say(zkey, " ", val)

            ngx.sleep(2)
            
            local zkey, val = dogs:zget("foo", "bar")
            ngx.say(zkey)

            local len, err = dogs:zset("foo", "bar", "hello2")
            if len then
                ngx.say("zset ", len)
            else
                ngx.say("zset err: ", err)
            end

            local zkey, val = dogs:zget("foo", "bar")
            ngx.say(zkey, " ", val)

            local val, err = dogs:zrem("foo", "bar")
            if val then
              ngx.say(val)
            else
              ngx.say("zrem err: ", err)
            end

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
zset 1
bar hello
nil
zset 1
bar hello2
hello2
--- no_error_log
[error]


=== TEST 3: zset & zgetall
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict dogs_1 1m;
    lua_shared_dict dogs_2 1m;
    lua_shared_dict dogs_3 1m;
    lua_shared_dict dogs_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location = /test {
        content_by_lua_block {
            local shdict = require "shdict"
            local dogs = shdict.new("dogs")

            local vals = {
              { "a", 1 }, { "b", 2 }, { "c", 3 }, { "d", 4 }, { "e", 5 }
            }

            for _,v in ipairs(vals) do
               local len, err = dogs:zset("foo", unpack(v))
               if not len then
                   ngx.say("zset err: ", err)
               end
            end

            ngx.say(dogs:zcard("foo"))

            local v = dogs:zgetall("foo")
            for _,i in ipairs(v) do
              ngx.say(unpack(i))
            end
  
            for _,i in pairs(vals) do
               local zkey = unpack(i) 
               ngx.print(dogs:zrem("foo", zkey))
            end
            ngx.say()
            ngx.say(dogs:zcard("foo"))

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
5
a1
b2
c3
d4
e5
12345
0
--- no_error_log
[error]


=== TEST 4: zset & zscan
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict dogs_1 1m;
    lua_shared_dict dogs_2 1m;
    lua_shared_dict dogs_3 1m;
    lua_shared_dict dogs_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location = /test {
        content_by_lua_block {
            local shdict = require "shdict"
            local dogs = shdict.new("dogs")

            local vals = {
              { "a", 1 }, { "b", 2 }, { "c", 3 }, { "d", 4 }, { "e", 5 }
            }

            for _,v in ipairs(vals) do
               local len, err = dogs:zset("foo", unpack(v))
               if not len then
                   ngx.say("zset err: ", err)
               end
            end

            ngx.say(dogs:zcard("foo"))

            dogs:zscan("foo", function(k,v)
              ngx.say(k, v)
            end)

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
5
a1
b2
c3
d4
e5
--- no_error_log
[error]


=== TEST 5: zset & zscan (range)
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict dogs_1 1m;
    lua_shared_dict dogs_2 1m;
    lua_shared_dict dogs_3 1m;
    lua_shared_dict dogs_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location = /test {
        content_by_lua_block {
            local shdict = require "shdict"
            local dogs = shdict.new("dogs")

            local vals = {
              { "a", 1 },
              { "aa", 11 },
              { "b", 2 },
              { "bb", 22 },
              { "aaa", 111 },
              { "aab", 112 },
              { "x", 0 }
            }

            for _,v in ipairs(vals) do
               local len, err = dogs:zset("foo", unpack(v))
               if not len then
                   ngx.say("zset err: ", err)
               end
            end

            ngx.say(dogs:zcard("foo"))

            dogs:zscan("foo", function(k,v)
              if k:sub(1,2) ~= "aa" then
                return true
              end
              ngx.say(k, v)
            end, "aa")

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
7
aa11
aaa111
aab112
--- no_error_log
[error]


=== TEST 6: complex keys - zset & zget & zrem
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict dogs_1 1m;
    lua_shared_dict dogs_2 1m;
    lua_shared_dict dogs_3 1m;
    lua_shared_dict dogs_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location = /test {
        content_by_lua_block {
            local shdict = require "shdict"
            local dogs = shdict.new("dogs")

            local v = {
              { { a=1, b=1, c=1 }, 111 },
              { { a=1, b=1, c=2 }, 112 },
              { { a=1, b=1, c=3 }, 113 },
              { { a=1, b=2, c=1 }, 121 },
              { { a=1, b=2, c=2 }, 122 },
              { { a=1, b=2, c=3 }, 123 },
              { { a=1, b=3, c=1 }, 131 },
              { { a=1, b=3, c=2 }, 132 },
              { { a=1, b=3, c=3 }, 133 }
            }

            for _,i in ipairs(v)
            do
              local k,v = unpack(i)
              local len, err = dogs:zset("foo", k, v)
              if len then
                ngx.say(len)
              else
                ngx.say(err)
              end
            end

            for _,i in ipairs(v)
            do
              local k,v = unpack(i)
              local zkey, val, err = dogs:zget("foo", k, v)
              if zkey then
                ngx.say(zkey.a, zkey.b, zkey.c, " ", val)
              else
                ngx.say(err)
              end
            end

            for _,i in ipairs(v)
            do
              local k,v = unpack(i)
              local val, err = dogs:zrem("foo", k)
              if val then
                ngx.say(val)
              else
                ngx.say(err)
              end
            end

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
1
2
3
4
5
6
7
8
9
111 111
112 112
113 113
121 121
122 122
123 123
131 131
132 132
133 133
111
112
113
121
122
123
131
132
133
--- no_error_log
[error]


=== TEST 7: complex keys - object_zset & object_zget & object_zrem
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict dogs_1 1m;
    lua_shared_dict dogs_2 1m;
    lua_shared_dict dogs_3 1m;
    lua_shared_dict dogs_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location = /test {
        content_by_lua_block {
            local shdict = require "shdict"
            local dogs = shdict.new("dogs")

            local v = {
              { { a=1, b=1, c=1 }, { val=111 } },
              { { a=1, b=1, c=2 }, { val=112 } },
              { { a=1, b=1, c=3 }, { val=113 } },
              { { a=1, b=2, c=1 }, { val=121 } },
              { { a=1, b=2, c=2 }, { val=122 } },
              { { a=1, b=2, c=3 }, { val=123 } },
              { { a=1, b=3, c=1 }, { val=131 } },
              { { a=1, b=3, c=2 }, { val=132 } },
              { { a=1, b=3, c=3 }, { val=133 } }
            }

            for _,i in ipairs(v)
            do
              local k,v = unpack(i)
              local len, err = dogs:object_zset("foo", k, v)
              if len then
                ngx.say(len)
              else
                ngx.say(err)
              end
            end

            for _,i in ipairs(v)
            do
              local k,v = unpack(i)
              local zkey, val, err = dogs:object_zget("foo", k, v)
              if zkey then
                ngx.say(zkey.a, zkey.b, zkey.c, " ", val.val)
              else
                ngx.say(err)
              end
            end

            for _,i in ipairs(v)
            do
              local k,v = unpack(i)
              local val, err = dogs:object_zrem("foo", k)
              if val then
                ngx.say(val.val)
              else
                ngx.say(err)
              end
            end

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
1
2
3
4
5
6
7
8
9
111 111
112 112
113 113
121 121
122 122
123 123
131 131
132 132
133 133
111
112
113
121
122
123
131
132
133
--- no_error_log
[error]


=== TEST 8: object_zset & object_zscan
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict dogs_1 1m;
    lua_shared_dict dogs_2 1m;
    lua_shared_dict dogs_3 1m;
    lua_shared_dict dogs_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location = /test {
        content_by_lua_block {
            local shdict = require "shdict"
            local dogs = shdict.new("dogs")

            local vals = {
              { "a", { val=1 } }, { "b", { val = 2 } }, { "c", { val = 3 } }, { "d", { val = 4 } }, { "e", { val = 5 } }
            }

            for _,v in ipairs(vals) do
               local len, err = dogs:object_zset("foo", unpack(v))
               if not len then
                   ngx.say("zset err: ", err)
               end
            end

            ngx.say(dogs:zcard("foo"))

            dogs:object_zscan("foo", function(k,v)
              ngx.say(k, v.val)
            end)

            dogs:delete("foo")
        }
    }
--- request
GET /test
--- response_body
5
a1
b2
c3
d4
e5
--- no_error_log
[error]
