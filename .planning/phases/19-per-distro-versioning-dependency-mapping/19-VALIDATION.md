---
phase: 19
slug: per-distro-versioning-dependency-mapping
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-06-05
updated: 2026-06-06
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
| 19-01-01 | 01 | 1 | PKG-09, PKG-10 | T-19-01 / T-19-03 / T-19-04 | VERSION_ID/DISTRO regex-validated (`^[0-9]+\.[0-9]+$`) before composing version string; detector hard-fails (no silent fallback) on any unmapped soname | unit (syntax + DISTRO-override) | `bash -n functions.sh && DISTRO="26.04" bash -c 'source functions.sh; v=$(detect_distro_version_id); [[ "$v" == "26.04" ]] || exit 1' && DISTRO="2604" bash -c 'source functions.sh; ! detect_distro_version_id >/dev/null 2>&1'` | ✅ (functions.sh) | ✅ green (audit 2026-06-06: PASS on macOS; unit test 11/11 on ubuntu-24) |
| 19-01-02 | 01 | 1 | PKG-09 | T-19-01 | VERSION_SUFFIX composed once in config.sh (single source of truth); malformed DISTRO fails config load closed | unit (syntax + DISTRO-override) | `bash -n config.sh && DISTRO="24.04" bash -c 'source config.sh >/dev/null 2>&1; [[ "${VERSION_SUFFIX}" == "~ubuntu24.04.podman1" ]]'` | ✅ (config.sh) | ✅ green (audit 2026-06-06: PASS on ubuntu-24 for both 24.04/26.04 suffixes; macOS FAIL is the documented BSD-realpath env constraint, run on Linux) |
| 19-02-01 | 02 | 2 | PKG-08, PKG-10 | T-19-06 / T-19-07 | No `\|\| true`/fallback around detection (D-03 hard-fail preserved under set -euo pipefail); quoted DESTDIR/binary-path expansions | integration (syntax + grep structural) | `bash -n scripts/package_all.sh && ! grep -q 'detect_crun_parser_depend' scripts/package_all.sh && ! grep -q 'CRUN_PARSER_DEPEND' scripts/package_all.sh && grep -q 'detect_runtime_depends' scripts/package_all.sh && grep -q 'DETECTED_DEPENDS' scripts/package_all.sh` | ✅ (package_all.sh) | ✅ green (audit 2026-06-06: PASS) |
| 19-02-02 | 02 | 2 | PKG-08 | T-19-05 | Detected names come only from host package DB (not network); `${DETECTED_DEPENDS}` at column 0, malformed/empty YAML caught by nfpm parse (Plan 04) | integration (grep structural) | `for f in crun podman buildah skopeo conmon pasta; do grep -q 'DETECTED_DEPENDS' "packaging/nfpm/$f.yaml" \|\| exit 1; done && ! grep -rqE '^[[:space:]]*-[[:space:]]*(libgpgme11\|libseccomp2\|libsystemd0\|libcap2\|libglib2\.0-0\|libsubid4\|libsqlite3-0)([[:space:]]\|$)' packaging/nfpm/` | ✅ (YAMLs exist; edited in place) | ✅ green (audit 2026-06-06: PASS) |
| 19-03-01 | 03 | 1 | PKG-09 | T-19-08 | dpkg `--compare-versions` is the authoritative oracle; only literal in-script fixtures, no external input surface | unit (dpkg oracle) | `bash -n scripts/verify_versions.sh && test -x scripts/verify_versions.sh && grep -q 'dpkg --compare-versions' scripts/verify_versions.sh` (full proof: `bash scripts/verify_versions.sh` exits 0 on any dpkg host) | ✅ (net-new, exists) | ✅ green (audit 2026-06-06: structural PASS on macOS; full dpkg run exit 0 on ubuntu-24, all 6 orderings OK) |
| 19-04-01 | 04 | 3 | PKG-10 (D-14) | T-19-10 | Baseline encodes documented t64 substitution explicitly; undocumented 24.04 dep delta FAILS rather than silently passing | integration (on-Ubuntu detector + render-and-parse) | `bash -n scripts/verify_depends.sh && test -x scripts/verify_depends.sh && grep -q 'detect_runtime_depends' scripts/verify_depends.sh && grep -Eq 'libgpgme11t64\|t64' scripts/verify_depends.sh` (full proof: `DISTRO=24.04 bash scripts/verify_depends.sh` exits 0 on an Ubuntu host with built DESTDIR) | ✅ (net-new, exists) | ✅ green (audit 2026-06-06: structural PASS; on-host `DISTRO=24.04`/`DISTRO=26.04` runs exit 0 on ubuntu-24/ubuntu-26 — Plan 05 + 19-UAT.md evidence) |
| 19-04-02 | 04 | 3 | PKG-08 | T-19-09 / T-19-11 / T-19-SC | SMOKE_RUNTIME validated to exactly `docker`/`podman`; hard-error (no silent skip) when no runtime present; throwaway `--rm` container | smoke (container) | `bash -n scripts/smoke_install_2604.sh && test -x scripts/smoke_install_2604.sh && grep -q 'apt-get install' scripts/smoke_install_2604.sh && grep -Eq 'ubuntu:26.04\|resolute' scripts/smoke_install_2604.sh` (full proof: `bash scripts/smoke_install_2604.sh` installs cleanly on a host with a container runtime + 26.04-built debs) | ✅ (net-new, exists) | ✅ green (audit 2026-06-06: structural PASS; smoke exit 0 on ubuntu-26, libgpgme45/libsubid5 pulled — Plan 05 + 19-UAT.md Test 3 resolved) |
| 19-04-03 | 04 | 3 | PKG-08 (D-14) | T-19-10 / T-19-11 | Blocking human gate confirms the on-host proofs the autonomous tasks cannot exercise on the macOS dev host | manual (human-verify checkpoint) | manual — see Manual-Only Verifications | ✅ (proofs executed) | ✅ green (all four deferred on-host proofs executed green 2026-06-06 on Lima VMs; 19-UAT.md status: resolved, 19-VERIFICATION.md status: passed) |
| 19-05-01 | 05 | 1 | PKG-08, PKG-10 | T-19-06 (D-03) | Deps derived from DIRECT DT_NEEDED only (dpkg-shlibdeps semantics, no transitive closure); dynamic-loader pseudo-entry skipped; statically-linked binary yields empty dep set (not a hard-fail); D-03 hard-fail preserved for unresolved sonames of dynamic binaries | unit (compiled-fixture regression, dpkg-host-gated) | `bash tests/test_detect_distro_depends.sh` (Tests 7–9: gcc `-static` fixture → empty set; gcc `-lsystemd` fixture → libsystemd0 present, transitive extras liblz4-1/liblzma5/libzstd1/libgcrypt20/libgpg-error0 absent; loader entry absent. SKIP on non-dpkg hosts; full run on ubuntu-24) | ✅ (tests added 2026-06-06) | ✅ green (11/11 on ubuntu-24; 6/6 on macOS with Tests 7–9 SKIP) |
| 19-05-02 | 05 | 2 | PKG-08 | T-19-12 | Smoke co-installs the internal `podman-container-configs` sibling .deb with skopeo in one apt-get call; hard-error on empty sibling glob; skopeo install stays hard (no best-effort) so a real rename regression still fails the gate | integration (structural grep) + smoke (container) | `bash -n scripts/smoke_install_2604.sh && grep -q 'podman-container-configs_\*' scripts/smoke_install_2604.sh && grep -Eq 'apt-get install -y "\$\{configs_deb\[0\]\}" "\$\{skopeo_deb\[0\]\}"' scripts/smoke_install_2604.sh` (full proof: smoke exit 0 on ubuntu-26) | ✅ (smoke_install_2604.sh) | ✅ green (audit 2026-06-06: structural PASS; on-host smoke exit 0 on ubuntu-26 per 19-05-SUMMARY/UAT) |
| 19-05-03 | 05 | 3 | — (docs hygiene) | — | Every remaining skopeo `libsqlite3-0` reference in 19-RESEARCH/19-CONTEXT/19-PATTERNS annotated as stale/historical | docs (grep) | `grep -rn 'libsqlite3-0' .planning/phases/19-per-distro-versioning-dependency-mapping/19-{RESEARCH,CONTEXT,PATTERNS}.md \| grep -ivE 'stale\|removed\|not.*link\|pre-v3\|historical\|no sqlite\|falsifi'` exits non-zero (no unannotated refs) | ✅ (docs edited) | ✅ green (audit 2026-06-06: PASS) |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Net-new verification scripts created by this phase's plans (no pre-existing test framework to install — RESEARCH Validation Architecture):

- [x] `scripts/verify_versions.sh` — D-11 dpkg `--compare-versions` ordering assertions incl. the added legacy `~podman1` < new `~ubuntu24.04.podman1` upgrade assertion (PKG-09) — **created by Plan 03, Task 1** (exists; exit 0 on ubuntu-24)
- [x] `scripts/verify_depends.sh` — on-Ubuntu detector smoke (run `detect_runtime_depends` on every built binary), the t64-adjusted D-14 functional-equivalence baseline (PKG-10), and the `${DETECTED_DEPENDS}` render-and-parse check (incl. empty-deps and mixed-static-deps cases) — **created by Plan 04, Task 1** (exists; exit 0 on both distros after Plan 05 fix)
- [x] `scripts/smoke_install_2604.sh` — 26.04 container apt-install smoke, parameterized by component/arch with `SMOKE_RUNTIME`/`SMOKE_IMAGE` overrides (PKG-08) — **created by Plan 04, Task 2** (exists; exit 0 on ubuntu-26 after Plan 05 sibling-deb fix)

No xUnit framework install required — the project's "tests" are shell verification scripts plus a container smoke. The detector itself (`detect_runtime_depends`) and the version-suffix composition are created by Plan 01 in `functions.sh`/`config.sh`.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions | Outcome (2026-06-06) |
|----------|-------------|------------|-------------------|----------------------|
| 26.04-built .deb apt-installs cleanly on a real 26.04 userland (libgpgme45/libsubid5 resolve) | PKG-08 | Requires a real ubuntu:26.04 (or resolute) container userland the autonomous macOS dev host cannot exercise; gated by the Plan 04 Task 3 blocking human-verify checkpoint | Build for 26.04 in an ubuntu:26.04/resolute container, run `bash scripts/smoke_install_2604.sh`; expect skopeo (and podman) to apt-install cleanly and `skopeo --version` to print | ✅ EXECUTED GREEN — exit 0 on ubuntu-26 Lima VM; apt pulled libgpgme45 2.0.1-2build1, libsubid5 1:4.17.4-2ubuntu3, libassuan9 3.0.2-2build1; `skopeo --version` = 1.22.0 (19-UAT.md Test 3 resolved via Plan 05 commit 46017da) |
| 24.04 detected set is functionally equivalent to the pre-v3.0 hardcoded set (t64-aware) | PKG-10 (D-14) | Requires a real ubuntu:24.04 host with a populated DESTDIR and dpkg/ldd; t64 functional equivalence cannot be asserted on macOS; gated by the Plan 04 Task 3 checkpoint | Build for 24.04 (`DISTRO=24.04 ./scripts/package_all.sh`), run `DISTRO=24.04 bash scripts/verify_depends.sh`; expect exit 0 with libgpgme11t64/libglib2.0-0t64 present and non-t64 names unchanged, and every nFPM YAML render+parse clean | ✅ EXECUTED GREEN — exit 0 on ubuntu-24 Lima VM; Part A all PASS (t64-adjusted baseline incl. corrected skopeo `libgpgme11t64 libsubid4`), Part B 26/26 render+parse PASS (19-UAT.md Test 1 resolved via Plan 05 commit b1e43a3) |
| 26.04 detected set shows the renamed packages (self-corrected, no YAML edit) | PKG-08 | Requires the on-26.04 detector run; confirms the mechanism self-corrected | Inspect the 26.04 detected set recorded by `verify_depends.sh`; confirm it contains libgpgme45/libsubid5 | ✅ EXECUTED GREEN — `DISTRO=26.04 verify_depends.sh` exit 0 on ubuntu-26; detected sets show libgpgme45/libsubid5 with no transitive extras (19-05-SUMMARY) |

The blocking human-verify checkpoint (Plan 04, Task 3) confirms all of the above plus the `verify_versions.sh` ordering proof in one gate before the phase advances. **All four deferred on-host proofs were executed green on the Lima VMs on 2026-06-06** (19-UAT.md status: resolved; 19-VERIFICATION.md status: passed).

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies (Plan 04 Task 3 is an intentional `checkpoint:human-verify` with a `<human-check>` — the on-host/container proofs cannot be automated on the macOS dev host)
- [x] Sampling continuity: no 3 consecutive tasks without automated verify (every code-producing task carries an automated syntax/structural check; only the final checkpoint is manual)
- [x] Wave 0 covers all MISSING references (`verify_versions.sh`, `verify_depends.sh`, `smoke_install_2604.sh` are net-new, created by Plans 03/04; the detector/suffix live in functions.sh/config.sh created by Plan 01)
- [x] No watch-mode flags
- [x] Feedback latency < 10s (quick run is dpkg-only literal fixtures)
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-06-05

---

## Validation Audit 2026-06-06

| Metric | Count |
|--------|-------|
| Gaps found | 1 |
| Resolved | 1 |
| Escalated | 0 |

**Audit scope:** all 8 original map rows re-executed (macOS structural checks + ubuntu-24/ubuntu-26 Lima VM runs for the dpkg-dependent commands) — all green. Plan 05 (gap-closure, executed 2026-06-06 after this file was approved) added to the Per-Task Verification Map as rows 19-05-01..03.

**Gap resolved:** Task 19-05-01's detector rewrite (direct DT_NEEDED semantics, commit `b1e43a3`) had no unit-level regression coverage — only the slow on-host `verify_depends.sh` (full build + DESTDIR required) exercised the three new behaviors. `tests/test_detect_distro_depends.sh` extended with Tests 7–9 (compiled gcc fixtures, dpkg-host-gated, SKIP on macOS):
- Test 7: `gcc -static` fixture → empty dep set, exit 0 (static-binary handling)
- Test 8: `gcc -lsystemd` fixture → `libsystemd0` present AND transitive extras (liblz4-1/liblzma5/libzstd1/libgcrypt20/libgpg-error0) absent — the discriminating regression test for a transitive-closure rollback
- Test 9: dynamic-loader pseudo-entry (`ld-linux*.so`) absent from output

**Evidence:** 11/11 pass on ubuntu-24 (real compiled fixtures, libsystemd-dev present); 6/6 pass on macOS (Tests 7–9 SKIP cleanly).

**Known advisory (intentionally NOT tested):** CR-01 from 19-REVIEW.md (missing `objdump` → silent empty dep set passes D-03) is a documented impl hardening gap deferred to Phase 21 CI work — a test would fail against current impl; tracked there, not here.
