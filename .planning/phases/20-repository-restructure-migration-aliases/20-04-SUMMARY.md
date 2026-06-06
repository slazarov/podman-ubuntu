---
phase: 20-repository-restructure-migration-aliases
plan: 04
subsystem: infra
tags: [reprepro, gpg, acquire-by-hash, apt, integration-test, no-clobber, lima, bash]

# Dependency graph
requires:
  - phase: 20-01
    provides: "9-stanza distributions + resolve_publish_targets routing/alias contract"
  - phase: 20-02
    provides: "scripts/repo_byhash.sh add_byhash_and_resign() post-export by-hash + re-sign"
  - phase: 20-03
    provides: "track+distro-aware repo_manage.sh + 9-suite mirror-then-include ci_publish.sh"
provides:
  - "tests/test_repo_assemble_byhash.sh: Ubuntu-only integration harness (assemble -> by-hash -> gpg verify -> no-clobber -> empty-but-signed), SKIPs on macOS"
  - "On-VM proof (Lima ubuntu-24): real reprepro/gpg assemble passes 48/0 and the full tests/*.sh suite is green"
affects: [gsd-verify-work, migration-aliases]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Ubuntu-only integration harness: command-v guard SKIPs on macOS, runs a real reprepro includedeb + per-suite export on the Lima VM"
    - "Isolated throwaway GNUPGHOME under mktemp with gpgconf --kill all + rm -rf on EXIT (no host keyring mutation, no committed key)"
    - "Direct-assemble proof path: drive repo_manage.sh (the assemble core ci_publish.sh wraps) then source repo_byhash.sh per suite, isolating the assemble+by-hash+signature behaviors from the mirror-down/URL plumbing"

key-files:
  created:
    - tests/test_repo_assemble_byhash.sh
  modified: []

key-decisions:
  - "Used the plan's documented direct-assemble alternative (repo_manage.sh + add_byhash_and_resign per suite) rather than driving full ci_publish.sh against a file:// URL — keeps the proof focused on REPO-08/Criterion-4/REPO-06 behaviors"
  - "ed25519 batch keygen with an RSA-3072 fallback for older gpg builds; key trusted ultimately via import-ownertrust"
  - "Empty-but-signed stable-2604 exported directly with reprepro (repo_manage.sh requires .deb files), then by-hashed/re-signed, proving D-14"
  - "no-clobber proven by capturing edge-2404 Packages SHA256 before a stable-2404-only re-publish and asserting byte-identity after"

patterns-established:
  - "Pattern: production-critical reprepro/gpg/apt behaviors are authored on macOS (bash -n + SKIP) and proven on the Lima ubuntu-24 VM in a dedicated integration harness"

requirements-completed: []
requirements-partial: [REPO-06, REPO-08]

# Metrics
duration: 3min
completed: 2026-06-06
---

# Phase 20 Plan 04: On-Host Integration Proof (assemble + by-hash + no-clobber + legacy-client) Summary

**Authored `tests/test_repo_assemble_byhash.sh` — an Ubuntu-only integration harness that assembles the multi-suite repo on a real reprepro/gpg host, applies by-hash + re-sign, and asserts Acquire-By-Hash, by-hash layout, signature-chain validity after mutation, no-clobber, and empty-but-signed -2604 — and proved it green (48/0) plus the full unit suite on the Lima ubuntu-24 VM. The deployed-Pages legacy-client (REPO-07) and live by-hash proofs (steps 3-4) are deferred to the human checkpoint, as they require the production CDN.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-06-06T20:46:03Z
- **Completed:** 2026-06-06T20:49:16Z
- **Tasks:** 2 (Task 1 complete; Task 2 is a blocking human-action checkpoint — steps 1-2 executed on the VM, steps 3-4 deferred)
- **Files modified:** 1 (1 created)

## Accomplishments

- **Task 1 — integration harness authored and proven.** `tests/test_repo_assemble_byhash.sh` follows the project test skeleton (assert helpers, summary tail) and is Ubuntu-only: it SKIPs cleanly when reprepro/gpg/dpkg-deb/sha256sum are not all present (the macOS dev host), and on a reprepro/gpg host it:
  - generates a throwaway ed25519 (RSA-fallback) GPG key in an isolated `GNUPGHOME` under `mktemp`, trusted ultimately, with `gpgconf --kill all` + `rm -rf` on EXIT;
  - builds four tiny fixture .debs (`podman-suite` and `conmon-suite`, amd64+arm64, versioned `~ubuntu24.04.podman1`) via `dpkg-deb --build`;
  - assembles `stable 2404` and `edge 2404` through `repo_manage.sh` (exercising the versioned suite + bare alias D-12 path), exports an empty `stable-2604` directly (D-14), and applies `add_byhash_and_resign` per suite;
  - asserts REPO-08, Criterion 4, and REPO-06.
- **Verified on Lima ubuntu-24:** `reprepro` installed (distro package, sanctioned T-20-SC), harness runs **48 passed, 0 failed**, exit 0. A1 confirmed: reprepro emits MD5Sum/SHA1/SHA256 in the Release (SHA256 is the strongest available, asserted).
- **Full unit suite green on the VM:** all `tests/*.sh` pass on ubuntu-24 (Plans 01-03 tests + this harness). `test_extract_version_nightly.sh` initially errored only because the VM's git had no configured identity (it shells out to `git`); after setting a throwaway `user.email`/`user.name` it passes 9/0. This is an environmental gap in the VM, not a Phase-20 regression.

## On-VM / On-Pages Verification Results (Task 2)

| Step | Requirement | Where | Result |
|------|-------------|-------|--------|
| 1. Integration harness | REPO-06/REPO-08/Criterion 4 | Lima ubuntu-24 | **PASS** — `Results: 48 passed, 0 failed`, exit 0 |
| 2. Full test suite | Plans 01-03 unit regression | Lima ubuntu-24 | **PASS** — all `tests/*.sh` green (nightly test needs a git identity in the VM; passes once set) |
| 3. Deployed legacy-client (no Suite-change prompt + 24.04 resolve) | REPO-07 (D-15) | Deployed GitHub Pages | **DEFERRED** — requires the 9-suite tree deployed to the production CDN + real REPO_URL; manual-only per 20-VALIDATION.md |
| 4. Live by-hash fetch returns 200 | REPO-08 on production | Deployed GitHub Pages | **DEFERRED** — requires the deployed CDN |

Steps 1-2 constitute the pre-deploy gate and are fully green. Steps 3-4 are production-CDN behaviors that cannot run from the dev host (no deployed repo URL yet) and are surfaced for the human at the blocking checkpoint.

## Task Commits

1. **Task 1: Author the Ubuntu-only assemble + by-hash + no-clobber integration harness** — `00b88a2` (test)

## Files Created/Modified

- `tests/test_repo_assemble_byhash.sh` — Ubuntu-only integration harness. SKIP guard on macOS; isolated throwaway GNUPGHOME; fixture .deb builder; assemble via repo_manage.sh (stable/edge 2404) + direct empty stable-2604 export; per-suite `add_byhash_and_resign`; assertion groups A (Acquire-By-Hash), B (by-hash adjacency + byte-identity, strongest algo), C (gpg --verify InRelease + Release.gpg after mutation), D (no-clobber), E (empty-but-signed -2604).

## Decisions Made

- Drove the proof via `repo_manage.sh` + per-suite `add_byhash_and_resign` (the plan's documented direct-assemble alternative) rather than `ci_publish.sh` against a `file://` URL — isolates the REPO-08/Criterion-4/REPO-06 behaviors from the mirror-down/URL/index.html plumbing, which is exercised separately in CI on real deploy.
- ed25519 batch keygen with an RSA-3072 fallback so the harness works across gpg builds; ownertrust set to ultimate to avoid verify warnings.
- Empty `stable-2604` exported directly with `reprepro export` (repo_manage.sh requires .deb files) then by-hashed and re-signed, proving the empty-but-signed D-14 path end to end.

## Deviations from Plan

None affecting code. The plan's Task 1 `<verify>` runs `bash tests/test_repo_assemble_byhash.sh` — on macOS this SKIPs (by design); the real pass was obtained on the Lima ubuntu-24 VM per CLAUDE.md and the executor environment note. No source behavior changed.

## Issues Encountered

- `test_extract_version_nightly.sh` errored on the VM until a git `user.email`/`user.name` was configured (the test shells out to `git`). Environmental, not a Phase-20 defect; passes 9/0 once set. Logged here for transparency — out of scope for code changes (SCOPE BOUNDARY).
- ShellCheck is a project convention but is not installed on the macOS dev host; `bash -n` is clean and the harness runs green on the VM.

## Threat Surface

No new surface beyond the plan's `<threat_model>`. T-20-12 (invalid signature chain after by-hash mutation) is now positively disproven on a real host: `gpg --verify InRelease` and `gpg --verify Release.gpg Release` pass for every populated suite AND for the empty stable-2604 after `add_byhash_and_resign` re-signs. T-20-13 (test key contaminating the host keyring) is mitigated by the isolated `GNUPGHOME` + `gpgconf --kill all` + `rm -rf` EXIT trap. T-20-SC: only `reprepro` (distro-packaged) was apt-installed on the VM — no npm/PyPI/crates. T-20-11 (legacy-client Suite-change prompt) remains the deferred deploy-gated proof (Task 2 step 3).

## User Setup Required

To close Task 2 (the blocking human-action checkpoint), after the Phase-20 changes are deployed to GitHub Pages run, on the Lima ubuntu-24 VM, the deferred steps 3-4 from the plan against the real `REPO_URL` (legacy-client bare-`stable` `apt update` must show no "changed its 'Suite' value" line and `apt-cache policy podman-suite` must show a `~ubuntu24.04.podman1` candidate; a live by-hash fetch must return HTTP 200). See the checkpoint return for exact commands.

## Next Phase Readiness

- Pre-deploy gate is green: the assembled multi-suite repo is by-hash-equipped, signature-valid after mutation, no-clobbering, and empty-but-signed for -2604 on a real reprepro/gpg host (REPO-06, REPO-08, Criterion 4 proven).
- Remaining before `/gsd-verify-work`: the deployed-Pages legacy-client continuity proof (REPO-07, closes the STATE.md research flag) and the live by-hash 200 — both deploy-gated, awaiting the publish job + human verification at the Task 2 checkpoint.

## Self-Check: PASSED

- FOUND: tests/test_repo_assemble_byhash.sh
- FOUND commit: 00b88a2 (Task 1)
- Harness verified green on Lima ubuntu-24 (48 passed, 0 failed); full tests/*.sh suite green.

---
*Phase: 20-repository-restructure-migration-aliases*
*Completed: 2026-06-06 (Task 1 + Task 2 steps 1-2; Task 2 steps 3-4 deferred to blocking human checkpoint)*
