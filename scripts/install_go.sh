#!/bin/bash

# Abort on Error
set -e

# Determine toolpath if not set already
relativepath="../" # Define relative path to go from this script to the root level of the tool
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi

# Load Configuration
source "${toolpath}/config.sh"

# Load Functions
source "${toolpath}/functions.sh"

# Create Folders
mkdir -p ${GOROOT}

# Download a Binary Distribution
wget https://go.dev/dl/${GOTAG}.linux-amd64.tar.gz -O ${GOTAG}.linux-amd64.tar.gz
tar xvf ${GOTAG}.linux-amd64.tar.gz --strip-components=1 -C ${GOROOT}
