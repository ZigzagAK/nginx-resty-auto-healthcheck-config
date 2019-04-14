use Test::Nginx::Socket;
use Test::Nginx::Socket::Lua::Stream;

no_shuffle();

repeat_each(1);

plan tests => repeat_each() * (2 * blocks() * 6);

run_tests();

__DATA__

=== TEST 1: http disable + enable peer
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.1:3456;
      listen 127.0.0.1:4567;
      location = /ping {
        echo pong;
      }
    }
    upstream test {
      zone test 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.1:3456 down;
      server 127.0.0.1:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck"
        local opts = hc.get(ngx.var.arg_upstream)
        for _,h in ipairs(opts.disabled_hosts or {}) do
          ngx.say(h)
        end
        local status = hc.status(ngx.var.arg_upstream)
        local t = {}
        for peer,s in pairs(status.primary) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /http/disable_peer?upstream=test&peer=127.0.0.1:3456",
     "GET /test?upstream=test",
     "GET /http/enable_peer?upstream=test&peer=127.0.0.1:3456",
     "GET /wait?time=2",
     "GET /test?upstream=test"]
--- response_body eval
    ["",
     "OK",
"127.0.0.1:3456
127.0.0.1:2345 0
127.0.0.1:3456 1
127.0.0.1:4567 0
",
     "OK",
     "",
"127.0.0.1:2345 0
127.0.0.1:3456 0
127.0.0.1:4567 0
"]


=== TEST 2: stream disable + enable peer
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.1:3456;
      listen 127.0.0.1:4567;
      location = /ping {
        echo pong;
      }
    }
--- stream_config
    upstream test {
      zone test 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.1:3456 down;
      server 127.0.0.1:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- stream_server_config
    proxy_pass test;
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck.stream"
        local opts = hc.get(ngx.var.arg_upstream)
        for _,h in ipairs(opts.disabled_hosts or {}) do
          ngx.say(h)
        end
        local status = hc.status(ngx.var.arg_upstream)
        local t = {}
        for peer,s in pairs(status.primary) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /stream/disable_peer?upstream=test&peer=127.0.0.1:3456",
     "GET /test?upstream=test",
     "GET /stream/enable_peer?upstream=test&peer=127.0.0.1:3456",
     "GET /wait?time=2",
     "GET /test?upstream=test"]
--- response_body eval
    ["",
     "OK",
"127.0.0.1:3456
127.0.0.1:2345 0
127.0.0.1:3456 1
127.0.0.1:4567 0
",
     "OK",
     "",
"127.0.0.1:2345 0
127.0.0.1:3456 0
127.0.0.1:4567 0
"]


=== TEST 3: http disable ip + enable ip
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.2:3456;
      listen 127.0.0.3:4567;
      location = /ping {
        echo pong;
      }
    }
    upstream test1 {
      zone test1 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
    upstream test2 {
      zone test2 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck"
        local t = {}
        for u,opts in pairs(hc.get()) do
	      for _,h in ipairs(opts.disabled_hosts or {}) do
	        table.insert(t, u .. "," .. h)
	      end
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
        t = {}
        for u,status in pairs(hc.status()) do
          for peer,s in pairs(status.primary) do
            table.insert(t, string.format("%s,%s %d", u, peer, s.down))
          end
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /http/disable_ip?ip=127.0.0.2",
     "GET /test",
     "GET /http/enable_ip?ip=127.0.0.2",
     "GET /wait?time=2",
     "GET /test"]
--- response_body eval
    ["",
     "OK",
"test1,127.0.0.2
test2,127.0.0.2
test1,127.0.0.1:2345 0
test1,127.0.0.2:3456 1
test1,127.0.0.3:4567 0
test2,127.0.0.1:2345 0
test2,127.0.0.2:3456 1
test2,127.0.0.3:4567 0
",
     "OK",
     "",
"test1,127.0.0.1:2345 0
test1,127.0.0.2:3456 0
test1,127.0.0.3:4567 0
test2,127.0.0.1:2345 0
test2,127.0.0.2:3456 0
test2,127.0.0.3:4567 0
"]


=== TEST 4: stream disable ip + enable ip
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.2:3456;
      listen 127.0.0.3:4567;
      location = /ping {
        echo pong;
      }
    }
--- stream_config
    upstream test1 {
      zone test1 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
    upstream test2 {
      zone test2 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- stream_server_config
    proxy_pass test1;
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck.stream"
        local t = {}
        for u,opts in pairs(hc.get()) do
	      for _,h in ipairs(opts.disabled_hosts or {}) do
	        table.insert(t, u .. "," .. h)
	      end
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
        t = {}
        for u,status in pairs(hc.status()) do
          for peer,s in pairs(status.primary) do
            table.insert(t, string.format("%s,%s %d", u, peer, s.down))
          end
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /stream/disable_ip?ip=127.0.0.2",
     "GET /test",
     "GET /stream/enable_ip?ip=127.0.0.2",
     "GET /wait?time=2",
     "GET /test"]
--- response_body eval
    ["",
     "OK",
"test1,127.0.0.2
test2,127.0.0.2
test1,127.0.0.1:2345 0
test1,127.0.0.2:3456 1
test1,127.0.0.3:4567 0
test2,127.0.0.1:2345 0
test2,127.0.0.2:3456 1
test2,127.0.0.3:4567 0
",
     "OK",
     "",
"test1,127.0.0.1:2345 0
test1,127.0.0.2:3456 0
test1,127.0.0.3:4567 0
test2,127.0.0.1:2345 0
test2,127.0.0.2:3456 0
test2,127.0.0.3:4567 0
"]


=== TEST 5: http disable upstream + enable upstream
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.2:3456;
      listen 127.0.0.3:4567;
      location = /ping {
        echo pong;
      }
    }
    upstream test1 {
      zone test1 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
    upstream test2 {
      zone test2 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
    upstream test3 {
      zone test3 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck"
        local t = {}
        for u,opts in pairs(hc.get()) do
          table.insert(t, u .. " " .. opts.disabled)
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
        t = {}
        for u,status in pairs(hc.status()) do
          for peer,s in pairs(status.primary) do
            table.insert(t, string.format("%s,%s %d", u, peer, s.down))
          end
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /http/disable_upstream?upstream=test2",
     "GET /test",
     "GET /http/enable_upstream?upstream=test2",
     "GET /wait?time=2",
     "GET /test"]
--- response_body eval
    ["",
     "OK",
"test1 0
test2 1
test3 0
test1,127.0.0.1:2345 0
test1,127.0.0.2:3456 0
test1,127.0.0.3:4567 0
test2,127.0.0.1:2345 1
test2,127.0.0.2:3456 1
test2,127.0.0.3:4567 1
test3,127.0.0.1:2345 0
test3,127.0.0.2:3456 0
test3,127.0.0.3:4567 0
",
     "OK",
     "",
"test1 0
test2 0
test3 0
test1,127.0.0.1:2345 0
test1,127.0.0.2:3456 0
test1,127.0.0.3:4567 0
test2,127.0.0.1:2345 0
test2,127.0.0.2:3456 0
test2,127.0.0.3:4567 0
test3,127.0.0.1:2345 0
test3,127.0.0.2:3456 0
test3,127.0.0.3:4567 0
"]


=== TEST 6: stream disable upstream + enable upstream
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.2:3456;
      listen 127.0.0.3:4567;
      location = /ping {
        echo pong;
      }
    }
--- stream_config
    upstream test1 {
      zone test1 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
    upstream test2 {
      zone test2 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
    upstream test3 {
      zone test3 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.2:3456 down;
      server 127.0.0.3:4567 down;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- stream_server_config
    proxy_pass test1;
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck.stream"
        local t = {}
        for u,opts in pairs(hc.get()) do
          table.insert(t, u .. " " .. opts.disabled)
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
        t = {}
        for u,status in pairs(hc.status()) do
          for peer,s in pairs(status.primary) do
            table.insert(t, string.format("%s,%s %d", u, peer, s.down))
          end
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /stream/disable_upstream?upstream=test2",
     "GET /test",
     "GET /stream/enable_upstream?upstream=test2",
     "GET /wait?time=2",
     "GET /test"]
--- response_body eval
    ["",
     "OK",
"test1 0
test2 1
test3 0
test1,127.0.0.1:2345 0
test1,127.0.0.2:3456 0
test1,127.0.0.3:4567 0
test2,127.0.0.1:2345 1
test2,127.0.0.2:3456 1
test2,127.0.0.3:4567 1
test3,127.0.0.1:2345 0
test3,127.0.0.2:3456 0
test3,127.0.0.3:4567 0
",
     "OK",
     "",
"test1 0
test2 0
test3 0
test1,127.0.0.1:2345 0
test1,127.0.0.2:3456 0
test1,127.0.0.3:4567 0
test2,127.0.0.1:2345 0
test2,127.0.0.2:3456 0
test2,127.0.0.3:4567 0
test3,127.0.0.1:2345 0
test3,127.0.0.2:3456 0
test3,127.0.0.3:4567 0
"]


=== TEST 7: http disable + enable primary
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.1:3456;
      listen 127.0.0.1:4567;
      location = /ping {
        echo pong;
      }
    }
    upstream test {
      zone test 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.1:3456 down;
      server 127.0.0.1:4567 down backup;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck"
        local opts = hc.get(ngx.var.arg_upstream)
        for _,h in ipairs(opts.disabled_hosts or {}) do
          ngx.say(h)
        end
        local status = hc.status(ngx.var.arg_upstream)
        local t = {}
        for peer,s in pairs(status.primary) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        for peer,s in pairs(status.backup) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /http/disable_primary?upstream=test",
     "GET /test?upstream=test",
     "GET /http/enable_primary?upstream=test",
     "GET /wait?time=2",
     "GET /test?upstream=test"]
--- response_body eval
    ["",
     "OK",
"127.0.0.1:2345
127.0.0.1:3456
127.0.0.1:2345 1
127.0.0.1:3456 1
127.0.0.1:4567 0
",
     "OK",
     "",
"127.0.0.1:2345 0
127.0.0.1:3456 0
127.0.0.1:4567 0
"]


=== TEST 8: stream disable + enable primary
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.1:3456;
      listen 127.0.0.1:4567;
      location = /ping {
        echo pong;
      }
    }
--- stream_config
    upstream test {
      zone test 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.1:3456 down;
      server 127.0.0.1:4567 down backup;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- stream_server_config
    proxy_pass test;
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck.stream"
        local opts = hc.get(ngx.var.arg_upstream)
        for _,h in ipairs(opts.disabled_hosts or {}) do
          ngx.say(h)
        end
        local status = hc.status(ngx.var.arg_upstream)
        local t = {}
        for peer,s in pairs(status.primary) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        for peer,s in pairs(status.backup) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /stream/disable_primary?upstream=test",
     "GET /test?upstream=test",
     "GET /stream/enable_primary?upstream=test",
     "GET /wait?time=2",
     "GET /test?upstream=test"]
--- response_body eval
    ["",
     "OK",
"127.0.0.1:2345
127.0.0.1:3456
127.0.0.1:2345 1
127.0.0.1:3456 1
127.0.0.1:4567 0
",
     "OK",
     "",
"127.0.0.1:2345 0
127.0.0.1:3456 0
127.0.0.1:4567 0
"]


=== TEST 9: http disable + enable backup
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.1:3456;
      listen 127.0.0.1:4567;
      location = /ping {
        echo pong;
      }
    }
    upstream test {
      zone test 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.1:3456 down;
      server 127.0.0.1:4567 down backup;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck"
        local opts = hc.get(ngx.var.arg_upstream)
        for _,h in ipairs(opts.disabled_hosts or {}) do
          ngx.say(h)
        end
        local status = hc.status(ngx.var.arg_upstream)
        local t = {}
        for peer,s in pairs(status.primary) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        for peer,s in pairs(status.backup) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /http/disable_backup?upstream=test",
     "GET /test?upstream=test",
     "GET /http/enable_backup?upstream=test",
     "GET /wait?time=2",
     "GET /test?upstream=test"]
--- response_body eval
    ["",
     "OK",
"127.0.0.1:4567
127.0.0.1:2345 0
127.0.0.1:3456 0
127.0.0.1:4567 1
",
     "OK",
     "",
"127.0.0.1:2345 0
127.0.0.1:3456 0
127.0.0.1:4567 0
"]


=== TEST 10: stream disable + enable backup
--- http_config
    lua_package_path 'lua/?.lua;;';
    server {
      listen 127.0.0.1:2345;
      listen 127.0.0.1:3456;
      listen 127.0.0.1:4567;
      location = /ping {
        echo pong;
      }
    }
--- stream_config
    upstream test {
      zone test 128k;
      server 127.0.0.1:2345 down;
      server 127.0.0.1:3456 down;
      server 127.0.0.1:4567 down backup;
      check type=http rise=1 fall=1 timeout=1000 interval=1;
      check_request_uri GET /ping;
      check_response_codes 200;
      check_response_body pong;
    }
--- stream_server_config
    proxy_pass test;
--- config
    include $TEST_NGINX_ROOT_DIR/conf/conf.d/healthcheck/dynamic.conf;
    location = /wait {
      echo_sleep $arg_time;
    }
    location = /test {
      content_by_lua_block {
        local hc = require "ngx.healthcheck.stream"
        local opts = hc.get(ngx.var.arg_upstream)
        for _,h in ipairs(opts.disabled_hosts or {}) do
          ngx.say(h)
        end
        local status = hc.status(ngx.var.arg_upstream)
        local t = {}
        for peer,s in pairs(status.primary) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        for peer,s in pairs(status.backup) do
          table.insert(t, string.format("%s %d", peer, s.down))
        end
        table.sort(t)
        for _,p in ipairs(t) do
          ngx.say(p)
        end
      }
    }
--- timeout: 5
--- request eval
    ["GET /wait?time=2",
     "GET /stream/disable_backup?upstream=test",
     "GET /test?upstream=test",
     "GET /stream/enable_backup?upstream=test",
     "GET /wait?time=2",
     "GET /test?upstream=test"]
--- response_body eval
    ["",
     "OK",
"127.0.0.1:4567
127.0.0.1:2345 0
127.0.0.1:3456 0
127.0.0.1:4567 1
",
     "OK",
     "",
"127.0.0.1:2345 0
127.0.0.1:3456 0
127.0.0.1:4567 0
"]
