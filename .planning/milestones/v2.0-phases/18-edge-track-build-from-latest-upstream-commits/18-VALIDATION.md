---
phase: 18
slug: edge-track-build-from-latest-upstream-commits
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-06
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash + dpkg (shell-based validation) |
| **Config file** | None — validation is inline in scripts |
| **Quick run command** | `dpkg --compare-versions "6.0.0~git20260306.abc1234~podman1" lt "6.0.0~podman1" && echo PASS` |
| **Full suite command** | `./scripts/package_all.sh` (validates all version extraction) |
| **Estimated runtime** | ~10 seconds (version checks), ~5 minutes (full build) |

---

## Sampling Rate

- **After every task commit:** `dpkg --compare-versions` spot checks on generated version strings
- **After every plan wave:** Full `package_all.sh` run in CI
- **Before `/gsd:verify-work`:** Successful nightly workflow run producing packages in all three suites
- **Max feedback latency:** 10 seconds (version checks)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 18-01-01 | 01 | 1 | EDGE-01 | unit | `source versions-nightly.env && [[ "$NIGHTLY_BUILD" == "true" ]]` | pending |
| 18-01-02 | 01 | 1 | EDGE-01, EDGE-02 | unit | `grep -q "extract_version_nightly" scripts/package_all.sh && dpkg --compare-versions "1.0.0~git20260306.abc1234~podman1" lt "1.0.0~podman1"` | pending |
| 18-01-03 | 01 | 1 | EDGE-03 | CI-gated | Full installability requires complete build environment; validated by CI workflow (Plan 18-02) | pending |
| 18-02-01 | 02 | 2 | EDGE-04 | unit | `grep -q "nightly" scripts/ci_publish.sh && grep -c "OTHER_SUITES" scripts/ci_publish.sh` | pending |
| 18-02-02 | 02 | 2 | EDGE-05 | unit | `grep -q "schedule" .github/workflows/build-packages.yml && grep -q "NIGHTLY_BUILD" .github/workflows/build-packages.yml` | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] Version comparison test script — validates all component nightly versions sort correctly
- [ ] `nightly` suite added to `packaging/repo/conf/distributions`
- [ ] `versions-nightly.env` file created with `NIGHTLY_BUILD=true` and `SHALLOW_CLONE=false`

---

## CI-Gated Verifications

| Behavior | Requirement | Why CI-Gated | Verification Path |
|----------|-------------|--------------|-------------------|
| Nightly .deb packages are valid and installable | EDGE-03 | Requires full build environment with all upstream repos cloned, compiled, and packaged. Cannot be validated locally without ~2hr build. | CI workflow builds + `dpkg -i` in post-build step |
| Nightly workflow triggers on cron schedule | EDGE-05 | Requires GitHub Actions cron execution | Verify via Actions tab run history after 24h |

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Nightly workflow triggers on cron schedule | EDGE-05 | Requires GitHub Actions cron execution | Verify via Actions tab run history after 24h |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify commands
- [x] Tilde sort correctness exercised by dpkg --compare-versions in Task 18-01-02 verify
- [x] EDGE-03 acknowledged as CI-gated with explicit rationale
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] No watch-mode flags
- [x] Feedback latency < 10s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
