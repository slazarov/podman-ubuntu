#!/bin/bash

source config.sh

git clone https://go.googlesource.com/go $GOPATH
cd $GOPATH
git checkout $GOVERSION
cd src
./all.bash
export PATH=$GOPATH/bin:$PATH
