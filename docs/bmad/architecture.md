# Architecture

A staged, environment-driven Bash pipeline. Every value is overridable purely
by environment variables (`${VAR:-default}` in `config.sh`); the same scripts
serve all three release tracks and both distros with no hardcoded versions.

## 1. Pipeline Stages (end to end)

| Stage | Owner | What happens |
|-------|-------|--------------|
| 0. Track selection | `versions-stable.env` / `versions-nightly.env` (sourced by caller) or CI env | Exports `*_TAG` pins (stable), or `NIGHTLY_BUILD=true SHALLOW_CLONE=false` (nightly), or nothing (edge) |
| 1. Bootstrap | `setup.sh` | `set -euo pipefail`, toolpath detect, `source config.sh` + `functions.sh`, install ERR trap |
| 2. Preflight | `scripts/preflight_check.sh` | cgroups v2, subuid/subgid, `/dev/fuse`, kernel ≥5.11, noexec mounts. Errors abort; warnings continue |
| 3. Toolchain install | `install_dependencies.sh`, `install_rust.sh`, `install_protoc.sh`, `install_go.sh` | apt build-deps; rustup at MSRV; protoc; Go at auto-detected version |
| 4. Component builds | `scripts/build_*.sh` (13 scripts) | Each clones into `build/`, checks out tag, builds, installs into `$DESTDIR` |
| 5. Config + manpage install | `install_container-configs.sh`, `install_container-manpages.sh` | Config files + section-5 man pages staged into `$DESTDIR` |
| 6. Packaging | `scripts/package_all.sh` (separate entry; needs `DESTDIR` + `nfpm`) | Version extraction, runtime-dep detection, envsubst render, `nfpm pkg` → `output/*.deb` (12 components + `podman-suite`) |
| 7. Repo assembly | `scripts/ci_publish.sh` → `repo_manage.sh` → `repo_byhash.sh` | reprepro `includedeb`/`export`, mirror untouched suites, Acquire-By-Hash + re-sign, generate `index.html` |
| 8. Smoke gate | `scripts/smoke_repo_install.sh` | Install `podman-suite` from the assembled `file://` repo in a container, run `podman info` |
| 9. Publish | `.github/workflows/build-packages.yml` (`publish` job) | `upload-pages-artifact` + `deploy-pages` (atomic, **main-branch-only**) |

`setup.sh` itself runs stages 1–5 (build + install). Packaging (6) and
publish (7–9) are separate entry points orchestrated by CI.

## 2. Configuration System (`config.sh`)

Single source of truth, env-driven via `${VAR:-default}`.

- **Recursive-source guards:** `config.sh` and `functions.sh` guard with
  `_CONFIG_SH_SOURCED` / `_FUNCTIONS_SH_SOURCED` (not exported — children
  re-source). `functions.sh` tail-sources `config.sh` because `config.sh`
  calls helpers like `get_required_go_version`.
- **Arch detection:** `detect_architecture` maps `x86_64→amd64`,
  `aarch64/arm64→arm64`; derives `GOARCH`, `PROTOC_ARCH`, `RUSTUP_ARCH`,
  `SCCACHE_ARCH`.
- **Distro identity:** `detect_distro_version_id` honors `${DISTRO}` else
  `/etc/os-release` `VERSION_ID`, validated `^[0-9]+\.[0-9]+$` (Ubuntu-only).
  Composes `VERSION_SUFFIX="~ubuntu${DISTRO_VERSION_ID}.podman1"`.
- **Auto-detected toolchain versions:** `GOVERSION` from podman `go.mod`;
  `RUST_VERSION` from netavark `Cargo.toml`; `PROTOC_VERSION` from GitHub
  latest release if unset.
- **Suite routing:** `VALID_TRACKS=(stable edge nightly)`,
  `VALID_DISTROS=(2404 2604)`, `ALL_SUITES` (9). `is_valid_suite()` and
  `resolve_publish_targets(track, distro)` — the latter also emits the bare
  legacy alias when distro is `2404`.

**Three tracks, selected purely by env:** stable (all `*_TAG` set → checkout
pinned tag), edge (no tags → `get_latest_tag`), nightly (`NIGHTLY_BUILD=true`
→ default-branch HEAD). `versions-*.env` are plain sourceable exports with no
logic; there is deliberately no `versions-edge.env` (edge = absence of pins).

## 3. Build-Script Shared Pattern

Every `scripts/build_*.sh` follows the same skeleton:

1. `#!/bin/bash` + `set -euo pipefail`
2. Toolpath bootstrap (resolve `toolpath` via `BASH_SOURCE` if unset)
3. `source "${toolpath}/config.sh"` then `source "${toolpath}/functions.sh"`
4. `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR` (installed **after** sourcing)
5. `cd "${BUILD_ROOT}"`, `log_build_output "<component>"`
6. `step_start`/`step_done` phases: `git_clone_update` → `git_checkout "${*_TAG}"` → optional cache config → `run_logged make ...` → install into `$DESTDIR`

Key helpers in `functions.sh`: `git_clone_update`, `git_checkout` (nightly HEAD
/ explicit tag / latest-tag), `run_logged` (logs, dumps last 40 lines on
failure), `step_start`/`step_done` (timed), `error_handler`,
`detect_runtime_depends`. Because each script bootstraps itself, any component
builds standalone (`./scripts/build_conmon.sh`) with no orchestrator; `DESTDIR`
unset → installs to the live system, set → stages into the tree. `setup.sh`
drives them via `run_script()`, which `source`s each sub-script so exported env
(e.g. `GIT_CHECKED_OUT_TAG`) persists.

## 4. The 12 Packaged Components (+ tooling)

`package_all.sh`'s `COMPONENTS` array = 12 packaged; plus the `podman-suite`
meta-package = 13 `.deb`s. There are 13 `build_*.sh` scripts but 12 packaged
components (`build_go-md2man.sh` and `build_container-libs.sh` produce tooling /
config artifacts).

| Component | What | Toolchain |
|-----------|------|-----------|
| podman | Container engine | Go |
| crun | Fast C OCI runtime | C (autotools) |
| conmon | OCI runtime monitor | C + Go |
| buildah | OCI image builder | Go |
| skopeo | Image copy/inspect | Go |
| netavark | Network stack | Rust |
| aardvark-dns | Container DNS | Rust |
| fuse-overlayfs | Rootless FUSE overlay FS | Rust (v2+) or C (v1.x), auto-detected by `Cargo.toml` presence |
| catatonit | Minimal container init | C (autotools) |
| pasta (passt) | User-mode networking | C — always HEAD, versioned by date |
| toolbox | Interactive toolbox CLI | Go + Meson |
| container-configs | containers-common config files + `seccomp.json` (from `container-libs` repo, `CONTAINER_LIBS_TAG=common/vX.Y.Z`) | Go codegen |
| *go-md2man* | markdown→man converter (tooling, not packaged) | Go |

## 5. Packaging (`package_all.sh` + `packaging/nfpm/*.yaml`)

- **Staging model:** build scripts install into `$DESTDIR`; `package_all.sh`
  requires `DESTDIR` set + `nfpm` on PATH.
- **Version extraction:** `extract_version` (stable/edge, strips `v`;
  container-configs strips `common/v`; pasta uses `date`) or
  `extract_version_nightly` (reads dev version from source, appends
  `~git{YYYYMMDD}.{sha}`). All get `${VERSION_SUFFIX}` appended.
- **Runtime dependency injection:** `detect_runtime_depends` reads each
  binary's **direct `DT_NEEDED` sonames** (`objdump -p`, not full `ldd`
  transitive closure — deliberate fix), resolves each to its owning package via
  `dpkg-query -S`, excludes `libc6`/`libgcc-s1`, hard-fails on any unmapped
  soname. Static binaries (fuse-overlayfs, catatonit) yield empty sets.
  Inject-only components (crun, conmon, pasta) carry their own `depends:`
  header, emitted only when non-empty.
- **Naming & metadata:** packages are `podman-<component>`; filenames
  `podman-<component>_<version>~ubuntu{24.04|26.04}.podman1_<arch>.deb`. Each
  declares **Conflicts/Replaces/Provides** against the official Ubuntu package
  name (e.g. `podman-pasta` → `passt`, `podman-container-configs` →
  `golang-github-containers-common`) so source builds swap cleanly. `podman-suite`
  is a contents-free meta-package depending on all 12.

## 6. APT Repository Publish

- **reprepro** materializes 9 distributions in
  `packaging/repo/conf/distributions`: 3 bare legacy aliases + 6 versioned
  suites (`{stable,edge,nightly}-{2404,2604}`), all `SignWith: yes`,
  `Architectures: amd64 arm64`, `Components: main`.
- **`repo_manage.sh`** (`<track> <distro> <deb-dir> [out]`): imports GPG,
  `reprepro includedeb` each `.deb`, then `reprepro export` **per-suite** (a
  bare export would emit empty indexes and risk clobbering).
- **`repo_byhash.sh`**: reprepro lacks native Acquire-By-Hash (Debian #820660);
  materializes `by-hash/<ALGO>/<hash>` copies + `Acquire-By-Hash: yes`, then
  **re-signs** (editing Release invalidates reprepro's signature). Prevents apt
  hash-sum mismatch during the Pages CDN's stale-index window.
- **`ci_publish.sh`** (the multi-suite assembler): computes untouched suites,
  preserves earlier-pass Release files in place (no-clobber), mirrors untouched
  suites **verbatim** (byte-identical signed tree), builds target suites, applies
  by-hash + re-sign, and generates `index.html`. Clobber-prevention has three
  layers: per-suite export, earlier-pass in-place preservation, verbatim signed
  mirroring.
- **Republish gating** (`check_republish_needed.sh`): for manual stable/edge
  dispatch, compares would-build versions against what's published (both distros
  × both arches), emits `skip=true` only on full match. `pasta` excluded (floats
  daily). Strictly conservative — any uncertainty → `skip=false`.

## 7. CI Pipeline (`.github/workflows/build-packages.yml`)

Triggers: daily cron (nightly) + `workflow_dispatch` (`build_track` choice).

- **check-changes** (schedule): compares upstream HEAD SHAs against cached `nightly-sha.json`.
- **check-republish** (manual stable/edge): runs `check_republish_needed.sh`.
- **build:** single matrix, `fail-fast: false`, 4 cells — `2404 amd64`,
  `2404 arm64` (native `ubuntu-24.04-arm`), `2604 amd64`/`2604 arm64` (runner +
  `container: ubuntu:26.04`). Native builds (no emulation); container cells set
  `SKIP_FUSE_CHECK=true`; distro-isolated Go caches and `debs-<distro>-<arch>`
  artifacts.
- **publish:** gated `github.ref == 'refs/heads/main'` (main-only), runs even on
  partial failure (skips empty deb dirs), assembles both distros into one
  accumulating `repo-output`, runs the smoke gate, then atomic `deploy-pages`.

## 8. Testing

13 pure-bash tests in `tests/` run anywhere (they sed-extract + `eval` helper
bodies to avoid `config.sh`'s os-release hard-fail). Ubuntu-only integration
tests (`test_repo_assemble_byhash.sh`, `test_ci_publish_multipass.sh`) exercise
real reprepro/gpg. On-Ubuntu proof gates: `verify_versions.sh` (dpkg version
ordering), `verify_depends.sh` (detector against a 24.04 baseline), `smoke_*.sh`.
Syntax check anywhere via `bash -n`.

## Notable Technical Debt

- Stale `go 1.22.6` sed patches in several Go build scripts (silent no-ops on newer `go.mod`).
- Hardcoded `/tmp/nfpm-*.yaml` render paths in `package_all.sh` (no `mktemp`).
- `get_latest_tag` called twice on the no-tag path in `git_checkout`.
- pasta cannot be pinned (always HEAD) → excluded from republish gating.
- `container-configs` triple naming mismatch (repo `container-libs`, package `podman-container-configs`, var `CONTAINER_LIBS_TAG`).
- `podman-debian` residue in `lima/*.yaml` mount paths and the generated page `<title>`.
- `COMPONENT_BINARIES`/`INJECT_ONLY_DEPENDS` duplicated between `package_all.sh` and `verify_depends.sh` (kept in sync by comment discipline).
- `ci_publish.sh` (~740 lines) is a deeply nested state machine — a maintenance hotspot, guarded by `test_ci_publish_multipass.sh`.
