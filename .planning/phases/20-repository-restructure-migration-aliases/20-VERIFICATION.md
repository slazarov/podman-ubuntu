---
phase: 20-repository-restructure-migration-aliases
verified: 2026-06-07T00:00:00Z
status: gaps_found
score: 3/4
overrides_applied: 0
gaps:
  - truth: "Repository metadata includes Acquire-By-Hash: yes on every suite, so apt clients fetching from the GitHub Pages CDN never hit a hash-sum mismatch (REPO-08, SC-3)"
    status: partial
    reason: "add_byhash_and_resign() runs under inherited set -euo pipefail. The Release-self by-hash loop (lines 72-79) assigns rh via `local rh; rh=$(sha256sum ... | awk ...)`. When rh is pre-declared via `local` and assigned separately, bash propagates pipefail from the pipe head to the outer assignment — confirmed with `false | awk` under bash 5.3. This can abort the function mid-way after InRelease/Release.gpg have been removed (line 83) but before re-signing, leaving the repository in a half-signed state on GitHub Pages. This is CR-01 from the code review, unaddressed in the codebase."
    artifacts:
      - path: "scripts/repo_byhash.sh"
        issue: "Lines 72-79: `local rh; rh=$(${cmd} \"${lrelease}\" | awk ...)` under inherited set -euo pipefail can abort the function on a pipe-head failure, leaving InRelease/Release.gpg deleted but not regenerated. No pipefail isolation (set +e/+o pipefail) in the function."
    missing:
      - "Wrap add_byhash_and_resign body with pipefail isolation: `local _opts; _opts=$(set +o); set +e +o pipefail; trap 'eval \"${_opts}\"' RETURN` at function entry, OR split the pipe so the assignment is never subject to the pipe head's exit status"
      - "Add a regression test case to test_repo_assemble_byhash.sh for the pipefail abort scenario"
  - truth: "The publish tooling routes a given track's packages into the correct <track>-<distro> suite without clobbering the other five suites' contents (SC-4)"
    status: partial
    reason: "For a 26.04 publish (DISTRO=2604), resolve_publish_targets returns only [<track>-2604]. The bare alias (<track>) is NOT a publish target, so it is placed in OTHER_SUITES (ci_publish.sh:113-125, confirmed by test). In Step 4 (lines 214-237), the bare alias's mirrored debs are re-includedeb'd and re-exported into the bare suite with a fresh reprepro db, regenerating its Release with a new Date and new signature — even though the package content is byte-identical. This re-signing reopens the CDN hash-mismatch window that Acquire-By-Hash is designed to prevent: an apt client can see a new InRelease (different signature) served against a stale by-hash index, exactly the failure mode REPO-08 addresses. No test exercises a 26.04 publish path; the integration harness only tests 24.04 publishes. This is CR-02 from the code review, unaddressed in the codebase."
    artifacts:
      - path: "scripts/ci_publish.sh"
        issue: "Lines 113-125: for DISTRO=2604, OTHER_SUITES includes the bare alias (stable/edge/nightly). Lines 214-237: the bare alias is re-included from mirrored debs and re-exported, regenerating Release Date + signature even though package content is unchanged. The no-clobber guarantee as documented applies to package content but the Acquire-By-Hash semantic (signature stability) is not preserved."
      - path: "tests/test_repo_assemble_byhash.sh"
        issue: "No 26.04 publish path is exercised. The no-clobber test (lines 310-338) only uses stable-2404 publishes. The bare-alias re-export behavior on a 26.04 publish is entirely untested."
    missing:
      - "Either treat the bare alias as a first-class target on 26.04 publishes (exclude it from re-include/re-export; mirror its dists/ tree verbatim), or add a test that publishes a 26.04 track and asserts the bare alias Release Date/signature is preserved before and after"
      - "Add a test case to test_repo_assemble_byhash.sh that runs a 26.04 assemble and asserts the bare alias is NOT re-signed when its content is unchanged"
deferred: []
human_verification:
  - test: "Production-URL validation: after the 9-suite tree is first published to GitHub Pages by CI, run the deferred steps from 20-04-SUMMARY.md against the real REPO_URL"
    expected: "apt-get update against bare stable succeeds with no 'changed its Suite value' prompt; apt-cache policy resolves a ~ubuntu24.04.podman1 candidate; by-hash fetch returns HTTP 200 from the production CDN"
    why_human: "Production CDN behavior cannot be verified without an actual deploy. The local-VM D-15 simulation proved apt semantics; CDN caching behavior requires real Pages serving."
---

# Phase 20: Repository Restructure & Migration Aliases — Verification Report

**Phase Goal:** The APT repository serves all six versioned suites from a single URL under one GPG key, while existing users on bare suite names keep receiving 24.04 packages with no client-side change
**Verified:** 2026-06-07T00:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Repository serves six versioned suites from one URL with one GPG key; apt update against any suite succeeds with valid signatures (SC-1, REPO-06) | VERIFIED | `packaging/repo/conf/distributions` has exactly 9 stanzas (6 versioned + 3 aliases), all with `SignWith: yes`. `resolve_publish_targets` routing is wired through `repo_manage.sh` and `ci_publish.sh`. Integration harness ran 48/48 on Lima ubuntu-24 proving real reprepro export + gpg --verify pass for all assembled suites. |
| 2 | Existing users with bare stable/edge/nightly in .sources receive 24.04 packages with no client-side change (SC-2, REPO-07) | VERIFIED | Bare alias stanzas carry `Suite: stable`/`edge`/`nightly` (not `-2404`), which is the REPO-07 mechanism. D-15 local-VM simulation proved `apt-get update` against old-tree then new-tree at same URL produced no "changed its 'Suite' value" prompt and `~ubuntu24.04.podman1` candidate resolved. Production-URL confirmation deferred (see Human Verification). |
| 3 | Repository metadata includes Acquire-By-Hash: yes on every suite; CDN hash-sum mismatches are prevented (SC-3, REPO-08) | PARTIAL — FAILED | `scripts/repo_byhash.sh` `add_byhash_and_resign()` implements the injection and re-sign. Integration harness verified it works on a real reprepro host. However, CR-01 from the code review is unaddressed: the function body runs under inherited `set -euo pipefail`; the pattern `local rh; rh=$(sha256sum ... \| awk ...)` propagates pipefail from the pipe head and can abort mid-function after removing InRelease/Release.gpg but before re-signing, leaving a half-signed repo. Confirmed: `bash -c 'set -euo pipefail; f() { local rh; rh="$(false \| awk "{print \$1}")"; }; f'` exits non-zero. |
| 4 | Publish tooling routes packages into the correct suite without clobbering other suites' contents (SC-4, REPO-06/07) | PARTIAL — FAILED | For 24.04 publishes, the mirror-then-include no-clobber property is proven by the integration harness (48/48). For 26.04 publishes (DISTRO=2604), the bare aliases (stable/edge/nightly) land in OTHER_SUITES and are re-included from mirrored debs then re-exported — regenerating Release Date + signature despite unchanged package content. This reopens the CDN hash-mismatch window Acquire-By-Hash is designed to prevent (CR-02 from code review, confirmed by examining ci_publish.sh:113-125 and tracing `resolve_publish_targets stable 2604`). No test covers a 26.04 publish path in the integration harness. |

**Score:** 2/4 truths fully verified (SC-1 and SC-2); SC-3 and SC-4 are partial (implementation present, correctness defects unresolved)

### Deferred Items

None.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `packaging/repo/conf/distributions` | 9-stanza reprepro config (6 versioned + 3 aliases) | VERIFIED | 9 Suite lines, 9 Codename lines, 9 SignWith:yes lines; bare aliases carry Suite:stable/edge/nightly; 6 versioned suites present; 3 DEPRECATED descriptions; no createsymlinks |
| `config.sh` | Suite whitelist arrays + resolve_publish_targets routing helper | VERIFIED | `VALID_TRACKS`, `VALID_DISTROS`, `ALL_SUITES` declared at file scope; `is_valid_suite()` and `resolve_publish_targets()` defined at column 0; D-12 alias rule implemented |
| `tests/test_distributions_suites.sh` | Parse-assertion of 9-stanza distributions file | VERIFIED | 15/15 assertions pass on macOS |
| `tests/test_suite_routing.sh` | Routing + whitelist-rejection unit test | VERIFIED | 8/8 assertions pass on macOS |
| `tests/test_alias_routing.sh` | 24.04-includes-alias / 26.04-excludes-alias unit test | VERIFIED | 12/12 assertions pass on macOS |
| `scripts/repo_byhash.sh` | Post-export by-hash + re-sign helper | STUB-RISK | File exists; `add_byhash_and_resign()` implements injection + re-sign; wired into ci_publish.sh. Defect: body runs under inherited pipefail with no isolation — can abort mid-function (CR-01). |
| `tests/test_byhash_parse.sh` | Release-section parser unit test | VERIFIED | 8/8 assertions pass on macOS |
| `scripts/repo_manage.sh` | Track+distro-aware single-publish builder | VERIFIED | `<track> <distro> <deb-dir> [output]` CLI; routes via `resolve_publish_targets`; feeds PUBLISH_TARGETS loop; per-target export; empty-target guard present |
| `scripts/ci_publish.sh` | 9-suite mirror-then-include publisher with by-hash post-processing | PARTIAL | Sources repo_byhash.sh; calls `add_byhash_and_resign` per suite; 9-suite ALL_SUITES consumed from config.sh; index.html iterates ALL_SUITES. Defect: for DISTRO=2604, bare aliases land in OTHER_SUITES and are re-exported (CR-02) |
| `.github/workflows/build-packages.yml` | Publish job with distro argument | VERIFIED | `distro=2404` step output added; ci_publish.sh invoked with `steps.track.outputs.distro` as second positional; YAML is valid |
| `tests/test_repo_assemble_byhash.sh` | Ubuntu-only integration harness | PARTIAL | Syntax-clean; SKIPs on macOS; ran 48/48 on Lima ubuntu-24; covers 24.04 publishes, by-hash, no-clobber, empty-but-signed-2604. Does NOT test a 26.04 publish path (CR-02 untested). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `tests/test_suite_routing.sh` | `config.sh resolve_publish_targets` | sed-extract + eval | WIRED | Extracts function and arrays via sed, evals and calls directly |
| `packaging/repo/conf/distributions` | apt client cached Suite value | bare alias stanza Suite: stable | WIRED | `grep -q '^Suite: stable$'` succeeds; bare aliases confirmed without -2404 suffix |
| `scripts/ci_publish.sh` | `config.sh resolve_publish_targets / ALL_SUITES` | sourced; mapfile from process substitution | WIRED | Lines 83, 114 both reference; `OTHER_SUITES` derived from `ALL_SUITES` |
| `scripts/ci_publish.sh` | `scripts/repo_byhash.sh add_byhash_and_resign` | source at line 24; loop at lines 259-264 | WIRED | Sourced near top; called for every suite with a Release |
| `.github/workflows/build-packages.yml publish job` | `scripts/ci_publish.sh` | 5-arg invocation at line 312-314 | WIRED | `track`, `steps.track.outputs.distro`, `deb-dir`, `repo-url`, `output-dir` passed |

### Data-Flow Trace (Level 4)

This phase produces shell tooling (not a web app), so data-flow Level 4 applies to the publish pipeline:

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `scripts/repo_manage.sh` | `PUBLISH_TARGETS` | `resolve_publish_targets()` via `mapfile` | Yes — validated by unit tests and integration harness | FLOWING |
| `scripts/ci_publish.sh` | `ALL_SUITES` | sourced from `config.sh` | Yes — 9-element array confirmed | FLOWING |
| `scripts/ci_publish.sh` | `add_byhash_and_resign` call | `scripts/repo_byhash.sh` sourced | Real — but CR-01 pipefail risk | FLOWING (with defect) |
| `scripts/repo_byhash.sh` | by-hash copies + Acquire-By-Hash injection | Real Release file from reprepro export | Yes — 48/48 on VM | FLOWING (with CR-01 fragility) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `resolve_publish_targets stable 2404` returns two lines | `bash tests/test_suite_routing.sh` | 8/8 pass | PASS |
| `resolve_publish_targets edge 2604` returns single line | `bash tests/test_alias_routing.sh` | 12/12 pass | PASS |
| distributions file has 9 Suite lines, bare aliases unsuffixed | `bash tests/test_distributions_suites.sh` | 15/15 pass | PASS |
| byhash Release parser is section-boundary-correct | `bash tests/test_byhash_parse.sh` | 8/8 pass | PASS |
| Integration harness SKIPs on macOS | `bash tests/test_repo_assemble_byhash.sh` | SKIP exit 0 | PASS |
| Integration harness passes on Lima ubuntu-24 | On-VM execution (documented in 20-04-SUMMARY.md) | 48/48 pass | PASS (recorded, not re-run) |
| D-15 legacy-client simulation | On-VM local D-15 sim (documented in 20-04-SUMMARY.md) | 9/9 pass | PASS (recorded, not re-run) |

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| `tests/test_distributions_suites.sh` | `bash tests/test_distributions_suites.sh` | 15 passed, 0 failed | PASS |
| `tests/test_suite_routing.sh` | `bash tests/test_suite_routing.sh` | 8 passed, 0 failed | PASS |
| `tests/test_alias_routing.sh` | `bash tests/test_alias_routing.sh` | 12 passed, 0 failed | PASS |
| `tests/test_byhash_parse.sh` | `bash tests/test_byhash_parse.sh` | 8 passed, 0 failed | PASS |
| `tests/test_repo_assemble_byhash.sh` | `bash tests/test_repo_assemble_byhash.sh` | SKIP on macOS (by design; 48/48 on Lima ubuntu-24 per 20-04-SUMMARY.md) | PASS (SKIP) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| REPO-06 | 20-01, 20-03, 20-04 | Six versioned suites from single URL, one GPG key | SATISFIED | 9-stanza distributions + SignWith:yes on all; routing helper wired; integration harness proves real reprepro export works |
| REPO-07 | 20-01, 20-03, 20-04 | Bare suite aliases serve 24.04 packages, no client-side change | SATISFIED | Bare alias stanzas carry Suite:stable (not stable-2404); D-15 local-VM simulation proved no Suite-change prompt and 24.04 candidate resolves |
| REPO-08 | 20-02, 20-03, 20-04 | Acquire-By-Hash on all suites, no CDN hash-sum mismatches | BLOCKED | Implementation exists and was proven on the VM for 24.04 publishes. CR-01 (pipefail abort risk in add_byhash_and_resign) and CR-02 (bare-alias re-sign on 26.04 publish) are unaddressed defects that can cause production failures: half-signed repos (CR-01) and CDN hash-mismatch windows on 26.04 publishes (CR-02) |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/repo_byhash.sh` | 72-79 | `local rh; rh=$(cmd \| awk)` under inherited `set -euo pipefail` with no isolation | BLOCKER | Can abort `add_byhash_and_resign` mid-execution after removing InRelease/Release.gpg but before re-signing; leaves repo in half-signed state on GitHub Pages (CR-01 from code review) |
| `scripts/ci_publish.sh` | 113-125 | For DISTRO=2604, bare aliases are placed in OTHER_SUITES and subsequently re-exported, regenerating Release Date + signature | BLOCKER | Reopens CDN hash-mismatch window for bare aliases on 26.04 publishes, defeating the REPO-08 protection for those suites (CR-02 from code review) |
| `scripts/repo_manage.sh` | 112, 193 | `gpg --list-keys --with-colons \| grep fpr \| head -1` — unanchored grep, selects first key on keyring regardless of which is the signing key | WARNING | Can export wrong public key to podman-ubuntu.gpg if multiple keys on keyring; clients would fail apt update with GPG verification error (WR-01) |
| `config.sh`, `scripts/ci_publish.sh`, `scripts/repo_manage.sh`, `scripts/repo_byhash.sh` | 8-9 | Unquoted `${scriptpath}/${relativepath}` in `realpath` call | WARNING | Word-splits on paths with spaces; AGENTS.md mandates quoting all expansions (WR-03) |
| `scripts/ci_publish.sh` | 388-405 | Package names/versions from Packages index interpolated directly into HTML with no escaping | WARNING | XSS vector for nightly builds from upstream HEAD; malformed HTML from versions containing `<`/`>` (WR-04) |

### Human Verification Required

#### 1. Production-URL Validation (REPO-07 + REPO-08 on live CDN)

**Test:** After the Phase-20 9-suite tree is first published to GitHub Pages by the CI publish job, run the deferred D-15 and by-hash checks from 20-04-SUMMARY.md against the real `REPO_URL`:

```bash
# REPO-07: legacy bare-stable client against production CDN
limactl shell ubuntu-24 -- bash -c 'cd /opt/podman-debian && curl -fsSL <REPO_URL>/podman-ubuntu.gpg | sudo tee /usr/share/keyrings/podman-ubuntu.gpg >/dev/null && echo "deb [signed-by=/usr/share/keyrings/podman-ubuntu.gpg] <REPO_URL> stable main" | sudo tee /etc/apt/sources.list.d/podman-legacy.list && sudo apt-get update 2>&1 | tee /tmp/legacy-update.log'
limactl shell ubuntu-24 -- bash -c '! grep -q "changed its .Suite. value" /tmp/legacy-update.log && apt-cache policy podman-suite 2>&1 | grep -q "~ubuntu24.04.podman1" && echo LEGACY-OK'

# REPO-08: live by-hash fetch against production CDN
limactl shell ubuntu-24 -- bash -c 'curl -fsSL -o /dev/null -w "%{http_code}\n" <REPO_URL>/dists/stable/main/binary-amd64/by-hash/SHA256/$(curl -fsSL <REPO_URL>/dists/stable/main/binary-amd64/Packages | sha256sum | cut -d" " -f1)'
```

**Expected:** `apt-get update` exit 0; NO "changed its 'Suite' value" line; `apt-cache policy` shows `~ubuntu24.04.podman1` candidate; by-hash fetch returns HTTP 200.

**Why human:** Production CDN behavior (GitHub Pages caching, edge serving) cannot be verified without an actual deploy of the 9-suite tree to the live repo. The local-VM D-15 simulation proved apt semantics; the CDN caching window requires real production data.

---

## Gaps Summary

Two code defects from the code review (20-REVIEW.md) remain unaddressed in the codebase and block the phase goal:

**CR-01 (BLOCKER):** `add_byhash_and_resign()` in `scripts/repo_byhash.sh` runs under the inherited `set -euo pipefail` from `ci_publish.sh`. The pattern `local rh; rh=$(sha256sum ... | awk ...)` — where `rh` is pre-declared on a separate `local` line and assigned separately — propagates pipefail from the pipe head. Confirmed: `bash -c 'set -euo pipefail; f() { local rh; rh="$(false | awk ...)"; }; f'` exits non-zero. On a sha512sum or awk failure, the function aborts after deleting InRelease/Release.gpg (line 83 is in a later block, but the pattern in lines 72-79 is the risk) but before re-signing, leaving the published GitHub Pages repo in a half-signed state. Since `add_byhash_and_resign` is called for up to 9 suites in a loop, a single failure can abort the entire publish mid-way. This directly threatens REPO-08 (SC-3).

**CR-02 (BLOCKER):** For a 26.04 publish (`DISTRO=2604`), `resolve_publish_targets` correctly returns only `<track>-2604`. However, the bare alias (`<track>`) lands in `OTHER_SUITES` (verified by tracing `ci_publish.sh:113-125`). In Step 4, the bare alias's debs are re-`includedeb`'d from mirrored packages and re-`export`ed with a fresh reprepro db, regenerating its `Release` with a new Date and new signature — even though package content is unchanged. This re-signing reopens the CDN hash-mismatch window that Acquire-By-Hash is designed to eliminate: an apt client can see a new `InRelease` (different signature/date) served against a stale cached `by-hash` index. No test covers a 26.04 publish path; the integration harness only exercises 24.04 publishes and the empty-but-signed 2604 export (which never goes through the re-include/re-export path). This directly threatens REPO-08 (SC-3) and the no-clobber guarantee (SC-4) for 26.04 publishes.

The two gaps share a root cause: the 26.04 publish path (which is the primary new capability being built in Phase 20) is not exercised end-to-end in any test, and the `add_byhash_and_resign` helper has no pipefail isolation. Both must be fixed before Phase 21 builds on top of this foundation.

---

_Verified: 2026-06-07_
_Verifier: Claude (gsd-verifier)_
