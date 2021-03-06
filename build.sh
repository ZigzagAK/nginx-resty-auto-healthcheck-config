#!/bin/bash

# Copyright, Aleksey Konovkin (alkon2000@mail.ru)
# BSD license type

download=0
if [ "$1" == "1" ]; then
  download=1
fi
build_deps=0

DIR="$(pwd)"

VERSION="1.15.6"
PCRE_VERSION="8.39"

SUFFIX=""

BASE_PREFIX="$DIR/build"
INSTALL_PREFIX="$DIR/install"

PCRE_PREFIX="$DIR/build/pcre-$PCRE_VERSION"
JIT_PREFIX="$DIR/build/deps/luajit"

export LUAJIT_INC="$JIT_PREFIX/usr/local/include/luajit-2.1"
export LUAJIT_LIB="$JIT_PREFIX/usr/local/lib"

export LD_LIBRARY_PATH="$JIT_PREFIX/lib"

shared="so"

current_os=`uname`
if [ "$current_os" = "Darwin" ]; then
  arch=`uname -m`
  vendor="apple"
  shared="dylib"
fi

function clean() {
  rm -rf install  2>/dev/null
  rm -rf $(ls -1d build/* 2>/dev/null | grep -v deps)    2>/dev/null
  if [ $download -eq 1 ]; then
    rm -rf download 2>/dev/null
  fi
}

if [ "$1" == "clean" ]; then
  clean
  exit 0
fi

function build_luajit() {
  echo "Build luajit"
  cd luajit2
  make > /dev/null
  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  DESTDIR="$JIT_PREFIX" make install > /dev/null
  cd ..
}

function build_int64() {
  echo "Build int64" | tee -a $BUILD_LOG
  cd lua_int64
  LUA_INCLUDE_DIR="$JIT_PREFIX/usr/local/include/luajit-2.1" LDFLAGS="-L$JIT_PREFIX/usr/local/lib -lluajit-5.1" make > /dev/null
  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  cd ..
}

function build_cJSON() {
  echo "Build cjson" | tee -a $BUILD_LOG
  cd lua-cjson
  LUA_INCLUDE_DIR="$JIT_PREFIX/usr/local/include/luajit-2.1" WITH_INT64="${DIR}/build/lua_int64" LDFLAGS="-L$JIT_PREFIX/usr/local/lib -lluajit-5.1" make > /dev/null
  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  cd ..
}

function build_debug() {
  cd nginx-$VERSION$SUFFIX
  echo "Configuring debug nginx-$VERSION$SUFFIX"
  ./configure --prefix="$INSTALL_PREFIX/nginx-$VERSION$SUFFIX" \
              --with-pcre=$PCRE_PREFIX \
              --with-http_stub_status_module \
              --with-stream \
              --with-debug \
              --with-http_auth_request_module \
              --with-cc-opt="-O0 -D_WITH_LUA_API" \
              --add-module=../ngx_devel_kit \
              --add-module=../lua-nginx-module \
              --add-module=../echo-nginx-module \
              --add-module=../stream-lua-nginx-module \
              --add-module=../lua-shared-dict \
              --add-module=../ngx_dynamic_upstream \
              --add-module=../ngx_dynamic_upstream_lua \
              --add-module=../ngx_dynamic_healthcheck > /dev/null 2>/dev/stderr

  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi

  echo "Build debug nginx-$VERSION$SUFFIX"
  make -j 8 > /dev/null 2>/dev/stderr

  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  make install > /dev/null

  mv "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/sbin/nginx" "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/sbin/nginx.debug"
  cd ..
}

function build_release() {
  cd nginx-$VERSION$SUFFIX
  echo "Configuring release nginx-$VERSION$SUFFIX"
  ./configure --prefix="$INSTALL_PREFIX/nginx-$VERSION$SUFFIX" \
              --with-pcre=$PCRE_PREFIX \
              --with-cc-opt="-D_WITH_LUA_API" \
              --with-http_stub_status_module \
              --with-stream \
              --with-http_auth_request_module \
              --add-module=../ngx_devel_kit \
              --add-module=../lua-nginx-module \
              --add-module=../echo-nginx-module \
              --add-module=../stream-lua-nginx-module \
              --add-module=../lua-shared-dict \
              --add-module=../ngx_dynamic_upstream \
              --add-module=../ngx_dynamic_upstream_lua \
              --add-module=../ngx_dynamic_healthcheck > /dev/null 2>/dev/stderr


  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi

  echo "Build release nginx-$VERSION$SUFFIX"
  make -j 8 > /dev/null 2>/dev/stderr

  r=$?
  if [ $r -ne 0 ]; then
    exit $r
  fi
  make install > /dev/null
  cd ..
}

function download_module() {
  if [ $download -eq 1 ] || [ ! -e $3.tar.gz ]; then
    echo "Download $1/$2/$3.git from=$4"
    git clone $1/$2/$3.git > /dev/null 2>&1
    echo "$1/$2/$3.git" > $3.log
    echo >> $3.log
    cd $3
    git checkout $4 > /dev/null 2>&1
    echo $4" : "$(git log -1 --oneline | awk '{print $1}') >> ../$3.log
    echo >> ../$3.log
    git log -1 | grep -E "(^[Cc]ommit)|(^[Aa]uthor)|(^[Dd]ate)" >> ../$3.log
    cd ..
    tar zcf $3.tar.gz $3 > /dev/null 2>&1
    rm -rf $3
  else
    echo "Get $3" | tee -a $BUILD_LOG
  fi
}

function gitclone() {
  git clone $1 > /dev/null 2> /tmp/err
  if [ $? -ne 0 ]; then
    cat /tmp/err
  fi
}

function download_nginx() {
  if [ $download -eq 1 ] || [ ! -e nginx-$VERSION.tar.gz ]; then
    echo "Download nginx-$VERSION"
    curl -s -L -O http://nginx.org/download/nginx-$VERSION.tar.gz
  else
    echo "Get nginx-$VERSION.tar.gz"
  fi
}

function download_pcre() {
  if [ $download -eq 1 ] || [ ! -e pcre-$PCRE_VERSION.tar.gz ]; then
    echo "Download PCRE-$PCRE_VERSION"
    curl -s -L -O http://ftp.cs.stanford.edu/pub/exim/pcre/pcre-$PCRE_VERSION.tar.gz
  else
    echo "Get pcre-$PCRE_VERSION.tar.gz"
  fi
}

download_debug() {
  cd debug

  download_module https://github.com pkulchenko  MobDebug   master
  download_module https://github.com diegonehab  luasocket  master

  cd ..
}

function extract_downloads() {
  cd download

  for d in $(ls -1 *.tar.gz)
  do
    echo "Extracting $d"
    tar zxf $d -C ../build --no-overwrite-dir 2>/dev/null
  done

  for d in $(ls -1 debug/*.tar.gz)
  do
    echo "Extracting $d"
    tar zxf $d -C ../build/debug --no-overwrite-dir 2>/dev/null
  done

  cd ..
}

function download() {
  mkdir build                2>/dev/null
  mkdir build/debug          2>/dev/null
  mkdir build/deps           2>/dev/null

  mkdir download             2>/dev/null
  mkdir download/debug       2>/dev/null
  mkdir download/lua_modules 2>/dev/null

  cd download

  download_pcre
  download_nginx

  download_module https://github.com ZigzagAK    ngx_dynamic_upstream             master
  download_module https://github.com ZigzagAK    ngx_dynamic_upstream_lua         master
  download_module https://github.com ZigzagAK    ngx_dynamic_healthcheck          master
  download_module https://github.com openresty   stream-lua-nginx-module          master
  download_module https://github.com simpl       ngx_devel_kit                    master
  download_module https://github.com openresty   lua-nginx-module                 master
  download_module https://github.com ZigzagAK    lua-cjson                        mixed
  download_module https://github.com ZigzagAK    lua_int64                        master
  download_module https://github.com openresty   echo-nginx-module                master
  download_module https://github.com openresty   luajit2                          v2.1-agentzh
  download_module https://github.com ZigzagAK    lua-shared-dict                  master

  download_debug

  cd ..
}

function install_file() {
  echo "Install $1"
  if [ ! -e "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$2" ]; then
    mkdir -p "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$2"
  fi
  cp -rL $3 $1 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$2/"
}

function install_files() {
  for f in $(ls $1)
  do
    install_file $f $2 $3
  done
}

function build_lua_debug() {
  cd debug

  cd luasocket

  MYCFLAGS=-I$LUAJIT_INC MYLDFLAGS=-L$LUAJIT_LIB make >/dev/null 2>/dev/null
  prefix=$(pwd)/install_dir make install >/dev/null 2>&1

  cd install_dir

  install_file lib/lua/*/socket       debug/clibs
  install_file share/lua/*/socket.lua debug

  cd ../..

  install_file MobDebug/src/mobdebug.lua debug

  cd ..
}

function build() {
  cd build

  if [ $build_deps -eq 1 ] || [ ! -e deps/luajit ]; then
    build_luajit
  fi

  build_int64
  build_cJSON

#  make clean > /dev/null 2>&1
#  build_debug

  make clean > /dev/null 2>&1
  build_release

  install_file  "$JIT_PREFIX/usr/local/lib"           .
  install_file  lua-cjson/cjson.so                    lib/lua/5.1
  install_file  lua_int64/int64.so                    lib/lua/5.1
  install_file  "lua_int64/liblua_int64.$shared"      lib

  build_lua_debug

  cd ..
}

clean
download
extract_downloads
build

function install_resty_module() {
  if [ -e $DIR/../$2 ]; then
    echo "Get $DIR/../$2"
    dir=$(pwd)
    cd $DIR/..
    zip -qr $dir/$2.zip $(ls -1d $2/* | grep -vE "(install$)|(build$)|(download$)|(.git$)")
    cd $dir
  else
    if [ $6 -eq 1 ] || [ ! -e $2-$5.zip ] ; then
      echo "Download $2 branch=$5"
      rm -rf $2-$5 2>/dev/null
      curl -s -L -O https://github.com/$1/$2/archive/$5.zip
      mv $5.zip $2-$5.zip
    else
      echo "Get $2-$5"
    fi
  fi
  echo "Install $2/$3"
  if [ ! -e "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4" ]; then
    mkdir -p "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4"
  fi
  if [ -e $2-$5.zip ]; then
    unzip -q $2-$5.zip
    cp -r $2-$5/$3 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4/"
    rm -rf $2-$5
  elif [ -e $2-$5.tar.gz ]; then
    tar zxf $2-$5.tar.gz
    cp -r $2-$5/$3 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4/"
    rm -rf $2-$5
  elif [ -e $2.zip ]; then
    unzip -q $2.zip
    cp -r $2/$3 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4/"
    rm -rf $2
  elif [ -e $2.tar.gz ]; then
    tar zxf $2.tar.gz
    cp -r $2/$3 "$INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$4/"
    rm -rf $2
  fi
}

function make_dir() {
  mkdir $INSTALL_PREFIX/nginx-$VERSION$SUFFIX/$1
}

function install_lua_modules() {
  if [ $download -eq 1 ]; then
    rm -rf download/lua_modules/* 2>/dev/null
  fi

  cd download/lua_modules

  install_resty_module openresty    lua-resty-lock                      lib                . master $download
  install_resty_module pintsized    lua-resty-http                      lib                . master $download
  install_resty_module openresty    lua-resty-core                      lib                . master $download
  install_resty_module openresty    lua-resty-lrucache                  lib                . master $download

  cd ../..

  install_file scripts/start.sh                     .
  install_file scripts/stop.sh                      .
  install_file scripts/debug.sh                     .
  install_file scripts/restart.sh                   .
  install_file lua                                  .
  install_file conf                                 .
  install_file debug/rmdebug.lua                    debug
}

install_lua_modules

cd "$DIR"

kernel_name=$(uname -s)
kernel_version=$(uname -r)

cd install

tar zcvf nginx-$VERSION$SUFFIX-$kernel_name-$kernel_version.tar.gz nginx-$VERSION$SUFFIX
rm -rf nginx-$VERSION$SUFFIX

cd ..

exit $r