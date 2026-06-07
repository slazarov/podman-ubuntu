---
phase: 21-ci-build-matrix-extension-to-26-04
verified: 2026-06-07T00:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification: null
---

# Phase 21: CI Build Matrix Extension to 26.04 — Verification Report

**Phase Goal:** One CI workflow builds all four distro×arch cells, producing native 26.04 packages, with distro-isolated caches/artifacts and a publish step that only runs when every cell succeeds
**Verified:** 2026-06-07
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A single workflow run builds all four distro×arch combinations (24.04/26.04 × amd64/arm64) via one `strategy.matrix`, and a 26.04 cell failure does not abort the 24.04 cells (`fail-fast: false`) | VERIFIED | `jobs.build.strategy.matrix.include` has exactly 4 cells; `jobs.build.strategy.fail-fast` is `false` (Python assertion confirmed); old `build-amd64`/`build-arm64` jobs absent; `test_ci_matrix.sh` 27/27 PASS |
| 2 | The 26.04 cells build inside `ubuntu:26.04` containers on the existing native runners, written runner-agnostic so switching to GA `ubuntu-26.04` runners is a one-line change | VERIFIED | `container: ${{ matrix.container }}` at job level; 2604 cells have `container: ubuntu:26.04`; 2404 cells have `container: ''`; `runs-on: ${{ matrix.runner }}` — the runner label is a matrix field not hardcoded in any step; workflow comment at line 118 documents the one-line swap procedure |
| 3 | Build caches and artifacts carry a distro dimension (`debs-<distro>-<arch>` artifact names, distro in cache keys) and the publish download never merges across distros, so no 26.04 binary can leak into a 24.04 package or vice versa | VERIFIED | Cache key: `go-${{ matrix.distro }}-${{ matrix.arch }}-${{ steps.track.outputs.track }}-${{ github.run_number }}`; artifact: `debs-${{ matrix.distro }}-${{ matrix.arch }}`; two distinct download steps (`debs-2404-*` → `all-debs-2404/`, `debs-2604-*` → `all-debs-2604/`); no bare `pattern: debs-*` step exists; PyYAML set-equality assertion confirms `pats == {'debs-2404-*','debs-2604-*'}` |
| 4 | The publish job runs only when all four build cells succeed; if any cell fails, the live repository is left untouched | VERIFIED | `jobs.publish.needs == ['build']`; `jobs.publish.if: always() && needs.build.result == 'success'`; single terminal `deploy-pages@v4` — both distros assembled into `repo-output` before the one-shot deploy; `test_ci_matrix.sh` assertion 8 proves the gating expression |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.github/workflows/build-packages.yml` | Single matrixed build job replacing build-amd64/build-arm64 | VERIFIED | File exists; 369 lines; parses as valid YAML (PyYAML); all structural assertions pass |
| `tests/test_ci_matrix.sh` | Pure-bash/YAML assertion test for matrix + publish-gating contract | VERIFIED | File exists; `#!/bin/bash` + `set -euo pipefail`; 291 lines (well above min_lines: 40); `bash tests/test_ci_matrix.sh` exits 0 with 27/27 PASS |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `build` job matrix cells | `setup.sh` / `package_all.sh` | `DISTRO=$DISTRO_DOTTED` env in both "Build all components" and "Package all components" steps | WIRED | Closed case map at lines 180-184 and 245-249: `2404→24.04`, `2604→26.04`; both steps export `DISTRO=$DISTRO_DOTTED` before invoking `./setup.sh` and `./scripts/package_all.sh` |
| `publish` job | `scripts/ci_publish.sh` | Per-distro invocation with compact labels `2404`/`2604` | WIRED | `publish_distro "2404" "all-debs-2404"` then `publish_distro "2604" "all-debs-2604"` at lines 354-355; `ci_publish.sh "${TRACK}" "${label}" "${deb_dir}" "${REPO_URL}" "repo-output"` at line 350; `bash -n scripts/ci_publish.sh` exits 0 |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Workflow parses as valid YAML | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-packages.yml'))"` | Valid | PASS |
| Contract test: all 27 assertions | `bash tests/test_ci_matrix.sh` | 27 passed, 0 failed | PASS |
| ci_publish.sh syntax | `bash -n scripts/ci_publish.sh` | exit 0 | PASS |
| test_ci_matrix.sh syntax | `bash -n tests/test_ci_matrix.sh` | exit 0 | PASS |
| No regression in other tests | `bash tests/test_suite_routing.sh` / `test_distributions_suites.sh` / `test_detect_distro_depends.sh` / `test_extract_version_nightly.sh` / `test_alias_routing.sh` / `test_byhash_parse.sh` / `test_mirror_verbatim.sh` | All pass (0 failures) | PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CICD-05 | 21-01, 21-02 | Single workflow builds all four distro×arch combinations via strategy matrix | SATISFIED | 4-cell matrix confirmed by PyYAML; `test_ci_matrix.sh` assertions 1, 3, 4 |
| CICD-06 | 21-01 | Ubuntu 26.04 packages built inside ubuntu:26.04 containers, runner-agnostic | SATISFIED | `container: ${{ matrix.container }}`; `runs-on: ${{ matrix.runner }}`; YAML comment documents one-line GA runner swap; `test_ci_matrix.sh` assertion 5 |
| CICD-07 | 21-01, 21-02 | Build caches and artifacts carry distro dimension; no cross-distro contamination | SATISFIED | Cache key and artifact name both use `matrix.distro`+`matrix.arch`; two scoped download steps; PyYAML set-equality check on patterns; `test_ci_matrix.sh` assertions 6, 7, 9 |
| CICD-08 | 21-02 | Publish runs only when all four cells succeed; live repo untouched otherwise | SATISFIED | `needs.build.result == 'success'` gate; single terminal `deploy-pages`; `test_ci_matrix.sh` assertion 8 |

All four phase-21 requirements are satisfied and marked Complete in REQUIREMENTS.md traceability table.

### Anti-Patterns Found

The code review (21-REVIEW.md) found 1 critical and 5 warnings. Assessment against must-haves:

| Finding | Severity | Invalidates Must-Have? | Assessment |
|---------|----------|----------------------|------------|
| CR-01: Bootstrap `apt-get update` is un-retried against stale image index | Critical | NO | The un-retried `apt-get update` is a reliability/robustness defect. A transient mirror failure will fail the 26.04 cell and — via the correct `needs.build.result == 'success'` gate — skip publish. This is a correctness concern (flaky infra blocking a good build) but it does not invalidate CICD-05, CICD-06, or CICD-08 as designed requirements. The gating semantics are correct; the bootstrap resilience is a quality improvement. |
| WR-01: Duplicated `case "${{ matrix.distro }}"` distro-mapping in two steps | Warning | NO | Two copies of the same case map is a maintainability/drift risk for future distros. Does not affect the four current cells or any must-have for this phase. |
| WR-02: No pre-upload assertion that `output/*.deb` is non-empty and distro-correct | Warning | NO | Defense-in-depth gap; a successful build is assumed to produce debs. Does not affect structural requirements. |
| WR-03: `publish_distro` skip-on-empty returns 0 instead of failing | Warning | NO — partial nuance | The skip-on-empty behavior slightly weakens the atomicity guarantee: if a build succeeds but produces zero debs (unexpected), a partial publish proceeds silently. However, the `needs.build.result == 'success'` gate is correctly wired (the primary CICD-08 requirement), and reaching an empty deb dir requires a separate upstream defect. The must-have "publish job runs only when all four build cells succeed" is verified. |
| WR-04: Test does not assert distinct download *paths* (only patterns) | Warning | NO | The test's no-merge guarantee is under-specified for a regression where both patterns landed in the same path. The actual workflow *does* use distinct paths (`all-debs-2404/` vs `all-debs-2604/`) verified by PyYAML inspection above. The test gap is a test quality issue, not a workflow defect. |
| WR-05: Grep-floor label counts use `grep -c` (lines not invocation-proof) | Warning | NO | The grep assertion that ci_publish.sh is called with both `"2404"` and `"2604"` is weaker than claimed. The actual workflow uses `publish_distro "2404" "all-debs-2404"` and `publish_distro "2604" "all-debs-2604"` which are the actual invocation lines and are present in the file. The test floor is weak but the workflow implementation is correct. |

**Verdict on review findings:** None of the 6 findings (CR-01 through WR-05) invalidates any of the 4 phase must-haves. CR-01 is a robustness concern that could cause flaky build failures, not a design defect. All structural requirements (CICD-05/06/07/08) are correctly implemented per codebase evidence.

### Human Verification Required

None. All phase-21 requirements are structural (YAML wiring, gating logic, artifact naming, cache key shape) and are fully verifiable by YAML parsing and the contract test. No visual UI, real-time behavior, or external service behavior is involved.

The following items are NOT human-verification requirements but are carried research flags for the first real CI run:

- CR-01 fix (retry loop on bootstrap `apt-get update`) is a robustness improvement recommended before the first 26.04 CI execution.
- The production smoke of the 9-suite APT tree and GA `ubuntu-26.04`/`ubuntu-26.04-arm` runner availability await the first real publish (carried from Phase 20).

### Gaps Summary

No gaps. All four must-have truths are verified with codebase evidence:

1. The single `strategy.matrix` with `fail-fast: false` is in place and produces exactly four cells (PyYAML confirmed, 27-assertion test confirmed).
2. The 26.04 container wiring (`container: ${{ matrix.container }}`, `runs-on: ${{ matrix.runner }}`) is correct and runner-agnostic per design.
3. Distro isolation is enforced structurally at three levels: cache key prefix, artifact name, and distinct download directories in publish — no cross-distro merge path exists.
4. The atomic publish gate (`needs.build.result == 'success'` on a single `fail-fast: false` matrix job) correctly aggregates all four cells; the single terminal `deploy-pages` action enforces atomicity.

The phase goal is achieved.

---

_Verified: 2026-06-07_
_Verifier: Claude (gsd-verifier)_
