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

**Authored `tests/test_repo_assemble_byhash.sh` — an Ubuntu-only integration harness that assembles the multi-suite repo on a real reprepro/gpg host, applies by-hash + re-sign, and asserts Acquire-By-Hash, by-hash layout, signature-chain validity after mutation, no-clobber, and empty-but-signed -2604 — and proved it green (48/0) plus the full unit suite on the Lima ubuntu-24 VM. The legacy-client continuity (REPO-07) and by-hash-over-HTTP (REPO-08) apt-client semantics (steps 3-4) are now proven via a local-VM D-15 simulation (old 3-stanza tree → new 9-suite tree swapped at a constant URL: `apt-get update` shows no Suite-change prompt, a `~ubuntu24.04.podman1` candidate resolves from bare `stable`, by-hash fetch returns 200) — 9/0. The production-URL/CDN confirmation remains deferred until the first CI publish of the 9-suite tree.**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-06-06T20:46:03Z
- **Completed:** 2026-06-06T20:49:16Z
- **Tasks:** 2 (Task 1 complete; Task 2 steps 1-2 executed on the VM, steps 3-4 resolved via local-VM D-15 simulation — production-URL smoke deferred to first CI publish)
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
| 3. Legacy-client (no Suite-change prompt + 24.04 resolve) | REPO-07 (D-15) | Lima ubuntu-24 (local-VM D-15 simulation) | **PASS (simulated)** — validated via local-VM D-15 simulation (apt-client semantics proven); production-URL confirmation deferred until first CI publish of the 9-suite tree |
| 4. by-hash fetch returns 200 | REPO-08 (apt-client) | Lima ubuntu-24 (local-VM D-15 simulation) | **PASS (simulated)** — by-hash HTTP 200 on bare `stable` and versioned `stable-2404`; production-CDN confirmation deferred until first CI publish |

Steps 1-2 constitute the pre-deploy gate and are fully green. Steps 3-4 are now **validated via a local-VM D-15 simulation** that swaps an old-tree (pre-restructure 3-stanza, bare `stable`) for the new 9-suite tree at a constant `localhost` URL, proving the apt-client semantics without the production deploy. The production-URL/CDN confirmations remain deferred until the first CI publish of the 9-suite tree.

### Local-VM D-15 simulation (steps 3-4)

Old-tree → new-tree swap at a constant URL on Lima ubuntu-24, all entirely VM-local (no production repo touched). The dummy package carries `~ubuntu24.04.podman1`; the VM is arm64 so the fixture `.deb` is arm64 (apt only considers the native arch for the policy candidate).

1. **Old tree** assembled from `git show dafa53c^:packaging/repo/conf/distributions` (the 3-stanza pre-restructure config), `includedeb` into bare `stable`, exported, signed with a throwaway ed25519 key. Served via `python3 -m http.server 8099`. A bare-`stable` `.sources` (`deb [signed-by=...] http://localhost:8099 stable main`) → `apt-get update` succeeds, caching the OLD `Suite` metadata.
2. **New tree** assembled with the ACTUAL phase-20 tooling — `scripts/repo_manage.sh stable 2404 <debdir> <out>` (populates `stable-2404` + bare `stable` alias, D-12), a direct empty-but-signed `stable-2604` export, then `add_byhash_and_resign` per exported suite — with the SAME throwaway key and SAME dummy `.deb`. Served directory contents swapped in place at the same port/URL.
3. **Re-update against the swapped tree** (`/tmp/legacy-update.log`):
   - `apt-get update` exit 0,
   - **NO line matching `changed its 'Suite' value`** (REPO-07 / T-20-11 — the definitive legacy-continuity proof against an apt client that had cached the old bare-`stable` Suite),
   - no `does not have a Release file`, no `Conflicting distribution`, no `E:` lines,
   - `apt-cache policy podman-suite` → `Candidate: 5.0.0~ubuntu24.04.podman1` (24.04 routing from bare `stable`).
4. **by-hash over HTTP**: `sha256sum` of the served `dists/<suite>/main/binary-arm64/Packages` → `curl .../by-hash/SHA256/<hash>` returns **HTTP 200** on both bare `stable` and versioned `stable-2404` (REPO-08).

**Result: 9 passed, 0 failed.** VM left clean — sources entry, keyring, http server, and `/tmp/d15-sim` all removed (verified post-run: no `podman-d15-sim.list`, no `podman-d15-sim.gpg`, no `/tmp/d15-sim`, zero `http.server 8099` processes).

### Production-URL checks that remain deferred

After the Phase-20 changes are deployed to GitHub Pages (publish job on push/merge of the 9-suite tree), re-run, on the Lima ubuntu-24 VM against the real `REPO_URL`:

```bash
# REPO-07 (D-15/D-17) — legacy bare-stable client against the production CDN:
limactl shell ubuntu-24 -- bash -c 'cd /opt/podman-debian && curl -fsSL <REPO_URL>/podman-ubuntu.gpg | sudo tee /usr/share/keyrings/podman-ubuntu.gpg >/dev/null && echo "deb [signed-by=/usr/share/keyrings/podman-ubuntu.gpg] <REPO_URL> stable main" | sudo tee /etc/apt/sources.list.d/podman-legacy.list && sudo apt-get update 2>&1 | tee /tmp/legacy-update.log'
limactl shell ubuntu-24 -- bash -c '! grep -q "changed its .Suite. value" /tmp/legacy-update.log && apt-cache policy podman-suite 2>&1 | grep -q "~ubuntu24.04.podman1" && echo LEGACY-OK'

# REPO-08 — live by-hash fetch against the deployed CDN:
limactl shell ubuntu-24 -- bash -c 'curl -fsSL -o /dev/null -w "%{http_code}\n" <REPO_URL>/dists/stable/main/binary-amd64/by-hash/SHA256/$(curl -fsSL <REPO_URL>/dists/stable/main/binary-amd64/Packages | sha256sum | cut -d" " -f1)'
```

Expect: `apt-get update` exit 0, NO "changed its 'Suite' value" line, `apt-cache policy` shows a `~ubuntu24.04.podman1` candidate, and the by-hash fetch returns HTTP 200.

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

No new surface beyond the plan's `<threat_model>`. T-20-12 (invalid signature chain after by-hash mutation) is now positively disproven on a real host: `gpg --verify InRelease` and `gpg --verify Release.gpg Release` pass for every populated suite AND for the empty stable-2604 after `add_byhash_and_resign` re-signs. T-20-13 (test key contaminating the host keyring) is mitigated by the isolated `GNUPGHOME` + `gpgconf --kill all` + `rm -rf` EXIT trap. T-20-SC: only `reprepro` (distro-packaged) was apt-installed on the VM — no npm/PyPI/crates. **T-20-11 (legacy-client Suite-change prompt) is now positively disproven via the local-VM D-15 simulation**: an apt client that cached the OLD bare-`stable` Suite re-updates against the NEW 9-suite tree at the same URL with NO "changed its 'Suite' value" prompt and resolves the 24.04 candidate. The production-CDN re-confirmation of this same behavior is deferred to the first CI publish (commands in the verification-results section above).

## User Setup Required

Task 2's apt-client semantics (steps 3-4) are now proven via the local-VM D-15 simulation above. The only remaining action is the **production-URL confirmation** after the 9-suite tree is first published to GitHub Pages by the CI publish job: re-run the deferred commands (listed in the "Production-URL checks that remain deferred" section) on the Lima ubuntu-24 VM against the real `REPO_URL`. This is a confirmation against the production CDN, not a gate on this plan — the apt-client behavior it checks is already proven locally.

## Next Phase Readiness

- Pre-deploy gate is green: the assembled multi-suite repo is by-hash-equipped, signature-valid after mutation, no-clobbering, and empty-but-signed for -2604 on a real reprepro/gpg host (REPO-06, REPO-08, Criterion 4 proven).
- Legacy-client continuity (REPO-07, closes the STATE.md research flag) and by-hash-over-HTTP (REPO-08) apt-client semantics are now proven via the local-VM D-15 simulation (old→new swap at a constant URL): no Suite-change prompt, 24.04 candidate resolves from bare `stable`, by-hash HTTP 200. The phase gate before `/gsd-verify-work` is satisfied.
- Production smoke deferred: the same behavior should be re-confirmed against the deployed Pages CDN after the first CI publish of the 9-suite tree (commands recorded above). This is a production smoke check, not a blocker for this plan.

## Self-Check: PASSED

- FOUND: tests/test_repo_assemble_byhash.sh
- FOUND commit: 00b88a2 (Task 1)
- Harness verified green on Lima ubuntu-24 (48 passed, 0 failed); full tests/*.sh suite green.
- Local-VM D-15 simulation verified green on Lima ubuntu-24 (9 passed, 0 failed): old→new swap, no Suite-change prompt, `~ubuntu24.04.podman1` candidate resolves, by-hash HTTP 200 on bare `stable` + `stable-2404`.
- VM left clean post-run: no `podman-d15-sim` sources/keyring, no `/tmp/d15-sim`, zero `http.server 8099` processes.

---
*Phase: 20-repository-restructure-migration-aliases*
*Completed: 2026-06-07 (Task 1 + Task 2 steps 1-2 on the VM; Task 2 steps 3-4 resolved via local-VM D-15 simulation; production-URL smoke deferred to first CI publish)*
