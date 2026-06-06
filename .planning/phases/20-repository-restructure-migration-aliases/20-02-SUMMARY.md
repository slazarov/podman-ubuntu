---
phase: 20-repository-restructure-migration-aliases
plan: 02
subsystem: infra
tags: [reprepro, apt, acquire-by-hash, gpg, by-hash, github-pages, bash, awk]

# Dependency graph
requires:
  - phase: 20-01
    provides: nine-suite reprepro distribution layout + bare-alias mechanism (resolve_publish_targets)
provides:
  - "scripts/repo_byhash.sh exposing add_byhash_and_resign(): post-export by-hash materialization + Acquire-By-Hash injection + re-sign"
  - "tests/test_byhash_parse.sh: section-boundary-correct Release parser test (macOS-runnable)"
affects: [20-03, 20-04]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Post-export Acquire-By-Hash bolt-on: cp+gpg wrapper around reprepro's own Release output"
    - "Sourceable-or-standalone script (BASH_SOURCE==$0 entrypoint guard)"

key-files:
  created:
    - scripts/repo_byhash.sh
    - tests/test_byhash_parse.sh
  modified: []

key-decisions:
  - "by-hash copies written adjacent to each index plus a Release-level copy (Pitfall 3 avoided)"
  - "Release-by-hash computed AFTER Acquire-By-Hash injection so by-hash bytes equal served bytes (Pitfall 2 ordering)"
  - "Re-sign is mandatory after Release mutation (D-08): rm stale InRelease/Release.gpg then regenerate clearsign + detached"
  - "Parser guards with [[ -f ]] / command -v so a missing SHA512 section is a no-op (strongest-available rule, A1)"
  - "Single by-hash generation only — no multi-generation retention (D-09 / Pitfall 5)"

patterns-established:
  - "Pattern 1: Helper relies on repo_manage.sh having already imported the GPG key — does NOT re-import"
  - "Pattern 2: Test pins the production awk parser verbatim and fails loudly if repo_byhash.sh drifts"

requirements-completed: [REPO-08]

# Metrics
duration: 4min
completed: 2026-06-06
---

# Phase 20 Plan 02: Acquire-By-Hash Post-Export Bolt-On Summary

**Self-contained `add_byhash_and_resign()` helper that materializes adjacent by-hash index copies, injects `Acquire-By-Hash: yes`, and re-signs InRelease/Release.gpg after each reprepro export — plus a macOS-runnable Release-parser test.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-06-06
- **Completed:** 2026-06-06
- **Tasks:** 2
- **Files modified:** 2 (both created)

## Accomplishments
- `scripts/repo_byhash.sh` providing a sourceable `add_byhash_and_resign(lsuite, lrepo)` that performs the full post-export sequence: parse Release SHA256/SHA512 sections → cp each index into `$(dirname)/by-hash/<ALGO>/<hash>` → idempotently inject `Acquire-By-Hash: yes` after the `Suite:` line → by-hash the Release file itself → re-sign InRelease (clearsign) + Release.gpg (detached).
- Script is dual-mode: function-only when sourced, runs `add_byhash_and_resign "$1" "$2"` when executed standalone (for VM verification in Plan 04).
- `tests/test_byhash_parse.sh` pinning the exact awk parser against a literal reprepro-style Release fixture (MD5Sum/SHA256/SHA512 sections), proving section-boundary correctness — 8/8 assertions pass on macOS with no reprepro/gpg/apt dependency.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/repo_byhash.sh with add_byhash_and_resign()** - `c958424` (feat)
2. **Task 2: Write tests/test_byhash_parse.sh against a literal reprepro Release fixture** - `5a80acb` (test)

## Files Created/Modified
- `scripts/repo_byhash.sh` - Post-export Acquire-By-Hash helper; standard skeleton (shebang, `set -euo pipefail`, toolpath bootstrap, config.sh/functions.sh sourcing, ERR trap) copied from repo_manage.sh.
- `tests/test_byhash_parse.sh` - Pure-bash/awk test of the Release-section parser with a literal fixture and a drift guard against repo_byhash.sh.

## Decisions Made
None beyond those specified in the plan — followed the RESEARCH Code Examples (lines 289-333) sequence exactly: by-hash indexes → inject → by-hash Release → re-sign. Source ordering (injection sed before Release-hash cp before re-sign) is preserved, satisfying T-20-04/T-20-05.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. `bash -n` clean on both files; the parser test passes 8/8 on the macOS dev host. ShellCheck not installed on the dev host (project convention is best-effort, not CI-enforced) — to be exercised on the Lima VM alongside the full by-hash + `gpg --verify` proof in Plan 04.

## Threat Surface
No new surface beyond the plan's `<threat_model>`. The helper mutates Release then re-signs (T-20-04 mitigated), computes the Release by-hash after injection (T-20-05 mitigated), and writes by-hash adjacent to each index (T-20-06 mitigated). No package-manager installs (gpg/cp/awk/coreutils only).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `add_byhash_and_resign` is ready for Plan 03 to call per-suite after each `reprepro export`.
- A1 (which hash algos reprepro emits) and full `gpg --verify InRelease` against a real export remain DEFERRED to the Lima VM in Plan 04 — the parser's `[[ -f ]]`/`command -v` guards make a missing SHA512 section a safe no-op in the meantime.

## Self-Check: PASSED

- FOUND: scripts/repo_byhash.sh
- FOUND: tests/test_byhash_parse.sh
- FOUND: .planning/phases/20-repository-restructure-migration-aliases/20-02-SUMMARY.md
- FOUND commit: c958424 (Task 1)
- FOUND commit: 5a80acb (Task 2)
