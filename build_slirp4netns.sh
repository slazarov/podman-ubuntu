#!/bin/bash

source config.sh

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="$GOPATH:$PATH"

git clone https://github.com/rootless-containers/slirp4netns.git
cd slirp4netns
git checkout "${SLIRP4NETNS_TAG}"


./autogen.sh
./configure --prefix=/usr/local
make
sudo make install


####make BUILDTAGS="selinux seccomp apparmor"

####sudo cp slirp4netns /usr/local/bin/slirp4netns
