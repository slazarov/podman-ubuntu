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

#git clone https://github.com/opencontainers/runc.git $GOPATH/src/github.com/opencontainers/runc
#cd $GOPATH/src/github.com/opencontainers/runc

git clone https://github.com/opencontainers/runc.git
cd runc

if [[ -n "${RUNC_TAG}" ]]
then
   git checkout "${RUNC_TAG}"
else
   git checkout $(git describe --tags --abbrev=0)
fi

make BUILDTAGS="selinux seccomp apparmor"
sudo cp runc /usr/local/bin/runc
