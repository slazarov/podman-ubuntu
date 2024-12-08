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

# First of all install a relatively recent version in order to BUILD go
export GOVERSION="1.22.6"
export GOTAG="go${GOVERSION}"
export GOPATH="/opt/go/${GOVERSION}/bin"
export GOROOT="/opt/go/${GOVERSION}"

git clone https://go.googlesource.com/go $GOROOT
cd $GOROOT

if [[ -n "${GOTAG}" ]]
then
   git checkout "${GOTAG}"
else
   git checkout $(git describe --tags --abbrev=0)
fi

cd src
./all.bash
export PATH=$GOPATH/bin:$PATH


# Reload Configuration
source ${toolpath}/config.sh

# Then install the desired Version
git clone https://go.googlesource.com/go $GOROOT
cd $GOROOT

if [[ -n "${GOTAG}" ]]
then
   git checkout "${GOTAG}"
else
   git checkout $(git describe --tags --abbrev=0)
fi

cd src
./all.bash
export PATH=$GOPATH/bin:$PATH
