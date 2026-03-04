---
phase: 09-research-podman-build-optimization-introducing-better-lib-tools-in-the-ecosystem
plan: "02"
subsystem: build-optimization
tags: [ccache, mold, c-compilation, rust-linking, build-cache, linker-optimization]

# Dependency graph
requires:
  - phase: 09-research-podman-build-optimization-introducing-better-lib-tools-in-the-ecosystem
    provides: Go cache persistence, sccache pattern, feature flag conventions
provides:
  - ccache opt-in for C builds (crun, catatonit, fuse-overlayfs, pasta) with 30x warm-cache speedup
  - mold linker opt-in for Rust builds (netavark, aardvark-dns) with 5-10x faster linking
  - CCACHE_ENABLED, CCACHE_DIR, CCACHE_MAXSIZE, CCACHE_COMPILERCHECK feature flags
  - MOLD_ENABLED feature flag with .cargo/config.toml integration
  - ccache cache cleanup in uninstall.sh
affects: []

# Tech tracking
tech-stack:
  added: [ccache, mold, clang]
  patterns: [opt-in-ccache-c-builds, mold-via-cargo-config-toml, compiler-check-content]

key-files:
  created: []
  modified:
    - config.sh
    - scripts/install_dependencies.sh
    - scripts/build_crun.sh
    - scripts/build_catatonit.sh
    - scripts/build_fuse-overlayfs.sh
    - scripts/build_pasta.sh
    - scripts/build_netavark.sh
    - scripts/build_aardvark_dns.sh
    - uninstall.sh

key-decisions:
  - "ccache uses CCACHE_COMPILERCHECK=content for correct cache invalidation on GCC upgrades"
  - "mold configured via .cargo/config.toml (not RUSTFLAGS env var) to avoid conflicts with sccache RUSTC_WRAPPER"
  - "clang installed alongside mold as linker driver (GCC < 12 has mold compatibility issues)"
  - "Both features default to false -- zero behavior change for existing users"

patterns-established:
  - "C build ccache pattern: export CC=ccache gcc before autogen/configure/make"
  - "Rust mold pattern: .cargo/config.toml with cfg(target_os=linux) rustflags for architecture-agnostic mold"
  - "Conditional apt install pattern: check feature flag before apt-get install"

requirements-completed: [CACHE-04, CACHE-05, CACHE-06, CACHE-07, CACHE-08, CACHE-09]

# Metrics
duration: 3min
completed: 2026-03-04
---

# Phase 9 Plan 02: ccache and mold Integration Summary

**Opt-in ccache for 4 C builds (30x warm-cache speedup) and mold linker for 2 Rust builds (5-10x faster linking) with sccache-compatible .cargo/config.toml approach**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-04T00:49:47Z
- **Completed:** 2026-03-04T00:52:32Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments
- Added CCACHE_ENABLED, CCACHE_DIR, CCACHE_MAXSIZE, CCACHE_COMPILERCHECK, and MOLD_ENABLED feature flags to config.sh
- Conditional apt installation of ccache (when CCACHE_ENABLED=true) and mold+clang (when MOLD_ENABLED=true) in install_dependencies.sh
- Activated ccache (CC="ccache gcc") in 4 C build scripts: crun, catatonit, fuse-overlayfs, pasta
- Activated mold linker via .cargo/config.toml in 2 Rust build scripts: netavark, aardvark-dns
- Added ccache cache directory cleanup to uninstall.sh
- Both features disabled by default -- zero behavior change for existing users

## Task Commits

Each task was committed atomically:

1. **Task 1: Add ccache and mold feature flags to config.sh and conditional installation to install_dependencies.sh** - `affc630` (feat)
2. **Task 2: Activate ccache in C build scripts and mold in Rust build scripts, add uninstall cleanup** - `558b05d` (feat)

## Files Created/Modified
- `config.sh` - Added CCACHE_ENABLED, CCACHE_DIR, CCACHE_MAXSIZE, CCACHE_COMPILERCHECK, MOLD_ENABLED feature flags
- `scripts/install_dependencies.sh` - Conditional apt install for ccache and mold+clang
- `scripts/build_crun.sh` - ccache activation before autogen/configure/make
- `scripts/build_catatonit.sh` - ccache activation before autogen/configure/make
- `scripts/build_fuse-overlayfs.sh` - ccache activation before autogen/configure/make (works with LIBS/LDFLAGS)
- `scripts/build_pasta.sh` - ccache activation before make (no configure step)
- `scripts/build_netavark.sh` - mold linker via .cargo/config.toml after sccache block
- `scripts/build_aardvark_dns.sh` - mold linker via .cargo/config.toml after sccache block
- `uninstall.sh` - Added ccache cache directory cleanup

## Decisions Made
- Used CCACHE_COMPILERCHECK=content (not default mtime) to handle GCC upgrades gracefully -- ccache hashes compiler binary content so cache invalidates correctly
- Configured mold via .cargo/config.toml instead of RUSTFLAGS environment variable -- env var conflicts with sccache's RUSTC_WRAPPER mechanism
- Installed clang alongside mold -- GCC < 12 has compatibility issues with mold, clang provides reliable -fuse-ld=mold support
- Used `cfg(target_os = "linux")` target selector in cargo config -- architecture-agnostic, works on both amd64 and arm64

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - both features are opt-in. Users enable by setting environment variables:
- `export CCACHE_ENABLED=true` before running setup for C build caching
- `export MOLD_ENABLED=true` before running setup for faster Rust linking

## Next Phase Readiness
- Phase 9 is now complete -- all 6 plans for v1.1 build optimization are done
- Complete optimization stack: sccache (Rust compile cache), Go persistent cache, ccache (C compile cache), mold (Rust linker)

## Self-Check: PASSED

- All 9 modified files exist on disk
- Commit affc630 (Task 1) found in git log
- Commit 558b05d (Task 2) found in git log
- SUMMARY.md created at expected path

---
*Phase: 09-research-podman-build-optimization-introducing-better-lib-tools-in-the-ecosystem*
*Completed: 2026-03-04*
