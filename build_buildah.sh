#!/bin/bash

# Abort on Error
# set -e

# Determine toolpath if not set already
relativepath="./" # Define relative path to go from this script to the root level of the tool
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi

# Load Configuration
source ${toolpath}/config.sh

# Change Folder to Build Root
cd "${BUILD_ROOT}" || exit

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="$GOPATH:$PATH"

git clone https://github.com/containers/buildah.git
cd buildah

if [[ -n "${BUILDAH_TAG}" ]]
then
   # Use Specified Tag
   git checkout "${BUILDAH_TAG}"
else
   # Get Latest Tag
   git checkout $(git describe --tags --abbrev=0)
fi

# Must Patch 1.22.6 -> 1.23 in /usr/src/podman/buildah/go.mod
sed -Ei "s|^go 1.22.6$|go 1.23|" go.mod


#make

#make BUILDTAGS="selinux seccomp apparmor systemd" PREFIX=/usr
make BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr


sudo make install

#buildah --help
