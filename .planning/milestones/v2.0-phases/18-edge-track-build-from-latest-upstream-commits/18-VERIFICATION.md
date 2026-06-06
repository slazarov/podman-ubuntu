---
phase: 18-edge-track-build-from-latest-upstream-commits
verified: 2026-03-06T13:00:00Z
status: human_needed
score: 4/5 success criteria verified
re_verification: false
human_verification:
  - test: "Run the GitHub Actions workflow manually with build_track=nightly, then wait up to 24h for the daily cron trigger at 04:30 UTC"
    expected: "Workflow completes successfully, producing .deb packages with version strings matching X.Y.Z~gitYYYYMMDD.XXXXXXX~podman1; packages install cleanly via 'dpkg -i'; cron run appears in Actions tab history"
    why_human: "EDGE-03 (nightly .deb packages are valid and installable) requires a full ~2h build environment with all upstream repos cloned and compiled. EDGE-05 (daily cron trigger) cannot be verified until GitHub Actions actually fires the schedule."
---

# Phase 18: Edge Track — Build from Latest Upstream Commits
# Verification Report

**Phase Goal:** Users can install bleeding-edge packages built from the latest upstream commits via a nightly APT suite, with correct Debian snapshot versioning that auto-upgrades to tagged releases
**Verified:** 2026-03-06T13:00:00Z
**Status:** human_needed (4/5 success criteria verified by static analysis; 1 CI-gated + 1 cron-dependent require human confirmation)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Nightly version strings (e.g., 6.0.0~git20260306.abc1234~podman1) sort below tagged releases via dpkg | VERIFIED | `extract_version_nightly` outputs `${base}~git${datestamp}.${sha}` format; tilde convention is Debian policy; test suite includes `dpkg --compare-versions` check (skipped gracefully on macOS) |
| 2 | Dev versions are correctly extracted from each upstream component's source files (version.go, Cargo.toml, configure.ac, VERSION, meson.build) | VERIFIED | `extract_version_nightly()` in `scripts/package_all.sh` lines 63-134 covers all 12 components: podman, buildah, skopeo, netavark, aardvark-dns, conmon, fuse-overlayfs, catatonit, crun, toolbox, container-configs, pasta |
| 3 | Nightly .deb packages are valid and installable via dpkg -i | NEEDS HUMAN | Requires full CI build environment; cannot verify statically. Declared CI-gated in `18-VALIDATION.md`. |
| 4 | reprepro accepts nightly packages into a dedicated nightly suite alongside stable and edge | VERIFIED | `packaging/repo/conf/distributions` has three stanzas (Suite: stable, Suite: edge, Suite: nightly); `ci_publish.sh` validates "nightly" as a legal suite and uses `reprepro includedeb nightly` |
| 5 | A daily cron workflow triggers nightly builds automatically, and the nightly track is also available via manual dispatch | VERIFIED (static) / NEEDS HUMAN (cron fire) | Workflow has `schedule: cron: '30 4 * * *'`; `nightly` is a third choice option in `build_track` input; scheduled runs default to `nightly` via `inputs.build_track \|\| 'nightly'`. Actual cron execution requires 24h wait. |

**Score:** 4/5 success criteria fully verified by static analysis; 1 CI-gated (EDGE-03)

---

## Required Artifacts

### Plan 18-01 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `versions-nightly.env` | Nightly build config (NIGHTLY_BUILD=true, SHALLOW_CLONE=false) | VERIFIED | Exists, 21 lines, exports both required variables with correct values |
| `functions.sh` | Nightly-aware git_checkout that stays on HEAD when NIGHTLY_BUILD=true | VERIFIED | Lines 180-192: nightly branch checks `${NIGHTLY_BUILD:-false} == "true" && -z "${ltag}"`, detects default branch, pulls HEAD, exports `GIT_CHECKED_OUT_TAG="nightly"` |
| `packaging/repo/conf/distributions` | Three-suite reprepro config (stable, edge, nightly) | VERIFIED | 27 lines, three stanzas confirmed: Suite: stable (line 3), Suite: edge (line 11), Suite: nightly (line 21) |
| `scripts/package_all.sh` | extract_version_nightly function for all 12 components | VERIFIED | Function at lines 63-134 with case statement for all 12 components; pasta special case returns plain datestamp; nightly loop at line 313; meta-package nightly branch at line 360 |

### Plan 18-02 Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/ci_publish.sh` | Three-suite CI publisher with multi-suite preservation | VERIFIED | Suite validation includes "nightly" (line 69); `ALL_SUITES=(stable edge nightly)` (line 91); `OTHER_SUITES` array with loop (lines 92-97); landing page has nightly track div and tab (lines 281, 297, 307) |
| `.github/workflows/build-packages.yml` | Workflow with nightly option, cron trigger, NIGHTLY_BUILD env | VERIFIED | Cron `30 4 * * *` at line 5; `nightly` as third choice (line 15); `NIGHTLY_BUILD=true SHALLOW_CLONE=false` injected for nightly track (lines 79, 171); "Resolve build track" step in all 3 jobs (lines 37, 132, 209) |

### Bonus Artifact

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tests/test_extract_version_nightly.sh` | TDD test suite for nightly version extraction | VERIFIED | 273 lines, 7+ test cases with mock git repos; dpkg tilde sort test with graceful macOS skip |

---

## Key Link Verification

### Plan 18-01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `versions-nightly.env` | `functions.sh` | `NIGHTLY_BUILD` env var | WIRED | `NIGHTLY_BUILD="true"` exported in versions-nightly.env; `${NIGHTLY_BUILD:-false}` checked in git_checkout (functions.sh line 184) |
| `scripts/package_all.sh` | `functions.sh` | `GIT_CHECKED_OUT_TAG` (plan-stated) / `NIGHTLY_BUILD` (actual) | WIRED (via env) | Note: The nightly path in package_all.sh uses `NIGHTLY_BUILD` directly (line 313), not `GIT_CHECKED_OUT_TAG`. `GIT_CHECKED_OUT_TAG` is set to "nightly" by git_checkout but is not consumed by package_all.sh in the nightly path. The actual control flow works correctly — `NIGHTLY_BUILD` flows from versions-nightly.env through the workflow env to package_all.sh. |

### Plan 18-02 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `.github/workflows/build-packages.yml` | `versions-nightly.env` | `NIGHTLY_BUILD=true SHALLOW_CLONE=false` inlined | WIRED | Workflow inlines the same values (lines 79, 171) rather than sourcing the file; plan explicitly documents this as intentional to avoid sudo env sourcing complexity |
| `.github/workflows/build-packages.yml` | `scripts/ci_publish.sh` | passes nightly as suite argument | WIRED | `./scripts/ci_publish.sh "${{ steps.track.outputs.track }}"` at workflow line 230-234; resolved track can be "nightly" |
| `scripts/ci_publish.sh` | `packaging/repo/conf/distributions` | reprepro uses distributions config for nightly suite | WIRED | ci_publish.sh copies conf/distributions to OUTPUT_DIR (line 179) then calls `reprepro includedeb "${other_suite}"` for each non-current suite |

---

## Requirements Coverage

Requirements EDGE-01 through EDGE-05 are referenced in ROADMAP.md (Phase 18 section) but are not defined in `.planning/REQUIREMENTS.md` (not found in that file). Coverage mapped from ROADMAP Success Criteria:

| Requirement | Source Plan | Mapped Success Criterion | Status | Evidence |
|-------------|-------------|--------------------------|--------|----------|
| EDGE-01 | 18-01 | Tilde version strings sort below tagged releases | SATISFIED | extract_version_nightly tilde format + test coverage |
| EDGE-02 | 18-01 | Dev versions extracted from source files for all 12 components | SATISFIED | extract_version_nightly case statement with 12 component handlers |
| EDGE-03 | 18-01 | Nightly .deb packages are valid and installable | CI-GATED | Acknowledged in 18-VALIDATION.md; requires full build environment |
| EDGE-04 | 18-02 | reprepro accepts nightly packages into dedicated nightly suite | SATISFIED | Three-suite distributions config + ci_publish.sh nightly handling |
| EDGE-05 | 18-02 | Daily cron workflow + manual dispatch for nightly track | SATISFIED (static) | Cron trigger in workflow YAML; nightly input option; actual cron execution needs 24h to confirm |

**Orphaned requirements:** None found. All 5 requirement IDs claimed by the plans are accounted for.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/ci_publish.sh` | 300, 304, 308 | `REPO_URL_PLACEHOLDER` strings | INFO | Intentional — replaced at runtime by `sed -i "s\|REPO_URL_PLACEHOLDER\|${REPO_URL#https://}\|g"` on line 350. Not a genuine stub. |

No blockers or warnings found. All critical paths implement substantive logic.

---

## Human Verification Required

### 1. Nightly Package Installability (EDGE-03)

**Test:** Trigger the GitHub Actions workflow with `build_track=nightly` via manual dispatch. After the workflow completes (~2h), download the produced `.deb` files from the workflow artifact or the published APT repo and run `dpkg -i <package>.deb` on an Ubuntu 24.04 system.
**Expected:** All 12 component packages install without errors; `podman --version` returns a version string matching the pattern `X.Y.Z~gitYYYYMMDD.XXXXXXX`
**Why human:** Requires a complete build environment with all upstream repos (podman, buildah, skopeo, etc.) cloned, compiled, and packaged. The full build takes approximately 2 hours and cannot be approximated by static analysis.

### 2. Daily Cron Trigger (EDGE-05 — cron execution)

**Test:** Wait up to 24 hours after the workflow is deployed to the `main` branch. Check the GitHub Actions tab for an automatically-triggered run at approximately 04:30 UTC.
**Expected:** A workflow run appears in the Actions tab with trigger type "Schedule", selecting the nightly build track automatically (since `inputs.build_track` is absent for cron runs, defaulting to `nightly`).
**Why human:** GitHub Actions cron schedules only execute when the workflow file exists on the default branch and the repository has recent activity. Cannot verify cron execution without waiting for the schedule to fire.

---

## Gaps Summary

No gaps blocking goal achievement. All statically-verifiable must-haves pass. The two human verification items are expected CI-gated behaviors explicitly documented in `18-VALIDATION.md` as requiring a live build environment or cron execution.

**Implementation quality notes:**

1. The key link documented in Plan 18-01 (`package_all.sh -> functions.sh via GIT_CHECKED_OUT_TAG`) does not match the actual implementation. `package_all.sh` uses `NIGHTLY_BUILD` directly, not `GIT_CHECKED_OUT_TAG`. This is a documentation inaccuracy but the actual wiring is correct and complete — `NIGHTLY_BUILD` flows correctly from `versions-nightly.env` through the workflow environment to `package_all.sh`.

2. The tilde sort test in `tests/test_extract_version_nightly.sh` gracefully skips on macOS (where `dpkg` is unavailable). The PLAN notes this limitation explicitly. Tilde sort behavior is guaranteed by Debian policy, so this is acceptable.

3. Four commits document the phase 18-01 work atomically (`a846f2a`, `e882080`, `ded7bdc`, `55539fb`) and two commits for phase 18-02 (`81e2b61`, `c9b4314`). All six commits verified in git log.

---

_Verified: 2026-03-06T13:00:00Z_
_Verifier: Claude (gsd-verifier)_
