#!/bin/bash

source config.sh

wget https://github.com/protocolbuffers/protobuf/releases/download/${PROTOC_TAG}/protoc-${PROTOC_VERSION}-linux-x86_64.zip

mkdir -p ${PROTOC_ROOT_FOLDER}/${PROTOC_VERSION}
unzip protoc-${PROTOC_VERSION}-linux-x86_64.zip -d ${PROTOC_ROOT_FOLDER}/${PROTOC_VERSION}

# Required Fix otherwise go complains about 1.22.6 vs 1.23 mismatch
export PATH="${PROTOC_PATH}:${PATH}"

ln -s ${PROTOC_PATH} /usr/local/bin/protoc
