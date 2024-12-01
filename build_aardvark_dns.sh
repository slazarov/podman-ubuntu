#!/bin/bash

source config.sh

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
. "$HOME/.cargo/env"
#export PATH="CUSTOMPATH:$PATH"

git clone https://github.com/containers/aardvark-dns
cd aardvark-dns
git checkout "${AARDVARK_DNS_TAG}"

make

#make BUILDTAGS="selinux seccomp apparmor systemd" PREFIX=/usr
#make BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr
#sudo make install

cp bin/aardvark-dns /usr/local/bin/aardvark-dns
