#!/bin/bash

# Abort on Error
set -e

# Determine toolpath if not set already
relativepath="./" # Define relative path to go from this script to the root level of the tool
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi

# Load Configuration
source "${toolpath}/config.sh"

# Load Functions
source "${toolpath}/functions.sh"

# Change Folder to Build Root
cd "${BUILD_ROOT}" || exit

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
. "$HOME/.cargo/env"
#export PATH="CUSTOMPATH:$PATH"

git clone https://github.com/containers/aardvark-dns
cd aardvark-dns

if [[ -n "${AARDVARK_DNS_TAG}" ]]
then
   git checkout "${AARDVARK_DNS_TAG}"
else
   git checkout $(git describe --tags --abbrev=0)
fi

make

#make BUILDTAGS="selinux seccomp apparmor systemd" PREFIX=/usr
#make BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr
#sudo make install

cp bin/aardvark-dns /usr/local/bin/aardvark-dns
