#!/bin/bash

source config.sh

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="$GOPATH:$PATH"

git clone https://github.com/containers/fuse-overlayfs.git
cd fuse-overlayfs
git checkout "${FUSE_OVERLAYFS_TAG}"


./autogen.sh
LIBS="-ldl" LDFLAGS="-static" ./configure --prefix /usr/local 
make
sudo make install

#./autogen.sh
#./configure
#make
#sudo make install


####make BUILDTAGS="selinux seccomp apparmor"

####sudo cp fuse-overlayfs /usr/local/bin/fuse-overlayfs
