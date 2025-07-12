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

# Download Protoc
wget https://github.com/protocolbuffers/protobuf/releases/download/${PROTOC_TAG}/protoc-${PROTOC_VERSION}-linux-x86_64.zip -O protoc-${PROTOC_VERSION}-linux-x86_64.zip

mkdir -p ${PROTOC_ROOT_FOLDER}/${PROTOC_VERSION}
unzip protoc-${PROTOC_VERSION}-linux-x86_64.zip -d ${PROTOC_ROOT_FOLDER}/${PROTOC_VERSION}

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="${PROTOC_PATH}:${PATH}"

ln -s ${PROTOC_PATH} /usr/local/bin/protoc
