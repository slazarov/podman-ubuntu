---
phase: 20-repository-restructure-migration-aliases
plan: 06
subsystem: infra
tags: [reprepro, apt-repository, by-hash, ci-publish, gpg, verbatim-mirror, html-escape]

# Dependency graph
requires:
  - phase: 20-repository-restructure-migration-aliases (Plan 03)
    provides: ci_publish.sh mirror-then-include multi-suite publish + OTHER_SUITES derivation
  - phase: 20-repository-restructure-migration-aliases (Plan 05)
    provides: pipefail-isolated add_byhash_and_resign + Test group F in the integration harness
provides:
  - Verbatim-mirror path for non-target bare aliases on 26.04 publishes (CR-02 closed) — unchanged suites keep their original Release Date + InRelease + Release.gpg
  - HTML-escaped package names/versions in the generated index.html (WR-04 closed)
  - Test group G in test_repo_assemble_byhash.sh proving a 26.04 publish does not re-sign the untouched bare alias
affects: [phase-21, ci-publish, apt-repository]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Verbatim-mirror: for a non-target suite whose live dists/<suite>/ tree exists, copy the signed metadata tree + referenced pool entries as-is and exclude it from both re-includedeb/re-export and add_byhash_and_resign — preserving Release Date/signature byte-for-byte on unchanged content"
    - "esc() sed escaper (& first, then < > \") applied to dynamic package/version values before HTML heredoc interpolation"

key-files:
  created: []
  modified:
    - scripts/ci_publish.sh
    - tests/test_repo_assemble_byhash.sh

key-decisions:
  - "Chose the verifier's verbatim-mirror option (vs an alternative Release-Date stabilization) — lowest-risk, matches the locked D-10 rebuild-the-world model: the fix stops MUTATING suites the publish did not change rather than introducing a persistent reprepro db or incremental gh-pages checkout"
  - "VERBATIM_SUITES are excluded from total_other_count so the Step 4 re-includedeb/re-export block never runs for them; a separate IS_VERBATIM map gates both Step 4 and Step 4b"
  - "Verbatim pool entries are placed at the exact path the mirrored Packages Filename: lines reference, so apt resolves packages against the served (unchanged) index"

patterns-established:
  - "Non-target suites with a live signed tree are served verbatim; only publish targets and non-target suites WITHOUT a live tree pass through the fresh export + re-sign path"

requirements-completed: [REPO-08, REPO-06]

# Metrics
duration: 12min
completed: 2026-06-07
---

# Phase 20 Plan 06: CR-02 Verbatim Alias Mirror + WR-04 HTML Escape Summary

**On a 26.04 publish the non-target bare aliases (stable/edge/nightly) are now served verbatim — their original Release Date, InRelease, and Release.gpg are preserved byte-for-byte instead of being re-exported and re-signed — closing the Acquire-By-Hash CDN hash-mismatch window; package names/versions in index.html are HTML-escaped.**

## Performance

- **Duration:** ~12 min
- **Completed:** 2026-06-07
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Closed verification GAP 2 / CR-02 (BLOCKER): `scripts/ci_publish.sh` no longer re-`includedeb`'s + re-`export`s + re-signs the bare legacy aliases on a 26.04 publish. A non-target suite with a live `dists/<suite>/` tree is mirrored verbatim (Release, InRelease, Release.gpg, per-arch Packages/Release, by-hash dirs) with its original signature, and the referenced pool entries are placed at their exact `Filename:` paths so apt still resolves the packages. The suite is excluded from the Step 4 re-export loop and the Step 4b by-hash + re-sign loop. This stops the Release Date/signature regeneration on byte-identical content that reopened the CDN hash-mismatch window (T-20-17).
- Preserved the locked CONTEXT decisions: D-12 (24.04 publish still feeds BOTH `<track>-2404` and the bare `<track>` alias from fresh debs, because the alias is a publish target there and never enters the verbatim path), D-13/D-10 (no persistent reprepro db, no incremental checkout — the fix stays within the rebuild-the-world mirror-then-include model), and D-14 (verbatim path no-ops cleanly when the live alias tree 404s on first deploy / empty-2604).
- Closed WR-04: added an `esc()` helper and HTML-escaped the dynamic package name + version before interpolating them into the generated `index.html` rows (T-20-18 mitigated) — closing the malformed-markup / XSS vector for nightly versions derived from upstream HEAD.
- Added Test group G to the integration harness proving the bare alias is NOT re-signed on a 26.04 publish (Date + InRelease + Release.gpg byte-stable, signature still verifies) while the `stable-2604` target IS freshly signed with `Acquire-By-Hash`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Verbatim-mirror non-target aliases on 26.04 (CR-02) + HTML-escape index.html (WR-04)** - `fff4fa7` (fix)
2. **Task 2: Test group G — 26.04 publish preserves the untouched bare alias** - `7c38734` (test)

_Per the harness's macOS SKIP design, Task 2's RED→GREEN runs only on Lima ubuntu-24, where Task 1's implementation is already present (HEAD `fff4fa7` at run time). The test and the (already-committed) implementation travel together — the same pattern documented in Plan 05._

## Files Created/Modified
- `scripts/ci_publish.sh` — Step 2 now calls a new `mirror_suite_verbatim` helper for each OTHER suite, recording success in `VERBATIM_SUITES` / `IS_VERBATIM`; verbatim suites are excluded from `total_other_count` (gating Step 4) and skipped explicitly in both the Step 4 re-includedeb/re-export loop and the Step 4b `add_byhash_and_resign` loop. Verbatim pool entries are downloaded to their exact `Filename:` paths. Added the `esc()` HTML escaper and applied it to `${pkg}`/`${ver}` in the index.html row heredoc.
- `tests/test_repo_assemble_byhash.sh` — Appended "Test group G: CR-02 — 26.04 publish preserves the untouched bare alias" after Test group F. Builds a `~ubuntu26.04.podman1` fixture deb, captures the bare `stable` alias signed state, runs `repo_manage.sh stable 2604` (targets only `stable-2604`) + `add_byhash_and_resign stable-2604` ONLY, then asserts G-1 (Date/InRelease/Release.gpg byte-stable), G-2 (alias signature still verifies), G-3 (`stable-2604` freshly signed with Acquire-By-Hash). Reuses the existing isolated GNUPGHOME, fixture builder, assert_* helpers, and macOS SKIP guard.

## Decisions Made
- Chose the verbatim-mirror option the verifier offered (over an alternative way of stabilizing the Release Date) because it is the lower-risk fix and matches the locked D-10 rebuild-the-world model — it does not introduce a persistent reprepro db or an incremental gh-pages checkout; it simply stops mutating suites the publish did not change.
- Used a `mirror_suite_verbatim` shell function with a `wget -r` recursive mirror of `dists/<suite>/` and a `curl` per-file fallback, so the signed top-level metadata and by-hash dirs arrive byte-identical even on a wget-less runner.
- Excluded verbatim suites from `total_other_count` (not just from the inner loop) so the entire Step 4 conf-rebuild/re-include block is bypassed when every OTHER suite is verbatim — avoiding any reprepro touch of a preserved suite.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. All 62 harness assertions (groups A-G) passed on Lima ubuntu-24 on the first run.

## Verification Notes
- `bash -n` clean on `scripts/ci_publish.sh` and `tests/test_repo_assemble_byhash.sh`.
- `tests/test_repo_assemble_byhash.sh` SKIPs cleanly (exit 0) on the macOS dev host.
- Full harness executed on Lima ubuntu-24: **62 passed, 0 failed**, Test groups A-G all present. Group D (24.04 no-clobber) and Group E (empty-but-signed stable-2604, D-14) still pass — the verbatim change does not regress the 24.04 fresh-feed path or first-deploy tolerance. Group F (Plan 05 pipefail isolation) still passes. Group G (new) proves the bare alias is byte-stable across a 26.04 publish.
- ShellCheck is not installed on the macOS dev host nor on the ubuntu-24 VM; `bash -n` was used per the AGENTS.md "works anywhere" convention. Recommend running ShellCheck in CI to satisfy the AGENTS.md expectation.

## Next Phase Readiness
- CR-02 BLOCKER closed: 26.04 publishes preserve signature stability for the suites they do not change (REPO-08 SC-3 no CDN hash-sum mismatches; SC-4 no clobbering of other suites). WR-04 closed. The phase's two gap-closure plans (05, 06) are both complete; recommend a verifier re-run to confirm the gaps are resolved.

## Self-Check: PASSED

All modified files present on disk; both task commits (`fff4fa7`, `7c38734`) present in git history.
