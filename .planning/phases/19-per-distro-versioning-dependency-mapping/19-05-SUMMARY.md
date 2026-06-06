---
phase: 19-per-distro-versioning-dependency-mapping
plan: 05
subsystem: infra
tags: [nfpm, dpkg, dpkg-shlibdeps, dt_needed, objdump, ldd, apt, ubuntu-2604, bash]

# Dependency graph
requires:
  - phase: 19-per-distro-versioning-dependency-mapping (Plans 01-04)
    provides: detect_runtime_depends() ldd->dpkg-query detector, verify_depends.sh D-14 baseline, smoke_install_2604.sh PKG-08 harness
provides:
  - detect_runtime_depends() deriving deps from DIRECT DT_NEEDED sonames only (dpkg-shlibdeps semantics, no transitive closure)
  - corrected BASELINE_24_04[skopeo] without the stale libsqlite3-0 datum
  - smoke_install_2604.sh installing the podman-container-configs sibling .deb alongside skopeo in one apt-get invocation
  - all three deferred on-host proofs (24.04 verify_depends, 26.04 verify_depends, 26.04 smoke) confirmed GREEN on Lima VMs
affects: [phase-21-ci-matrix, phase-20-apt-suites]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dependency detection via objdump -p NEEDED (direct DT_NEEDED) resolved through the per-binary ldd map, not the full ldd transitive closure"
    - "Statically-linked binaries (ldd 'not a dynamic executable') yield an empty dep set instead of hard-failing"
    - "Smoke harness co-installs internal sibling .debs with the proved component .deb in one apt-get call so apt needs the archive only for SYSTEM deps"

key-files:
  created:
    - .planning/phases/19-per-distro-versioning-dependency-mapping/19-05-SUMMARY.md
  modified:
    - functions.sh
    - scripts/verify_depends.sh
    - scripts/smoke_install_2604.sh
    - .planning/phases/19-per-distro-versioning-dependency-mapping/19-RESEARCH.md
    - .planning/phases/19-per-distro-versioning-dependency-mapping/19-CONTEXT.md
    - .planning/phases/19-per-distro-versioning-dependency-mapping/19-PATTERNS.md

key-decisions:
  - "Direct DT_NEEDED via objdump -p, resolved through the per-binary ldd map — matches dpkg-shlibdeps; deps-of-deps are NOT declared because each dependency package declares its own transitive deps"
  - "Skip the dynamic-loader pseudo-entry (ld-linux*.so / ld-*.so.*): objdump lists it as NEEDED but ldd has no `=> /path` for it; it is owned by libc6 (an EXCLUDE) so dropping it changes no result"
  - "ldd 'not a dynamic executable' (static binaries: fuse-overlayfs, catatonit) is a legitimate zero-dep case, not a breakage — continue with empty deps; D-03 hard-fail preserved for unresolved sonames of dynamic binaries"
  - "skopeo baseline corrected to libgpgme11t64 libsubid4 (libsqlite3-0 was a stale pre-v3.0 datum; skopeo v1.22.0 built with no sqlite BUILDTAG links no sqlite)"
  - "Smoke skopeo install stays HARD (no best-effort); only the internal sibling configs .deb is added so a real rename regression still fails the gate (T-19-12)"

patterns-established:
  - "Pattern: detector derives Depends from direct DT_NEEDED only (objdump -p NEEDED -> per-binary ldd soname=>path -> realpath -> dpkg-query -S), mirroring Debian dpkg-shlibdeps"
  - "Pattern: smoke harness offers internal-only sibling .debs (podman-container-configs) to apt from the local /out mount so the archive is only needed for system deps"

requirements-completed: [PKG-08, PKG-10]

# Metrics
duration: ~25min
completed: 2026-06-06
---

# Phase 19 Plan 05: Detector Transitive-Closure + Smoke Sibling-Dep Gap Closure Summary

**Fixed the dependency detector to use direct DT_NEEDED sonames (dpkg-shlibdeps semantics) instead of the full ldd transitive closure, dropped the stale skopeo libsqlite3-0 baseline, and taught the 26.04 smoke harness to install the podman-container-configs sibling .deb alongside skopeo — turning all three deferred Phase 19 on-host proofs green on the Lima VMs.**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-06-06 (Plan 05 execution)
- **Completed:** 2026-06-06
- **Tasks:** 3
- **Files modified:** 6 (3 scripts/source + 3 phase docs)

## Accomplishments
- `detect_runtime_depends()` now enumerates a binary's DIRECT DT_NEEDED sonames (`objdump -p | awk '/NEEDED/{print $2}'`) and resolves each through that binary's own ldd `soname => /path` map, eliminating the 23-line transitive-closure over-reporting that failed 24.04 verify_depends.
- Corrected `BASELINE_24_04[skopeo]` to `libgpgme11t64 libsubid4` (removed stale `libsqlite3-0` — skopeo v1.22.0 links no sqlite).
- `DISTRO=24.04 verify_depends.sh` now exits 0 on ubuntu-24 (Part A all PASS — podman/buildah=`libgpgme11t64 libseccomp2`, skopeo=`libgpgme11t64 libsubid4`, crun=`libcap2 libseccomp2 libsystemd0 libyajl2`, conmon=`libglib2.0-0t64 libsystemd0`; Part B 26/26 PASS).
- `DISTRO=26.04 verify_depends.sh` still exits 0 on ubuntu-26; detected sets show the renamed packages (`libgpgme45`, `libsubid5`) with no transitive extras — no regression to the rename-self-correction proof.
- `smoke_install_2604.sh` installs `/out/podman-container-configs_*.deb` + `/out/podman-skopeo_*.deb` in one apt-get call; exit 0 on ubuntu-26, apt pulled `libgpgme45 2.0.1-2build1`, `libsubid5 1:4.17.4-2ubuntu3`, `libassuan9 3.0.2-2build1` from the archive, `skopeo --version` printed 1.22.0.
- Annotated all stale skopeo `libsqlite3-0` references in the three phase docs so a future reader is not misled into re-adding it.

## Task Commits

Each task was committed atomically:

1. **Task 1: Derive deps from direct DT_NEEDED + drop stale skopeo baseline** - `b1e43a3` (fix)
2. **Task 2: Install podman-container-configs sibling .deb alongside skopeo in the smoke harness** - `46017da` (fix)
3. **Task 3: Annotate stale skopeo libsqlite3-0 references in phase docs** - `f6f427c` (docs)

**Plan metadata:** _(final docs commit — SUMMARY/STATE/ROADMAP/REQUIREMENTS)_

## Files Created/Modified
- `functions.sh` - `detect_runtime_depends()` rewritten to derive deps from direct DT_NEEDED sonames (objdump -p) resolved via the per-binary ldd map; loader pseudo-entry skipped; static-binary zero-dep case handled; header comment block updated to dpkg-shlibdeps semantics with the transitive-closure diagnosis cited.
- `scripts/verify_depends.sh` - `BASELINE_24_04[skopeo]` corrected to `libgpgme11t64 libsubid4` (stale `libsqlite3-0` removed).
- `scripts/smoke_install_2604.sh` - container step globs and installs the `podman-container-configs` sibling .deb together with skopeo in one apt-get invocation; hard-errors if the sibling glob is empty; skopeo install kept hard.
- `.planning/phases/.../19-RESEARCH.md`, `19-CONTEXT.md`, `19-PATTERNS.md` - skopeo `libsqlite3-0` references annotated as stale / not-actually-linked / historical; RESEARCH RESOLVED entry gained a CORRECTED note.

## Decisions Made
- **objdump -p NEEDED + per-binary ldd resolution** chosen over `readelf -d` for parse stability (plan-preferred); package name still comes only from `dpkg-query -S` (D-01/D-04 preserved — no hardcoded soname->package map; crun's JSON parser still falls out automatically as `libyajl2`).
- **Dynamic-loader skip** (`ld-linux*.so*`, `ld-*.so.*`): objdump lists the loader as NEEDED, but ldd has no `=> /path` resolution for it; it is owned by libc6 (an EXCLUDE), so dropping it changes no result while avoiding a false "did not resolve" hard-fail. This was an auto-fix discovered on the first arm64 on-host run (see Deviations).
- **Static-binary handling**: `ldd` exits non-zero with "not a dynamic executable" for statically-linked fuse-overlayfs/catatonit; treated as a legitimate empty dep set rather than a hard-fail. D-03 hard-fail discipline is preserved for genuinely unresolved NEEDED sonames of dynamic binaries.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Skip the dynamic-loader DT_NEEDED pseudo-entry**
- **Found during:** Task 1 (first on-host run on ubuntu-24, arm64)
- **Issue:** `objdump -p` lists `ld-linux-aarch64.so.1` as a NEEDED entry, but ldd prints the loader without a `=> /path` form, so the new per-soname resolver hard-failed with "direct NEEDED soname 'ld-linux-aarch64.so.1' did not resolve to an on-disk path". The plan's step 2 said to skip the loader "exactly as today" but did not anticipate the loader appearing in the objdump NEEDED list on arm64.
- **Fix:** Added a `case` guard skipping `ld-linux*.so*`, `ld.so*`, `ld-*.so.*` before resolution. The loader is owned by libc6 (already in EXCLUDE), so the result is unchanged.
- **Files modified:** functions.sh
- **Verification:** 24.04 verify_depends progressed past podman; final exit 0.
- **Committed in:** b1e43a3 (Task 1 commit)

**2. [Rule 1 - Bug] Statically-linked binary handling (ldd non-zero exit)**
- **Found during:** Task 1 (second on-host run on ubuntu-24)
- **Issue:** The new code ran `ldd` outside a pipeline and tested its exit status; for statically-linked binaries (fuse-overlayfs, catatonit) ldd exits non-zero with "not a dynamic executable", which hard-failed the detector. The OLD code masked this because the non-zero ldd exit inside a process substitution piped to awk was never checked. A static binary legitimately has zero dynamic deps — not a breakage.
- **Fix:** Detect the "not a dynamic executable" message and `continue` with an empty dep set for that binary; only hard-fail on unresolved sonames of genuinely dynamic binaries (D-03 preserved).
- **Files modified:** functions.sh
- **Verification:** 24.04 verify_depends completed all components (fuse-overlayfs/catatonit detected = []); final exit 0.
- **Committed in:** b1e43a3 (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 bug)
**Impact on plan:** Both auto-fixes are correctness requirements for the new direct-DT_NEEDED detector to run on real arm64 binaries and on statically-linked components. No scope creep — both are inside the function the plan directed me to change, and both preserve the D-03 hard-fail discipline the plan required.

## Issues Encountered
- ShellCheck is not installed on the macOS dev host (`command -v shellcheck` returns nothing), so the expected ShellCheck pass over the touched scripts could not be run locally. `bash -n` is clean on `functions.sh`, `scripts/verify_depends.sh`, and `scripts/smoke_install_2604.sh`, and all three on-host proofs run cleanly under `set -euo pipefail`. Recommend a ShellCheck pass in CI or on a Linux host.

## User Setup Required
None - no external service configuration required. (Verification ran in the existing Lima VMs ubuntu-24 / ubuntu-26.)

## Next Phase Readiness
- All four Phase 19 deferred on-host proofs are now satisfiable: this plan closed the two that were failing (24.04 verify_depends, 26.04 smoke) and confirmed the 26.04 verify_depends no-regression. The remaining proof (`verify_versions.sh`) was already passing per Plan 03.
- Phase 19 success criteria 1 (26.04 installable) and 4 (24.04 functional equivalence) are now demonstrably met on real Ubuntu.
- `fuse-overlayfs`/`catatonit` are confirmed statically linked (detected dep set = empty) on both distros — the conditional YAML follow-up noted in Plan 04 needs no system-dep injection for them.
- Ready for `/gsd-verify-work` on Phase 19.

## Self-Check: PASSED

- Files verified present: functions.sh, scripts/verify_depends.sh, scripts/smoke_install_2604.sh, 19-05-SUMMARY.md
- Commits verified in git log: b1e43a3 (Task 1), 46017da (Task 2), f6f427c (Task 3)
- On-host proofs all green: DISTRO=24.04 verify_depends exit 0 (ubuntu-24), DISTRO=26.04 verify_depends exit 0 (ubuntu-26), smoke_install_2604.sh exit 0 (ubuntu-26)

---
*Phase: 19-per-distro-versioning-dependency-mapping*
*Completed: 2026-06-06*
