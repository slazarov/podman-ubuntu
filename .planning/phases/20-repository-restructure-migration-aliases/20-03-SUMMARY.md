---
phase: 20-repository-restructure-migration-aliases
plan: 03
subsystem: infra
tags: [reprepro, apt, ci, suite-routing, acquire-by-hash, mirror-then-include, bash, github-actions]

# Dependency graph
requires:
  - phase: 20-01
    provides: "9-stanza distributions + config.sh resolve_publish_targets/ALL_SUITES routing contract"
  - phase: 20-02
    provides: "scripts/repo_byhash.sh add_byhash_and_resign() post-export by-hash + re-sign helper"
provides:
  - "track+distro-aware repo_manage.sh feeding versioned suite + 24.04 bare alias from one .deb set"
  - "9-suite mirror-then-include ci_publish.sh with per-suite by-hash + re-sign post-processing"
  - "publish job in build-packages.yml passing distro in the new 5-arg ci_publish.sh shape"
affects: [20-04, ci-matrix-2604, migration-aliases]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Mirror-then-include no-clobber publish: OTHER_SUITES = ALL_SUITES - PUBLISH_TARGETS; every publish reassembles all 9 suites, only published target(s) take fresh content"
    - "Per-target reprepro export discipline (never bare export) extended from single-suite to PUBLISH_TARGETS loop (Pitfall 4)"
    - "Subshell-validation guard: mapfile from resolve_publish_targets process substitution cannot abort parent on bad input, so empty-array check re-asserts the hard error"
    - "CI distro value threaded through a step output (distro=2404) rather than inlined, making the Phase-21 matrix wiring a one-line change"

key-files:
  created: []
  modified:
    - scripts/repo_manage.sh
    - scripts/ci_publish.sh
    - .github/workflows/build-packages.yml

key-decisions:
  - "Added an explicit empty-PUBLISH_TARGETS guard in both scripts because resolve_publish_targets runs in a process-substitution subshell, where its non-zero exit cannot propagate to abort the parent (Rule 2 - correctness)"
  - "ALL_SUITES is consumed from config.sh (sourced) and NOT redeclared locally in ci_publish.sh — the old local 3-element ALL_SUITES was deleted in favor of the 9-element sourced array"
  - "by-hash step placed as Step 4b between the re-include block and temp-dir cleanup, iterating ALL_SUITES and guarding on dists/<suite>/Release existence so empty/unpopulated suites are a no-op"
  - "index.html available_suites loop iterates the 9-suite ALL_SUITES; the existing empty-Packages skip is the D-18 mechanism that hides unpopulated -2604 suites"
  - "distro plumbed as a step output (distro=2404) referenced via steps.track.outputs.distro; no build matrix added (Phase 21)"

patterns-established:
  - "Pattern: routing-helper consumers guard the subshell mapfile with an empty-array check to preserve fail-fast on invalid track/distro"
  - "Pattern: the integration spine sources both Plan-01 (routing) and Plan-02 (by-hash) helpers and drives the whole 9-suite assembly from the single (track, distro) input"

requirements-completed: [REPO-06, REPO-07, REPO-08]

# Metrics
duration: 5min
completed: 2026-06-06
---

# Phase 20 Plan 03: Publish-Path Integration (track+distro routing + 9-suite mirror-then-include + by-hash) Summary

**Wired the Plan-01 routing helper and Plan-02 by-hash helper into the live publish path: `repo_manage.sh` now takes `<track> <distro>` and feeds both the versioned suite and the 24.04 bare alias from one .deb set with per-target export; `ci_publish.sh` mirrors down the untouched suites, reassembles all 9 suites without clobbering, runs `add_byhash_and_resign` per exported suite, and renders the 9-suite index while hiding empties; and the publish job passes `distro=2404` in the new 5-arg shape.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-06T20:37:09Z
- **Completed:** 2026-06-06T20:42:07Z
- **Tasks:** 3
- **Files modified:** 3 (all modified)

## Accomplishments

- **repo_manage.sh** is now track+distro-aware. CLI changed from `<suite> <deb-dir> [output]` to `<track> <distro> <deb-dir> [output]`; the hardcoded stable/edge/nightly whitelist is replaced by `mapfile -t PUBLISH_TARGETS < <(resolve_publish_targets "${TRACK}" "${DISTRO}")`. The includedeb loop now adds each fresh .deb into every member of `PUBLISH_TARGETS` (versioned suite + bare alias on 24.04, D-12), and export is a per-target loop (`reprepro -b ... export "${target}"`) instead of a bare `export` (Pitfall 4). db/conf cleanup remains after export. Echo/summary lines now report TRACK/DISTRO/PUBLISH_TARGETS.
- **ci_publish.sh** generalized to the 9-suite mirror-then-include pattern. CLI inserts the distro dimension (`<track> <distro> <deb-dir> <repo-url> <output-dir>`). It consumes the sourced 9-element `ALL_SUITES` (the old local 3-element redeclaration was deleted) and derives `OTHER_SUITES = ALL_SUITES − PUBLISH_TARGETS`, so for a 24.04 publish BOTH `<track>-2404` and the bare `<track>` are excluded from mirror-down (no clobber, T-20-07/D-13). The first-deploy 404 tolerance (`curl -sfL ... || true` + empty-Packages continue) is preserved verbatim for the new -2404/-2604 URLs (T-20-10/A3). repo_manage.sh is invoked with the new args; the other-suite re-include keeps per-suite export. A new Step 4b sources `repo_byhash.sh` and calls `add_byhash_and_resign "${suite}" "${OUTPUT_DIR}"` for every suite that has a Release, after all exports and before temp cleanup (REPO-08/D-07). The index.html loop now iterates `ALL_SUITES`, with the existing empty-skip hiding unpopulated -2604 suites (D-18). The static "Choose a Track" / tab blocks are untouched (Phase-22 territory).
- **build-packages.yml** publish job now emits `distro=2404` from the `track` step and passes `${{ steps.track.outputs.distro }}` as the second positional to `ci_publish.sh`, matching the new 5-arg shape. The reprepro install, download-artifact, and upload/deploy-pages steps are unchanged (atomic deploy preserved, D-10/D-16). No build matrix added — Phase 21.

## Task Commits

Each task was committed atomically:

1. **Task 1: Make repo_manage.sh track+distro-aware and feed the alias on 24.04** - `5439b0e` (feat)
2. **Task 2: Generalize ci_publish.sh to 9-suite mirror-then-include + by-hash post-processing** - `b3cfc4f` (feat)
3. **Task 3: Plumb the distro argument through the publish job in build-packages.yml** - `bf0ce93` (feat)

## Files Created/Modified

- `scripts/repo_manage.sh` - New `<track> <distro> <deb-dir> [output]` CLI; routes via `resolve_publish_targets`; includedeb-into-every-target loop; per-target export; empty-target guard; TRACK/DISTRO/PUBLISH_TARGETS in echos and structure summary.
- `scripts/ci_publish.sh` - New 5-arg CLI with distro as positional 2; sources `repo_byhash.sh`; `OTHER_SUITES = ALL_SUITES − PUBLISH_TARGETS`; mirror-down generalized to N suites with 404 tolerance intact; invokes repo_manage.sh with new args; Step 4b by-hash + re-sign per exported suite; index.html iterates 9-suite ALL_SUITES with empty-skip retained; summary reports published vs mirrored suites.
- `.github/workflows/build-packages.yml` - `distro=2404` step output added to the publish job's `track` step; ci_publish.sh call passes `steps.track.outputs.distro` as the second arg.

## Decisions Made

- **Subshell-validation guard (Rule 2 — correctness).** `resolve_publish_targets` exits non-zero on a bad track/distro, but it runs inside a `< <(...)` process substitution, so under `set -euo pipefail` that non-zero exit cannot abort the parent — `mapfile` simply yields an empty array. To preserve the Plan-01 "clear error and abort" convention, both scripts now check `[[ ${#PUBLISH_TARGETS[@]} -eq 0 ]]` and exit 1 (the helper's own stderr already names the rejected value). This is a deviation (see below).
- **Consume, do not redeclare, ALL_SUITES.** The old `ALL_SUITES=(stable edge nightly)` local in ci_publish.sh was removed; the sourced 9-element array from config.sh is the single source of truth, per the plan.
- **by-hash placement.** Step 4b runs after every export (target suites via repo_manage.sh, other suites via the re-include loop) and before temp cleanup, guarded on `dists/<suite>/Release` existence — empty/unpopulated suites are a safe no-op (matching the helper's own `[[ -f ]]` guard).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] Added empty-PUBLISH_TARGETS guard after the routing-helper call in both scripts**
- **Found during:** Task 1 (repo_manage.sh), repeated in Task 2 (ci_publish.sh)
- **Issue:** The plan specifies `mapfile -t PUBLISH_TARGETS < <(resolve_publish_targets ...)` and states the helper "already validates track+distro and exits non-zero on bad input, preserving the clear error message convention." However, `resolve_publish_targets` runs in a process-substitution subshell; its `return 1`/non-zero exit does NOT propagate to abort the parent shell under `set -euo pipefail`. A bad track/distro would silently yield an empty `PUBLISH_TARGETS` array and the publish would proceed with zero includedeb targets rather than failing fast — defeating mitigation T-20-09 (malformed publish target aborts the publish).
- **Fix:** Added `if [[ ${#PUBLISH_TARGETS[@]} -eq 0 ]]; then echo "ERROR: could not resolve publish targets..." >&2; exit 1; fi` immediately after the mapfile in both `scripts/repo_manage.sh` and `scripts/ci_publish.sh`. The helper's own stderr message (which names the rejected track/distro) still fires inside the subshell, so the operator sees both.
- **Files modified:** scripts/repo_manage.sh, scripts/ci_publish.sh
- **Commits:** `5439b0e` (repo_manage.sh), `b3cfc4f` (ci_publish.sh)

## Issues Encountered

None blocking. ShellCheck is a project convention but is not installed on this macOS dev host; `bash -n` syntax checks are clean for both touched scripts. The real 9-suite assemble + per-suite export + by-hash + `gpg --verify` + no-clobber diff requires reprepro/gpg and is deferred to the Lima VM / CI in Plan 04 (CLAUDE.md: `bash -n` only on macOS).

## Threat Surface

No new surface beyond the plan's `<threat_model>`. T-20-07 (clobbering) is mitigated by `OTHER_SUITES = ALL_SUITES − PUBLISH_TARGETS` + per-target/per-suite export. T-20-08 (by-hash before re-sign / skipped suites) is mitigated by calling `add_byhash_and_resign` for every suite with a Release after all exports. T-20-09 (malformed publish target) is mitigated by `resolve_publish_targets` validation, hardened further by the empty-array guard above. T-20-10 (first-deploy 404) tolerance preserved verbatim. No package-manager installs (bash wiring + workflow YAML; reprepro install step unchanged).

## User Setup Required

None. The live 9-suite publish that materializes these suites runs in CI / on the Lima VM (Plan 04).

## Next Phase Readiness

- The integration spine is complete: a single `(track, distro)` input now drives the full 9-suite assembly through repo_manage.sh (target + alias) and ci_publish.sh (mirror-then-include + by-hash + index).
- Plan 04 should execute the real publish on the Lima VM / CI to prove: per-suite export produces 9 valid signed Releases, `gpg --verify InRelease` passes after by-hash injection, the no-clobber diff holds (untouched suites byte-identical pre/post), and the first 9-suite deploy tolerates the -2404/-2604 404s.
- Phase 21 swaps the literal `distro=2404` step output for a per-distro matrix var — a one-line change as designed.

## Self-Check: PASSED

- FOUND: scripts/repo_manage.sh (modified)
- FOUND: scripts/ci_publish.sh (modified)
- FOUND: .github/workflows/build-packages.yml (modified)
- FOUND commit: 5439b0e (Task 1)
- FOUND commit: b3cfc4f (Task 2)
- FOUND commit: bf0ce93 (Task 3)
- bash -n clean on both scripts; workflow YAML parses (python3 + ruby); Plan-01 routing tests + Plan-02 by-hash test all pass.

---
*Phase: 20-repository-restructure-migration-aliases*
*Completed: 2026-06-06*
