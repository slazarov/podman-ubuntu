# podman-ubuntu

Compile and install the latest Podman container stack from source on Debian/Ubuntu, or install pre-built packages from the hosted APT repository.

[![lint](https://github.com/slazarov/podman-ubuntu/actions/workflows/lint.yml/badge.svg)](https://github.com/slazarov/podman-ubuntu/actions/workflows/lint.yml)
[![build](https://github.com/slazarov/podman-ubuntu/actions/workflows/build-packages.yml/badge.svg)](https://github.com/slazarov/podman-ubuntu/actions/workflows/build-packages.yml)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)

| | |
|---|---|
| **License** | AGPL-3.0 |
| **Platforms** | Ubuntu 24.04 (Noble Numbat), Ubuntu 26.04 (Resolute Raccoon) |
| **Architectures** | amd64 (x86_64), arm64 (aarch64) |

Forked from [luckylinux/podman-debian](https://github.com/luckylinux/podman-debian) with significant additions: arm64 support, fully non-interactive builds, a hosted APT repository, CI/CD pipelines, 12 packaged components, opt-in build caching, and three release tracks (stable, v5, nightly).

---

## Install via APT (Recommended)

Add the repository and install the full Podman stack in four commands:

```bash
# Download the GPG signing key
sudo mkdir -p /etc/apt/keyrings
sudo wget -qO /etc/apt/keyrings/podman-ubuntu.gpg \
  https://slazarov.github.io/podman-ubuntu/podman-ubuntu.gpg

# Add the repository (DEB822 format).
# Use the suite for your Ubuntu version: stable-2404 (24.04) or stable-2604 (26.04).
sudo tee /etc/apt/sources.list.d/podman-ubuntu.sources << 'EOF'
Types: deb
URIs: https://slazarov.github.io/podman-ubuntu
Suites: stable-2404
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
EOF

# Update and install
sudo apt update
sudo apt install -y podman-suite
```

The `podman-suite` meta-package pulls in all 12 components listed below.

For full details, troubleshooting, and per-package installation, see [docs/apt-repository.md](docs/apt-repository.md).

### Release Tracks

Each track is published per Ubuntu version with a distro-qualified suite name:

| Track | Ubuntu 24.04 suite | Ubuntu 26.04 suite | Update Frequency |
|-------|--------------------|--------------------|------------------|
| **stable** | `stable-2404` | `stable-2604` | Podman 6.x, auto-updated within the major (soak window) |
| **v5** | `v5-2404` | `v5-2604` | Podman 5.x maintenance, auto-updated within the series |
| **nightly** | `nightly-2404` | `nightly-2604` | Daily at 4:30 AM UTC |

Use **stable** for the current Podman 6.x line, **v5** to stay on the Podman 5.x maintenance line, and **nightly** for bleeding-edge development.

To switch tracks, change the `Suites:` line in your sources file and re-run `apt update`:

```bash
# Example: switch from stable to v5 on Ubuntu 24.04
sudo sed -i 's/^Suites: .*/Suites: v5-2404/' /etc/apt/sources.list.d/podman-ubuntu.sources
sudo apt update
sudo apt upgrade
```

> **Note:** The bare suite names `stable` and `nightly` are deprecated as of v1.3 and will be removed in a future release. They continue to serve Ubuntu 24.04 packages during the deprecation window. The `v5` track has no bare alias — always use its distro-qualified name (`v5-2404` / `v5-2604`). New setups should use the distro-qualified names above; existing users should migrate (see [docs/apt-repository.md](docs/apt-repository.md)).

---

## Individual Packages

All packages use the `podman-*` prefix and declare `Conflicts`, `Replaces`, and `Provides` against the official Ubuntu packages, so the newer compiled-from-source versions take priority.

| Package | Description |
|---------|-------------|
| `podman-podman` | Container engine (core) |
| `podman-crun` | OCI runtime |
| `podman-conmon` | Container monitor |
| `podman-netavark` | Container networking |
| `podman-aardvark-dns` | DNS for container networks |
| `podman-pasta` | User-mode networking (passt) |
| `podman-fuse-overlayfs` | Rootless overlay filesystem |
| `podman-catatonit` | Minimal init for containers |
| `podman-buildah` | OCI image builder |
| `podman-skopeo` | Container image utility |
| `podman-toolbox` | Containerized development environments |
| `podman-container-configs` | Configuration files for `/etc/containers/` |

Install only the core runtime (it pulls required dependencies automatically):

```bash
sudo apt install podman-podman
```

---

## Build from Source

For users who prefer to compile everything locally rather than using the APT repository.

### Prerequisites

- Debian or Ubuntu system (tested on Ubuntu 24.04 and 26.04)
- Root or sudo access
- Internet access

The build auto-detects the Go and Rust toolchain versions from upstream sources (Podman's `go.mod` and Netavark's `Cargo.toml`) and installs Go, Rust, and protoc itself, so no manual toolchain setup is required.

### Build Steps

```bash
git clone https://github.com/slazarov/podman-ubuntu.git
cd podman-ubuntu

# Resolve the stable-track policy into concrete version tags (Podman 6.x)
eval "$(./scripts/resolve_versions.sh versions-stable.env)"

# Run the build (as root, preserving the environment)
sudo -E ./setup.sh
```

`setup.sh` runs a pre-flight validation step, then builds and installs all 12 components from source. The build is fully non-interactive and auto-detects the system architecture (amd64 or arm64).

To build the Podman 5.x maintenance track, resolve `versions-v5.env` instead (`eval "$(./scripts/resolve_versions.sh versions-v5.env)"`). To build the nightly track from upstream HEAD, source `versions-nightly.env` before running `setup.sh`.

### Build Options

Override environment variables before running `setup.sh` to enable opt-in build caching (all disabled by default):

```bash
# Enable sccache for Rust builds (50-90% rebuild speedup)
export SCCACHE_ENABLED=true

# Enable ccache for C builds (30x faster warm-cache rebuilds)
export CCACHE_ENABLED=true

# Enable mold linker for Rust builds (5-10x faster linking)
export MOLD_ENABLED=true

eval "$(./scripts/resolve_versions.sh versions-stable.env)"
sudo -E ./setup.sh
```

| Layer | Purpose | Speedup | Enable |
|-------|---------|---------|--------|
| **sccache** | Rust compilation cache | 50-90% rebuild | `export SCCACHE_ENABLED=true` |
| **ccache** | C compilation cache | 30x warm-cache | `export CCACHE_ENABLED=true` |
| **Go cache** | Shared Go module/build cache | 20x rebuild | Enabled by default (`GOCACHE`, `GOMODCACHE`) |
| **mold** | Fast linker for Rust | 5-10x linking | `export MOLD_ENABLED=true` |

### Uninstall

To cleanly remove all components installed from source:

```bash
sudo ./uninstall.sh
```

---

## Components

The project builds and packages the following 12 components from upstream sources:

| Component | Upstream Repository | Description |
|-----------|---------------------|-------------|
| Podman | [containers/podman](https://github.com/containers/podman) | Daemonless container engine |
| Buildah | [containers/buildah](https://github.com/containers/buildah) | OCI image builder |
| Skopeo | [containers/skopeo](https://github.com/containers/skopeo) | Container image operations (copy, inspect, sign) |
| crun | [containers/crun](https://github.com/containers/crun) | Fast, low-memory OCI runtime (C) |
| conmon | [containers/conmon](https://github.com/containers/conmon) | Container monitor (stdio, exit code, logging) |
| Netavark | [containers/netavark](https://github.com/containers/netavark) | Container network stack (Rust) |
| Aardvark-DNS | [containers/aardvark-dns](https://github.com/containers/aardvark-dns) | Authoritative DNS for container networks |
| pasta/passt | [passt.top](https://passt.top/) | User-mode networking (no root required) |
| fuse-overlayfs | [containers/fuse-overlayfs](https://github.com/containers/fuse-overlayfs) | FUSE overlay filesystem for rootless containers |
| catatonit | [openSUSE/catatonit](https://github.com/openSUSE/catatonit) | Minimal init process for containers |
| Toolbox | [containers/toolbox](https://github.com/containers/toolbox) | Containerized CLI development environments |
| containers-common | [containers/common](https://github.com/containers/common) | Shared config files, seccomp profiles, policy |

### Track Versions

Versions are not hand-pinned. The **stable** track follows the Podman 6.x line and the **v5** track follows the Podman 5.x maintenance line; each auto-updates within its series. [`scripts/resolve_versions.sh`](scripts/resolve_versions.sh) reads a policy file ([`versions-stable.env`](versions-stable.env) / [`versions-v5.env`](versions-v5.env)) declaring per-component series caps and a soak window (a new upstream tag is only adopted once its commit is at least `STABLE_SOAK_DAYS`, default 7, old), then materializes the concrete tags — with Buildah derived from Podman's `go.mod`. The concrete versions currently published are shown in the package-versions table on the repository's [`index.html`](https://slazarov.github.io/podman-ubuntu/). The **nightly** track builds from upstream HEAD daily.

---

## Supported Platforms

| Platform | Architectures |
|----------|--------------|
| Ubuntu 24.04 (Noble Numbat) | amd64 (x86_64), arm64 (aarch64) |
| Ubuntu 26.04 (Resolute Raccoon) | amd64 (x86_64), arm64 (aarch64) |

Every distro × architecture cell is built natively in CI (not cross-compiled), and APT selects the correct one automatically.

---

## Non-Goals

To stay focused, the project deliberately does **not** provide: end-user pinning to an arbitrary version (each track auto-updates within its own policy — major series plus a soak window), a GUI installer, non-Debian/Ubuntu distributions, 32-bit ARM, resumable or partial builds, component selection, or CNI networking (removed upstream in Podman 5.0).

---

## License

[AGPL-3.0](LICENSE)

---

## Credits

- Forked from [luckylinux/podman-debian](https://github.com/luckylinux/podman-debian)
- Upstream: [Podman](https://github.com/containers/podman) by the Containers project
