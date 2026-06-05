---
phase: 19-per-distro-versioning-dependency-mapping
verified: 2026-06-05T13:30:00Z
status: human_needed
score: 8/12 must-haves verified (4 deferred to human verification)
overrides_applied: 0
human_verification:
  - test: "Build for DISTRO=24.04 and run verify_depends.sh exit 0"
    expected: "DISTRO=24.04 bash scripts/verify_depends.sh exits 0; detected set functionally equals the t64-adjusted baseline (libgpgme11t64/libglib2.0-0t64 present; non-t64 names unchanged); every nFPM YAML renders and parses successfully"
    why_human: "Requires an Ubuntu 24.04 host with dpkg, ldd, nfpm, and a fully populated DESTDIR from a real build run. macOS dev host cannot satisfy any of these conditions."
  - test: "Run bash scripts/verify_versions.sh on a dpkg host"
    expected: "All 6 assert_lt orderings pass, script exits 0, prints 'All version ordering assertions passed'"
    why_human: "dpkg is not available on the macOS dev host. Script is structurally verified and orderings are sound by dpkg tilde semantics (documented in 19-RESEARCH.md Pitfall 2), but exit-0 runtime proof requires a Linux system with dpkg installed."
  - test: "Build 26.04 packages and run bash scripts/smoke_install_2604.sh"
    expected: "skopeo (and optionally podman) apt-installs cleanly inside an ubuntu:26.04 or resolute container, pulling libgpgme45 / libsubid5, and skopeo --version prints successfully. Script exits 0."
    why_human: "Requires a container runtime (docker or podman) that can pull ubuntu:26.04 / resolute, and 26.04-built .deb files in output/. The host cannot run Ubuntu 26.04 build containers."
  - test: "Confirm 26.04 detected set shows renamed packages (libgpgme45/libsubid5) with zero YAML edits"
    expected: "The 26.04 detected set recorded by verify_depends.sh contains libgpgme45 and libsubid5 — proving the ldd->dpkg-query mechanism self-corrected for the rename without any nFPM YAML change."
    why_human: "Requires running detect_runtime_depends against 26.04-built binaries inside an ubuntu:26.04 environment. Verifies PKG-08 mechanism correctness (not just structural wiring)."
---

# Phase 19: Per-Distro Versioning & Dependency Mapping — Verification Report

**Phase Goal:** Each distro's packages carry a distinct version identity and declare the runtime dependencies that actually exist on that distro, so building the same upstream version for two distros produces installable, non-colliding .deb files
**Verified:** 2026-06-05T13:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | config.sh exports VERSION_SUFFIX as ~ubuntu{VERSION_ID}.podman1 derived from the build host | VERIFIED | `config.sh:51` exports `VERSION_SUFFIX="~ubuntu${DISTRO_VERSION_ID}.podman1"`; DISTRO=26.04 and DISTRO=24.04 override paths tested on dev host; syntax clean |
| 2 | A DISTRO env var override forces the version suffix without reading /etc/os-release | VERIFIED | `detect_distro_version_id()` at `functions.sh:55-57` checks `${DISTRO:-}` first; `DISTRO="26.04"` bash test returns "26.04" exit 0; `DISTRO="2604"` correctly rejected by regex |
| 3 | detect_runtime_depends() returns soname-derived owning package names and hard-fails on any unmapped library | VERIFIED (structural) | Function at `functions.sh:101-135` uses ldd->realpath->dpkg-query->dedupe; hard-fail guard at line 117-119; libc6/libgcc-s1 excluded; no soname literals. Full ELF->package proof requires Ubuntu host (human verification) |
| 4 | detect_distro_version_id() hard-fails when VERSION_ID cannot be determined and no DISTRO override is set | VERIFIED | Error path at `functions.sh:63-65`; regex validation at lines 69-72; both tested on dev host via function isolation |
| 5 | package_all.sh derives each component's system-library depends from its binaries at build time via detect_runtime_depends | VERIFIED (structural) | `package_all.sh:374` calls `detect_runtime_depends "${component_bins[@]}" | sed 's/^/  - /'`; COMPONENT_BINARIES map present at lines ~290-301 covering all 10 binary-shipping components including pasta with both passt+pasta; no `|| true` (D-03 preserved) |
| 6 | The hardcoded VERSION_SUFFIX line in package_all.sh is gone; per-distro VERSION_SUFFIX from config.sh is appended in the packaging loop | VERIFIED | `grep -cE '^[[:space:]]*VERSION_SUFFIX="~podman1"'` returns 0; package_all.sh:26 comment confirms config.sh is authoritative; 4 `${VERSION_SUFFIX}` append sites at lines 340/351/404/407 intact |
| 7 | detect_crun_parser_depend and the CRUN_PARSER_DEPEND special case are fully removed | VERIFIED | `grep -c 'detect_crun_parser_depend' package_all.sh` = 0; `grep -c 'CRUN_PARSER_DEPEND' package_all.sh` = 0; `grep -r 'CRUN_PARSER_DEPEND' packaging/nfpm/` = 0 |
| 8 | Every nFPM YAML that carried hardcoded system-lib deps now injects ${DETECTED_DEPENDS} and keeps only internal podman-* deps literal | VERIFIED | All 6 YAMLs (crun/podman/buildah/skopeo/conmon/pasta) contain `${DETECTED_DEPENDS}` at column 0; no hardcoded libgpgme11/libseccomp2/libsystemd0/libcap2/libglib2.0-0/libsubid4/libsqlite3-0; podman.yaml retains 8 internal podman-* deps; skopeo.yaml+buildah.yaml retain podman-container-configs; pasta gained a depends block |
| 9 | A suffixed version sorts below the plain upstream version | UNCERTAIN | Assertion present in `verify_versions.sh` (`assert_lt "5.5.2~ubuntu24.04.podman1" "5.5.2"`); script syntax and structure verified; runtime proof requires dpkg host (human verification #2) |
| 10 | The 24.04 suffix form sorts below the 26.04 suffix form | UNCERTAIN | Assertion present verbatim; dpkg runtime required |
| 11 | A nightly form sorts below the tagged-release form for the same distro | UNCERTAIN | Assertion present verbatim; dpkg runtime required |
| 12 | The legacy ~podman1 form sorts below the new ~ubuntu24.04.podman1 form | UNCERTAIN | Assertion present verbatim; dpkg runtime required |

**Score:** 8/12 truths verified (4 require dpkg/Ubuntu host — human verification)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `functions.sh` | detect_distro_version_id() and detect_runtime_depends() | VERIFIED | Both functions present at lines 52-135; syntax clean; DISTRO override path tested |
| `config.sh` | VERSION_SUFFIX composition from distro VERSION_ID | VERIFIED | Lines 44-53; exports DISTRO_VERSION_ID and VERSION_SUFFIX; detect_distro_version_id called at load time |
| `scripts/package_all.sh` | Per-component detection + ${DETECTED_DEPENDS} injection | VERIFIED | detect_runtime_depends call at line 374; COMPONENT_BINARIES map; envsubst allowlist updated; crun special case removed; syntax clean |
| `packaging/nfpm/crun.yaml` | depends block driven by ${DETECTED_DEPENDS} | VERIFIED | ${DETECTED_DEPENDS} at column 0, line 16; no hardcoded system libs |
| `packaging/nfpm/podman.yaml` | ${DETECTED_DEPENDS} + 8 internal podman-* deps preserved | VERIFIED | Both present; hardcoded libgpgme11/libseccomp2 removed |
| `packaging/nfpm/buildah.yaml` | ${DETECTED_DEPENDS} + podman-container-configs | VERIFIED | Both present; hardcoded libs removed |
| `packaging/nfpm/skopeo.yaml` | ${DETECTED_DEPENDS} + podman-container-configs | VERIFIED | Both present; hardcoded libs removed |
| `packaging/nfpm/conmon.yaml` | ${DETECTED_DEPENDS} only | VERIFIED | ${DETECTED_DEPENDS} at column 0; hardcoded libglib2.0-0/libsystemd0 removed |
| `packaging/nfpm/pasta.yaml` | New depends block with ${DETECTED_DEPENDS} | VERIFIED | depends block added; ${DETECTED_DEPENDS} at column 0, line 16 |
| `scripts/verify_versions.sh` | dpkg --compare-versions assertions, D-11 ordering, executable | VERIFIED (structural) | Syntax clean; executable; set -euo pipefail; dpkg --compare-versions present; 7 assert_lt invocations (6 calls + 1 def); all 4 mandatory D-11 literals present verbatim |
| `scripts/verify_depends.sh` | On-Ubuntu detector smoke + D-14 baseline + render/parse check | VERIFIED (structural) | Syntax clean; executable; set -euo pipefail; detect_runtime_depends + envsubst + libgpgme11t64 + libglib2.0-0t64 all present; runtime requires Ubuntu host |
| `scripts/smoke_install_2604.sh` | 26.04 container apt-install proof | VERIFIED (structural) | Syntax clean; executable; apt-get install + ubuntu:26.04/resolute + command -v docker/podman + SMOKE_RUNTIME + --rm all present; runtime requires container environment |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| config.sh | functions.sh::detect_distro_version_id | function call at config load | WIRED | config.sh:12 sources functions.sh; config.sh:47 calls detect_distro_version_id directly |
| functions.sh::detect_runtime_depends | dpkg-query -S | resolved .so path lookup | WIRED | functions.sh:116 `dpkg-query -S "$(realpath "${lib}")"` |
| scripts/package_all.sh | functions.sh::detect_runtime_depends | per-component call on DESTDIR binaries | WIRED | package_all.sh:374 `detect_runtime_depends "${component_bins[@]}"` |
| scripts/package_all.sh | packaging/nfpm/*.yaml | envsubst with ${DETECTED_DEPENDS} in allowlist | WIRED | package_all.sh:381 envsubst allowlist `'${VERSION} ${ARCH} ${DESTDIR} ${DETECTED_DEPENDS}'` |
| scripts/verify_versions.sh | dpkg --compare-versions | assert_lt wrapper | WIRED (structural) | Pattern present; runtime execution deferred to dpkg host |
| scripts/verify_depends.sh | functions.sh::detect_runtime_depends | run detector on every built binary | WIRED (structural) | detect_runtime_depends call present; runtime deferred to Ubuntu host |
| scripts/smoke_install_2604.sh | ubuntu:26.04 container | apt-get install of the built .deb | WIRED (structural) | ubuntu:26.04/resolute reference present; runtime deferred to container host |

### Data-Flow Trace (Level 4)

This phase produces shell scripts that manipulate data at build time — not components that render UI. Level 4 data-flow traces apply to the critical path:

| Flow | Source | Transform | Destination | Status |
|------|--------|-----------|-------------|--------|
| Distro identity | DISTRO env or /etc/os-release | detect_distro_version_id() regex-validates | VERSION_SUFFIX in config.sh | FLOWING (code path verified on dev host) |
| Per-component system libs | DESTDIR binaries via ldd | detect_runtime_depends() -> sed indent | ${DETECTED_DEPENDS} in envsubst | WIRED (structural; full flow requires Ubuntu host) |
| ${DETECTED_DEPENDS} | package_all.sh DETECTED_DEPENDS export | envsubst into nFPM YAML | nFPM depends: block in .deb | WIRED (structural; render-and-parse requires nfpm on Ubuntu host) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| DISTRO override accepted | `DISTRO="26.04" bash -c 'source functions.sh; detect_distro_version_id'` | "26.04" exit 0 | PASS |
| Compact DISTRO form rejected | `DISTRO="2604" bash -c 'source functions.sh; detect_distro_version_id'` | non-zero exit | PASS |
| functions.sh syntax clean | `bash -n functions.sh` | exit 0 | PASS |
| config.sh syntax clean | `bash -n config.sh` | exit 0 | PASS |
| package_all.sh syntax clean | `bash -n scripts/package_all.sh` | exit 0 | PASS |
| verify_versions.sh syntax + executable | `bash -n scripts/verify_versions.sh && test -x ...` | exit 0 | PASS |
| verify_depends.sh syntax + executable | `bash -n scripts/verify_depends.sh && test -x ...` | exit 0 | PASS |
| smoke_install_2604.sh syntax + executable | `bash -n scripts/smoke_install_2604.sh && test -x ...` | exit 0 | PASS |
| verify_versions.sh runtime (dpkg oracle) | `bash scripts/verify_versions.sh` | DEFERRED: dpkg absent on macOS | SKIP |
| verify_depends.sh runtime (Ubuntu + DESTDIR) | `DISTRO=24.04 bash scripts/verify_depends.sh` | DEFERRED: requires Ubuntu host | SKIP |
| smoke_install_2604.sh runtime (container) | `bash scripts/smoke_install_2604.sh` | DEFERRED: requires container + 26.04 debs | SKIP |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|---------|
| PKG-09 | 19-01, 19-03 | Per-distro version suffix distinct and dpkg-sortable | VERIFIED (structural; runtime dpkg proof human-needed) | VERSION_SUFFIX=~ubuntu${DISTRO_VERSION_ID}.podman1 in config.sh; all 4 mandatory orderings present in verify_versions.sh; REQUIREMENTS.md marks PKG-09 Complete |
| PKG-08 | 19-02, 19-04 | 26.04 packages declare renamed runtime deps (libgpgme45, libsubid5) so apt install succeeds | PARTIAL — mechanism wired; on-host proof deferred | ${DETECTED_DEPENDS} injection wired; smoke_install_2604.sh authored and structurally verified; apt-install execution requires human verification |
| PKG-10 | 19-01, 19-02, 19-04 | Runtime deps resolved from ldd soname->package at build time | PARTIAL — mechanism wired; end-to-end proof deferred | detect_runtime_depends() present and wired into package_all.sh pipeline; verify_depends.sh with t64 baseline authored; real ELF->package proof requires Ubuntu host |

All three requirements claimed by Phase 19 plans are accounted for. No orphaned requirements.

**Notes on requirement status vs REQUIREMENTS.md:**
- PKG-09 marked `[x]` (Complete) in REQUIREMENTS.md — justified: VERSION_SUFFIX code path verified on dev host; verify_versions.sh structural check passes; dpkg runtime execution is confirmatory, not definitional
- PKG-08 and PKG-10 remain `[ ]` (Pending) in REQUIREMENTS.md — correct: on-host proofs required before these can be marked complete

### Anti-Patterns Found

No TBD, FIXME, or XXX markers found in any file modified by this phase.

No unreferenced debt markers. No stub implementations in the critical code path.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| functions.sh | 116 | `2>/dev/null` swallows dpkg-query stderr; `head -n1` after `awk` can misparse diversion records (REVIEW CR-01, WR-01) | WARNING | D-03 hard-fail safety property holds (unmapped lib still aborts build); but operator diagnostic degrades — opaque ERR-trap failure instead of actionable "no owning package for X" message. Not a correctness blocker for the safety property; is a diagnosability gap. |
| verify_depends.sh | 210-213 | `partA_fail` global accumulator suppresses PASS lines after first failure (REVIEW WR-03) | WARNING | Multi-component failure report is misleading — operator loses pass/fail status of components after the first failure. Does not affect whether the overall script exits correctly. |
| verify_depends.sh | 181-184 | `T64_EXPECTED` check accepts t64 names for any component, not just those whose baseline includes the substitution (REVIEW WR-04) | WARNING | Could rubber-stamp a misattributed dep (e.g. conmon suddenly reporting libgpgme11t64). Weakens the equivalence check T-19-10 is meant to provide. |
| functions.sh | 69-72 | `^[0-9]+\.[0-9]+$` regex + `~ubuntu` literal hard-fails on Debian VERSION_ID="12" (single integer) (REVIEW WR-05) | INFO | Repo is named podman-debian but Phase 19 is Ubuntu-only by design. Error message should say "Ubuntu only" explicitly. No impact for the declared Phase 19 scope (Ubuntu 24.04/26.04). |

### Human Verification Required

The following four proofs require a real Ubuntu userland with the build pipeline run. They were explicitly deferred in 19-04-SUMMARY.md when the Task 3 checkpoint was auto-approved under --auto chain mode.

#### 1. 24.04 Functional Equivalence Proof (verify_depends.sh)

**Test:** On an Ubuntu 24.04 host with populated DESTDIR: `DISTRO=24.04 ./scripts/package_all.sh` then `DISTRO=24.04 bash scripts/verify_depends.sh`
**Expected:** Exit 0; detected set for podman/buildah shows libgpgme11t64 (not libgpgme11); for conmon shows libglib2.0-0t64 (not libglib2.0-0); all non-t64 deps (libseccomp2, libsystemd0, libcap2, libsqlite3-0, libsubid4) match the pre-v3.0 baseline unchanged; every nFPM YAML renders and parses without error; version strings in built .debs carry `~ubuntu24.04.podman1`
**Why human:** dpkg, ldd, nfpm, and a populated DESTDIR from a real 24.04 build are all Linux-only. Confirms PKG-10 mechanism correctness and PKG-08/SC-4 (24.04 no regression).

#### 2. Version Ordering Oracle Proof (verify_versions.sh)

**Test:** On any host with dpkg: `bash scripts/verify_versions.sh`
**Expected:** All 6 assert_lt orderings pass; script prints OK lines for each, prints "All version ordering assertions passed", exits 0
**Why human:** dpkg is absent on the macOS dev host. Script is structurally correct and orderings are sound by dpkg tilde semantics, but exit-0 runtime proof requires a Linux system. Confirms PKG-09/SC-2 (ordering).

#### 3. 26.04 Container apt-install Smoke (smoke_install_2604.sh)

**Test:** On a host with docker or podman and 26.04-built .debs in output/: `bash scripts/smoke_install_2604.sh`
**Expected:** apt-get install of the podman-skopeo_*_*.deb (and optionally podman-suite) inside ubuntu:26.04 (or resolute) container exits 0; renamed deps libgpgme45 and libsubid5 are pulled automatically; `skopeo --version` prints; container removed with --rm
**Why human:** Requires a container runtime able to pull ubuntu:26.04/resolute and 26.04-built .deb files. Confirms PKG-08/SC-1 (26.04 installability with renamed deps).

#### 4. 26.04 Self-Corrected Dep Set Confirmation

**Test:** After running verify_depends.sh with DISTRO=26.04 (or inspecting the recorded output from the 26.04 build run), confirm the detected set for podman/buildah/skopeo shows libgpgme45 (not libgpgme11) and libsubid5 (not libsubid4)
**Expected:** The ldd->dpkg-query mechanism automatically picked up the 26.04-renamed packages without any nFPM YAML edit — confirming the D-04 "no soname special-case" design is correct
**Why human:** Requires 26.04 build environment. Confirms the PKG-10 mechanism delivers PKG-08 correctness automatically.

### Code Review Findings Summary (from 19-REVIEW.md)

The code review found 1 Critical + 6 Warning findings. None are safety-property blockers but several affect diagnosability:

- **CR-01 (Critical — diagnosability):** `2>/dev/null` on `dpkg-query -S` + `head -n1` after `awk` means an unmapped library hard-fails the build (correct) but with a generic ERR-trap error rather than the intended "no owning package for X" message. WR-01 adds: diversion records can cause `awk | head` to return "diversion by foo" as the package name, which would produce an uninstallable .deb. These are recommended fixes before the on-host proofs are run.
- **WR-02:** inject-only components (crun/conmon/pasta) produce `depends: null` YAML if detection yields an empty set. verify_depends.sh Part B would FAIL this as garbled. Latent issue for statically-linked binary edge case.
- **WR-03, WR-04:** verify_depends.sh diagnosability issues — PASS-line suppression after first failure; overly-permissive t64 allowlist.
- **WR-05:** Ubuntu-only regex is correct for Phase 19 scope but error message should be explicit.

These findings are advisory for the current verification; they do not change the structural VERIFIED status of the wiring. However, CR-01 and WR-01 should be addressed before the on-host proofs are run to ensure accurate failure diagnosis.

### Gaps Summary

No structural gaps. All phase artifacts exist, are syntactically valid, and are wired correctly. The four human_verification items are not gaps — the work (script authoring, structural validation, wiring) was done correctly on the dev host; the proofs require an Ubuntu execution environment that is not available here.

The REVIEW findings (CR-01, WR-01 in particular) are advisory fixes recommended before running the on-host proofs, but do not constitute phase-goal failures.

---

_Verified: 2026-06-05T13:30:00Z_
_Verifier: Claude (gsd-verifier)_
