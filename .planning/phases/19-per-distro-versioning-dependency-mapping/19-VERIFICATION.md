---
phase: 19-per-distro-versioning-dependency-mapping
verified: 2026-06-06T22:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: human_needed
  previous_score: 8/12 must-haves verified (4 deferred to human verification)
  gaps_closed:
    - "DISTRO=24.04 verify_depends.sh exits 0 on ubuntu-24 — transitive-closure over-reporting fixed (objdump DT_NEEDED); stale libsqlite3-0 dropped from BASELINE_24_04[skopeo]; Part A all PASS, Part B 26/26 PASS (commit b1e43a3)"
    - "smoke_install_2604.sh exits 0 on ubuntu-26 — podman-container-configs sibling .deb co-installed with skopeo in single apt-get; libgpgme45/libsubid5/libassuan9 resolved from archive, skopeo --version = 1.22.0 (commit 46017da)"
    - "DISTRO=26.04 verify_depends.sh exits 0 on ubuntu-26 with no regression (no transitive extras; libgpgme45/libsubid5 detected via mechanism)"
    - "verify_versions.sh exit 0 on ubuntu-24 — all 6 ordering assertions passed (UAT Test 2, not a gap, confirmed passing)"
  gaps_remaining: []
  regressions: []
---

# Phase 19: Per-Distro Versioning & Dependency Mapping — Verification Report

**Phase Goal:** Each distro's packages carry a distinct version identity and declare the runtime dependencies that actually exist on that distro, so building the same upstream version for two distros produces installable, non-colliding .deb files
**Verified:** 2026-06-06T22:00:00Z
**Status:** PASSED
**Re-verification:** Yes — after gap closure via Plan 19-05 (gap_closure: true)

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | A package built with DISTRO=26.04 declares the renamed 26.04 dependencies (libgpgme45, libsubid5) instead of the 24.04 names, and apt install resolves them on a real ubuntu:26.04 system | VERIFIED | skopeo.yaml + buildah.yaml + podman.yaml inject `${DETECTED_DEPENDS}` at column 0. detect_runtime_depends uses dpkg-query -S against the 26.04 host DB which returns libgpgme45/libsubid5 automatically (no hardcoded soname mapping). UAT Test 3 (resolved in 19-UAT.md, status: resolved): smoke_install_2604.sh exit 0 on ubuntu-26, apt pulled libgpgme45 2.0.1-2build1, libsubid5 1:4.17.4-2ubuntu3, libassuan9 3.0.2-2build1 from the archive, skopeo --version = 1.22.0. Commit 46017da. |
| SC-2 | The same upstream version built for each distro produces distinct version strings (~ubuntu24.04.podman1 vs ~ubuntu26.04.podman1) that satisfy dpkg --compare-versions: each sorts below the official upstream version, and the 24.04 form sorts below the 26.04 form so dist-upgrades order correctly | VERIFIED | config.sh line 51: `export VERSION_SUFFIX="~ubuntu${DISTRO_VERSION_ID}.podman1"`. detect_distro_version_id() honors DISTRO override (tested on macOS host: DISTRO=26.04 returns "26.04", DISTRO=2604 rejected by regex). verify_versions.sh has all 6 assert_lt orderings including the required `5.5.2~ubuntu24.04.podman1 < 5.5.2~ubuntu26.04.podman1` and `5.5.2~ubuntu24.04.podman1 < 5.5.2`. UAT Test 2 (passed from the start): exit 0 on ubuntu-24, all 6 OK lines, "All version ordering assertions passed". |
| SC-3 | Runtime library dependencies are derived at build time from the binaries' linked sonames (ldd soname→package mapping) rather than hardcoded, so a future distro rename is picked up without editing nFPM config by hand | VERIFIED | detect_runtime_depends() uses objdump -p NEEDED → per-binary ldd soname→path resolution → realpath → dpkg-query -S (host package DB only). Confirmed: no hardcoded soname→package mapping anywhere in functions.sh (grep returns zero matches for libjson-c/libyajl literals). All 6 target nFPM YAMLs inject `${DETECTED_DEPENDS}`; old hardcoded system-lib lines (libgpgme11, libseccomp2, libsystemd0, libcap2, libglib2.0-0, libsubid4, libsqlite3-0) are completely absent from packaging/nfpm/. Old detect_crun_parser_depend() + CRUN_PARSER_DEPEND fully removed from package_all.sh. |
| SC-4 | Building for 24.04 with the new code path produces packages byte-functionally equivalent to the pre-v3.0 24.04 packages (no regression to the shipping pipeline) | VERIFIED | verify_depends.sh Part A baseline asserts detected set equals t64-adjusted D-14 baseline. UAT Test 1 (resolved in 19-UAT.md via 19-05 commit b1e43a3): DISTRO=24.04 verify_depends.sh exit 0 on ubuntu-24 — Part A all PASS (podman/buildah=libgpgme11t64 libseccomp2; skopeo=libgpgme11t64 libsubid4; crun=libcap2 libseccomp2 libsystemd0 libyajl2; conmon=libglib2.0-0t64 libsystemd0). Part B 26/26 PASS. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `functions.sh` | detect_distro_version_id() + detect_runtime_depends() | VERIFIED | Both functions defined. detect_distro_version_id: DISTRO override → /etc/os-release → hard-fail; regex validates ^[0-9]+\.[0-9]+$. detect_runtime_depends: objdump -p NEEDED → per-binary ldd map → realpath → dpkg-query -S; libc6/libgcc-s1 excluded; ld-linux loader skipped; static binaries handled as zero-dep; D-03 hard-fail on unresolved NEEDED or unmapped soname. `bash -n` clean. Commit b1e43a3 rewrote the function from ldd-closure to direct DT_NEEDED. |
| `config.sh` | VERSION_SUFFIX composition from detect_distro_version_id | VERIFIED | Line 47: `export DISTRO_VERSION_ID="$(detect_distro_version_id)"`. Line 51: `export VERSION_SUFFIX="~ubuntu${DISTRO_VERSION_ID}.podman1"`. functions.sh sourced at line 12 so detect_distro_version_id is in scope. Tested in isolation (macOS): DISTRO=26.04 → function returns 26.04; composition `~ubuntu${DISTRO_VERSION_ID}.podman1` is correct. `bash -n` clean. |
| `scripts/verify_versions.sh` | dpkg --compare-versions ordering proof, executable | VERIFIED | Present and executable. 7 assert_lt invocations including all 4 mandatory D-11 orderings + 26.04 nightly + pasta date form. All required literals verified by grep. `bash -n` clean. UAT Test 2 passed on ubuntu-24 (not a gap). |
| `scripts/verify_depends.sh` | On-Ubuntu detector smoke + D-14 baseline + render/parse | VERIFIED | BASELINE_24_04[skopeo]="libgpgme11t64 libsubid4" (libsqlite3-0 removed at line 122). detect_runtime_depends wired. T64_PRE_SUBST per-component t64 acceptance map present. Part A + Part B logic confirmed. `bash -n` clean. UAT Test 1 resolved (exit 0 on ubuntu-24). |
| `scripts/smoke_install_2604.sh` | 26.04 container apt-install smoke (PKG-08) | VERIFIED | configs_deb=( /out/podman-container-configs_*.deb ) globbed at line 158. Hard-error if empty (guard at line 171-175). `apt-get install -y "${configs_deb[0]}" "${skopeo_deb[0]}"` at line 183 (single invocation). Skopeo install stays hard (no best-effort guard). `bash -n` clean. UAT Test 3 resolved (exit 0 on ubuntu-26, skopeo 1.22.0). Commit 46017da. |
| `scripts/package_all.sh` | detect_runtime_depends wired; DETECTED_DEPENDS injection; no hardcoded suffix | VERIFIED | `VERSION_SUFFIX="~podman1"` removed (config.sh authoritative, comment at line 27 confirms). detect_crun_parser_depend + CRUN_PARSER_DEPEND fully gone (grep returns 0). COMPONENT_BINARIES map at lines 290-301 with pasta having both passt+pasta. INJECT_ONLY_DEPENDS map at lines 310-314. detect_runtime_depends called per-component at line 392. envsubst allowlist includes DETECTED_DEPENDS at line 408. `bash -n` clean. |
| 6 nFPM YAMLs: crun/podman/buildah/skopeo/conmon/pasta | ${DETECTED_DEPENDS} injection; hardcoded sys-libs removed | VERIFIED | All 6 contain ${DETECTED_DEPENDS}. No nFPM YAML contains literal hardcoded system-lib dep lines (verified by grep). crun.yaml has ${DETECTED_DEPENDS} at column 0 (inject-only). podman.yaml retains all 8 internal podman-* deps. skopeo.yaml + buildah.yaml retain podman-container-configs. pasta.yaml gained a depends block. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| config.sh | functions.sh::detect_distro_version_id | function call at config load time | WIRED | functions.sh sourced at config.sh:12; `export DISTRO_VERSION_ID="$(detect_distro_version_id)"` at line 47. Function tested directly: DISTRO=26.04 → returns "26.04". |
| functions.sh::detect_runtime_depends | dpkg-query -S | resolved .so path lookup (outside pipeline) | WIRED | `if ! dpkg_out="$(dpkg-query -S "${resolved}" 2>&1)"; then ... return 1` at line 181-185. Run outside pipeline with explicit exit-status test. |
| scripts/package_all.sh | functions.sh::detect_runtime_depends | per-component call on DESTDIR binaries | WIRED | 4 occurrences of detect_runtime_depends in package_all.sh. Called inside the packaging loop with ${DESTDIR}/${rel_bin} expanded paths. No `|| true` (D-03 preserved under set -euo pipefail + ERR trap). |
| scripts/package_all.sh | packaging/nfpm/*.yaml | envsubst with ${DETECTED_DEPENDS} in allowlist | WIRED | `envsubst '${VERSION} ${ARCH} ${DESTDIR} ${DETECTED_DEPENDS}'` at line 408. CRUN_PARSER_DEPEND removed from the allowlist. |
| scripts/smoke_install_2604.sh | /out/podman-container-configs_*.deb | glob fed to same apt-get invocation as skopeo .deb | WIRED | `configs_deb=( /out/podman-container-configs_*.deb )` at line 158. Hard-error if empty. `apt-get install -y "${configs_deb[0]}" "${skopeo_deb[0]}"` at line 183 — single invocation so apt co-resolves local .debs and needs archive only for system deps. |
| scripts/verify_depends.sh | functions.sh::detect_runtime_depends | run detector on every built binary, compare to baseline | WIRED | `detect_runtime_depends "${component_bins[@]}"` called in the Part A loop. Same function as package_all.sh uses. |

### Probe Execution

The phase's verification probes are the Lima VM on-host runs. They cannot be re-executed from the macOS host. The 19-UAT.md (status: resolved) and 19-05-SUMMARY.md record the authoritative human-executed evidence.

| Probe | Evidence | Status |
|-------|----------|--------|
| `DISTRO=24.04 bash scripts/verify_depends.sh` on ubuntu-24 | 19-UAT.md Test 1 (resolved): exit 0, Part A all PASS, Part B 26/26 PASS. Commit b1e43a3. | PASS (UAT-verified) |
| `DISTRO=26.04 bash scripts/verify_depends.sh` on ubuntu-26 | 19-UAT.md Test 1 caveat + 19-05-SUMMARY.md: exit 0, libgpgme45/libsubid5 detected, no transitive extras; no regression. | PASS (UAT-verified) |
| `SMOKE_RUNTIME=podman bash scripts/smoke_install_2604.sh` on ubuntu-26 | 19-UAT.md Test 3 (resolved): exit 0, apt pulled libgpgme45/libsubid5/libassuan9 from archive, skopeo --version 1.22.0. Commit 46017da. | PASS (UAT-verified) |
| `bash scripts/verify_versions.sh` on ubuntu-24 | 19-UAT.md Test 2 (passed, not a gap): exit 0, all 6 OK lines, "All version ordering assertions passed". | PASS (UAT-verified) |

### Requirements Coverage

| Requirement | Plans | Description | Status | Evidence |
|-------------|-------|-------------|--------|---------|
| PKG-08 | 19-02, 19-04, 19-05 | 26.04 packages declare correct renamed runtime deps (libgpgme45, libsubid5) so apt install succeeds | SATISFIED | ${DETECTED_DEPENDS} injection wired through package_all.sh → envsubst → nFPM YAMLs. smoke_install_2604.sh exit 0 on ubuntu-26 (UAT Test 3 resolved). libgpgme45/libsubid5 confirmed pulled from archive. REQUIREMENTS.md marks PKG-08 [x] Complete. |
| PKG-09 | 19-01, 19-03 | Per-distro version suffix ~ubuntu24.04.podman1 / ~ubuntu26.04.podman1; dpkg-sortable | SATISFIED | config.sh exports VERSION_SUFFIX="~ubuntu${DISTRO_VERSION_ID}.podman1". verify_versions.sh all 6 assertions pass on ubuntu-24 (UAT Test 2). Distinct filenames confirmed by ~ubuntu24.04.podman1 vs ~ubuntu26.04.podman1 suffix. REQUIREMENTS.md marks PKG-09 [x] Complete. |
| PKG-10 | 19-01, 19-02, 19-05 | Runtime deps resolved at build time via ldd soname→package detection; no hardcoded mapping | SATISFIED | detect_runtime_depends() with objdump DT_NEEDED → ldd resolution → dpkg-query -S; no hardcoded soname→package map confirmed. Wired through package_all.sh. verify_depends.sh Part A all PASS on ubuntu-24 (UAT Test 1 resolved). REQUIREMENTS.md marks PKG-10 [x] Complete. |

No orphaned requirements: REQUIREMENTS.md traceability table maps PKG-08/PKG-09/PKG-10 to Phase 19 and all are marked complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none found) | — | — | — | — |

No TBD/FIXME/XXX markers, no TODO/HACK/PLACEHOLDER patterns found in any file modified by this phase. No unreferenced debt markers.

### Code Review Advisory Findings (19-REVIEW.md — post-plan-05, status: issues_found)

The 19-REVIEW.md (reviewed 2026-06-06) identified 2 critical and 5 warning findings in the gap-closure code. Per the developer's re-verification context, these are advisory robustness/future-proofing concerns, not failures of the phase's ROADMAP success criteria. The on-host proofs in the UAT already ran successfully with these gaps present, confirming the current-state code works on properly-equipped Ubuntu build hosts.

**CR-01 (19-REVIEW.md): objdump availability not checked** — `objdump -p "${bin}"` runs inside a process substitution (`done < <(objdump -p ... | awk ...)`) whose exit status is not propagated. A missing `objdump` binary silently yields zero NEEDED entries, producing an empty dep set that passes D-03. `verify_depends.sh` prerequisite check (line 72) does not include `objdump`. The UAT proofs ran on a host where `objdump` was present and working. This is a latent D-03 hardening gap for pipeline execution on a host without `binutils` installed. **Advisory: recommend adding objdump to the prerequisite check and running it outside the process substitution before the Phase 21 CI matrix build.**

**CR-02 (19-REVIEW.md): netavark/aardvark-dns/fuse-overlayfs/catatonit YAMLs lack ${DETECTED_DEPENDS}** — Detection runs on these 4 components but the result is never injected (their nFPM YAMLs have no placeholder). Currently their detected set is empty (static or Rust binaries with only libc6/libgcc-s1 excluded), so no real deps are dropped today. This is a latent correctness gap for when any of these components gain a real shared-library dependency. **Advisory: recommend adding ${DETECTED_DEPENDS} to these 4 YAMLs and to INJECT_ONLY_DEPENDS as appropriate before Phase 21.**

These findings do not affect the four ROADMAP success criteria, all of which are verified by the UAT evidence.

### Human Verification Required

None. All four ROADMAP success criteria have been humanly verified on the Lima VMs:
- SC-1 (PKG-08): smoke_install_2604.sh exit 0 on ubuntu-26 (UAT Test 3 resolved)
- SC-2 (PKG-09): verify_versions.sh exit 0 on ubuntu-24 (UAT Test 2 passed)
- SC-3 (PKG-10): detect_runtime_depends mechanism proven via verify_depends.sh (UAT Tests 1 and 4)
- SC-4 (regression): verify_depends.sh DISTRO=24.04 Part A all PASS on ubuntu-24 (UAT Test 1 resolved)

The 19-UAT.md status is `resolved` with all 4 tests either passed or resolved.

### Gaps Summary

No gaps. All four ROADMAP success criteria are verified with on-host evidence recorded in 19-UAT.md (status: resolved). The two 19-REVIEW.md critical findings are advisory future-proofing concerns that do not affect the phase's success criteria as defined in ROADMAP.md. They are noted above for follow-up in Phase 21.

---

_Verified: 2026-06-06T22:00:00Z_
_Verifier: Claude (gsd-verifier)_
