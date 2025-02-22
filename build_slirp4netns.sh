#!/bin/bash

# Abort on Error
# set -e

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
export PATH="$GOPATH:$PATH"


git_clone_update https://github.com/rootless-containers/slirp4netns.git slirp4netns
cd slirp4netns

if [[ -n "${SLIRP4NETNS_TAG}" ]]
then
   git checkout "${SLIRP4NETNS_TAG}"
else
   git checkout $(get_latest_tag)
fi


./autogen.sh
./configure --prefix=/usr/local
make
sudo make install


####make BUILDTAGS="selinux seccomp apparmor"

####sudo cp slirp4netns /usr/local/bin/slirp4netns
