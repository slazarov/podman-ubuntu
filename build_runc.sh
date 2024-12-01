#!/bin/bash

source config.sh

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="$GOPATH:$PATH"

#git clone https://github.com/opencontainers/runc.git $GOPATH/src/github.com/opencontainers/runc
#cd $GOPATH/src/github.com/opencontainers/runc

git clone https://github.com/opencontainers/runc.git
cd runc
git checkout "${RUNC_TAG}"

make BUILDTAGS="selinux seccomp apparmor"
sudo cp runc /usr/local/bin/runc
