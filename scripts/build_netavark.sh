#!/bin/bash

# Abort on Error
# set -e

# Determine toolpath if not set already
relativepath="../" # Define relative path to go from this script to the root level of the tool
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
. "$HOME/.cargo/env"
#export PATH="CUSTOMPATH:$PATH"

# Load Configuration
source "${toolpath}/config.sh"

# Load Functions
source "${toolpath}/functions.sh"

# Change Folder to Build Root
cd "${BUILD_ROOT}" || exit

git_clone_update https://github.com/containers/netavark netavark
cd netavark
git_checkout "${NETAVARK_TAG}"

# Log Component
log_component "netavark"

# Build
make

#make BUILDTAGS="selinux seccomp apparmor systemd" PREFIX=/usr
#make BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr


#sudo make install

cp bin/netavark /usr/local/bin/netavark
cp bin/netavark-dhcp-proxy-client /usr/local/bin/netavark-dhcp-proxy-client
