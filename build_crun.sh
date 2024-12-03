#!/bin/bash

source config.sh

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="$GOPATH:$PATH"

git clone https://github.com/containers/crun.git
cd crun
git checkout "${CRUN_TAG}"


# On Fedora the Following Flags/Features are additionally enabled compared to Debian in the built runtime: +LIBKRUN +WASM:wasmedge

./autogen.sh
./configure
make
sudo make install


####make BUILDTAGS="selinux seccomp apparmor"

###sudo cp crun /usr/local/bin/crun
