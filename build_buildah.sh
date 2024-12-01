#!/bin/bash

source config.sh

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="$GOPATH:$PATH"

git clone https://github.com/containers/buildah.git
cd buildah
git checkout "${BUILDAH_TAG}"

# Must Patch 1.22.6 -> 1.23 in /usr/src/podman/buildah/go.mod
sed -Ei "s|^go 1.22.6$|go 1.23|" go.mod


#make

#make BUILDTAGS="selinux seccomp apparmor systemd" PREFIX=/usr
make BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr


sudo make install

#buildah --help
