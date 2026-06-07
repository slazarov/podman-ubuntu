---
phase: 22-migration-docs-installability-smoke-tests
fixed_at: 2026-06-07T12:30:00Z
review_path: .planning/phases/22-migration-docs-installability-smoke-tests/22-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 22: Code Review Fix Report

**Fixed at:** 2026-06-07T12:30:00Z
**Source review:** .planning/phases/22-migration-docs-installability-smoke-tests/22-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5
- Fixed: 5
- Skipped: 0

## Fixed Issues

### WR-01: SHA-tracking cache frozen at first save

**Files modified:** `.github/workflows/build-packages.yml`
**Commit:** 55bd79f
**Applied fix:** Changed the static `nightly-sha-v1` cache key to a per-run
dynamic key `nightly-sha-v1-${{ github.run_number }}` with a `restore-keys`
prefix `nightly-sha-v1-` so each run saves a fresh snapshot and the next run
restores the most-recent one. This matches the updatable-cache pattern already
used for the Go cache at lines 167-170.
**Status:** fixed: requires human verification (CI cache behavior cannot be verified locally)

---

### WR-02: `available_suites[]` is dead code

**Files modified:** `scripts/ci_publish.sh`, `tests/test_index_html_distro.sh`
**Commit:** 28fa366
**Applied fix:** Removed the `available_suites` loop and its stale comment
(lines 462-470 in pre-fix ci_publish.sh). The array was built from 9
distro-qualified suite directories but the version table is keyed on 3 bare
track names — the structures don't map to each other, so "wiring it in" would
be a redesign. Dropped the now-meaningless D-10 guard assertion for
`available_suites` in `test_index_html_distro.sh:80`, keeping the
`<th>Package</th>` table header assertion that actually validates the table. All
14 remaining test assertions pass after the change.
**Status:** fixed: requires human verification (D-10 contract change)

---

### WR-03: Spurious empty table row when all bare-suite Packages files absent

**Files modified:** `scripts/ci_publish.sh`
**Commit:** 6063bb2
**Applied fix:** Added `| grep -v '^$'` into the pipeline between the `printf`
and `sort -u` inside the `readarray` process substitution. This filters the
empty-string element that `printf` emits when all three associative arrays are
empty, making the `[[ ${#_all_pkgs[@]} -gt 0 ]]` guard reliable regardless of
invocation order (e.g., a first-run 2604-only publish).
**Status:** fixed

---

### WR-04: `TRACK` interpolated into APT suite name without validation

**Files modified:** `scripts/smoke_repo_install.sh`
**Commit:** 3398caf
**Applied fix:** Added a `case` block between the LABEL validation and the
`SUITE=` assignment that rejects `TRACK` values outside `{stable,edge,nightly}`
with a clear error message and `exit 1`. Updated the SECURITY comment at lines
32-35 to accurately enumerate all three validated inputs (distro label, TRACK,
and SMOKE_RUNTIME) and their respective whitelists.
**Status:** fixed

---

### WR-05: Tests not wired into CI

**Files modified:** `.github/workflows/build-packages.yml`, `tests/test_docs_suites.sh`, `tests/test_index_html_distro.sh`
**Commit:** ed54816
**Applied fix:** Added a "Run doc and HTML unit tests" step in the `publish`
job immediately after the checkout step. Both test scripts run `bash
tests/test_docs_suites.sh` and `bash tests/test_index_html_distro.sh`. Both
scripts have no build prerequisites and completed green (10/10 and 14/14
assertions) in the worktree before committing. Updated both test file headers
to remove the "LOCAL/MANUAL only" disclaimer and note the new CI wiring.
**Status:** fixed

---

_Fixed: 2026-06-07T12:30:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
