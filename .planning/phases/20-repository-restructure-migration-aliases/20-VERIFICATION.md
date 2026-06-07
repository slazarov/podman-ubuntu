---
phase: 20-repository-restructure-migration-aliases
verified: 2026-06-07T02:45:00Z
status: passed
score: 4/4
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 3/4
  gaps_closed:
    - "SC-3/SC-4 wget path bug (re-review CR-01 / T-20-17): mirror_suite_verbatim rebuilt as a Release-driven fetch in commit 53b778f — the signed Release is the manifest; InRelease/Release.gpg fetched verbatim, every checksummed index curled and verified against the signed hash, by-hash copies reconstructed locally. No wget crawl, no URL-shape dependency. Proven three ways: (1) tests/test_mirror_verbatim.sh sed-extracts the production function and drives it against a path-segmented URL — 19/19 on macOS AND Lima ubuntu-24; (2) end-to-end UAT (20-UAT.md Test 9): the real ci_publish.sh stable 2604 run against a live tree served at http://localhost:8098/podman-ubuntu (the exact project-pages shape that broke wget) took the verbatim path — 'Mirrored stable/stable-2404 dists/ tree verbatim (original signature preserved)', bare alias Date/InRelease/Release.gpg byte-identical, pool entries at exact Filename: paths, by-hash reconstructed, stable-2604 freshly signed with Acquire-By-Hash — 12/12; (3) full integration harness still green at HEAD, 62/0."
  gaps_remaining: []
  regressions: []
gaps: []
human_verification:
  - test: "Production-URL validation: after the 9-suite tree is first published to GitHub Pages by CI, run apt-get update against the live repository using bare suite names and verify no 'changed its Suite value' prompt, a ~ubuntu24.04.podman1 candidate resolves, and by-hash fetch returns HTTP 200."
    expected: "apt-get update exits 0 with no 'changed its Suite value' in output; apt-cache policy shows ~ubuntu24.04.podman1 candidate; curl against a by-hash/<algo>/<hash> path returns HTTP 200 from the Pages CDN."
    why_human: "Production GitHub Pages CDN caching and serving behavior cannot be verified without an actual deploy of the 9-suite tree to the live repo. The local-VM D-15 simulation proved apt semantics; the CDN caching window requires real production data."
---

# Phase 20: Repository Restructure & Migration Aliases — Verification Report

**Phase Goal:** The APT repository serves all six versioned suites from a single URL under one GPG key, while existing users on bare suite names keep receiving 24.04 packages with no client-side change
**Verified:** 2026-06-07T02:45:00Z
**Status:** passed (4/4)
**Re-verification:** Yes — third round, after fix 53b778f (Release-driven verbatim fetch) and full UAT (20-UAT.md, 8/9 passed)

## Re-verification Addendum (2026-06-07, post-53b778f)

The single gap recorded below (mirror_suite_verbatim wget path bug) was closed by commit
`53b778f` — "fix(20): rebuild verbatim alias mirror as Release-driven fetch (T-20-17)" —
which replaced the `wget -r` crawl with a Release-manifest-driven curl fetch (signed Release
is the manifest; every listed index fetched and verified against the signed hash; by-hash
copies reconstructed locally; signatures arrive verbatim or the suite falls back to the
re-export path). Evidence the gap is closed:

1. **Unit:** `tests/test_mirror_verbatim.sh` (shipped with the fix) drives the production
   function against a path-segmented URL mimicking `https://<owner>.github.io/<repo-name>`
   — 19 passed / 0 failed on both the macOS dev host and Lima ubuntu-24.
2. **End-to-end (UAT Test 9):** the real `ci_publish.sh stable 2604` was run on Lima
   ubuntu-24 against a live tree served at `http://localhost:8098/podman-ubuntu` (the exact
   URL shape that defeated wget). The verbatim path was taken for both live suites
   (`IS_VERBATIM=true`); the bare `stable` alias came through byte-identical (Date,
   InRelease, Release.gpg) with a valid signature; pool entries landed at exact `Filename:`
   paths; by-hash was reconstructed; `stable-2604` was freshly signed with
   `Acquire-By-Hash: yes`. 12 passed / 0 failed.
3. **No regression:** the full integration harness (`tests/test_repo_assemble_byhash.sh`,
   groups A–G) remains green at HEAD — 62 passed / 0 failed on Lima ubuntu-24; all
   macOS-safe unit suites pass (43/43); the D-15 legacy-client simulation re-run at HEAD
   passes 7/0 (no Suite-change prompt, 24.04 candidate from bare `stable`, by-hash HTTP 200).

The historical report below documents the previous round (3/4) and is retained as the
record of what the gap was; its "Still failing" findings are superseded by this addendum.

## Acknowledged Gaps

Acknowledged by user on 2026-06-07 during /gsd-verify-work phase completion:

- **Production-URL smoke (human_verification item):** the post-deploy confirmation against
  the live GitHub Pages CDN remains deferred — local main is 80 commits ahead of origin and
  the 9-suite tree has never been published (live Pages still serves the old 3-suite tree).
  The apt-client behavior is fully proven locally (UAT Tests 6 and 9); re-run the deferred
  commands in 20-04-SUMMARY.md against the real REPO_URL after the first CI publish.

## Re-verification Summary

Prior verification (2026-06-07T00:00:00Z, score 2/4) found two blockers:

- **Original CR-01 (CLOSED):** `add_byhash_and_resign` ran under inherited `set -euo pipefail` with no isolation. Plan 20-05 added the RETURN-trap save/restore pattern (`local _saved_opts; _saved_opts="$(set +o)"; set +e +o pipefail; trap 'eval "${_saved_opts}"' RETURN`). Confirmed present at `scripts/repo_byhash.sh:53-55`.

- **Original CR-02 (PARTIALLY CLOSED):** On 26.04 publishes, bare aliases were re-exported/re-signed in Step 4 despite unchanged content. Plan 20-06 introduced `mirror_suite_verbatim()` and the `IS_VERBATIM` tracking map to skip re-export/re-sign for non-target suites that can be mirrored verbatim. The *logic* is correct. However, the implementation contains a path-mapping bug: `wget -nH --cut-dirs=0` against the CI project-pages URL (`https://slazarov.github.io/podman-ubuntu`) saves files to `${lmirror}/podman-ubuntu/dists/<suite>/` but the code checks for `${lmirror}/dists/<suite>/`. wget exits 0, so the curl fallback is never triggered, `mirror_suite_verbatim` returns 1, and `IS_VERBATIM` stays false. The bare alias is re-exported and re-signed in production, reopening the CDN hash-mismatch window. The re-review (20-REVIEW.md, reviewed 2026-06-06T22:04:06Z) identifies this as CR-01 (renumbered in the review context).

**Closed in this round:** 3 prior must-haves (pipefail isolation, WR-01 GPG key, WR-03 realpath quoting, WR-04 HTML escaping, Test groups F and G structure).
**Still failing:** 1 must-have (SC-3/SC-4: verbatim mirror is a no-op in CI due to wget path bug).

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Repository serves six versioned suites from one URL with one GPG key; apt update against any suite succeeds with valid signatures (SC-1, REPO-06) | VERIFIED | `packaging/repo/conf/distributions` has exactly 9 stanzas (6 versioned + 3 aliases), all with `SignWith: yes`. `resolve_publish_targets` routing wired through `repo_manage.sh` and `ci_publish.sh`. Unit tests 15/15, 8/8, 12/12 pass on macOS. Integration harness confirmed 62/62 on Lima ubuntu-24 per 20-06-SUMMARY.md. |
| 2 | Existing users with bare stable/edge/nightly in .sources receive 24.04 packages with no client-side change (SC-2, REPO-07) | VERIFIED | Bare alias stanzas carry `Suite: stable`/`edge`/`nightly` (not `-2404`), which is the REPO-07 mechanism — confirmed by `grep '^Suite: stable$'`. `resolve_publish_targets` includes bare alias in 24.04 targets (D-12). D-15 local-VM simulation proved no "changed its Suite value" prompt. Production-URL confirmation deferred to human verification. |
| 3 | Repository metadata includes Acquire-By-Hash: yes on every suite; CDN hash-sum mismatches are prevented (SC-3, REPO-08) | PARTIAL — FAILED | `add_byhash_and_resign` pipefail isolation (original CR-01) is now FIXED: RETURN-trap present at `repo_byhash.sh:53-55`. However, the verbatim-mirror path (CR-02) is broken in CI: `wget --cut-dirs=0` against a project-pages URL places files under `${lmirror}/REPONAME/dists/` not `${lmirror}/dists/`. wget exits 0, curl fallback skipped, `[[ -d ]]` check fails, `mirror_suite_verbatim` returns 1. Bare aliases on 26.04 publishes are re-signed despite unchanged content, reopening the hash-mismatch window. |
| 4 | Publish tooling routes packages into the correct suite without clobbering other suites' contents (SC-4, REPO-06/07) | PARTIAL — FAILED | For 24.04 publishes: mirror-then-include no-clobber property is proven by 62/62 integration harness. For 26.04 publishes: the wget path bug (see Truth 3) means `IS_VERBATIM` is always false in CI, so bare aliases are re-exported/re-signed on every 26.04 publish — the clobbering of signature metadata is the same defect. Test group G correctly asserts the desired behavior but does not exercise the `mirror_suite_verbatim` / wget code path. |

**Score:** 3/4 truths verified (SC-1, SC-2 fully; SC-3 and SC-4 share one remaining gap from the wget path bug)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `packaging/repo/conf/distributions` | 9-stanza reprepro config (6 versioned + 3 aliases) | VERIFIED | 9 Suite lines, 9 Codename lines, 9 SignWith:yes; bare aliases carry Suite:stable/edge/nightly; 6 versioned suites present; 3 DEPRECATED descriptions; no createsymlinks |
| `config.sh` | Suite whitelist arrays + resolve_publish_targets routing helper | VERIFIED | `VALID_TRACKS`, `VALID_DISTROS`, `ALL_SUITES` at file scope; `is_valid_suite()` and `resolve_publish_targets()` at column 0; D-12 alias rule (2404 returns versioned + bare; 2604 returns versioned only) |
| `tests/test_distributions_suites.sh` | Parse-assertion of 9-stanza distributions file | VERIFIED | 15/15 pass on macOS |
| `tests/test_suite_routing.sh` | Routing + whitelist-rejection unit test | VERIFIED | 8/8 pass on macOS |
| `tests/test_alias_routing.sh` | 24.04-includes-alias / 26.04-excludes-alias unit test | VERIFIED | 12/12 pass on macOS |
| `scripts/repo_byhash.sh` | Post-export by-hash + re-sign helper with pipefail isolation | VERIFIED | `_saved_opts`/`set +e +o pipefail`/RETURN-trap at lines 53-55; `add_byhash_and_resign` can no longer abort mid-function; `local cmd rh` consolidated (IN-02); quoted realpath bootstrap |
| `tests/test_byhash_parse.sh` | Release-section parser unit test | VERIFIED | 8/8 pass on macOS |
| `scripts/repo_manage.sh` | Track+distro-aware single-publish builder with anchored GPG key | VERIFIED | Uses `resolve_publish_targets`; both GPG_KEY_ID sites use `gpg --list-secret-keys | awk '/^fpr:/{print $10; exit}'` (WR-01); quoted realpath bootstrap (WR-03) |
| `scripts/ci_publish.sh` | 9-suite mirror-then-include publisher with verbatim-mirror + by-hash | PARTIAL | `mirror_suite_verbatim()` present; `IS_VERBATIM`/`VERBATIM_SUITES` tracking present; Step 4 and Step 4b guards present; `esc()` HTML escaper applied to pkg/ver (WR-04); quoted realpath (WR-03). BUG: `wget --cut-dirs=0` places files at wrong path for project-pages URL; IS_VERBATIM is always false in CI. |
| `tests/test_repo_assemble_byhash.sh` | Ubuntu-only integration harness with Test groups A-G | VERIFIED (structure) / NOT FULLY WIRED | Test groups F (pipefail regression) and G (26.04 publish bare alias byte-stable) are present and pass on Lima ubuntu-24 (62/62 per 20-06-SUMMARY.md). Test group G does not exercise `mirror_suite_verbatim` or the wget code path; it models the intended behavior directly. |
| `.github/workflows/build-packages.yml` | Publish job with distro argument wired to ci_publish.sh | VERIFIED | `steps.track.outputs.distro` passed as second positional arg; REPO_URL constructed as `https://${repository_owner}.github.io/${repository.name}` (project-pages format — the one that triggers the wget cut-dirs bug) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `tests/test_suite_routing.sh` | `config.sh resolve_publish_targets` | sed-extract + eval | WIRED | Extracts function and arrays; calls directly; 8/8 pass |
| `packaging/repo/conf/distributions` | apt client cached Suite value | bare alias stanza `Suite: stable` | WIRED | `grep '^Suite: stable$'` succeeds; bare aliases confirmed without -2404 suffix |
| `scripts/ci_publish.sh` | `config.sh resolve_publish_targets / ALL_SUITES` | sourced; mapfile at line 83; ALL_SUITES loop at lines 114, 373, 411 | WIRED | Routing helper and 9-element array both consumed |
| `scripts/ci_publish.sh` | `scripts/repo_byhash.sh add_byhash_and_resign` | source at line 24; per-suite loop at lines 373-385 | WIRED | Sourced at top; called for non-verbatim suites with a Release |
| `scripts/ci_publish.sh` `IS_VERBATIM` tracking | Step 4 re-export skip + Step 4b re-sign skip | `IS_VERBATIM` guards at lines 324, 377 | WIRED (logic) / NOT WIRED (path) | Logic is correct; but IS_VERBATIM is always false in CI due to wget path bug |
| `.github/workflows/build-packages.yml` publish job | `scripts/ci_publish.sh` | 5-arg invocation at line 312-317 | WIRED | track, distro (from steps.track.outputs), deb-dir, repo-url, output-dir |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `resolve_publish_targets stable 2404` returns two lines | `bash tests/test_suite_routing.sh` | 8/8 pass | PASS |
| `resolve_publish_targets edge 2604` returns single line | `bash tests/test_alias_routing.sh` | 12/12 pass | PASS |
| distributions file has 9 Suite lines, bare aliases unsuffixed | `bash tests/test_distributions_suites.sh` | 15/15 pass | PASS |
| byhash Release parser is section-boundary-correct | `bash tests/test_byhash_parse.sh` | 8/8 pass | PASS |
| Integration harness SKIPs on macOS | `bash tests/test_repo_assemble_byhash.sh` | SKIP exit 0 | PASS |
| Integration harness passes on Lima ubuntu-24 | Documented in 20-06-SUMMARY.md | 62/62 pass | PASS (recorded, not re-run) |
| `add_byhash_and_resign` pipefail isolation present | `grep -n '_saved_opts\|set +e\|RETURN' scripts/repo_byhash.sh` | Lines 53-55 match | PASS |
| Both GPG_KEY_ID reads anchored in repo_manage.sh | `grep 'list-secret-keys' scripts/repo_manage.sh` | Lines 112, 193 match | PASS |
| All 4 realpath bootstraps quote path argument | `grep 'realpath.*canonicalize.*scriptpath.*relativepath' config.sh scripts/repo_byhash.sh scripts/repo_manage.sh scripts/ci_publish.sh` | All 4 match with quotes | PASS |
| esc() helper present and applied to pkg_e/ver_e | `grep -n 'esc()\|pkg_e\|ver_e' scripts/ci_publish.sh` | Lines 405, 526-529 match | PASS |
| `mirror_suite_verbatim` wget path correct for project-pages URL | Static analysis: wget --cut-dirs=0 on `https://slazarov.github.io/podman-ubuntu/dists/stable/` saves to `${lmirror}/podman-ubuntu/dists/stable/`; [[ -d ]] checks `${lmirror}/dists/stable` | FAILS — directory at wrong path | FAIL |

### Probe Execution

| Probe | Command | Result | Status |
|-------|---------|--------|--------|
| `tests/test_distributions_suites.sh` | `bash tests/test_distributions_suites.sh` | 15 passed, 0 failed | PASS |
| `tests/test_suite_routing.sh` | `bash tests/test_suite_routing.sh` | 8 passed, 0 failed | PASS |
| `tests/test_alias_routing.sh` | `bash tests/test_alias_routing.sh` | 12 passed, 0 failed | PASS |
| `tests/test_byhash_parse.sh` | `bash tests/test_byhash_parse.sh` | 8 passed, 0 failed | PASS |
| `tests/test_repo_assemble_byhash.sh` | `bash tests/test_repo_assemble_byhash.sh` | SKIP on macOS (by design; 62/62 on Lima ubuntu-24 per 20-06-SUMMARY.md) | PASS (SKIP) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| REPO-06 | 20-01, 20-03, 20-04 | Six versioned suites from single URL, one GPG key | SATISFIED | 9-stanza distributions with SignWith:yes on all; routing helper wired; 62/62 integration harness on Ubuntu |
| REPO-07 | 20-01, 20-03, 20-04 | Bare suite aliases serve 24.04 packages, no client-side change | SATISFIED | Bare alias stanzas carry `Suite: stable` (not stable-2404); D-15 local-VM simulation proved no Suite-change prompt and 24.04 candidate resolves |
| REPO-08 | 20-02, 20-03, 20-04, 20-05, 20-06 | Acquire-By-Hash on all suites, no CDN hash-sum mismatches | BLOCKED | Pipefail isolation (original CR-01) is fixed. However, the verbatim-mirror mechanism (CR-02 fix) is a no-op in CI: `wget --cut-dirs=0` on the project-pages URL saves files to the wrong path, `mirror_suite_verbatim` returns 1, bare aliases on 26.04 publishes are re-signed, reopening the CDN hash-mismatch window. |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/ci_publish.sh` | 181 | `wget -nH --cut-dirs=0` saves to `${lmirror}/REPONAME/dists/<suite>/` for project-pages URLs; `[[ -d ]]` at line 201 checks `${lmirror}/dists/<suite>/`; wget exits 0, curl fallback skipped, function returns 1 | BLOCKER | `IS_VERBATIM` stays false for all bare aliases in CI; verbatim-mirror logic is a no-op in production; bare aliases are re-signed on 26.04 publishes, defeating the CR-02 fix and reopening the CDN hash-mismatch window (REPO-08 / SC-3) |
| `scripts/ci_publish.sh` | 185-197 | curl fallback only fetches Release/InRelease/Release.gpg and per-arch Packages/Release; omits by-hash dirs and Packages.gz; served Release checksums files that 404 on apt client fetch | WARNING | The fallback path (if wget were unavailable) would serve an incomplete signed tree; noted by review WR-04. Currently secondary to the wget-path bug since fallback is never reached when wget exits 0. |

### Human Verification Required

#### 1. Production-URL Validation (REPO-07 + REPO-08 on live CDN)

**Test:** After the Phase-20 9-suite tree is first published to GitHub Pages by CI, run apt-get update against the live repository using bare suite names and verify:
- No "changed its 'Suite' value" prompt appears
- `apt-cache policy podman-suite` resolves a `~ubuntu24.04.podman1` candidate
- A by-hash fetch against a `dists/stable/main/binary-amd64/by-hash/SHA256/<hash>` URL returns HTTP 200

```bash
# Legacy bare-suite client
sudo curl -fsSL https://slazarov.github.io/podman-ubuntu/podman-ubuntu.gpg \
  | sudo tee /usr/share/keyrings/podman-ubuntu.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/podman-ubuntu.gpg] \
  https://slazarov.github.io/podman-ubuntu stable main" \
  | sudo tee /etc/apt/sources.list.d/podman-legacy.list
sudo apt-get update 2>&1 | tee /tmp/legacy-update.log
! grep -q "changed its 'Suite' value" /tmp/legacy-update.log && echo "LEGACY-OK"
apt-cache policy podman-suite 2>&1 | grep -q "~ubuntu24.04.podman1" && echo "CANDIDATE-OK"
```

**Expected:** `apt-get update` exits 0; no "changed its 'Suite' value" line; `~ubuntu24.04.podman1` candidate present; by-hash HTTP 200.

**Why human:** Production GitHub Pages CDN caching and serving behavior cannot be verified without an actual deploy. The local-VM D-15 simulation proved apt semantics; CDN caching behavior requires real production data.

### Gaps Summary

**One gap remains after gap-closure plans 20-05 and 20-06:**

**Mirror_suite_verbatim wget path bug (BLOCKER, re-review CR-01):** In `scripts/ci_publish.sh` the `mirror_suite_verbatim()` function runs `wget -q -r -np -nH --cut-dirs=0 -P "${lmirror}" "${REPO_URL}/dists/${lsuite}/"`. For the CI project-pages URL `https://slazarov.github.io/podman-ubuntu`, wget `-nH` strips only the hostname; `--cut-dirs=0` cuts zero path segments. The file `dists/stable/Release` is therefore saved to `${lmirror}/podman-ubuntu/dists/stable/Release` — with a leading `podman-ubuntu/` directory. wget exits 0 (files were fetched successfully). The `if ! wget ...` block's curl fallback (lines 185-197) is inside that block and is never reached when wget exits 0. The subsequent check `[[ -d "${lmirror}/dists/${lsuite}" ]]` at line 201 is false (the tree is under `${lmirror}/podman-ubuntu/dists/`, not `${lmirror}/dists/`). The else branch executes: `rm -rf "${lmirror}"; return 1`. `mirror_suite_verbatim` returns 1, `IS_VERBATIM["${suite}"]` is set to false, and the bare alias is fed through Step 4 re-`includedeb` + re-`export` and Step 4b `add_byhash_and_resign` — regenerating its Release Date + signature despite byte-identical package content. This reopens the Acquire-By-Hash CDN hash-mismatch window that CR-02 in plan 20-06 was intended to close.

The fix is to either: (a) compute the number of path segments in the REPO_URL after the host and pass that count as `--cut-dirs=N`; or (b) locate the actual mirrored tree with `find "${lmirror}" -type d -path "*/dists/${lsuite}" -print -quit` after wget, regardless of where wget placed it. A test should exercise this with a local URL containing a path segment.

Test group G (tests/test_repo_assemble_byhash.sh) correctly models the desired behavior — the bare alias is not re-signed when only `stable-2604` is the target — but it calls `repo_manage.sh` and `add_byhash_and_resign` directly without going through `mirror_suite_verbatim`. The wget path bug therefore passes all 62 current test assertions.

---

_Verified: 2026-06-07_
_Verifier: Claude (gsd-verifier)_
