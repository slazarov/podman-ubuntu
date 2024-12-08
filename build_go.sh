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

git clone https://go.googlesource.com/go $GOPATH
cd $GOPATH

if [[ -n "${GOVERSION}" ]]
then
   git checkout "${GOVERSION}"
else
   git checkout $(git describe --tags --abbrev=0)
fi

cd src
./all.bash
export PATH=$GOPATH/bin:$PATH
