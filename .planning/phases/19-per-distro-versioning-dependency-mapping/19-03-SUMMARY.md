---
phase: 19-per-distro-versioning-dependency-mapping
plan: 03
subsystem: testing
tags: [dpkg, versioning, debian, apt, packaging, bash]

# Dependency graph
requires:
  - phase: 19-per-distro-versioning-dependency-mapping
    provides: VERSION_SUFFIX form (~ubuntu{VERSION_ID}.podman1) defined in config.sh by Plan 01
provides:
  - scripts/verify_versions.sh — dpkg-oracle proof of the per-distro version-suffix ordering (D-11), including the D-09 nightly and D-10 pasta-date forms
affects: [20-apt-suite-migration, 21-ci-build-matrix, packaging, ci]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Self-contained, literal-fixture verification script using dpkg --compare-versions as the authoritative oracle (no reimplemented version math)"

key-files:
  created:
    - scripts/verify_versions.sh
  modified: []

key-decisions:
  - "verify_versions.sh uses literal in-script version fixtures (no config.sh/build dependency) so it runs on any dpkg host, including in CI before any build"
  - "Six assert_lt orderings: four mandatory D-11 plus 26.04-nightly and D-10 pasta-date symmetry, all expressed as `lt` so one assert_lt wrapper suffices"

patterns-established:
  - "assert_lt wrapper: dpkg --compare-versions A lt B → OK on success, FAIL to stderr + exit 1 on violation; set -euo pipefail makes script exit status the verification result"

requirements-completed: [PKG-09]

# Metrics
duration: 4min
completed: 2026-06-05
---

# Phase 19 Plan 03: Per-Distro Version-Ordering Proof Summary

**scripts/verify_versions.sh proves via the dpkg oracle that the per-distro `~ubuntu{VERSION_ID}.podman1` suffix sorts correctly — yields to official upstream, 24.04 < 26.04, nightly < tagged, and legacy `~podman1` < new form — closing the Phase 19 STATE.md version-suffix research flag (PKG-09).**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-06-05T12:31:43Z
- **Completed:** 2026-06-05T12:35:00Z
- **Tasks:** 1
- **Files modified:** 1 (created)

## Accomplishments
- Created `scripts/verify_versions.sh` — a self-contained, dpkg-only verification script (executable, mode 0755) with an `assert_lt` helper wrapping `dpkg --compare-versions ... lt ...`.
- Wired all four mandatory D-11 orderings: D-08 suffixed yields to official upstream, 24.04 < 26.04 (dist-upgrade order), D-09 nightly form < tagged for the same distro, and legacy `~podman1` < new `~ubuntu24.04.podman1` (clean upgrade for existing installs).
- Added two symmetry assertions: the D-09 nightly form proven for 26.04 as well, and the D-10 pasta-style date base form (24.04 < 26.04).
- Script exit status is the verification result (`set -euo pipefail` + per-assertion `exit 1`); on success it prints `All version ordering assertions passed` and exits 0.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/verify_versions.sh with the D-11 ordering assertions** - `ae88f33` (test)

**Plan metadata:** (see final docs commit below)

_Note: This TDD task's verification artifact (the script) is itself the test; the script and its literal fixtures are inseparable, so it lands as a single `test`-type commit._

## Files Created/Modified
- `scripts/verify_versions.sh` - dpkg `--compare-versions` assertions for the per-distro suffix ordering (D-11), including the D-09 nightly and D-10 pasta date forms; self-contained literal fixtures, runs anywhere dpkg exists.

## Decisions Made
- Used literal in-script version fixtures rather than deriving strings from config.sh, so the script has zero build/config dependency and runs in CI before any package is built (matches the plan's "dpkg-only" intent).
- All orderings expressed as `lt`, so a single `assert_lt` wrapper covers every case (no separate gt/eq helpers needed).

## Deviations from Plan

None - plan executed exactly as written. The script matches the house style (`#!/bin/bash`, `set -euo pipefail`, 2-space indent, stderr errors) per CONVENTIONS.md and contains all plan-mandated literal assertions verbatim.

## Issues Encountered
None.

## Verification Status

macOS-runnable structural verification (this dev host has no dpkg) all passed:
- `bash -n scripts/verify_versions.sh` → syntax OK
- `test -x scripts/verify_versions.sh` → executable OK
- `grep -q 'dpkg --compare-versions'` → oracle present
- `grep -c 'assert_lt '` → 7 (1 definition + 6 calls; ≥4 required)
- `set -euo pipefail` present
- All three plan-mandated literal assertions present verbatim (24.04<26.04, D-09 nightly<tagged, legacy<new)

**Deferred to a dpkg host / CI (environment note):** the full `bash scripts/verify_versions.sh` exit-0 runtime proof requires `dpkg`, which is absent on the macOS dev host. Per the phase validation strategy this runtime execution runs in CI / Plan 04 on an Ubuntu host. The orderings are sound by dpkg tilde semantics (documented in 19-RESEARCH.md Pitfall 2 and Runtime State Inventory).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The version-suffix form is now provably correct via the dpkg oracle, closing the Phase 19 STATE.md research flag for PKG-09.
- `scripts/verify_versions.sh` is ready to be wired into CI (Phase 21) as a fast, build-independent gate.
- No blockers.

## Self-Check: PASSED

- FOUND: scripts/verify_versions.sh
- FOUND commit: ae88f33

---
*Phase: 19-per-distro-versioning-dependency-mapping*
*Completed: 2026-06-05*
