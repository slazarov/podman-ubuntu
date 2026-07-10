# Getting Started

This guide gets you from a clean Ubuntu system to a working Podman container
stack. There are two paths:

- **Install via APT** — the fastest way to get the pre-built packages. Best for
  end users who just want to run containers.
- **Build from source** — clone this repository and compile all 12 components
  locally. Best for contributors, or anyone who wants to build their own packages.

Pick the path that matches your goal below.

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Operating system | Ubuntu 24.04 (Noble Numbat). Other Debian/Ubuntu releases may work but are untested. |
| Architecture | amd64 (x86_64) or arm64 (aarch64) — detected automatically |
| Privileges | Root or `sudo` access |
| Network | Internet access (to fetch packages or clone upstream sources) |

For **rootless containers**, the system must also satisfy the pre-flight checks
enforced by the build (and recommended for any host running Podman rootless):

| Check | Requirement | Why |
|-------|-------------|-----|
| cgroups v2 | `/sys/fs/cgroup/cgroup.controllers` present | Required for rootless Podman |
| FUSE support | `/dev/fuse` present and readable | Required for `fuse-overlayfs` rootless storage |
| Kernel version | `>= 5.11` recommended (`>= 4.18` minimum) | Native rootless overlay needs 5.11+ |
| subuid / subgid | Configured for your user | Rootless mode will not function without it |
| Mount options | No `noexec` on `/tmp` and `$HOME` | Build and runtime processes need to execute |

If you only run rootful containers (as `root`), the subuid/subgid requirement
does not apply.

**Building from source has no separate toolchain prerequisites.** The build
auto-detects the required Go version from Podman's `go.mod` and the Rust version
from Netavark's `Cargo.toml`, then installs Go, Rust, and protoc itself.

## Installation steps

### Path A: Install via APT (recommended for end users)

Add the repository signing key and source, then install the full stack:

```bash
# 1. Download the GPG signing key
sudo mkdir -p /etc/apt/keyrings
sudo wget -qO /etc/apt/keyrings/podman-ubuntu.gpg \
  https://slazarov.github.io/podman-ubuntu/podman-ubuntu.gpg

# 2. Add the repository (DEB822 format)
sudo tee /etc/apt/sources.list.d/podman-ubuntu.sources << 'EOF'
Types: deb
URIs: https://slazarov.github.io/podman-ubuntu
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
EOF

# 3. Update and install the full suite
sudo apt update
sudo apt install -y podman-suite
```

The `podman-suite` meta-package pulls in all 12 `podman-*` component packages.
To install only the core runtime instead, run `sudo apt install podman-podman`.

The `Suites:` line selects a release track — `stable` (default), `edge`, or
`nightly`. See [apt-repository.md](apt-repository.md) for per-package
installation, switching tracks, and troubleshooting.

### Path B: Build from source (for contributors)

```bash
# 1. Clone the repository
git clone https://github.com/slazarov/podman-ubuntu.git

# 2. Change into the project directory
cd podman-ubuntu

# 3. Source the version pins for the track you want
source versions-stable.env

# 4. Run the build as root, preserving the environment
sudo -E ./setup.sh
```

`sudo -E` preserves the version variables exported by `versions-stable.env` so
the build picks up the pinned tags. To build the bleeding-edge nightly track
from upstream HEAD instead, `source versions-nightly.env` in step 3.

`setup.sh` first runs a pre-flight validation pass (the checks in the
Prerequisites table). If validation fails, it stops and prints the failing check
with a suggested fix. On success it installs the toolchain and compiles and
installs all 12 components from source.

**Optional build caching** (all disabled by default) can dramatically speed up
repeat builds. Export these before sourcing the version file:

```bash
export SCCACHE_ENABLED=true   # Rust build cache (50-90% rebuild speedup)
export CCACHE_ENABLED=true    # C build cache (30x warm-cache rebuilds)
export MOLD_ENABLED=true      # Fast linker for Rust (5-10x faster linking)

source versions-stable.env
sudo -E ./setup.sh
```

## First run

After either installation path completes, verify Podman works:

```bash
# Confirm the installed version
podman --version

# Run a throwaway container
podman run --rm docker.io/library/hello-world
```

A successful run prints the hello-world banner and exits cleanly. If you are
running rootless and this fails, re-check the subuid/subgid and cgroups v2 items
in the Common setup issues section below.

If you built from source, you can also run the project's unit tests:

```bash
./tests/test_extract_version_nightly.sh
```

The script prints `Results: N passed, 0 failed` on success.

## Common setup issues

- **`VAL-01: cgroups v2 is not available`** — The host is on the legacy cgroups
  v1 hierarchy. Add `systemd.unified_cgroup_hierarchy=1` to the kernel command
  line and reboot. cgroups v2 is required for rootless Podman.

- **`VAL-02: subuid/subgid not configured`** — Your user has no subordinate UID/GID
  range, so rootless mode will not work. Configure one:
  ```bash
  sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
  ```
  This check is skipped when running as `root`.

- **`VAL-03: FUSE kernel support not available`** — `/dev/fuse` is missing or
  unreadable, which `fuse-overlayfs` needs for rootless storage. Install the
  `fuse3` package or enable FUSE in your kernel.

- **`VAL-05: noexec mount detected`** — `/tmp` or `$HOME` is mounted with
  `noexec`, which blocks build and runtime processes. Remove `noexec` from the
  mount options in `/etc/fstab`, or set `TMPDIR` to a directory on an executable
  filesystem before running the build.

- **APT can't verify the repository** — Confirm the GPG key downloaded to
  `/etc/apt/keyrings/podman-ubuntu.gpg` and that the `Signed-By:` path in your
  `.sources` file matches it exactly, then re-run `sudo apt update`.

## Next steps

- [ARCHITECTURE.md](ARCHITECTURE.md) — How the build-and-publish pipeline is
  structured, from `setup.sh` through packaging to the hosted APT repository.
- [apt-repository.md](apt-repository.md) — Full APT repository guide: release
  tracks, per-package installation, switching suites, and troubleshooting.
- [../README.md](../README.md) — Project overview, component list, and the
  current pinned versions for each release track.
