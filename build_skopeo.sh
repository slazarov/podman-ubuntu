#!/bin/bash

source config.sh

# Might actually not be needed for build-only (more for Troubleshooting)
# go install golang.org/x/tools/gopls@latest

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="$GOPATH:$PATH"

git clone https://github.com/containers/skopeo.git
cd skopeo
git checkout "${SKOPEO_TAG}"

# Must Patch 1.22.6 -> 1.23 in /usr/src/podman/podman/go.mod
sed -Ei "s|^go 1.22.6$|go 1.23|" go.mod

#make BUILDTAGS="selinux seccomp apparmor systemd" PREFIX=/usr
make BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr
sudo make install PREFIX=/usr


# Copy to Target Folder

