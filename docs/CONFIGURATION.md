# Configuration

This project builds the Podman container stack from source and packages it into `.deb`
files served from an APT repository. Configuration is driven primarily through
**environment variables** sourced before `setup.sh`, plus a small set of checked-in
configuration files for the runtime defaults, package metadata, and the APT repository
layout.

There is no single application config file. Instead:

- **Build behaviour** is controlled by environment variables defined in [`config.sh`](../config.sh),
  with per-track overrides in [`versions-stable.env`](../versions-stable.env) and
  [`versions-nightly.env`](../versions-nightly.env).
- **Runtime defaults** shipped to end users live under [`config/`](../config/) (and the
  config files produced by `build_container-libs.sh`).
- **Package metadata** lives in [`packaging/nfpm/`](../packaging/nfpm/).
- **APT repository layout** lives in [`packaging/repo/conf/`](../packaging/repo/conf/).

## Environment variables

All build-time variables follow the `${VAR:-default}` pattern in `config.sh`, so any
variable can be overridden by exporting it before running `setup.sh`. The tables below
group them by purpose.

### Build orchestration

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ARCH` | Optional | Auto-detected via `detect_architecture` | Target architecture. Either `amd64` or `arm64`. Drives `GOARCH`, `PROTOC_ARCH`, `RUSTUP_ARCH`, and `SCCACHE_ARCH`. |
| `NPROC` | Optional | `$(nproc)` | Parallel job count for `make`/`cargo` builds. |
| `SHALLOW_CLONE` | Optional | `true` | Shallow-clone git repositories to reduce network transfer. Set to `false` for development/debugging (required for nightly `git describe` support). |
| `DESTDIR` | **Required** for packaging | none | Staging tree that build scripts install into and `package_all.sh` reads from. `package_all.sh` exits with an error if it is unset or does not point to an existing directory (example: `/tmp/podman-staging`). |
| `BUILD_ROOT` | Optional | `${toolpath}/build` | Root directory for build artifacts. Created automatically. |
| `SKIP_FUSE_CHECK` | Optional | `false` | When `true`, a failed VAL-03 preflight check (`/dev/fuse` missing) is downgraded from a hard error to a warning. Intended for container build environments (CI) where the device is not exposed but compilation never opens it — fuse-overlayfs only needs `/dev/fuse` at runtime on the target system. |

### Component versions (build track selection)

These tags select which upstream version of each component is built. When a tag is empty,
`config.sh` leaves it unset and the build either auto-detects a version or stays on the
default branch HEAD (nightly). Set them all at once by sourcing a track file:

```bash
source versions-stable.env && ./setup.sh   # pinned stable releases
source versions-nightly.env && ./setup.sh  # latest upstream HEAD
```

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PODMAN_TAG` | Optional | empty | Podman release tag (e.g. `v5.8.0`). |
| `BUILDAH_TAG` | Optional | empty | Buildah release tag (e.g. `v1.43.0`). |
| `CRUN_TAG` | Optional | empty | crun release tag (e.g. `1.26`). |
| `CONMON_TAG` | Optional | empty | conmon release tag (e.g. `v2.2.1`). |
| `NETAVARK_TAG` | Optional | empty | Netavark release tag (e.g. `v1.17.2`). |
| `AARDVARK_DNS_TAG` | Optional | empty | aardvark-dns release tag (e.g. `v1.17.0`). |
| `SKOPEO_TAG` | Optional | empty | Skopeo release tag (e.g. `v1.22.0`). |
| `GOMD2MAN_TAG` | Optional | empty | go-md2man release tag (e.g. `v2.0.7`). |
| `TOOLBOX_TAG` | Optional | empty | Toolbox release tag (e.g. `0.3`). |
| `FUSE_OVERLAYFS_TAG` | Optional | empty | fuse-overlayfs release tag (e.g. `v1.16`). |
| `CATATONIT_TAG` | Optional | empty | catatonit release tag (e.g. `v0.2.1`). |
| `CONTAINER_LIBS_TAG` | Optional | empty | containers/container-libs tag for config files and `seccomp.json`. Uses namespaced tags such as `common/v0.67.0`. |
| `SCCACHE_TAG` | Optional | empty | sccache release tag (e.g. `v0.14.0`), used by the stable track. |
| `PROTOC_VERSION` | Optional | Auto-detected via `get_latest_protoc_version` | protoc version (e.g. `34.0`). |
| `PROTOC_TAG` | Optional | Derived as `v${PROTOC_VERSION}` | protoc release tag. |
| `GOVERSION` | Optional | Auto-detected from Podman's `go.mod` via `get_required_go_version` | Go toolchain version. Sets `GOPATH` and `GOROOT` under `/opt/go/${GOVERSION}`. |
| `RUST_VERSION` | Optional | Auto-detected from Netavark's `Cargo.toml` via `get_required_rust_version` | Rust toolchain version. |

### Nightly track

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NIGHTLY_BUILD` | Optional | `false` | When `true`, `git_checkout()` stays on the default branch HEAD instead of a tag, and `package_all.sh` extracts dev versions from source (e.g. `5.9.0~git20260306.abc1234`). Set by `versions-nightly.env`. |

When using the nightly track, `SHALLOW_CLONE` must be `false` so the commit history needed
for `git describe` is available. `versions-nightly.env` sets both variables.

### Build optimization (Rust / Cargo)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CARGO_BUILD_JOBS` | Optional | `$NPROC` | Parallel job count for cargo builds. |
| `SCCACHE_ENABLED` | Optional | `false` | Enable sccache for Rust build caching (50–90% rebuild speedup). |
| `SCCACHE_VERSION` | Optional | `0.14.0` | sccache version (only used when `SCCACHE_ENABLED=true`). |
| `SCCACHE_DIR` | Optional | `/var/cache/sccache` | sccache cache directory (only used when `SCCACHE_ENABLED=true`). |
| `MOLD_ENABLED` | Optional | `false` | Enable the mold linker for Rust builds (5–10x faster linking). Requires clang as the linker driver (installed automatically with mold). |

### Build optimization (C / C++)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CCACHE_ENABLED` | Optional | `false` | Enable ccache for C build caching (up to 30x faster warm-cache rebuilds). |
| `CCACHE_DIR` | Optional | `/var/cache/ccache` | ccache cache directory (only used when `CCACHE_ENABLED=true`). |
| `CCACHE_MAXSIZE` | Optional | `2G` | ccache maximum cache size. |
| `CCACHE_COMPILERCHECK` | Optional | `content` | Hash compiler binary content for correct cache invalidation on GCC upgrades. |

### Build optimization (Go)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GO_GCFLAGS` | Optional | `-c=16` | Go compiler flags for parallel compilation (~25% faster). |
| `GO_LDFLAGS` | Optional | `-s -w` | Go linker flags; strips debug symbols for smaller binaries. |
| `GOGC_BUILD` | Optional | `off` | Disable Go GC during compilation (~30% faster, uses ~2.5x RAM). Set to empty to re-enable. |
| `GOCACHE` | Optional | `/var/cache/go-build` | Go build cache, shared across component builds (20x faster rebuilds). |
| `GOMODCACHE` | Optional | `/var/cache/go-mod` | Go module cache. |

### Packaging and publishing

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VERSION` | Set by tooling | computed | Package version substituted into the nfpm YAML files (`${VERSION}`). Determined per component by `package_all.sh`. |
| `GPG_PRIVATE_KEY` | Optional (CI) | none | If set, `repo_manage.sh` / `ci_publish.sh` import this GPG key before signing. Accepts either a base64-encoded key (recommended for CI) or a raw ASCII-armored key. Store as `gpg --export-secret-keys --armor KEY_ID \| base64 -w0`. If unset, an existing secret key must already be present in the keyring. |
| `OUTPUT_DIR` | Optional | `${toolpath}/output` (package_all) / `${toolpath}/repo-output` (repo_manage) | Where built `.deb` files or the assembled APT repository are written. `repo_manage.sh` accepts it as the third positional argument; `package_all.sh` uses a fixed default. |

`GPG_KEY_ID` is derived at runtime inside `repo_manage.sh` from the imported keyring
fingerprint; it is not a user-supplied variable.

## Configuration files

### Runtime defaults: `config/containers.conf`

Installed to `/etc/containers/containers.conf` by the build, this sets the Podman engine
defaults shipped to users. See `man containers.conf(5)`.

```ini
[containers]
seccomp_profile = "/usr/share/containers/seccomp.json"

[engine]
runtime = "crun"
helper_binaries_dir = [
    "/usr/bin",
    "/usr/libexec/podman",
    "/usr/lib/podman"
]

[network]
network_backend = "netavark"
```

| Key | Section | Description |
|-----|---------|-------------|
| `seccomp_profile` | `[containers]` | Default seccomp profile path. Requires `/usr/share/containers/seccomp.json` from the `podman-container-configs` package. Comment out if unavailable. |
| `runtime` | `[engine]` | Default OCI runtime. Set to `crun` (faster and lower-memory than runc). |
| `helper_binaries_dir` | `[engine]` | Search paths for helper binaries (netavark, aardvark-dns, etc.). |
| `network_backend` | `[network]` | Network backend. Set to `netavark` (CNI was removed in Podman 5.0). |

Additional runtime config files (`policy.json`, `registries.conf`, `storage.conf`,
`registries.d/default.yaml`, and `seccomp.json`) are produced from upstream
`containers/container-libs` by `build_container-libs.sh` and shipped by the
`podman-container-configs` package — see [Per-environment overrides](#per-environment-overrides)
for how they behave on upgrade.

### Package metadata: `packaging/nfpm/`

Each component has an nfpm YAML manifest describing the produced `.deb`. These use
`${ARCH}` and `${VERSION}` placeholders substituted at build time. Key fields, using
[`podman.yaml`](../packaging/nfpm/podman.yaml) as the reference:

| Field | Example value | Description |
|-------|---------------|-------------|
| `name` | `podman-podman` | Debian package name. |
| `arch` | `${ARCH}` | Target architecture, substituted at build time. |
| `version` | `${VERSION}` | Package version, substituted at build time. |
| `version_schema` | `none` | Disables nfpm's semver normalization (allows nightly `~git…` versions). |
| `maintainer` | `Podman Ubuntu <noreply@github.com>` | Debian maintainer field. |
| `depends` | internal `podman-*` packages plus `libgpgme11`, `libseccomp2` | Runtime dependencies. |
| `conflicts` / `replaces` / `provides` | `podman` | Lets this package supersede the distro `podman`. |
| `contents` | binaries, man pages, systemd units, completions | Files installed and their modes. |

The [`suite.yaml`](../packaging/nfpm/suite.yaml) manifest is a meta-package
(`podman-suite`) with only `depends` and no `contents`, pulling in the full stack.

The [`container-configs.yaml`](../packaging/nfpm/container-configs.yaml) manifest marks the
`/etc/containers/*` files as `type: config` (dpkg conffiles) so user edits survive
upgrades, while `seccomp.json` is shipped as a plain data file that is overwritten on
upgrade.

### APT repository layout: `packaging/repo/conf/`

The [`distributions`](../packaging/repo/conf/distributions) file defines nine reprepro
suites. Each shares `Origin: podman-ubuntu`, `Label: Podman Ubuntu`,
`Architectures: amd64 arm64`, `Components: main`, and `SignWith: yes`:

| Suite / Codename | Purpose |
|------------------|---------|
| `stable` | DEPRECATED rolling alias for `stable-2404` (Ubuntu 24.04). |
| `edge` | DEPRECATED rolling alias for `edge-2404` (Ubuntu 24.04). |
| `nightly` | DEPRECATED rolling alias for `nightly-2404` (Ubuntu 24.04). |
| `stable-2404` | Ubuntu 24.04 — pinned stable releases. |
| `edge-2404` | Ubuntu 24.04 — latest tagged upstream. |
| `nightly-2404` | Ubuntu 24.04 — nightly git snapshots. |
| `stable-2604` | Ubuntu 26.04 — pinned stable releases. |
| `edge-2604` | Ubuntu 26.04 — latest tagged upstream. |
| `nightly-2604` | Ubuntu 26.04 — nightly git snapshots. |

The three bare aliases (`stable`, `edge`, `nightly`) are deprecated in favour of the
distro-versioned suites; each pins to its Ubuntu 24.04 equivalent for backward
compatibility.

The [`options`](../packaging/repo/conf/options) file sets reprepro's `verbose` and
`basedir .`. `repo_manage.sh` and `ci_publish.sh` take a `track` (`stable`, `edge`, or
`nightly`) and a `distro` (`2404` or `2604`) argument, validated against `VALID_TRACKS`
and `VALID_DISTROS` in `config.sh`; `resolve_publish_targets` composes them into the
versioned suite (e.g. `stable-2404`), plus the bare legacy alias when the distro is `2404`.

`packaging/repo/pubkey.gpg` is the committed public signing key used to verify the
repository.

## Required vs optional settings

The only **required** setting for the build-and-package flow is `DESTDIR`, validated at the
top of `package_all.sh`:

```text
ERROR: DESTDIR environment variable is not set.
  DESTDIR must point to a populated staging tree.
  Example: export DESTDIR=/tmp/podman-staging
```

For the publishing flow, a GPG secret key is required: either via `GPG_PRIVATE_KEY` (CI) or
already present in the local keyring. If neither is available, `repo_manage.sh` aborts:

```text
ERROR: No GPG secret key found in keyring.
  Either set GPG_PRIVATE_KEY environment variable (for CI)
  or import a key manually: gpg --import <private-key-file>
```

Every other variable is optional and falls back to a default (or an auto-detected value)
defined in `config.sh`.

## Defaults

Defaults are defined in `config.sh` using the `${VAR:-default}` pattern. Notable ones:

| Variable | Default | Where set |
|----------|---------|-----------|
| `SHALLOW_CLONE` | `true` | `config.sh` |
| `SCCACHE_ENABLED` | `false` | `config.sh` |
| `CCACHE_ENABLED` | `false` | `config.sh` |
| `MOLD_ENABLED` | `false` | `config.sh` |
| `CCACHE_MAXSIZE` | `2G` | `config.sh` |
| `GOCACHE` | `/var/cache/go-build` | `config.sh` |
| `GOMODCACHE` | `/var/cache/go-mod` | `config.sh` |
| `GO_GCFLAGS` | `-c=16` | `config.sh` |
| `GOGC_BUILD` | `off` | `config.sh` |
| `BUILD_ROOT` | `${toolpath}/build` | `config.sh` |
| `GOVERSION` | from Podman `go.mod` | `config.sh` (`get_required_go_version`) |
| `RUST_VERSION` | from Netavark `Cargo.toml` | `config.sh` (`get_required_rust_version`) |
| `PROTOC_VERSION` | latest detected | `config.sh` (`get_latest_protoc_version`) |
| `OUTPUT_DIR` | `${toolpath}/output` | `scripts/package_all.sh` |
| `OUTPUT_DIR` | `${toolpath}/repo-output` | `scripts/repo_manage.sh` (3rd argument) |

Component version tags default to empty in `config.sh`; the canonical pinned values live in
`versions-stable.env`.

## Per-environment overrides

This project uses **build tracks** rather than `.env.development` / `.env.production` files.
Select a track by sourcing the matching env file before `setup.sh`:

- **Stable** — `source versions-stable.env && ./setup.sh`. Sets every component tag to a
  pinned release (see [`versions-stable.env`](../versions-stable.env)).
- **Nightly** — `source versions-nightly.env && ./setup.sh`. Sets `NIGHTLY_BUILD=true` and
  `SHALLOW_CLONE=false`, leaving all component tags empty so builds track upstream HEAD.
- **Edge** — published from the latest tagged upstream; selected per-suite when running
  `repo_manage.sh` / `ci_publish.sh` with the `edge` argument.

Nightly versions use a tilde (`~`) so dpkg sorts them below tagged releases, letting users
auto-upgrade once a real release lands.

For end users consuming the packages, runtime behaviour is overridden through the standard
Podman configuration mechanism: the `/etc/containers/*` files are dpkg conffiles, so local
edits are preserved across package upgrades, while `seccomp.json` is refreshed from upstream
on every upgrade.
