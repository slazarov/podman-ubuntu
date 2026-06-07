# Codebase Structure

**Analysis Date:** 2026-06-07

## Directory Layout

```
podman-debian/
├── setup.sh                    # Top-level orchestrator — full pipeline entry point
├── uninstall.sh                # Remove all source-built components
├── config.sh                   # Central config: arch, distro, version suffix, suite routing
├── functions.sh                # Shared helpers: git_clone_update, run_logged, error_handler
├── versions-stable.env         # Pinned component version tags for stable track
├── versions-nightly.env        # Version pins for nightly track (typically empty → HEAD)
├── scripts/
│   ├── build_aardvark_dns.sh   # Build: Aardvark DNS (Rust)
│   ├── build_buildah.sh        # Build: Buildah (Go)
│   ├── build_catatonit.sh      # Build: Catatonit (C)
│   ├── build_conmon.sh         # Build: Conmon (C)
│   ├── build_container-libs.sh # Build: containers-common config files
│   ├── build_crun.sh           # Build: crun OCI runtime (C)
│   ├── build_fuse-overlayfs.sh # Build: fuse-overlayfs (C)
│   ├── build_go-md2man.sh      # Build: go-md2man man page converter (Go)
│   ├── build_netavark.sh       # Build: Netavark network stack (Rust)
│   ├── build_pasta.sh          # Build: pasta networking (C)
│   ├── build_podman.sh         # Build: Podman (Go)
│   ├── build_skopeo.sh         # Build: Skopeo (Go)
│   ├── build_toolbox.sh        # Build: Toolbox (Go)
│   ├── install_dependencies.sh # apt-get: system build dependencies
│   ├── install_go.sh           # Install Go toolchain
│   ├── install_rust.sh         # Install Rust toolchain (rustup)
│   ├── install_protoc.sh       # Install Protocol Buffers compiler
│   ├── install_container-configs.sh  # Install OCI runtime config files
│   ├── install_container-manpages.sh # Install container man pages
│   ├── package_all.sh          # DESTDIR → .deb files via nfpm
│   ├── preflight_check.sh      # Pre-build environment validation
│   ├── repo_manage.sh          # reprepro APT repo assembly for one (track, distro)
│   ├── ci_publish.sh           # CI: multi-suite repo publish with mirroring
│   ├── repo_byhash.sh          # Add Acquire-By-Hash indexes and re-sign
│   ├── smoke_install_2604.sh   # Smoke test: install .debs on Ubuntu 26.04
│   ├── verify_depends.sh       # Post-build dependency validation
│   └── verify_versions.sh      # Post-build binary version verification
├── packaging/
│   ├── nfpm/                   # nFPM package definitions (one YAML per component)
│   │   ├── podman.yaml
│   │   ├── buildah.yaml
│   │   ├── crun.yaml
│   │   ├── conmon.yaml
│   │   ├── netavark.yaml
│   │   ├── aardvark-dns.yaml
│   │   ├── skopeo.yaml
│   │   ├── toolbox.yaml
│   │   ├── fuse-overlayfs.yaml
│   │   ├── catatonit.yaml
│   │   ├── pasta.yaml
│   │   ├── container-configs.yaml
│   │   └── suite.yaml          # reprepro distributions config template
│   └── repo/
│       └── conf/               # reprepro repository configuration files
├── tests/
│   ├── test_alias_routing.sh
│   ├── test_byhash_parse.sh
│   ├── test_ci_matrix.sh
│   ├── test_detect_distro_depends.sh
│   ├── test_distributions_suites.sh
│   ├── test_extract_version_nightly.sh
│   ├── test_mirror_verbatim.sh
│   ├── test_repo_assemble_byhash.sh
│   └── test_suite_routing.sh
├── config/
│   └── containers.conf         # OCI runtime default configuration
├── lima/                       # Lima VM configs for local Ubuntu testing
│   └── *.yaml                  # ubuntu-24 and ubuntu-26 VM definitions
├── docs/                       # Architecture, configuration, testing documentation
├── .github/
│   └── workflows/
│       └── build-packages.yml  # CI: amd64+arm64 × 24.04+26.04 matrix build + publish
├── .planning/                  # GSD planning state (committed)
│   ├── codebase/               # Codebase map documents (this file's home)
│   ├── milestones/             # Milestone phase plans
│   ├── phases/                 # Active phase plans
│   ├── debug/                  # Debug session notes
│   └── research/               # Research documents
├── build/                      # Source checkouts (gitignored, created at build time)
├── output/                     # Built .deb files (gitignored)
└── log/                        # Build logs from run_logged (gitignored)
```

## Directory Purposes

**`scripts/`:**
- Purpose: All build, install, packaging, and repo management scripts
- Contains: build_*.sh (component builds), install_*.sh (toolchain), package_all.sh, repo scripts, validation scripts
- Key files: `scripts/package_all.sh`, `scripts/repo_manage.sh`, `scripts/ci_publish.sh`, `scripts/preflight_check.sh`

**`packaging/nfpm/`:**
- Purpose: nFPM package definitions — one YAML per component
- Contains: Declares package name, version template, files, Conflicts/Replaces/Provides against official Ubuntu packages, dependencies
- Key files: `packaging/nfpm/podman.yaml`, `packaging/nfpm/suite.yaml`

**`packaging/repo/conf/`:**
- Purpose: reprepro repository configuration
- Contains: distributions file defining all 9 suites (stable, edge, nightly + versioned variants)

**`tests/`:**
- Purpose: Bash unit tests for pipeline logic; run directly with `bash tests/<test>.sh`
- Contains: Tests for suite routing, version extraction, alias routing, byhash, CI matrix, distro detection
- Key pattern: No test framework — pure Bash assertions with exit codes

**`lima/`:**
- Purpose: Lima VM configurations for on-Ubuntu UAT and full builds on macOS
- Contains: ubuntu-24.yaml (Ubuntu 24.04), ubuntu-26.yaml (Ubuntu 26.04)
- Key detail: Repo mounted writable at `/opt/podman-debian` in both VMs

**`config/`:**
- Purpose: Runtime configuration files installed into the OS by install_container-configs.sh
- Contains: `containers.conf` — default OCI runtime configuration

**`build/`:**
- Purpose: Source checkouts cloned by git_clone_update during builds
- Generated: Yes (created at build time by build_*.sh scripts)
- Committed: No (gitignored)
- Note: Shared across Lima VMs via mount — do not build both distros simultaneously against this directory

**`output/`:**
- Purpose: Built .deb artifact output directory
- Generated: Yes (written by package_all.sh)
- Committed: No (gitignored)
- Note: Both distro builds accumulate here with distinct version suffixes (~ubuntu24.04.podman1 vs ~ubuntu26.04.podman1)

**`log/`:**
- Purpose: Per-component build logs written by run_logged
- Generated: Yes
- Committed: No (gitignored)

**`.planning/`:**
- Purpose: GSD planning state — roadmap, phase plans, research, debug notes
- Generated: No (manually maintained, committed, synced across machines)

## Key File Locations

**Entry Points:**
- `setup.sh`: Full pipeline orchestrator
- `scripts/build_<name>.sh`: Single-component standalone builds

**Configuration:**
- `config.sh`: Arch detection, distro detection, version suffix, suite routing, all env vars
- `functions.sh`: All shared helper functions
- `versions-stable.env`: Stable track version pins
- `versions-nightly.env`: Nightly track version pins

**Packaging:**
- `scripts/package_all.sh`: DESTDIR to .deb conversion
- `packaging/nfpm/*.yaml`: Per-component nFPM definitions

**APT Repository:**
- `scripts/repo_manage.sh`: Local single-suite repo assembly
- `scripts/ci_publish.sh`: CI multi-suite repo publish with mirroring
- `packaging/repo/conf/`: reprepro configuration

**Testing:**
- `tests/test_*.sh`: All Bash unit tests (run directly)
- `scripts/verify_depends.sh`: Post-build .deb dependency check
- `scripts/verify_versions.sh`: Post-build binary version check
- `scripts/smoke_install_2604.sh`: Smoke install test for Ubuntu 26.04

**CI:**
- `.github/workflows/build-packages.yml`: Full CI pipeline definition

## Naming Conventions

**Files:**
- Build scripts: `build_<component>.sh` (underscore separator, lowercase)
- Install scripts: `install_<thing>.sh`
- Test scripts: `test_<what>.sh` (all in `tests/`)
- nFPM definitions: `<component>.yaml` (hyphen separator, matching Debian package name)
- Version env files: `versions-<track>.env`

**Directories:**
- lowercase, hyphen-separated where multi-word (`fuse-overlayfs`, `container-libs`)
- gitignored runtime dirs: `build/`, `output/`, `log/`

**Variables:**
- Environment/config vars: UPPERCASE (`ARCH`, `DESTDIR`, `VERSION_SUFFIX`, `PODMAN_TAG`)
- Local function vars: lowercase (`arch`, `version_id`)
- Function parameter locals: prefixed `l` (`lcomponent`, `lfolder`, `lsuite`)
- Guard vars for sourced files: `_FILENAME_SH_SOURCED` pattern

**Functions:**
- snake_case (`git_clone_update`, `run_logged`, `error_handler`, `detect_architecture`)

## Where to Add New Code

**New build component:**
- Implementation: `scripts/build_<component>.sh` (copy header from existing build script: toolpath bootstrap → source config.sh → source functions.sh → error trap)
- Package definition: `packaging/nfpm/<component>.yaml`
- Version pin: add `export <COMPONENT>_TAG=...` to `versions-stable.env` and `versions-nightly.env`
- Wire into orchestrator: add `run_script "build_<component>.sh"` in `setup.sh` at the correct dependency position
- Tests: `tests/test_<component>_something.sh` if logic warrants it

**New toolchain installer:**
- Implementation: `scripts/install_<tool>.sh`
- Wire into `setup.sh` before component builds that depend on it

**New configuration variable:**
- Declare in `config.sh` using `${VAR:-default}` pattern with export; document in `docs/CONFIGURATION.md`

**New nFPM package field or packaging logic:**
- Edit `packaging/nfpm/<component>.yaml` for per-component changes
- Edit `scripts/package_all.sh` for pipeline-wide packaging logic

**New APT suite or routing rule:**
- Update VALID_TRACKS, VALID_DISTROS, ALL_SUITES arrays in `config.sh`
- Update resolve_publish_targets logic in `config.sh`
- Update reprepro distributions config in `packaging/repo/conf/`

**New test:**
- Add `tests/test_<topic>.sh`; test by running directly: `bash tests/test_<topic>.sh`

## Special Directories

**`build/` (gitignored):**
- Purpose: Upstream source checkouts managed by git_clone_update
- Generated: Yes, at build time
- Committed: No
- Warning: Shared by both Lima VMs via mount — builds for different distros must use separate copies

**`output/` (gitignored):**
- Purpose: Finished .deb artifacts from package_all.sh
- Generated: Yes
- Committed: No

**`log/` (gitignored):**
- Purpose: Build logs from run_logged helper
- Generated: Yes
- Committed: No

**`.planning/` (committed):**
- Purpose: GSD planning state synced across machines
- Generated: No
- Committed: Yes

---

*Structure analysis: 2026-06-07*
