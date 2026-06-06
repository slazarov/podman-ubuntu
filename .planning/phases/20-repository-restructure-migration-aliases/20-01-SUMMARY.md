---
phase: 20-repository-restructure-migration-aliases
plan: 01
subsystem: infra
tags: [reprepro, apt, distributions, suite-routing, bash, config]

# Dependency graph
requires:
  - phase: 19-per-distro-versioning
    provides: "DISTRO override + VERSION_SUFFIX in config.sh; per-distro .deb suffix coexistence"
  - phase: 15-apt-repository-and-signing
    provides: "3-stanza conf/distributions (Codename=Suite, SignWith:yes) and reprepro publish flow"
provides:
  - "9-stanza conf/distributions (6 versioned <track>-<distro> + 3 bare legacy aliases)"
  - "config.sh suite whitelist arrays: VALID_TRACKS, VALID_DISTROS, ALL_SUITES"
  - "config.sh routing helpers: resolve_publish_targets() (D-12 alias rule), is_valid_suite()"
  - "Wave-0 unit tests pinning the distributions parse and the routing/alias contract"
affects: [repo_manage, ci_publish, migration-aliases, ci-matrix-2604]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Sourceable, non-exported routing helpers defined at config.sh file scope so unit tests sed-extract + eval them without triggering os-release load (mirrors Phase 19 detect_distro_version_id extractability)"
    - "Bare-alias reprepro distribution (Suite: stable, not stable-2404) as the REPO-07 cached-Suite-preservation mechanism"

key-files:
  created:
    - tests/test_distributions_suites.sh
    - tests/test_suite_routing.sh
    - tests/test_alias_routing.sh
  modified:
    - config.sh
    - packaging/repo/conf/distributions

key-decisions:
  - "resolve_publish_targets emits targets one-per-line via printf so callers consume with mapfile/while read; D-12 24.04 alias appended as a second line, 26.04 single line"
  - "Suite whitelist arrays declared (not exported) — child scripts source config.sh, matching the source-not-export pattern"
  - "All 9 stanzas keep SignWith: yes (gpg default key) — valid under the single-imported-key CI invariant (REPO-06)"

patterns-established:
  - "Pattern: per-distro suite routing centralized in config.sh as the contract layer every downstream publish plan consumes"
  - "Pattern: macOS-safe bash unit tests extract config.sh functions via sed instead of sourcing, avoiding Ubuntu-only load-time side effects"

requirements-completed: [REPO-06, REPO-07]

# Metrics
duration: 2min
completed: 2026-06-06
---

# Phase 20 Plan 01: Repository Metadata + Suite Routing Foundation Summary

**Nine-suite reprepro distributions config (6 versioned + 3 bare legacy aliases) plus a sourceable `resolve_publish_targets` routing helper in config.sh implementing the D-12 24.04 alias rule, with three passing Wave-0 unit tests.**

## Performance

- **Duration:** 2 min
- **Started:** 2026-06-06T20:26:19Z
- **Completed:** 2026-06-06T20:28:50Z
- **Tasks:** 3
- **Files modified:** 5 (2 modified, 3 created)

## Accomplishments
- Rewrote `packaging/repo/conf/distributions` from 3 stanzas to 9: 6 versioned `<track>-<distro>` suites (stable/edge/nightly × 2404/2604) plus 3 bare legacy aliases. The bare aliases carry `Suite: stable`/`edge`/`nightly` (not `-2404`), which is the entire REPO-07 mechanism preserving apt's cached Suite value so legacy clients see no re-acceptance prompt.
- Added the suite-routing contract layer to `config.sh`: `VALID_TRACKS`/`VALID_DISTROS`/`ALL_SUITES` whitelist arrays, an `is_valid_suite()` membership check, and `resolve_publish_targets()` that maps `(track, distro)` to its publish targets — appending the bare alias only for 24.04 (D-12) and rejecting any out-of-whitelist track/distro.
- Shipped three macOS-safe Wave-0 unit tests (35 assertions total, all passing) pinning the distributions parse contract and the routing/alias contract without any reprepro/gpg/apt dependency.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add suite whitelist arrays + resolve_publish_targets routing helper to config.sh** - `5452baa` (feat)
2. **Task 2: Rewrite conf/distributions to 9 stanzas (6 versioned + 3 legacy aliases)** - `dafa53c` (feat)
3. **Task 3: Write the three Wave-0 unit tests** - `ae9715c` (test)

_Note: Task 1 was tagged tdd="true" in the plan, but the plan structures its tests into Task 3 (the Wave-0 test task); both function and tests were authored and verified within this plan. See TDD Gate Compliance below._

## Files Created/Modified
- `config.sh` - Added "Repository Suite Routing" section: `VALID_TRACKS`/`VALID_DISTROS`/`ALL_SUITES` arrays, `is_valid_suite()`, `resolve_publish_targets()`. No change to config.sh load-time output.
- `packaging/repo/conf/distributions` - 9 reprepro distribution stanzas; Suite==Codename, SignWith:yes on all; 3 alias Descriptions carry DEPRECATED note.
- `tests/test_distributions_suites.sh` - Parses distributions: 9 Suite/Codename/SignWith lines, Suite==Codename, bare aliases present, 6 versioned present, 3 DEPRECATED, no createsymlinks (15 assertions).
- `tests/test_suite_routing.sh` - Extracts and evals routing helpers; verifies resolve_publish_targets output for 2404/2604, whitelist rejection, is_valid_suite (8 assertions).
- `tests/test_alias_routing.sh` - D-12 rule across all three tracks: 2404 includes bare alias, 2604 excludes it (12 assertions).

## Decisions Made
- `resolve_publish_targets` emits one target per line via `printf '%s\n'` so callers (Plan 03 `repo_manage.sh`/`ci_publish.sh`) can read with `mapfile`/`while read`; the 24.04 bare alias is the second line, 26.04 yields a single line.
- Whitelist arrays declared, not exported (bash cannot export arrays cleanly) — downstream scripts source config.sh.
- All 9 stanzas keep `SignWith: yes` (gpg default key), valid because exactly one key is imported in CI (REPO-06 single-key criterion).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. ShellCheck is a project convention but is not installed on this macOS dev host; `bash -n` syntax checks passed for all touched scripts and all three unit tests pass.

## TDD Gate Compliance
Task 1 carried `tdd="true"`, but the plan deliberately separates the implementation (Task 1, config.sh helpers) from its tests (Task 3, the Wave-0 test files) rather than interleaving RED→GREEN within Task 1. As a result the commit sequence is `feat` (Task 1) → `feat` (Task 2) → `test` (Task 3); there is no preceding standalone RED `test(...)` commit for the routing helpers. The routing/alias behavior is nonetheless fully covered by `test_suite_routing.sh` and `test_alias_routing.sh`, which all pass. This matches the plan's authored task structure (tests are a distinct Wave-0 task) — flagged here for gate-sequence transparency.

## User Setup Required
None - no external service configuration required. This plan only touches repo metadata config and bash; the live reprepro publish that materializes these 9 suites is wired in Plan 03.

## Next Phase Readiness
- The contract layer is ready: Plan 03 can source `config.sh` and call `resolve_publish_targets <track> <distro>` to drive `reprepro includedeb`/`export` per target, and reprepro will read the 9-stanza `conf/distributions` to materialize all suites.
- On first 9-suite publish only the bare `stable`/`edge`/`nightly` exist live; the `-2404`/`-2604` Packages URLs 404 until first deploy — the existing mirror-down loop tolerates 404 (RESEARCH Runtime State Inventory). Plan 03 should confirm this still holds.

## Self-Check: PASSED

All created/modified files exist on disk; all 3 task commits present in git history.

---
*Phase: 20-repository-restructure-migration-aliases*
*Completed: 2026-06-06*
