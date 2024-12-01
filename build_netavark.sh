#!/bin/bash

source config.sh

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
. "$HOME/.cargo/env"
#export PATH="CUSTOMPATH:$PATH"

git clone https://github.com/containers/netavark
cd netavark
git checkout "${NETAVARK_TAG}"

make

#make BUILDTAGS="selinux seccomp apparmor systemd" PREFIX=/usr
#make BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr


#sudo make install

cp bin/netavark /usr/local/bin/netavark
cp bin/netavark-dhcp-proxy-client /usr/local/bin/netavark-dhcp-proxy-client
