# Development Guide

## Critical Constraint: Builds Run on Linux Only

The full pipeline writes to system paths and requires root, so it only runs on
Debian/Ubuntu. The dev machine is often macOS — you can edit scripts there but
cannot execute `setup.sh` / `build_*.sh` locally. On macOS:

- **Syntax check:** `bash -n scripts/build_podman.sh`
- **Unit tests:** `bash tests/test_suite_routing.sh` (pure-bash tests run anywhere)
- **Real execution:** use the Lima VMs (below)

## Prerequisites (on the build host)

Toolchains are installed by the pipeline itself (`install_go.sh`,
`install_rust.sh`, `install_protoc.sh`, `install_dependencies.sh`). You need a
Debian/Ubuntu host with root, `git`, `curl`, and `bash`. `nfpm` is **not**
installed by `setup.sh` — install it separately when packaging.

## Build Commands

```bash
# Stable — pinned versions
source versions-stable.env && sudo -E ./setup.sh

# Edge — auto-detect latest upstream tags (no env)
sudo ./setup.sh

# Nightly — upstream HEAD
sudo NIGHTLY_BUILD=true SHALLOW_CLONE=false ./setup.sh

# Single component (self-bootstraps config.sh + functions.sh)
./scripts/build_conmon.sh

# Package the staging tree into .debs (needs DESTDIR set + nfpm on PATH)
export DESTDIR=/root/podman-staging
./scripts/package_all.sh

# Uninstall everything installed from source
sudo ./uninstall.sh
```

`setup.sh` requires root — `apt-get` is invoked directly (no sudo wrapper).
Convention: `DESTDIR=/root/podman-staging`.

## Testing

```bash
# Pure-bash unit tests (anywhere, incl. macOS)
bash tests/test_suite_routing.sh
bash tests/test_extract_version_nightly.sh
bash tests/test_ci_matrix.sh

# Syntax check any script
bash -n scripts/ci_publish.sh
```

The 13 `tests/*.sh` are framework-free — plain bash assertions with exit codes.
They sed-extract and `eval` helper bodies so they don't trip `config.sh`'s
os-release hard-fail off-Ubuntu. Ubuntu-only integration tests
(`test_repo_assemble_byhash.sh`, `test_ci_publish_multipass.sh`) drive real
reprepro/gpg. On-Ubuntu proof gates: `verify_versions.sh`, `verify_depends.sh`,
`smoke_repo_install.sh`, `smoke_install_2604.sh`.

## Lima VM Testing (from macOS)

On-Ubuntu verification runs in Lima VMs `ubuntu-24` (24.04) and `ubuntu-26`
(26.04). Configs live in `lima/*.yaml`; the repo is mounted **writable** at
`/opt/podman-debian` in both.

```bash
# Command pattern (ignore the harmless "cd: /Users/...: No such file" noise)
limactl shell ubuntu-24 -- bash -c 'cd /opt/podman-debian && <command>'

# Full pipeline: run as root with DESTDIR set; detach long builds and log
limactl shell ubuntu-24 -- bash -c \
  'sudo -b env HOME=/root nohup bash -c \
   "cd /opt/podman-debian && source versions-stable.env && \
    export DESTDIR=/root/podman-staging && ./setup.sh" > /tmp/setup.log 2>&1'
```

Rules learned the hard way:

- **Run `sudo apt-get update` before the first build** — fresh VMs carry stale
  apt indexes; `install_dependencies.sh` will 404 on superseded versions.
- **`setup.sh` requires root** — use `sudo env HOME=/root ...`.
- **`nfpm` is NOT installed by `setup.sh`.** After the Go toolchain exists:
  `sudo env HOME=/root PATH="/opt/go/<ver>/bin:$PATH" go install
  github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.45.0` → lands in `/root/go/bin`; add
  that to PATH for `package_all.sh` / `verify_depends.sh`.
- **Never build both distros against the shared mount.** `BUILD_ROOT` is
  `<repo>/build`, shared by both VMs through the mount; make/cargo mtime reuse
  would link binaries against the *other* distro's libs. Build one distro on the
  mount; for the second VM, rsync the repo to VM-local disk first (exclude
  `build/`, `output/`, `.git/`), e.g. to `/root/podman-ubuntu-build`, and build there.
- **`smoke_install_2604.sh` needs a container runtime** — `ubuntu-26` has distro
  podman installed for this; run as root with `SMOKE_RUNTIME=podman`.
- 24.04/26.04-built `.deb`s coexist in `output/` (distinct
  `~ubuntu{24.04,26.04}.podman1` suffixes).

## Debugging a Build

`run_logged` writes per-component output to `log/` and, on failure, dumps the
last 40 lines to stderr. For a failing script, re-run with `bash -x
scripts/build_<c>.sh` (the `error_handler` banner suggests this). Each build
script is standalone, so you can iterate on one component without the full
`setup.sh`.
