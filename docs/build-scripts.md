# Build Scripts Reference

This document is a reference for every shell script in this repository that
participates in building the Podman container stack from source and turning it
into Debian packages. It covers the top-level entry points, the shared helper
libraries they source, the toolchain installers, the per-component build
scripts, and the packaging / repository-management scripts.

For the high-level pipeline view (how these scripts fit together), see
[ARCHITECTURE.md](ARCHITECTURE.md). For consuming the published APT repository,
see [apt-repository.md](apt-repository.md).

## Overview

The build is orchestrated by `setup.sh`, which sources a shared configuration
(`config.sh`) and function library (`functions.sh`), runs a host pre-flight
check, then executes the toolchain installers and per-component build scripts in
a fixed order. Each component is compiled from its upstream git repository into
a shared staging tree (`DESTDIR`). A separate packaging script
(`scripts/package_all.sh`) converts that staging tree into `.deb` files via
[nFPM](https://nfpm.goreleaser.com/), and `scripts/repo_manage.sh` assembles
those `.deb` files into a signed [reprepro](https://wiki.debian.org/reprepro)
APT repository.

### Common conventions

Almost every script in `scripts/` follows the same boilerplate:

- **Strict mode** — `set -euo pipefail` (exit on error, undefined variable, or
  pipe failure).
- **`toolpath` discovery** — each script computes `toolpath` (the repository
  root) from its own location so it can be run standalone or sourced.
- **Sourcing** — `config.sh` and `functions.sh` are sourced first (note that
  `functions.sh` sources `config.sh` at its end, and both guard against
  recursive sourcing).
- **Error trap** — `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR` is
  installed *after* sourcing, so a failing step prints the script name, line,
  and exit code.
- **`DESTDIR` staging** — build scripts install into `${DESTDIR}/usr/...` when
  `DESTDIR` is set (the packaging path) and fall back to `sudo install` into the
  live system when it is not (the direct-install path).
- **Build logging** — `log_build_output "<component>"` opens a per-component log
  in `log/build_<component>.log`, and `run_logged <cmd>` redirects verbose
  output there, dumping the last 40 lines to stderr only on failure.
- **Progress timing** — `step_start "..."` / `step_done` print and time each
  build step.

### Key environment variables

These are defined in `config.sh` and consumed across the scripts. All have
sensible defaults; most can be overridden from the environment.

| Variable | Purpose | Default |
| --- | --- | --- |
| `ARCH` | Normalized architecture (`amd64` / `arm64`) | auto-detected from `uname -m` |
| `GOVERSION` | Go toolchain version | auto-detected from Podman's `go.mod` |
| `RUST_VERSION` | Rust toolchain version | auto-detected from Netavark's `Cargo.toml` |
| `PROTOC_VERSION` | protoc version | latest release (or pinned) |
| `NPROC` | Parallel job count for `make` / `cargo` | number of CPU cores |
| `DESTDIR` | Staging tree for packaging installs | unset (direct install) |
| `BUILD_ROOT` | Build workspace (cloned sources, downloads) | `<repo>/build` |
| `SHALLOW_CLONE` | Shallow git clones to reduce transfer | `true` |
| `NIGHTLY_BUILD` | Build from upstream HEAD instead of a tag | `false` |
| `<COMPONENT>_TAG` | Pinned upstream tag per component | empty (auto-detect latest) |
| `SCCACHE_ENABLED` | Enable sccache for Rust caching | `false` |
| `CCACHE_ENABLED` | Enable ccache for C caching | `false` |
| `MOLD_ENABLED` | Enable mold linker for Rust | `false` |
| `GPG_PRIVATE_KEY` | GPG key to import (repo signing, CI) | unset |

Build-track presets live in `versions-stable.env` (pinned `*_TAG` values for the
stable track) and `versions-nightly.env` (sets `NIGHTLY_BUILD=true` and
`SHALLOW_CLONE=false`). Source one of these before `setup.sh` to select a track.

---

## Entry Points

### `setup.sh`

**Purpose:** Top-level build orchestrator. Runs the full pipeline from host
validation through component installation.

**Key inputs:** All `config.sh` variables; optionally a sourced
`versions-*.env` file to select a build track. Sets
`DEBIAN_FRONTEND=noninteractive` before any apt operations.

**Produces:** A fully built and installed Podman stack — either into `DESTDIR`
(when set) or directly into the system.

**Notable behavior:**
- Sources `config.sh` and `functions.sh`, then runs
  `scripts/preflight_check.sh` (via `run_preflight_checks`) and aborts if
  validation fails.
- Defines `run_script()`, which sources each sub-script with timing and records
  success in the `COMPONENTS_OK` array.
- Runs scripts in a fixed order: install dependencies, Rust, protoc, Go; then
  builds aardvark-dns, buildah, catatonit, conmon, crun, fuse-overlayfs,
  go-md2man, container-libs, netavark, pasta, podman, skopeo, toolbox; then
  installs container config files and man pages.

### `uninstall.sh`

**Purpose:** Removes source-installed Podman stack components, binaries,
caches, config, man pages, and systemd units.

**Key inputs:** `config.sh` variables (notably `BUILD_ROOT`).

**Produces:** A cleaned system with a printed summary of removed vs. skipped
items.

**Notable behavior:**
- Defines tracked-removal helpers `safe_rm_dir`, `safe_rm_file`, and
  `safe_make_uninstall` (which runs `make uninstall` in each `build/<component>`
  directory when present).
- Uses `remove_if_user_installed` (from `functions.sh`) for binaries under
  `/usr/bin` so dpkg-managed files are left untouched.
- Removes Go (`/opt/go`), all build/Go/ccache/sccache caches, and — if they were
  installed via `MOLD_ENABLED=true` — the `mold` and `clang` apt packages.

---

## Shared Helpers

These are sourced by every script rather than executed directly.

### `config.sh`

**Purpose:** Central build configuration. Detects architecture, resolves
toolchain versions, and exports all build paths, optimization flags, and
component tag variables.

**Notable behavior:**
- Maps `ARCH` to vendor-specific strings (`GOARCH`, `PROTOC_ARCH`,
  `RUSTUP_ARCH`, `SCCACHE_ARCH`).
- Auto-detects `GOVERSION` from Podman's `go.mod` and `RUST_VERSION` from
  Netavark's `Cargo.toml` (via `functions.sh` helpers) when not pinned.
- Auto-detects the latest `PROTOC_VERSION` when not pinned.
- Defines optimization toggles for sccache, ccache, mold, and Go build flags,
  plus persistent Go caches (`GOCACHE`, `GOMODCACHE`).
- Declares all `<COMPONENT>_TAG` variables, defaulting to empty (so the latest
  upstream tag is used unless a track pins them).
- Creates `BUILD_ROOT` and the Go cache directories.

### `functions.sh`

**Purpose:** Shared shell library used by every other script.

**Notable behavior — key functions:**
- `detect_architecture()` — normalizes `uname -m` to `amd64` / `arm64`; aborts
  on unsupported architectures.
- `get_latest_tag()` — returns the highest stable (non-rc) git tag in the
  current repo, handling both `v`-prefixed and numeric tags.
- `get_latest_protoc_version()` / `get_latest_go_version()` — query upstream
  release APIs.
- `get_required_go_version()` — reads Podman's `go.mod` (prefers the
  `toolchain` directive, falls back to the `go` directive, then to the latest
  Go release).
- `get_required_rust_version()` — reads Netavark's `Cargo.toml`
  `rust-version` (MSRV), falling back to `stable`.
- `git_clone_update()` — clones (honoring `SHALLOW_CLONE`) or fetches an
  existing repo.
- `git_checkout()` — checks out a tag, or stays on HEAD for nightly builds, or
  selects the latest tag; exports `GIT_CHECKED_OUT_TAG`.
- `log_component()` — appends an install/update line to a dated log file.
- `remove_if_user_installed()` — deletes a file only if dpkg does not own it.
- `cleanup_build_artifacts()` — removes downloaded archives from `BUILD_ROOT`.
- `error_handler()` — the ERR-trap handler that prints script/line/exit-code.
- `format_duration` / `script_start` / `script_done` / `step_start` /
  `step_done` — progress and timing helpers.
- `log_build_output()` / `run_logged()` — per-component build logging.

---

## Toolchain Installers

These run early in `setup.sh` to prepare the build environment. Each sources
`config.sh`/`functions.sh` and operates inside `BUILD_ROOT`.

### `scripts/install_dependencies.sh`

**Purpose:** Installs all apt build dependencies for the component stack.

**Produces:** System packages for building Podman, crun, buildah, conmon,
netavark, fuse-overlayfs, toolbox, and protoc (dev libraries, `make`, autotools,
`meson`, `cmake`, `pkg-config`, `uidmap`, etc.).

**Notable behavior:** Conditionally installs `ccache` when
`CCACHE_ENABLED=true`, and `mold` + `clang` when `MOLD_ENABLED=true`.

### `scripts/install_rust.sh`

**Purpose:** Installs the Rust toolchain via rustup.

**Key inputs:** `RUSTUP_ARCH`, `RUST_VERSION` (defaults to `stable`),
`SCCACHE_ENABLED`, `SCCACHE_VERSION`, `SCCACHE_ARCH`.

**Produces:** A rustup-managed toolchain at the requested version; optionally
the `sccache` binary in `/usr/local/bin` and its cache directory.

**Notable behavior:** Downloads `rustup-init` for the detected architecture and
installs sccache only when `SCCACHE_ENABLED=true`.

### `scripts/install_go.sh`

**Purpose:** Installs the Go toolchain.

**Key inputs:** `GOVERSION` (resolved in `config.sh`), `GOARCH`, `GOROOT`.

**Produces:** A Go installation under `/opt/go/<version>`.

**Notable behavior:** Downloads the official Go tarball for the detected
architecture, replaces any existing `GOROOT`, and calls
`cleanup_build_artifacts`.

### `scripts/install_protoc.sh`

**Purpose:** Installs the Protocol Buffers compiler (`protoc`).

**Key inputs:** `PROTOC_VERSION` / `PROTOC_TAG`, `PROTOC_ARCH`,
`PROTOC_ROOT_FOLDER`, `PROTOC_PATH`.

**Produces:** protoc under `/opt/protoc/<version>` with a `/usr/local/bin/protoc`
symlink.

**Notable behavior:** Downloads the matching protoc release zip and symlinks the
binary into `PATH`; calls `cleanup_build_artifacts`.

---

## Component Builds

There are 13 component build scripts. They share the same skeleton: clone/update
the upstream repo into `BUILD_ROOT/<component>`, check out the requested tag,
log the version, build, and install (into `DESTDIR` when set). Differences below
focus on build system and notable per-component behavior.

### `scripts/build_aardvark_dns.sh`

- **Upstream:** `github.com/containers/aardvark-dns` — **Build system:** Rust (`make`).
- **Inputs:** `AARDVARK_DNS_TAG`, `CARGO_BUILD_JOBS`, plus optional
  `SCCACHE_ENABLED` / `MOLD_ENABLED`.
- **Produces:** `aardvark-dns` binary in `${DESTDIR}/usr/bin`.
- **Notable:** Sources `~/.cargo/env` (with cloud-init `HOME` fallback); writes
  a project-level `.cargo/config.toml` for mold when enabled.

### `scripts/build_buildah.sh`

- **Upstream:** `github.com/containers/buildah` — **Build system:** Go (`make`).
- **Inputs:** `BUILDAH_TAG`, `GOPATH`, `NPROC`, Go flags (`GO_GCFLAGS`,
  `GO_LDFLAGS`).
- **Produces:** `buildah` binary, man pages, and bash completions.
- **Notable:** Patches `go.mod` (`go 1.22.6` → `go 1.23`); builds only the
  `bin/buildah` target (avoiding the `docs`→`install.tools` golangci-lint
  download) and generates man pages directly with `go-md2man`, replicating the
  upstream docs sed pipeline.

### `scripts/build_catatonit.sh`

- **Upstream:** `github.com/openSUSE/catatonit` — **Build system:** C / autotools.
- **Inputs:** `CATATONIT_TAG`, `NPROC`, optional `CCACHE_ENABLED`.
- **Produces:** `catatonit` (installed via `make install`).
- **Notable:** Creates an `m4` directory and runs `./autogen.sh` before
  `./configure --prefix=/usr`.

### `scripts/build_conmon.sh`

- **Upstream:** `github.com/containers/conmon` — **Build system:** Go (`make`).
- **Inputs:** `CONMON_TAG`, `NPROC`, Go flags.
- **Produces:** `conmon` binary via `make install.bin`.
- **Notable:** Installs only the binary (`install.bin`) to skip the docs target,
  which requires go-md2man; man pages are handled by
  `install_container-manpages.sh`.

### `scripts/build_crun.sh`

- **Upstream:** `github.com/containers/crun` — **Build system:** C / autotools.
- **Inputs:** `CRUN_TAG`, `NPROC`, optional `CCACHE_ENABLED`.
- **Produces:** `crun` (installed via `make install`).
- **Notable:** crun dynamically links a JSON parser at runtime; the actual
  runtime dependency (`libyajl2` or `libjson-c5`) is detected later during
  packaging (`detect_crun_parser_depend` in `package_all.sh`).

### `scripts/build_fuse-overlayfs.sh`

- **Upstream:** `github.com/containers/fuse-overlayfs` — **Build system:** Rust
  *or* C / autotools (auto-detected).
- **Inputs:** `FUSE_OVERLAYFS_TAG`, plus Rust or C caching toggles depending on
  the detected build system.
- **Produces:** `fuse-overlayfs` binary.
- **Notable:** Detects the build system by the presence of `Cargo.toml` — Rust
  for v2.0+ on `main`, C/autotools (`./autogen.sh`, static link with
  `LDFLAGS="-static"`) for v1.x tags.

### `scripts/build_go-md2man.sh`

- **Upstream:** `github.com/cpuguy83/go-md2man` — **Build system:** Go (`make`).
- **Inputs:** `GOMD2MAN_TAG`, `GOPATH`, Go flags.
- **Produces:** `go-md2man` binary in `/usr/local/bin`.
- **Notable:** Built early so later scripts (buildah, container-libs man pages)
  can generate man pages. Patches `go.mod` (`go 1.22.6` → `go 1.23`). Installs
  the binary directly with `cp` (not into `DESTDIR`) since it is a build-time
  tool, not a packaged artifact.

### `scripts/build_container-libs.sh`

- **Upstream:** `github.com/containers/container-libs` — **Build system:** Go
  codegen (`make -C common seccomp.json`).
- **Inputs:** `CONTAINER_LIBS_TAG` (use a `common/vX.Y.Z` tag), `GOPATH`.
- **Produces:** `common/pkg/seccomp/seccomp.json` inside the build tree (no
  binary install).
- **Notable:** This script only generates artifacts; the resulting
  `seccomp.json`, config files, and man-page sources are consumed later by
  `install_container-configs.sh` and `install_container-manpages.sh`. It
  verifies the generated `seccomp.json` exists before finishing.

### `scripts/build_netavark.sh`

- **Upstream:** `github.com/containers/netavark` — **Build system:** Rust (`make`).
- **Inputs:** `NETAVARK_TAG`, `CARGO_BUILD_JOBS`, optional sccache/mold.
- **Produces:** `netavark` and `netavark-dhcp-proxy-client` binaries in
  `${DESTDIR}/usr/bin`.

### `scripts/build_pasta.sh`

- **Upstream:** `passt.top/passt` (git protocol) — **Build system:** C (`make`).
- **Inputs:** `NPROC`, optional `CCACHE_ENABLED`.
- **Produces:** `passt`, `pasta`, and their `.avx2` variants (when present).
- **Notable:** passt has no release tags in this workflow — it always builds
  from HEAD and uses a date-based version (`YYYYMMDD`) as
  `GIT_CHECKED_OUT_TAG`. In direct-install mode it kills any running `pasta`
  processes before reinstalling and removes stray source files mistakenly placed
  in `/usr/local/bin`.

### `scripts/build_podman.sh`

- **Upstream:** `github.com/containers/podman` — **Build system:** Go (`make`).
- **Inputs:** `PODMAN_TAG`, `GOPATH`, `NPROC`, Go flags;
  `BUILDTAGS="seccomp apparmor systemd"`.
- **Produces:** Podman binaries, man pages, and completions via `make install`
  and `make install.completions`.

### `scripts/build_skopeo.sh`

- **Upstream:** `github.com/containers/skopeo` — **Build system:** Go (`make`).
- **Inputs:** `SKOPEO_TAG`, `GOPATH`, `GOROOT`, `NPROC`, Go flags;
  `BUILDTAGS="seccomp apparmor systemd"`.
- **Produces:** `skopeo` binary, man pages, and completions via `make install`.
- **Notable:** Patches `go.mod` (`go 1.22.6` → `go 1.23`).

### `scripts/build_toolbox.sh`

- **Upstream:** `github.com/containers/toolbox` — **Build system:** Meson.
- **Inputs:** `TOOLBOX_TAG`, `GOPATH`.
- **Produces:** `toolbox` and its supporting files via `meson install`.
- **Notable:** Configures with `meson setup --prefix /usr --buildtype=plain`,
  runs `meson test` before installing, and patches `go.mod` if present.

---

## Config and Man-Page Installers

These run after the component builds and consume artifacts produced by
`build_container-libs.sh`.

### `scripts/install_container-configs.sh`

**Purpose:** Installs the six container runtime configuration files to their
standard system paths.

**Produces (under `DESTDIR`):** `containers.conf` (from the project's
`config/` directory), `seccomp.json`, `policy.json`, `default.yaml`,
`storage.conf`, and `registries.conf` (the latter five from the
`container-libs` build tree).

**Notable behavior:** Aborts if the generated `seccomp.json` is missing
(requires `build_container-libs.sh` to have run), and verifies all six files
exist after installation.

### `scripts/install_container-manpages.sh`

**Purpose:** Builds and installs section-5 man pages from the `container-libs`
source.

**Produces (under `${DESTDIR}/usr/share/man/man5`):** Man pages generated with
`go-md2man` from `common/docs`, `image/docs`, and `storage/docs`, plus the
`.containerignore.5` alias (≈15 pages + 1 alias).

**Notable behavior:** Warns (non-fatal) if fewer than 15 man pages are found
after installation.

---

## Packaging and Repository Management

### `scripts/preflight_check.sh`

**Purpose:** Validates host requirements for rootless Podman before any build
work begins. Can be sourced (by `setup.sh`) or run standalone.

**Produces:** A pass/warn/fail report; returns non-zero when any error-level
check fails.

**Notable behavior — checks performed:**
- **VAL-01** cgroups v2 available (error).
- **VAL-02** subuid/subgid configured for the current user (warning; skipped
  for root).
- **VAL-03** FUSE kernel support (`/dev/fuse`) available (error).
- **VAL-04** kernel version — `>= 5.11` recommended, `>= 4.18` minimum (warn /
  error).
- **VAL-05** no `noexec` mount on `/tmp`, `$HOME`, or `$TMPDIR` (error).

### `scripts/package_all.sh`

**Purpose:** Builds all `.deb` packages from a populated staging tree using
nFPM.

**Key inputs:** `DESTDIR` (required, must exist), `ARCH`, the
`<COMPONENT>_TAG` variables, and `NIGHTLY_BUILD`. Requires the `nfpm` binary in
`PATH`.

**Produces:** One `.deb` per component plus the `podman-suite` meta-package, all
written to `<repo>/output`.

**Notable behavior:**
- Appends the `~podman1` version suffix so official distro packages can upgrade
  over these.
- `extract_version()` derives a clean version from each tag (special cases for
  pasta's date stamp and the `container-configs` namespaced tag).
- `extract_version_nightly()` (when `NIGHTLY_BUILD=true`) reads the dev version
  from each component's source files and appends `~git<date>.<sha>` so nightly
  builds sort below tagged releases.
- `resolve_tag_from_repo()` reads the checked-out tag back out of each build
  repo for edge builds where tags are not pinned.
- `detect_crun_parser_depend()` inspects `ldd` on the built crun binary to set
  the correct runtime parser dependency (`libjson-c5` or `libyajl2`).
- Pre-processes each `packaging/nfpm/<component>.yaml` with `envsubst`
  (filling `${VERSION}`, `${ARCH}`, `${DESTDIR}`, `${CRUN_PARSER_DEPEND}`)
  before calling `nfpm pkg --packager deb`.

### `scripts/repo_manage.sh`

**Purpose:** Builds a signed single-suite reprepro APT repository from a
directory of `.deb` files.

**Usage:** `repo_manage.sh <suite> <deb-directory> [output-directory]` where
`<suite>` is `stable`, `edge`, or `nightly` (default output:
`<repo>/repo-output`).

**Key inputs:** The arguments above, plus optional `GPG_PRIVATE_KEY` (imported
for CI signing; accepts base64-encoded or ASCII-armored keys).

**Produces:** A reprepro repository (`dists/`, `pool/`) with `InRelease` +
`Release.gpg` metadata and the public key published as `podman-ubuntu.gpg`.

**Notable behavior:**
- Validates the suite name and that the deb directory contains `.deb` files.
- Imports and ultimately-trusts the GPG key, or verifies a secret key already
  exists in the keyring.
- Copies `packaging/repo/conf/{distributions,options}`, runs
  `reprepro includedeb` per package, then `reprepro export`.
- Removes the reprepro `db/` and `conf/` internals afterward (not needed for
  serving) and prints the resulting repository structure.
