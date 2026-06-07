# Technology Stack

**Analysis Date:** 2026-06-07

## Languages

**Primary:**
- Bash (bash 4+) - All pipeline orchestration, build scripts, CI scripts, test files

**Secondary:**
- YAML - nFPM package definitions (`packaging/nfpm/*.yaml`), GitHub Actions workflow (`.github/workflows/build-packages.yml`), Lima VM configs (`lima/*.yaml`)

## Runtime

**Environment:**
- Linux only (Debian/Ubuntu). Scripts use `apt-get` directly and require Linux kernel features (namespaces, overlayfs). macOS development is supported only for editing; pipeline execution requires a Linux host or Lima VM.
- Target distros: Ubuntu 24.04 (amd64 + arm64), Ubuntu 26.04 (amd64 + arm64)

**Build Execution:**
- Requires root (`apt-get` is called without sudo wrappers inside scripts)
- Lima VMs for local testing: `ubuntu-24` (24.04) and `ubuntu-26` (26.04), repo mounted writable at `/opt/podman-debian`

## Frameworks

**Build Pipeline:**
- GNU Make - invoked by component build scripts for C components (crun, conmon, pasta)
- Cargo - invoked for Rust components (netavark, aardvark-dns)
- Go toolchain - invoked for Go components (podman, buildah, skopeo, go-md2man, toolbox)
- Meson - used for toolbox build (`scripts/build_toolbox.sh`)

**Packaging:**
- nFPM v2.45.0 - packages DESTDIR staging tree into `.deb` files; not installed by `setup.sh`, must be installed separately via `go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.45.0`
- reprepro - assembles the APT repository from `.deb` files; installed via `apt-get` in CI (`scripts/repo_manage.sh`, `scripts/ci_publish.sh`)

**Testing:**
- Bash (direct execution) - all tests in `tests/` are standalone bash scripts, no framework dependency

**CI:**
- GitHub Actions - `.github/workflows/build-packages.yml`; uses: `actions/checkout@v4`, `actions/cache@v4`, `actions/upload-artifact@v4`, `actions/download-artifact@v4`, `actions/configure-pages@v4`, `actions/upload-pages-artifact@v3`, `actions/deploy-pages@v4`

## Key Dependencies

**Toolchain (installed from upstream at build time, not via apt):**
- Go - downloaded from `https://go.dev/dl/` and installed to `/opt/go/<version>/`; version auto-detected from Podman's `go.mod`
- Rust (via rustup) - downloaded from `https://static.rust-lang.org/rustup/`; version auto-detected from Netavark's `Cargo.toml`
- protoc - downloaded from GitHub releases (`github.com/protocolbuffers/protobuf`); version configurable via `PROTOC_VERSION` (stable pins: `34.0`)

**Build Components (compiled from upstream source):**

| Component | Language | Stable Tag | Upstream |
|-----------|----------|------------|----------|
| podman | Go | v5.8.0 | `github.com/containers/podman` |
| buildah | Go | v1.43.0 | `github.com/containers/buildah` |
| skopeo | Go | v1.22.0 | `github.com/containers/skopeo` |
| go-md2man | Go | v2.0.7 | `github.com/cpuguy83/go-md2man` |
| toolbox | Go/Meson | 0.3 | `github.com/containers/toolbox` |
| conmon | C | v2.2.1 | `github.com/containers/conmon` |
| crun | C | 1.26 | `github.com/containers/crun` |
| catatonit | C | v0.2.1 | `github.com/openSUSE/catatonit` |
| fuse-overlayfs | C | v1.16 | `github.com/containers/fuse-overlayfs` |
| pasta | C | latest | `https://passt.top/passt` |
| netavark | Rust | v1.17.2 | `github.com/containers/netavark` |
| aardvark-dns | Rust | v1.17.0 | `github.com/containers/aardvark-dns` |
| container-libs | N/A | common/v0.67.0 | `github.com/containers/container-libs` |

**Optional Build Acceleration:**
- sccache v0.14.0 - Rust build caching (`SCCACHE_ENABLED=true`); downloaded from `github.com/mozilla/sccache/releases/`
- ccache - C build caching (`CCACHE_ENABLED=true`); installed via `apt-get`
- mold linker - faster Rust linking (`MOLD_ENABLED=true`)

**APT Build Dependencies (installed via apt-get by `scripts/install_dependencies.sh`):**
- libapparmor-dev, libassuan-dev, libbtrfs-dev, libc6-dev, libdevmapper-dev, libglib2.0-dev, libgpgme-dev, libgpg-error-dev, libprotobuf-dev, libprotobuf-c-dev, libseccomp-dev, libselinux1-dev, libsystemd-dev, libfuse3-dev, libcap-dev, libjson-c-dev, libyajl-dev, libsubid-dev
- Build tools: make, pkg-config, git, gcc, build-essential, pkgconf, libtool, autoconf, automake, python3, meson, codespell, cmake, uidmap, unzip

## Configuration

**Environment Variables:**
- Controlled entirely via environment variables with `${VAR:-default}` pattern in `config.sh`
- `ARCH` - target architecture (auto-detected); values: `amd64`, `arm64`
- `DISTRO` - override for distro version ID (dotted, e.g. `24.04`); auto-detected from `/etc/os-release`
- `NIGHTLY_BUILD=true` - enables nightly track (builds from HEAD, sets `SHALLOW_CLONE=false`)
- `SHALLOW_CLONE=true` (default) - shallow git clones for ~95% network savings
- `NPROC` - parallel job count (default: `nproc`)
- `SCCACHE_ENABLED=false`, `CCACHE_ENABLED=false`, `MOLD_ENABLED=false` - opt-in build accelerators
- `DESTDIR` - staging directory for `make install` output (required for `package_all.sh`)
- `GOCACHE=/var/cache/go-build`, `GOMODCACHE=/var/cache/go-mod` - Go cache directories
- Component version pins: `PODMAN_TAG`, `BUILDAH_TAG`, `CRUN_TAG`, `CONMON_TAG`, `NETAVARK_TAG`, `AARDVARK_DNS_TAG`, `SKOPEO_TAG`, `GOMD2MAN_TAG`, `TOOLBOX_TAG`, `FUSE_OVERLAYFS_TAG`, `CATATONIT_TAG`, `CONTAINER_LIBS_TAG`, `PROTOC_VERSION`

**Track Version Files:**
- `versions-stable.env` - pinned component versions for the stable release track (source before `setup.sh`)
- `versions-nightly.env` - nightly-specific overrides
- Edge track: auto-detects latest upstream tags at build time (no version file)

**Build Paths:**
- `BUILD_ROOT` = `<repo>/build` (component source checkouts, gitignored)
- `GO_ROOT_FOLDER` = `/opt/go`
- `PROTOC_ROOT_FOLDER` = `/opt/protoc`

## Platform Requirements

**Development (macOS):**
- Edit scripts; use `bash -n <script>` for syntax checks
- Real builds require Lima VMs via `limactl shell ubuntu-24 -- bash -c 'cd /opt/podman-debian && ...'`
- Unit tests run directly: `bash tests/<test>.sh`

**Production / CI:**
- Ubuntu 24.04 runners (amd64: `ubuntu-24.04`, arm64: `ubuntu-24.04-arm`)
- Ubuntu 26.04 cells run inside `ubuntu:26.04` container on 24.04 host runners
- APT repository published to GitHub Pages

---

*Stack analysis: 2026-06-07*
