use Test::Nginx::Socket;
use Test::Nginx::Socket::Lua::Stream;

repeat_each(1);

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
