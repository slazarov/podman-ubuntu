#!/bin/bash

source config.sh

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="$GOPATH:$PATH"

git clone https://github.com/cpuguy83/go-md2man.git
cd go-md2man
git checkout "${GOMD2MAN_TAG}"

# Must Patch 1.22.6 -> 1.23 in /usr/src/podman/buildah/go.mod
sed -Ei "s|^go 1.22.6$|go 1.23|" go.mod

make

cp bin/go-md2man /usr/local/bin
