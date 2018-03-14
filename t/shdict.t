use Test::Nginx::Socket;
use Test::Nginx::Socket::Lua::Stream;

repeat_each(2);

plan tests => repeat_each() * 2 * blocks();

$ENV{TEST_NGINX_MEMCACHED_PORT} ||= 11211;
$ENV{TEST_NGINX_MYSQL_PORT} ||= 3306;

run_tests();

__DATA__

=== TEST 1: get_all_keys
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict test_1 1m;
    lua_shared_dict test_2 1m;
    lua_shared_dict test_3 1m;
    lua_shared_dict test_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
      local dict = require "shdict"
      test = dict.new("test")
      sum = 0
      for i=1,9999
      do
        test:set(i, i)
        sum = sum + i
      end
    }
--- config
    location /test {
        content_by_lua_block {
          local keys = test:get_keys(0)
          for i=1,#keys
          do
            sum = sum - i
          end
          ngx.say(sum)
        }
    }
--- request
    GET /test
--- response_body
0

=== TEST 2: get_all_values
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict test_1 1m;
    lua_shared_dict test_2 1m;
    lua_shared_dict test_3 1m;
    lua_shared_dict test_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
      local dict = require "shdict"
      test = dict.new("test")
      sum = 0
      for i=1,9999
      do
        test:set(i, i)
        sum = sum + i
      end
    }
--- config
    location /test {
        content_by_lua_block {
          local values = test:get_values(0)
          for i=1,#values
          do
            sum = sum - values[i].value
          end
          ngx.say(sum)
        }
    }
--- request
    GET /test
--- response_body
0

=== TEST 3: get_all_objects
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict test_1 1m;
    lua_shared_dict test_2 1m;
    lua_shared_dict test_3 1m;
    lua_shared_dict test_4 1m;
    init_by_lua_block {
      require "lua.pointcuts.common"
      local dict = require "shdict"
      test = dict.new("test")
      sum = 0
      for i=1,9999
      do
        test:object_set(i, { i = i })
        sum = sum + i
      end
    }
--- config
    location /test {
        content_by_lua_block {
          local objects = test:get_objects(0)
          for i=1,#objects
          do
            sum = sum - objects[i].object.i
          end
          ngx.say(sum)
        }
    }
--- request
    GET /test
--- response_body
0

=== TEST 4: get_all_objects one chunk
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict test 10m;
    init_by_lua_block {
      require "lua.pointcuts.common"
      local dict = require "shdict"
      test = dict.new("test")
      sum = 0
      for i=1,9999
      do
        test:object_set(i, { i = i })
        sum = sum + i
      end
    }
--- config
    location /test {
        content_by_lua_block {
          local objects = test:get_objects()
          for i=1,#objects
          do
            sum = sum - objects[i].object.i
          end
          ngx.say(sum)
        }
    }
--- request
    GET /test
--- response_body
0

=== TEST 5: ttl
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict test 10m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location /test {
        content_by_lua_block {
          local dict = require "shdict"
          local test = dict.new("test")
          test:set("x", 1, 10)
          ngx.say(test:ttl("x"))
          test:expire("x", 0)
          ngx.say(test:ttl("x"))
          test:expire("x", 10.5)
          ngx.say(test:ttl("x"))
          test:expire("x", 0)
          ngx.say(test:ttl("x"))
        }
    }
--- request
    GET /test
--- response_body
10
0
10.5
0

=== TEST 6: capacity
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict test 10m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location /test {
        content_by_lua_block {
          local dict = require "shdict"
          local test = dict.new("test")
          ngx.say(test:capacity())
        }
    }
--- request
    GET /test
--- response_body_like
^\d+$

=== TEST 7: free_space
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict test 10m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location /test {
        content_by_lua_block {
          local dict = require "shdict"
          local test = dict.new("test")
          ngx.say(test:free_space())
        }
    }
--- request
    GET /test
--- response_body_like
^\d+$


=== TEST 8: zadd
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict test 10m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location /test {
        content_by_lua_block {
          local dict = require "shdict"
          local test = dict.new("test")
          test:zadd("foo", "bar", 1)
          test:zadd("foo", "bar", 1)
          test:zadd("foo", "rab", 2)
          test:zadd("foo", "rab", 2)
          test:zscan("foo", function(key, value)
            ngx.say(key,"=",value)
          end)
        }
    }
--- request
    GET /test
--- response_body
bar=1
rab=2


=== TEST 9: object_zadd
--- http_config
    lua_package_path 'lua/?.lua;;';
    lua_shared_dict test 10m;
    init_by_lua_block {
      require "lua.pointcuts.common"
    }
--- config
    location /test {
        content_by_lua_block {
          local dict = require "shdict"
          local test = dict.new("test")
          test:delete("foo")
          test:object_zadd("foo", "bar", { val=1 })
          test:object_zadd("foo", "bar", { val=2 })
          test:object_zadd("foo", "rab", { val=3 })
          test:object_zadd("foo", "rab", { val=4 })
          test:object_zscan("foo", function(key, value)
            ngx.say(key,"=",value.val)
          end)
        }
    }
--- request
    GET /test
--- response_body
bar=1
rab=3
