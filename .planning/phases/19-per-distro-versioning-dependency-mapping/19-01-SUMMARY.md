---
phase: 19-per-distro-versioning-dependency-mapping
plan: 01
subsystem: infra
tags: [bash, dpkg, ldd, os-release, nfpm, versioning, dependency-detection]

# Dependency graph
requires:
  - phase: 14-debian-package-building
    provides: nFPM packaging pipeline and detect_crun_parser_depend() prototype being generalized
  - phase: 18-edge-track-build-from-latest-upstream-commits
    provides: tilde (~git) version-suffix convention that the per-distro suffix extends
provides:
  - "functions.sh::detect_distro_version_id() — DISTRO override / os-release / hard-fail, regex-validated"
  - "functions.sh::detect_runtime_depends() — generalized ldd→realpath→dpkg-query soname-to-package detector"
  - "config.sh::VERSION_SUFFIX = ~ubuntu{VERSION_ID}.podman1 — single source of truth"
  - "config.sh::DISTRO_VERSION_ID — exported distro identity for downstream/CI"
affects: [phase-19-plan-02, phase-19-plan-03, phase-19-plan-04, cicd-pipeline]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Generalized ldd→dpkg-query runtime dependency detection (replaces hardcoded soname table)"
    - "DISTRO override → /etc/os-release → hard-fail distro detection mirroring the ARCH override idiom"
    - "Fail-closed VERSION_ID regex validation before version-string interpolation (T-19-01)"

key-files:
  created:
    - tests/test_detect_distro_depends.sh
  modified:
    - functions.sh
    - config.sh

key-decisions:
  - "DISTRO override carries the dotted VERSION_ID form (26.04), not the compact CI label (2604); the ^[0-9]+\\.[0-9]+$ regex enforces this and rejects 2604 intentionally"
  - "detect_runtime_depends excludes only libc6 and libgcc-s1 as universally-present base packages (D-02)"
  - "Detection hard-fails on any unmapped library or undeterminable distro — no silent fallback (D-03)"
  - "config.sh becomes the single source of truth for VERSION_SUFFIX; package_all.sh's hardcoded ~podman1 left intact for Plan 02 to remove"

patterns-established:
  - "Pattern 1: Distro identity via detect-or-override-then-export, peer to the ARCH block"
  - "Pattern 2: Soname→package mapping delegated to the host dpkg DB, never a hand-maintained table"

requirements-completed: [PKG-09, PKG-10]

# Metrics
duration: 3min
completed: 2026-06-05
---

# Phase 19 Plan 01: Per-Distro Versioning & Dependency-Mapping Foundation Summary

**Two build-time helpers (`detect_distro_version_id`, `detect_runtime_depends`) plus a per-distro `VERSION_SUFFIX = ~ubuntu{VERSION_ID}.podman1` composed in config.sh — the contract layer the rest of phase 19 builds against.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-06-05T12:25:06Z
- **Completed:** 2026-06-05T12:28:19Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments
- `detect_distro_version_id()` resolves the distro VERSION_ID from a `DISTRO` override or `/etc/os-release`, hard-fails when neither is available, and regex-validates the result (`^[0-9]+\.[0-9]+$`) before returning — fail-closed against version-string injection (T-19-01).
- `detect_runtime_depends()` generalizes the former `detect_crun_parser_depend()` prototype into `ldd → realpath → dpkg-query -S → dedupe → exclude libc6/libgcc-s1 → sort -u`, hard-failing on any unmapped library (D-03). The crun JSON-parser variant (libjson-c5 vs libyajl2) now falls out of the host package DB automatically (D-04) with no soname-specific logic.
- `config.sh` composes and exports `VERSION_SUFFIX = ~ubuntu${DISTRO_VERSION_ID}.podman1` plus `DISTRO_VERSION_ID` as the single source of truth (D-07/D-08), honoring the `DISTRO` override, with a status echo for build logs.
- Added a TDD test (`tests/test_detect_distro_depends.sh`) covering the dpkg-free behavior (distro detection, regex rejection, non-executable guard) with the real-ELF resolution assertion auto-skipped on non-Debian hosts.

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): failing tests for the two helpers** - `e8b85bc` (test)
2. **Task 1 (GREEN): detect_distro_version_id + detect_runtime_depends** - `d400537` (feat)
3. **Task 2: VERSION_SUFFIX composition in config.sh** - `b11543c` (feat)

_Task 1 followed the TDD RED→GREEN cycle; no refactor commit was needed (implementation was clean on first GREEN)._

## Files Created/Modified
- `functions.sh` - Added `detect_distro_version_id()` and `detect_runtime_depends()` after `detect_architecture()`, before the tail config.sh source. `detect_crun_parser_depend()` in package_all.sh left untouched (Plan 02 removes it).
- `config.sh` - Added a Distro Identity & Version Suffix block (peer to Architecture Detection) exporting `DISTRO_VERSION_ID` and `VERSION_SUFFIX`.
- `tests/test_detect_distro_depends.sh` - Self-contained bash test matching the existing `test_extract_version_nightly.sh` framework style.

## Decisions Made
- **DISTRO override format reconciliation (RESEARCH Open Question 1 / A3):** `DISTRO` carries the dotted VERSION_ID (`26.04`). The compact `2604` form referenced in a success criterion is a CI label, not the override contract — the regex rejects `2604` intentionally, documented inline. CI must pass the dotted form.
- **Base-package exclusion list:** only `libc6` and `libgcc-s1` (D-02) — universally present, never declared.
- **No soname special-casing:** the generalized detector absorbs the crun parser case via the host package DB (D-04); the only mention of the old soname names in functions.sh is a doc comment, which was reworded to remove the literal strings so the D-04 grep is unambiguous.

## Deviations from Plan

None - plan executed exactly as written. (The TDD test file `tests/test_detect_distro_depends.sh` is the standard RED-phase artifact for a `tdd="true"` task, following the existing `tests/` precedent — not a scope deviation.)

## Issues Encountered
- **macOS dev-host verify limitation (expected, environment-scoped):** Sourcing the full `config.sh` on macOS aborts early because line 9 uses GNU `realpath --canonicalize-missing`, which BSD `realpath` rejects — so `toolpath` is empty and `functions.sh` cannot be sourced. This is the documented dev-host constraint (`dpkg`/`ldd`/GNU-realpath are Linux-only here), not a code defect. The composition logic was proven two ways: (1) extracting `detect_distro_version_id` in isolation and running the exact config.sh export lines — yields `~ubuntu24.04.podman1` and `~ubuntu26.04.podman1`; (2) shimming a GNU-compatible `realpath` to emulate the Linux target and running the plan's exact `source config.sh` verify command end-to-end — both 24.04 and 26.04 pass. The Task 1 verify command and the TDD test pass natively on macOS (function-level, dpkg-free). Full `detect_runtime_depends` against a real ELF binary is deferred to Plan 04 (Ubuntu host), per the phase validation strategy.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The two helpers and the per-distro `VERSION_SUFFIX` are now contracts that **Plan 02** consumes: it wires `${DETECTED_DEPENDS}` into the nFPM YAMLs via `detect_runtime_depends`, removes `detect_crun_parser_depend()` and its call sites, and deletes the hardcoded `VERSION_SUFFIX="~podman1"` in package_all.sh so config.sh becomes authoritative.
- **Plan 03** (`scripts/verify_versions.sh`) will assert `dpkg --compare-versions` ordering against the suffix form this plan establishes.
- **Plan 04** exercises the dpkg/ldd-dependent behavior (real-ELF → package names, hard-fail on unmapped soname, 26.04 install smoke) on an Ubuntu host.
- No blockers.

## Self-Check: PASSED

- FOUND: functions.sh
- FOUND: config.sh
- FOUND: tests/test_detect_distro_depends.sh
- FOUND: .planning/phases/19-per-distro-versioning-dependency-mapping/19-01-SUMMARY.md
- FOUND: e8b85bc (test RED)
- FOUND: d400537 (feat Task 1)
- FOUND: b11543c (feat Task 2)

---
*Phase: 19-per-distro-versioning-dependency-mapping*
*Completed: 2026-06-05*
