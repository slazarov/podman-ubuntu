---
phase: 20-repository-restructure-migration-aliases
plan: 05
subsystem: infra
tags: [reprepro, gpg, apt-repository, by-hash, pipefail, bash]

# Dependency graph
requires:
  - phase: 20-repository-restructure-migration-aliases (Plan 02)
    provides: add_byhash_and_resign cp+gpg bolt-on around reprepro Release output
  - phase: 20-repository-restructure-migration-aliases (Plan 03)
    provides: ci_publish.sh mirror-then-include multi-suite publish (sources the helper under set -euo pipefail)
provides:
  - Pipefail-isolated add_byhash_and_resign that always reaches its re-sign block (CR-01 closed)
  - Anchored secret-key GPG fingerprint extraction in repo_manage.sh (WR-01 closed)
  - Quoted realpath toolpath bootstrap in config.sh, repo_byhash.sh, repo_manage.sh, ci_publish.sh (WR-03 closed)
  - Test group F regression in test_repo_assemble_byhash.sh (deleted-index survival + signature chain + option restore)
affects: [phase-21, ci-publish, apt-repository]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "RETURN-trap option restore: save caller options with set +o, drop errexit/pipefail locally, restore via a single 'trap eval RETURN' so every return path is covered"

key-files:
  created: []
  modified:
    - scripts/repo_byhash.sh
    - tests/test_repo_assemble_byhash.sh
    - scripts/repo_manage.sh
    - config.sh
    - scripts/ci_publish.sh

key-decisions:
  - "CR-01 fix uses the RETURN-trap option-restore form (set +e +o pipefail + trap 'eval _saved_opts' RETURN) as the single restore point, not awk-free rewrites — the function never re-enables set -e/pipefail itself"
  - "WR-01 uses gpg --list-secret-keys with an anchored /^fpr:/ awk match at both sites, deterministically selecting the actual signing key on a multi-key keyring"

patterns-established:
  - "Helpers sourced under an inherited set -euo pipefail isolate themselves with a saved-options + RETURN-trap prologue so a benign non-zero pipe head cannot abort a destructive-then-regenerate sequence"

requirements-completed: [REPO-08]

# Metrics
duration: 4min
completed: 2026-06-07
---

# Phase 20 Plan 05: CR-01 Pipefail Isolation + WR-01/WR-03 Gap Closure Summary

**Pipefail-isolated add_byhash_and_resign (RETURN-trap option restore) so the destructive rm of InRelease/Release.gpg is always followed by a re-sign, plus anchored secret-key GPG fingerprint extraction and quoted realpath bootstraps.**

## Performance

- **Duration:** ~4 min
- **Completed:** 2026-06-07
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Closed verification GAP 1 / CR-01 (BLOCKER): `add_byhash_and_resign` can no longer abort mid-function under the caller's `set -euo pipefail` after removing `InRelease`/`Release.gpg` but before re-signing — eliminating the half-signed-suite publish path (T-20-14).
- Closed WR-01: both GPG fingerprint reads in `repo_manage.sh` now use the anchored `gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}'` form, deterministically selecting the signing key on a multi-key keyring (T-20-15).
- Closed WR-03: all four realpath toolpath bootstraps now quote the path argument, so a checkout path containing a space resolves correctly (T-20-16).
- Added Test group F to the integration harness (F-1 deleted-index survival + valid signature chain, F-2 non-abort + InRelease/Release.gpg exist and verify, F-3 caller shell options unchanged across the call).

## Task Commits

Each task was committed atomically:

1. **Task 1: Pipefail isolation + regression test (tdd)** - `9604060` (fix)
2. **Task 2: Anchored GPG key extraction + quoted realpath bootstrap** - `2961b67` (fix)

_Task 1 was authored as a single fix commit: the implementation and Test group F travel together because the harness SKIPs on the macOS dev host (no reprepro/gpg) and runs RED→GREEN only on Lima ubuntu-24, where the fix is already present._

## Files Created/Modified
- `scripts/repo_byhash.sh` - Added pipefail-isolation prologue (`local _saved_opts; set +e +o pipefail; trap 'eval "${_saved_opts}"' RETURN`) to `add_byhash_and_resign`; consolidated `local cmd rh` once at function top (IN-02); quoted realpath bootstrap.
- `tests/test_repo_assemble_byhash.sh` - Added "Test group F: CR-01 pipefail isolation regression" (F-1/F-2/F-3) building on the assembled `${OUT}` tree, behind the existing macOS SKIP guard and isolated GNUPGHOME.
- `scripts/repo_manage.sh` - Both `GPG_KEY_ID` reads now anchored secret-key form; quoted realpath bootstrap.
- `config.sh` - Quoted realpath bootstrap.
- `scripts/ci_publish.sh` - Quoted realpath bootstrap.

## Decisions Made
- Used the RETURN-trap option-restore form (as given in 20-REVIEW.md CR-01) rather than the awk-free alternative — it covers all return paths (early `return 0`, normal end) from a single restore point and keeps the diff minimal.
- Applied the IN-02 `local cmd rh` consolidation while touching the function, removing the per-iteration `local rh` re-declaration inside the `for algo` loop.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. The acceptance grep for the anchored secret-key form returned a transient `0` only because `awk -F:` confused the verification grep pattern; a direct `grep -n 'list-secret-keys'` confirmed both sites (lines 112 and 193) carry the anchored form.

## Verification Notes
- `bash -n` clean on all four touched scripts and the harness.
- ShellCheck is not installed on the macOS dev host; `bash -n` was used per AGENTS.md ("works anywhere") convention. Run ShellCheck on Lima/CI to satisfy the AGENTS.md expectation.
- `tests/test_repo_assemble_byhash.sh` SKIPs cleanly (exit 0) on macOS as designed; the new Test group F runs only on the reprepro/gpg path.
- Existing pure-function suites pass on macOS: `test_byhash_parse.sh`, `test_suite_routing.sh`, `test_alias_routing.sh`, `test_distributions_suites.sh`.

## Deferred to Lima ubuntu-24 / CI
- Real execution of `tests/test_repo_assemble_byhash.sh` (including Test group F F-1/F-2/F-3 all PASS, 0 failures) on the Lima `ubuntu-24` VM, and ShellCheck over the touched scripts. The macOS dev host has no reprepro/gpg/dpkg-deb, so the assertions can only be proven on Ubuntu:
  `limactl shell ubuntu-24 -- bash -c 'cd /opt/podman-debian && bash tests/test_repo_assemble_byhash.sh'`

## Next Phase Readiness
- CR-01 BLOCKER closed; the multi-suite publish can no longer leave a half-signed repository on Pages. The two WARNING fixes harden the signing-key selection and the toolpath bootstrap.
- Recommend a verifier re-run after the Lima/CI Test group F execution confirms 0 failures.

## Self-Check: PASSED

All modified files present on disk; both task commits (`9604060`, `2961b67`) present in git history.
