# Source Tree Analysis

Annotated tree of the tracked codebase (runtime dirs `build/`, `output/`,
`log/` are gitignored and created at build time).

```
podman-ubuntu/
├── setup.sh                     # ENTRY: full pipeline orchestrator (stages 1–5)
├── uninstall.sh                 # Remove all source-built components (symmetric to install)
├── config.sh                    # Central config: arch/distro detection, version suffix, suite routing (${VAR:-default})
├── functions.sh                 # Shared helpers: git_clone_update, git_checkout, run_logged, step_*, error_handler, detect_runtime_depends
├── versions-stable.env          # Stable track: pins every *_TAG (sourced before setup.sh)
├── versions-nightly.env         # Nightly track: NIGHTLY_BUILD=true, SHALLOW_CLONE=false
├── scripts/
│   ├── build_<component>.sh      # 13 standalone build scripts (podman, crun, conmon, buildah,
│   │                             #   skopeo, netavark, aardvark_dns, fuse-overlayfs, catatonit,
│   │                             #   pasta, toolbox, container-libs, go-md2man)
│   ├── install_dependencies.sh   # apt build-deps
│   ├── install_go.sh             # Go toolchain (auto-detected version)
│   ├── install_rust.sh           # rustup at netavark MSRV
│   ├── install_protoc.sh         # Protocol Buffers compiler
│   ├── install_container-configs.sh   # Stage containers-common config files into $DESTDIR
│   ├── install_container-manpages.sh  # Stage section-5 man pages into $DESTDIR
│   ├── package_all.sh            # ENTRY: DESTDIR staging tree → .deb via nfpm (needs DESTDIR + nfpm)
│   ├── preflight_check.sh        # Pre-build environment validation (cgroups, subuid, fuse, kernel, noexec)
│   ├── ci_publish.sh             # ENTRY: multi-suite repo assembly + verbatim mirror + index.html (~740 LOC)
│   ├── repo_manage.sh            # Single (track,distro) reprepro assembly
│   ├── repo_byhash.sh            # Add Acquire-By-Hash indexes + re-sign
│   ├── check_republish_needed.sh # Republish gating for manual stable/edge dispatch
│   ├── verify_depends.sh         # Post-build .deb dependency validation (Ubuntu)
│   ├── verify_versions.sh        # Post-build dpkg version-ordering proof (Ubuntu)
│   ├── smoke_repo_install.sh     # Install podman-suite from assembled file:// repo (CI gate)
│   └── smoke_install_2604.sh     # Smoke install on Ubuntu 26.04
├── packaging/
│   ├── nfpm/<component>.yaml      # 12 component package defs + suite.yaml (meta-package / distributions template)
│   └── repo/conf/                # reprepro config: distributions (9 suites), options
├── config/
│   └── containers.conf           # Default OCI runtime configuration (installed into OS)
├── tests/
│   └── test_*.sh                 # 13 pure-bash unit/integration tests (run directly with bash)
├── lima/
│   ├── ubuntu-24.yaml            # Lima VM: Ubuntu 24.04 (repo mounted writable at /opt/podman-debian)
│   └── ubuntu-26.yaml            # Lima VM: Ubuntu 26.04
├── docs/                         # Documentation (hand-maintained + docs/bmad/ generated set)
├── .github/workflows/
│   └── build-packages.yml        # CI: 4-cell distro×arch native build matrix + gated publish
├── index.html                    # Stale root landing page (authoritative page is generated in ci_publish.sh)
├── AGENTS.md / CLAUDE.md         # AI-agent guidance (CLAUDE.md → @AGENTS.md)
└── README.md / CONTRIBUTING.md / LICENSE
```

## Entry Points

| Command | Purpose |
|---------|---------|
| `setup.sh` | Full build + install (stages 1–5) — needs root |
| `scripts/build_<component>.sh` | Single-component standalone build (self-bootstraps) |
| `scripts/package_all.sh` | Staging tree → `.deb` (needs `DESTDIR` + `nfpm`) |
| `scripts/ci_publish.sh` | Assemble the multi-suite APT repo |
| `uninstall.sh` | Remove all source-built components |

## Critical Files

- **`config.sh`** — every env var, arch/distro detection, `VERSION_SUFFIX`, suite routing arrays.
- **`functions.sh`** — all shared helpers; tail-sources `config.sh`.
- **`scripts/package_all.sh`** — packaging + dependency detection logic.
- **`scripts/ci_publish.sh`** — the publish state machine (clobber-prevention hotspot).
- **`packaging/repo/conf/distributions`** — the 9 reprepro suites.
- **`.github/workflows/build-packages.yml`** — the entire CI/CD definition.

## Where to Add Code

| Change | Where |
|--------|-------|
| New build component | `scripts/build_<c>.sh` (copy header) + `packaging/nfpm/<c>.yaml` + `*_TAG` in both `versions-*.env` + wire into `setup.sh` `run_script` at the right dependency position |
| New toolchain installer | `scripts/install_<tool>.sh`, wired into `setup.sh` before dependents |
| New config variable | `config.sh` (`${VAR:-default}` + export), documented in `docs/CONFIGURATION.md` |
| New packaging logic | `packaging/nfpm/<c>.yaml` (per-component) or `scripts/package_all.sh` (pipeline-wide) |
| New APT suite / routing | `VALID_TRACKS`/`VALID_DISTROS`/`ALL_SUITES` + `resolve_publish_targets` in `config.sh` + `packaging/repo/conf/distributions` |
| New test | `tests/test_<topic>.sh`, run with `bash tests/test_<topic>.sh` |
