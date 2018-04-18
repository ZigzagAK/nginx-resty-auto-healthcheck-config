#!/bin/bash

ulimit -c unlimited
DIR=$(pwd)
export LD_LIBRARY_PATH=$DIR/lib
export DYLD_LIBRARY_PATH=$LD_LIBRARY_PATH
./sbin/nginx.debug -p $DIR
