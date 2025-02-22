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

git clone https://github.com/openSUSE/catatonit.git
cd catatonit

if [[ -n "${CATATONIT_TAG}" ]]
then
   git checkout "${CATATONIT_TAG}"
else
   git checkout $(get_latest_tag)
fi


./autogen.sh
./configure
make
sudo make install
