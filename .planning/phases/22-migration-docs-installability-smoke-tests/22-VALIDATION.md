---
phase: 22
slug: migration-docs-installability-smoke-tests
status: ready
nyquist_compliant: true
wave_0_complete: true
created: 2026-06-07
---

# Phase 22 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bash (existing `tests/` harness) + `python3 yaml.safe_load` for the workflow |
| **Config file** | none — tests run directly |
| **Quick run command** | `bash tests/test_docs_suites.sh && bash tests/test_index_html_distro.sh` |
| **Full suite command** | `bash -n scripts/ci_publish.sh && bash -n scripts/smoke_repo_install.sh && bash tests/test_docs_suites.sh && bash tests/test_index_html_distro.sh && python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-packages.yml')); print('yaml ok')"` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run the task's `<automated>` verify (per the map below)
- **After every plan wave:** Run full suite command above
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

All three plans are **Wave 1** (parallel — exclusive `files_modified`, no overlap). Each task has an automated `<automated>` verify matching the plan's `<verify>` block.

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 22-01-01 | 01 | 1 | MIGR-01, MIGR-03 | T-22-DOC-01 | test asserts no `trusted=yes` in docs (RED test-first) | unit (syntax) | `bash -n tests/test_docs_suites.sh` | ✅ | ⬜ pending |
| 22-01-02 | 01 | 1 | MIGR-01, MIGR-03 | T-22-DOC-01 | docs use `Signed-By`, no `trusted=yes`; bare names only in deprecation/migration sections | doc-grep unit | `bash tests/test_docs_suites.sh` | ✅ | ⬜ pending |
| 22-02-01 | 02 | 1 | MIGR-02, MIGR-03 | T-22-HTML-02 | test asserts no `/usr/share/keyrings/`, no `trusted=yes` (RED test-first) | unit (syntax) | `bash -n tests/test_index_html_distro.sh` | ✅ | ⬜ pending |
| 22-02-02 | 02 | 1 | MIGR-02, MIGR-03 | T-22-HTML-01, T-22-HTML-02 | DEB822 snippets `Signed-By: /etc/apt/keyrings/`; `esc()` preserved; no `trusted=yes`; D-10 table preserved | string unit | `bash -n scripts/ci_publish.sh && bash tests/test_index_html_distro.sh` | ✅ | ⬜ pending |
| 22-03-01 | 03 | 1 | MIGR-04 | T-22-SMOKE-01 | distro-label + `SMOKE_RUNTIME` exact-match validated before interpolation | unit (syntax) | `bash -n scripts/smoke_repo_install.sh` | ✅ | ⬜ pending |
| 22-03-02 | 03 | 1 | MIGR-04 | T-22-SMOKE-02, T-22-SMOKE-03 | smoke gate before Pages upload (D-13); `[trusted=yes]` confined to CI-internal `file://` source | yaml parse | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-packages.yml')); print('yaml ok')"` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

**Requirement coverage:** MIGR-01 (Plan 01), MIGR-02 (Plan 02), MIGR-03 (Plans 01 + 02), MIGR-04 (Plan 03). All four phase requirements covered.

---

## Wave 0 Requirements

Wave 0 is complete — the RED test-first scaffolds are the first task of Plans 01 and 02, and every task's `<automated>` verify runs against tooling that already exists (`bash -n`, `python3 yaml`).

- [x] `tests/test_docs_suites.sh` scaffold (Plan 01 Task 1, test-first RED) — asserts the target suite-name/deprecation strings before the doc edit
- [x] `tests/test_index_html_distro.sh` scaffold (Plan 02 Task 1, test-first RED) — asserts the target toggle/snippet strings before the heredoc rewrite
- [x] `bash -n scripts/ci_publish.sh` — syntax check passes before/after modifying the heredoc
- [x] `bash -n scripts/smoke_repo_install.sh` — syntax check for the new helper
- [x] `python3 -c "import yaml; yaml.safe_load(...)"` — YAML parse for the workflow smoke-gate step

*Existing test infrastructure covers all automated checks; the MIGR-04 smoke gate's end-to-end run is inherently CI/Lima-environment-dependent (see Manual-Only).*

---

## Manual-Only Verifications

These cannot be proven on the macOS dev host and are deferred to PR preview / CI / Lima. They are NOT a substitute for the automated `<automated>` verifies above — every task still has an automated gate.

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| index.html distro toggle UX | MIGR-02 | Requires browser rendering | Open the generated index.html locally; verify the toggle defaults to 24.04 and switching to 26.04 swaps all three track snippets to the `-2604` suites; the package-versions table still renders |
| Migration sed one-liner validity | MIGR-03 | Requires a live `.sources` file to test | Dry-run the documented `sed -i` command on a sample `podman-ubuntu.sources`; verify `Suites: stable` → `Suites: stable-2404` |
| CI smoke containers both exit 0 | MIGR-04 | Requires Docker + the actual assembled repo | Run the publish job on a test branch, OR `bash scripts/smoke_repo_install.sh 2404 <repo-output>` in `ubuntu-24` and `... 2604` in `ubuntu-26` (Lima); confirm `apt install podman-suite` + `podman info` exit 0 in both. `/gsd-verify-work` MUST treat MIGR-04 as CI/Lima-proven, not macOS-proven |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references (test-first RED scaffolds are Wave 0)
- [x] No watch-mode flags
- [x] Feedback latency < 10s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ready
