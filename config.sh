#!/bin/bash

# Build Root
export BUILD_ROOT="./build"

# Go Root Folder
export GO_ROOT_FOLDER="/opt/go"

# Go Version and Path
#export GOVERSION="1.22.6"
export GOTAG="v${GOVERSION}"
#export GOPATH="/opt/go/${GOVERSION}/bin/go"
#export GOROOT="/opt/go/${GOVERSION}"

export GOVERSION="1.23.3"
export GOTAG="v${GOVERSION}"
export GOPATH="/opt/go/${GOVERSION}/bin/go"
export GOROOT="/opt/go/${GOVERSION}"

# Podman Version
export PODMAN_VERSION="5.3.1"
export PODMAN_TAG="v${PODMAN_VERSION}"

# Buildah Version
export BUILDAH_VERSION="1.38.0"
export BUILDAH_TAG="v${BUILDAH_VERSION}"

# Runc Version
export RUNC_VERSION="1.2.2"
export RUNC_TAG="v${RUNC_VERSION}"

# Crun Version
export CRUN_VERSION="1.18.2"
export CRUN_TAG="${CRUN_VERSION}"

# Conmon Version
export CONMON_VERSION="2.1.12"
export CONMON_TAG="v${CONMON_VERSION}"

# Slirp4netns Version
export SLIRP4NETNS_VERSION="1.3.1"
export SLIRP4NETNS_TAG="v${SLIRP4NETNS_VERSION}"

# Netavark Veersion
export NETAVARK_VERSION="1.13.0"
export NETAVARK_TAG="v${NETAVARK_VERSION}"

# Aardvark-DNS Version
export AARDVARK_DNS_VERSION="1.13.1"
export AARDVARK_DNS_TAG="v${AARDVARK_DNS_VERSION}"

# Skopeo Version
export SKOPEO_VERSION="1.17.0"
export SKOPEO_TAG="v${SKOPEO_VERSION}"

# GoMD2Man Version
export GOMD2MAN_VERSION="2.0.5"
export GOMD2MAN_TAG="v${GOMD2MAN_VERSION}"

# Protoc version and Path
export PROTOC_VERSION="29.0"
export PROTOC_TAG="v${PROTOC_VERSION}"
export PROTOC_ROOT_FOLDER="/opt/protoc"
export PROTOC_PATH="${PROTOC_ROOT_FOLDER}/${PROTOC_VERSION}/bin/protoc"

# Create Build Folder Root
mkdir -p "${BUILD_ROOT}"
