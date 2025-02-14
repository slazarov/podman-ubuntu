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


git clone https://github.com/containers/conmon
cd conmon

if [[ -n "${CONMON_TAG}" ]]
then
   git checkout "${CONMON_TAG}"
else
   git checkout $(get_latest_tag)
fi



export GOCACHE="$(mktemp -d)"
make
sudo make podman
