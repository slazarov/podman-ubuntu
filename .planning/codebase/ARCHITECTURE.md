<!-- refreshed: 2026-06-07 -->
# Architecture

**Analysis Date:** 2026-06-07

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────┐
│                         Entry Point                                  │
│  `setup.sh` (orchestrator)   `scripts/build_<component>.sh` (solo)  │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ sources
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Shared Infrastructure Layer                       │
│   `config.sh` (env/arch/distro/suite config)                        │
│   `functions.sh` (git_clone_update, run_logged, error_handler)      │
│   `versions-stable.env` / `versions-nightly.env` (version pins)    │
└──────────┬────────────────────────────────────┬─────────────────────┘
           │                                    │
           ▼                                    ▼
┌──────────────────────────┐        ┌───────────────────────────────┐
│  Toolchain Install       │        │   Component Build Scripts     │
│  `scripts/install_*.sh`  │        │   `scripts/build_<name>.sh`   │
│  (go, rust, protoc, apt) │        │   (13 components, DESTDIR)    │
└──────────────────────────┘        └──────────────┬────────────────┘
                                                   │ outputs into
                                                   ▼
                                    ┌──────────────────────────────┐
                                    │  Staging + Packaging         │
                                    │  `scripts/package_all.sh`    │
                                    │  `packaging/nfpm/*.yaml`     │
                                    │  `output/` (.deb files)      │
                                    └──────────────┬───────────────┘
                                                   │
                                                   ▼
                                    ┌──────────────────────────────┐
                                    │  APT Repo Assembly           │
                                    │  `scripts/repo_manage.sh`    │
                                    │  `scripts/ci_publish.sh`     │
                                    │  `packaging/repo/conf/`      │
                                    │  (reprepro, 9 suites)        │
                                    └──────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| setup.sh | Top-level orchestrator: runs preflight, sources all build scripts in order | `setup.sh` |
| config.sh | Arch detection, distro detection, version suffix, suite routing, all env vars | `config.sh` |
| functions.sh | Shared helpers: git_clone_update, run_logged, error_handler, step_start/step_done, detect_architecture, detect_distro_version_id | `functions.sh` |
| build_*.sh | One per component; clones from upstream, compiles, installs to DESTDIR | `scripts/build_*.sh` |
| install_*.sh | Toolchain and dependency installers (Go, Rust, protoc, apt packages) | `scripts/install_*.sh` |
| package_all.sh | Iterates DESTDIR staging tree, calls nfpm to emit .deb files into output/ | `scripts/package_all.sh` |
| repo_manage.sh | Feeds .deb files into a reprepro APT repository for a specific track+distro | `scripts/repo_manage.sh` |
| ci_publish.sh | CI publisher: mirrors untouched suites, builds new suite, merges all 9 into final repo | `scripts/ci_publish.sh` |
| repo_byhash.sh | Post-export helper: adds Acquire-By-Hash indexes and re-signs | `scripts/repo_byhash.sh` |
| preflight_check.sh | Pre-build validation (architecture, distro, dependencies) | `scripts/preflight_check.sh` |
| verify_depends.sh | Post-build dependency validation for built .deb packages | `scripts/verify_depends.sh` |
| verify_versions.sh | Compares installed binary versions against expected tags | `scripts/verify_versions.sh` |
| versions-stable.env | Pinned version tags for stable track | `versions-stable.env` |
| versions-nightly.env | Version tags for nightly track | `versions-nightly.env` |

## Pattern Overview

**Overall:** Shell-orchestrated build pipeline — not an application. Sequential script execution with shared environment via sourced files.

**Key Characteristics:**
- No application server, no runtime process — purely a build + packaging system
- All state shared via environment variables; `config.sh` is the single source of truth
- Every script is self-contained: sources `config.sh` + `functions.sh` itself so it can run standalone
- `${VAR:-default}` pattern throughout — track selection and version pins done entirely via env vars, never hardcoded
- Builds target three release tracks (stable, edge, nightly) and two distros (Ubuntu 24.04, 26.04) via env var injection

## Layers

**Shared Infrastructure Layer:**
- Purpose: Configuration, helpers, and constants shared across all scripts
- Location: `config.sh`, `functions.sh`
- Contains: arch/distro detection, version suffix computation, suite routing, git helpers, logging, error handler
- Depends on: nothing (lowest layer)
- Used by: every other script

**Version Pin Layer:**
- Purpose: Defines exact upstream versions for each release track
- Location: `versions-stable.env`, `versions-nightly.env`
- Contains: `export <COMPONENT>_TAG=...` assignments
- Depends on: nothing
- Used by: sourced before `setup.sh` to populate config.sh variables

**Toolchain Install Layer:**
- Purpose: Install compilers and build tools needed before component builds
- Location: `scripts/install_dependencies.sh`, `scripts/install_go.sh`, `scripts/install_rust.sh`, `scripts/install_protoc.sh`
- Contains: apt installs, Go/Rust/protoc binary downloads and installs
- Depends on: `config.sh`, `functions.sh`
- Used by: `setup.sh` (runs first, before any component build)

**Component Build Layer:**
- Purpose: Clone upstream source, compile, install binaries/libs into $DESTDIR
- Location: `scripts/build_*.sh` (13 scripts: aardvark_dns, buildah, catatonit, conmon, container-libs, crun, fuse-overlayfs, go-md2man, netavark, pasta, podman, skopeo, toolbox)
- Contains: git_clone_update calls, make/cargo/go build invocations via run_logged
- Depends on: toolchain layer, `config.sh`, `functions.sh`
- Used by: `setup.sh` (in dependency order), standalone invocation

**Packaging Layer:**
- Purpose: Convert DESTDIR staging tree into installable .deb files
- Location: `scripts/package_all.sh`, `packaging/nfpm/*.yaml`
- Contains: nfpm invocations, version extraction logic per component
- Depends on: component build layer output in $DESTDIR; nfpm binary (installed separately)
- Used by: CI after build phase; manual after build

**APT Repository Layer:**
- Purpose: Assemble a signed reprepro APT repository with 9 suites
- Location: `scripts/repo_manage.sh`, `scripts/ci_publish.sh`, `scripts/repo_byhash.sh`, `packaging/repo/conf/`
- Contains: reprepro commands, GPG signing, suite mirroring from live repo, Acquire-By-Hash generation
- Depends on: packaging layer output (.deb files in output/)
- Used by: CI publish job (`.github/workflows/build-packages.yml`)

**Validation Layer:**
- Purpose: Pre-build and post-build correctness checks
- Location: `scripts/preflight_check.sh`, `scripts/verify_depends.sh`, `scripts/verify_versions.sh`, `scripts/smoke_install_2604.sh`
- Contains: environment assertions, installed binary version comparisons, smoke install test
- Depends on: `config.sh`, `functions.sh`
- Used by: `setup.sh` (preflight), CI jobs (post-build verify)

## Data Flow

### Primary Build Path (stable track, amd64, Ubuntu 24.04)

1. Operator sources version pins: `source versions-stable.env` — sets PODMAN_TAG=v5.8.0 etc. (`versions-stable.env`)
2. Operator invokes `sudo -E ./setup.sh`
3. `setup.sh` sources `config.sh` → detects arch (ARCH=amd64), distro (DISTRO_VERSION_ID=24.04), computes VERSION_SUFFIX=~ubuntu24.04.podman1
4. `setup.sh` sources `functions.sh` → error trap installed
5. `scripts/preflight_check.sh` runs validation; failure aborts pipeline
6. `scripts/install_dependencies.sh` / `install_go.sh` / `install_rust.sh` / `install_protoc.sh` → toolchain ready
7. `scripts/build_<component>.sh` (x13) → each clones upstream at pinned tag, compiles, `make install DESTDIR=$DESTDIR`
8. `scripts/package_all.sh` → reads `packaging/nfpm/*.yaml`, calls nfpm per component → .deb files in `output/`
9. `scripts/repo_manage.sh stable 2404 output/ repo-output/` → reprepro adds .debs to suite stable-2404 and bare alias stable
10. `scripts/ci_publish.sh` (CI only) → mirrors other suites from live URL, merges into 9-suite repo, applies Acquire-By-Hash, signs with GPG

### Nightly Track Variant

1. `NIGHTLY_BUILD=true SHALLOW_CLONE=false ./setup.sh` — no version env file sourced
2. `config.sh` sees NIGHTLY_BUILD=true → sets component tags to upstream HEAD
3. Same pipeline; VERSION_SUFFIX remains distro-stamped
4. Publishes to nightly-2404 / nightly-2604 suites

**State Management:**
- No persistent runtime state; all state is environment variables scoped to the build invocation
- $DESTDIR staging directory accumulates installed files from all components
- `output/` accumulates .deb artifacts across distro builds
- `log/` accumulates per-script build logs written by run_logged

## Key Abstractions

**run_script wrapper (setup.sh):**
- Purpose: Times and error-wraps each sub-script invocation; appends to COMPONENTS_OK[]
- Pattern: `source "${toolpath}/scripts/${script}"` — not subprocess, inherits env

**run_logged (functions.sh):**
- Purpose: Runs a build command while writing output to `log/<component>.log` and streaming to stdout
- Pattern: called inside every build_*.sh instead of bare make/cargo

**git_clone_update (functions.sh):**
- Purpose: Clone repo if absent, fetch and checkout pinned tag if already present
- Used by: every build_*.sh to manage source in `build/<component>/`

**error_handler (functions.sh):**
- Purpose: Trap ERR signals; print failing script name, line number, exit code; exit cleanly
- Pattern: `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR` at top of every script after sourcing

**Version suffix (config.sh):**
- Purpose: Per-distro .deb version stamp (~ubuntu24.04.podman1) ensuring correct dpkg ordering
- Computed from detect_distro_version_id() → VERSION_SUFFIX; referenced by package_all.sh

**Suite routing (config.sh):**
- Purpose: Map (track, distro) pairs to reprepro suite names
- 9 suites: stable, edge, nightly (bare legacy aliases) + stable-2404, edge-2404, nightly-2404, stable-2604, edge-2604, nightly-2604
- resolve_publish_targets helper returns which suites to publish into for a given (track, distro) pair

## Entry Points

**Full pipeline:**
- Location: `setup.sh`
- Triggers: Manual (`sudo -E ./setup.sh`) or CI workflow
- Responsibilities: Preflight → toolchain → all 13 components → packaging → (CI) repo publish

**Single component:**
- Location: `scripts/build_<name>.sh`
- Triggers: Direct invocation (`./scripts/build_podman.sh`)
- Responsibilities: Clone upstream at pinned tag, compile, install to DESTDIR

**Packaging only:**
- Location: `scripts/package_all.sh`
- Triggers: After setup.sh build phase; requires DESTDIR populated and nfpm installed
- Responsibilities: Emit .deb files from staging tree

**APT repo assembly:**
- Location: `scripts/repo_manage.sh` (local), `scripts/ci_publish.sh` (CI with mirroring)
- Triggers: After packaging; accepts (track, distro, deb-dir, output-dir) args
- Responsibilities: Feed .debs into reprepro, sign, merge suites, Acquire-By-Hash

**CI:**
- Location: `.github/workflows/build-packages.yml`
- Triggers: Push, schedule (nightly), manual dispatch
- Responsibilities: Matrix build (amd64+arm64 x 24.04+26.04), publish to GitHub Pages

## Architectural Constraints

- **Threading:** Single-threaded sequential execution within a build; no parallel component builds. CI uses GitHub Actions matrix for parallel cross-architecture/cross-distro jobs.
- **Root required:** `setup.sh` calls apt-get directly without sudo wrapper; must be run as root.
- **Linux only:** Builds use Linux-specific paths (/etc/os-release, uname -m, apt-get). Scripts can be edited on macOS but not executed.
- **Source-not-subprocess:** Sub-scripts are sourced (`source scripts/foo.sh`), not executed as subprocesses, so they inherit the caller's environment and `set -euo pipefail` context.
- **No array exports:** Bash cannot export arrays; VALID_TRACKS, VALID_DISTROS, ALL_SUITES are declared but not exported — child scripts must source `config.sh` independently.
- **DESTDIR staging:** All component builds install to $DESTDIR (not system root); package_all.sh reads from DESTDIR. nfpm is NOT installed by setup.sh — must be installed separately.
- **Build directory isolation:** Source checkouts in `build/` are gitignored; both Lima VMs share the mount, so concurrent builds against the shared `build/` directory corrupt each other — second distro must build from a VM-local copy.

## Anti-Patterns

### Hardcoding version strings in build scripts

**What happens:** Writing `PODMAN_TAG="v5.8.0"` inside `build_podman.sh` instead of reading `${PODMAN_TAG:-}` from the environment.
**Why it's wrong:** The same scripts serve all three tracks; hardcoding bypasses the env-var selection mechanism and breaks nightly/edge builds.
**Do this instead:** Always use `${COMPONENT_TAG:-}` in build scripts; set the value in `versions-stable.env` / `config.sh` only.

### Running setup.sh without sourcing version pins

**What happens:** `sudo ./setup.sh` without first `source versions-stable.env`
**Why it's wrong:** `${PODMAN_TAG:-}` resolves to empty string → git_clone_update fetches HEAD, producing an unintended edge/nightly build on the stable track.
**Do this instead:** `source versions-stable.env && sudo -E ./setup.sh` for stable builds.

### Building both distros against the shared Lima mount simultaneously

**What happens:** Running ubuntu-24 and ubuntu-26 builds at the same time against `/opt/podman-debian`
**Why it's wrong:** `build/` is shared; make/cargo may reuse artifacts linked against the wrong distro's libraries.
**Do this instead:** Build one distro on the mount; rsync the repo to VM-local disk (excluding build/, output/, .git/) for the second distro build.

## Error Handling

**Strategy:** Fail-fast via `set -euo pipefail` at every script boundary; ERR trap reports exact script + line number.

**Patterns:**
- `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR` installed in every script after sourcing config.sh/functions.sh
- error_handler in `functions.sh` prints context and exits non-zero
- `setup.sh` tracks COMPONENTS_OK[] for progress visibility before failure
- Preflight validation in `scripts/preflight_check.sh` gates the pipeline before any build work begins

## Cross-Cutting Concerns

**Logging:** run_logged in `functions.sh` writes timestamped logs to `log/<component>.log`; also streams to stdout.
**Validation:** Preflight (preflight_check.sh) before build; post-build via verify_depends.sh and verify_versions.sh.
**Authentication:** GPG signing for APT repo; key imported from GPG_PRIVATE_KEY env var in CI via repo_manage.sh.

---

*Architecture analysis: 2026-06-07*
