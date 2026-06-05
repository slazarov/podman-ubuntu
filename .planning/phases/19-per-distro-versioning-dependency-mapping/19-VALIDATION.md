---
phase: 19
slug: per-distro-versioning-dependency-mapping
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-05
---

# Phase 19 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash verification scripts + container smoke (no xUnit framework in repo — RESEARCH Validation Architecture) |
| **Config file** | none — Wave 0 creates the verification scripts (`scripts/verify_versions.sh`, `scripts/verify_depends.sh`, `scripts/smoke_install_2604.sh`) |
| **Quick run command** | `bash scripts/verify_versions.sh` (D-11 dpkg --compare-versions assertions; runs anywhere dpkg exists, including CI before any build) |
| **Full suite command** | `bash scripts/verify_versions.sh && DISTRO=24.04 ./scripts/package_all.sh && DISTRO=24.04 bash scripts/verify_depends.sh && DISTRO=26.04 ./scripts/package_all.sh && bash scripts/smoke_install_2604.sh` (version ordering + 24.04 functional-equivalence + render-and-parse + 26.04 container apt-install smoke) |
| **Estimated runtime** | ~5–10 minutes (quick run <5s; full suite dominated by two builds + the 26.04 container pull/apt-install) |

---

## Sampling Rate

- **After every task commit:** Run `bash scripts/verify_versions.sh` (fast, dpkg-only, runs even on non-build hosts with dpkg). For the syntax/structural tasks (Plan 01/02/03), the per-task `<automated>` greps also run on the macOS dev host.
- **After every plan wave:** Run the full build for `DISTRO=24.04` + `DISTRO=26.04`, render+parse all nFPM YAMLs (`verify_depends.sh` Part B), and run the detector on every component.
- **Before `/gsd-verify-work`:** Full suite must be green — `verify_versions.sh` green AND 26.04 container apt-install smoke green AND 24.04 functional-equivalence green.
- **Max feedback latency:** 10 seconds for the quick run (`verify_versions.sh`); the on-host/container proofs (Plan 04) are gated behind the blocking human-verify checkpoint, not the per-commit loop.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 19-01-01 | 01 | 1 | PKG-09, PKG-10 | T-19-01 / T-19-03 / T-19-04 | VERSION_ID/DISTRO regex-validated (`^[0-9]+\.[0-9]+$`) before composing version string; detector hard-fails (no silent fallback) on any unmapped soname | unit (syntax + DISTRO-override) | `bash -n functions.sh && DISTRO="26.04" bash -c 'source functions.sh; v=$(detect_distro_version_id); [[ "$v" == "26.04" ]] || exit 1' && DISTRO="2604" bash -c 'source functions.sh; ! detect_distro_version_id >/dev/null 2>&1'` | ❌ W0 (functions.sh edited) | ⬜ pending |
| 19-01-02 | 01 | 1 | PKG-09 | T-19-01 | VERSION_SUFFIX composed once in config.sh (single source of truth); malformed DISTRO fails config load closed | unit (syntax + DISTRO-override) | `bash -n config.sh && DISTRO="24.04" bash -c 'source config.sh >/dev/null 2>&1; [[ "${VERSION_SUFFIX}" == "~ubuntu24.04.podman1" ]]'` | ❌ W0 (config.sh edited) | ⬜ pending |
| 19-02-01 | 02 | 2 | PKG-08, PKG-10 | T-19-06 / T-19-07 | No `\|\| true`/fallback around detection (D-03 hard-fail preserved under set -euo pipefail); quoted DESTDIR/binary-path expansions | integration (syntax + grep structural) | `bash -n scripts/package_all.sh && ! grep -q 'detect_crun_parser_depend' scripts/package_all.sh && ! grep -q 'CRUN_PARSER_DEPEND' scripts/package_all.sh && grep -q 'detect_runtime_depends' scripts/package_all.sh && grep -q 'DETECTED_DEPENDS' scripts/package_all.sh` | ❌ W0 (package_all.sh edited) | ⬜ pending |
| 19-02-02 | 02 | 2 | PKG-08 | T-19-05 | Detected names come only from host package DB (not network); `${DETECTED_DEPENDS}` at column 0, malformed/empty YAML caught by nfpm parse (Plan 04) | integration (grep structural) | `for f in crun podman buildah skopeo conmon pasta; do grep -q 'DETECTED_DEPENDS' "packaging/nfpm/$f.yaml" \|\| exit 1; done && ! grep -rqE '^[[:space:]]*-[[:space:]]*(libgpgme11\|libseccomp2\|libsystemd0\|libcap2\|libglib2\.0-0\|libsubid4\|libsqlite3-0)([[:space:]]\|$)' packaging/nfpm/` | ✅ (YAMLs exist; edited in place) | ⬜ pending |
| 19-03-01 | 03 | 1 | PKG-09 | T-19-08 | dpkg `--compare-versions` is the authoritative oracle; only literal in-script fixtures, no external input surface | unit (dpkg oracle) | `bash -n scripts/verify_versions.sh && test -x scripts/verify_versions.sh && grep -q 'dpkg --compare-versions' scripts/verify_versions.sh` (full proof: `bash scripts/verify_versions.sh` exits 0 on any dpkg host) | ❌ W0 (net-new) | ⬜ pending |
| 19-04-01 | 04 | 3 | PKG-10 (D-14) | T-19-10 | Baseline encodes documented t64 substitution explicitly; undocumented 24.04 dep delta FAILS rather than silently passing | integration (on-Ubuntu detector + render-and-parse) | `bash -n scripts/verify_depends.sh && test -x scripts/verify_depends.sh && grep -q 'detect_runtime_depends' scripts/verify_depends.sh && grep -Eq 'libgpgme11t64\|t64' scripts/verify_depends.sh` (full proof: `DISTRO=24.04 bash scripts/verify_depends.sh` exits 0 on an Ubuntu host with built DESTDIR) | ❌ W0 (net-new) | ⬜ pending |
| 19-04-02 | 04 | 3 | PKG-08 | T-19-09 / T-19-11 / T-19-SC | SMOKE_RUNTIME validated to exactly `docker`/`podman`; hard-error (no silent skip) when no runtime present; throwaway `--rm` container | smoke (container) | `bash -n scripts/smoke_install_2604.sh && test -x scripts/smoke_install_2604.sh && grep -q 'apt-get install' scripts/smoke_install_2604.sh && grep -Eq 'ubuntu:26.04\|resolute' scripts/smoke_install_2604.sh` (full proof: `bash scripts/smoke_install_2604.sh` installs cleanly on a host with a container runtime + 26.04-built debs) | ❌ W0 (net-new) | ⬜ pending |
| 19-04-03 | 04 | 3 | PKG-08 (D-14) | T-19-10 / T-19-11 | Blocking human gate confirms the on-host proofs the autonomous tasks cannot exercise on the macOS dev host | manual (human-verify checkpoint) | manual — see Manual-Only Verifications | ❌ W0 (depends on 19-04-01/02) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Net-new verification scripts created by this phase's plans (no pre-existing test framework to install — RESEARCH Validation Architecture):

- [ ] `scripts/verify_versions.sh` — D-11 dpkg `--compare-versions` ordering assertions incl. the added legacy `~podman1` < new `~ubuntu24.04.podman1` upgrade assertion (PKG-09) — **created by Plan 03, Task 1**
- [ ] `scripts/verify_depends.sh` — on-Ubuntu detector smoke (run `detect_runtime_depends` on every built binary), the t64-adjusted D-14 functional-equivalence baseline (PKG-10), and the `${DETECTED_DEPENDS}` render-and-parse check (incl. empty-deps and mixed-static-deps cases) — **created by Plan 04, Task 1**
- [ ] `scripts/smoke_install_2604.sh` — 26.04 container apt-install smoke, parameterized by component/arch with `SMOKE_RUNTIME`/`SMOKE_IMAGE` overrides (PKG-08) — **created by Plan 04, Task 2**

No xUnit framework install required — the project's "tests" are shell verification scripts plus a container smoke. The detector itself (`detect_runtime_depends`) and the version-suffix composition are created by Plan 01 in `functions.sh`/`config.sh`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| 26.04-built .deb apt-installs cleanly on a real 26.04 userland (libgpgme45/libsubid5 resolve) | PKG-08 | Requires a real ubuntu:26.04 (or resolute) container userland the autonomous macOS dev host cannot exercise; gated by the Plan 04 Task 3 blocking human-verify checkpoint | Build for 26.04 in an ubuntu:26.04/resolute container, run `bash scripts/smoke_install_2604.sh`; expect skopeo (and podman) to apt-install cleanly and `skopeo --version` to print |
| 24.04 detected set is functionally equivalent to the pre-v3.0 hardcoded set (t64-aware) | PKG-10 (D-14) | Requires a real ubuntu:24.04 host with a populated DESTDIR and dpkg/ldd; t64 functional equivalence cannot be asserted on macOS; gated by the Plan 04 Task 3 checkpoint | Build for 24.04 (`DISTRO=24.04 ./scripts/package_all.sh`), run `DISTRO=24.04 bash scripts/verify_depends.sh`; expect exit 0 with libgpgme11t64/libglib2.0-0t64 present and non-t64 names unchanged, and every nFPM YAML render+parse clean |
| 26.04 detected set shows the renamed packages (self-corrected, no YAML edit) | PKG-08 | Requires the on-26.04 detector run; confirms the mechanism self-corrected | Inspect the 26.04 detected set recorded by `verify_depends.sh`; confirm it contains libgpgme45/libsubid5 |

The blocking human-verify checkpoint (Plan 04, Task 3) confirms all of the above plus the `verify_versions.sh` ordering proof in one gate before the phase advances.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (Plan 04 Task 3 is an intentional `checkpoint:human-verify` with a `<human-check>` — the on-host/container proofs cannot be automated on the macOS dev host)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every code-producing task carries an automated syntax/structural check; only the final checkpoint is manual)
- [x] Wave 0 covers all MISSING references (`verify_versions.sh`, `verify_depends.sh`, `smoke_install_2604.sh` are net-new, created by Plans 03/04; the detector/suffix live in functions.sh/config.sh created by Plan 01)
- [x] No watch-mode flags
- [x] Feedback latency < 10s (quick run is dpkg-only literal fixtures)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-06-05
