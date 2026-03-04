# podman-debian
Install latest Podman on Debian

For latest stable as of 04.03.2026 you can use before running `setup.sh`

```
export SCCACHE_TAG="v0.14.0"
export PODMAN_TAG="v5.8.0"
export BUILDAH_TAG="v1.43.0"
export CRUN_TAG="1.26"               
export CONMON_TAG="v2.2.1"
export NETAVARK_TAG="v1.17.2"
export AARDVARK_DNS_TAG="v1.17.0"
export SKOPEO_TAG="v1.22.0"
export GOMD2MAN_TAG="v2.0.7"
export TOOLBOX_TAG="0.3"  # toolbox uses unprefixed tags (no v)
export FUSE_OVERLAYFS_TAG="v1.16"
export CATATONIT_TAG="v0.2.1"
export CONTAINER_LIBS_TAG="common/v0.67.0"  # container-libs uses namespaced tags: common/, image/, storage/
export PROTOC_TAG="v34.0"
export GOTAG="go1.26.0"
```

Forked from https://github.com/luckylinux/podman-debian

Added arm64 non-interactive support.