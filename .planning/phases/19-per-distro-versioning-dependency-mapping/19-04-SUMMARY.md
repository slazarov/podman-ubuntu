---
phase: 19-per-distro-versioning-dependency-mapping
plan: 04
subsystem: testing
tags: [bash, dpkg, ldd, nfpm, envsubst, apt, container, docker, podman, t64, dependency-detection]

# Dependency graph
requires:
  - phase: 19-per-distro-versioning-dependency-mapping
    provides: "Plan 01 detect_runtime_depends() + detect_distro_version_id(); Plan 02 ${DETECTED_DEPENDS} injection + COMPONENT_BINARIES; Plan 03 verify_versions.sh"
provides:
  - "scripts/verify_depends.sh — on-Ubuntu detector smoke, t64-adjusted D-14 functional-equivalence baseline, render-and-parse check for all nFPM YAMLs (both distros)"
  - "scripts/smoke_install_2604.sh — 26.04 container apt-install proof for renamed deps (libgpgme45/libsubid5) via docker/podman with --rm"
affects: [phase-21-cicd-pipeline, uat-on-host-verification]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "t64-aware functional-equivalence baseline (NOT string-equality) for the 24.04 no-regression check (RESEARCH Pitfall 1)"
    - "Render-and-parse validation: envsubst the nFPM YAML then nfpm pkg --config to catch empty/garbled depends blocks (Pitfall 3)"
    - "Runner-OS-agnostic install proof via a throwaway --rm container, runtime/image overridable (SMOKE_RUNTIME/SMOKE_IMAGE), hard-error (no silent skip) when no runtime present (T-19-11)"

key-files:
  created:
    - scripts/verify_depends.sh
    - scripts/smoke_install_2604.sh
  modified: []

key-decisions:
  - "fuse-overlayfs.yaml / catatonit.yaml were NOT edited — the detector run that would justify a ${DETECTED_DEPENDS} block is only obtainable on a real Ubuntu host; left unchanged pending the on-host detector run"
  - "The four end-to-end on-host proofs were DEFERRED, not executed — the macOS dev host has no dpkg/ldd/nfpm and cannot run Ubuntu 24.04/26.04 builds; the Task 3 checkpoint was auto-approved under --auto chain only to unblock the chain, not because the proofs passed"

patterns-established:
  - "Pattern 1: on-host proof scripts are authored and structurally validated on the dev host, then executed as UAT/CI gates on a real Ubuntu userland"
  - "Pattern 2: 24.04 no-regression is asserted as functional equivalence (t64 substitution documented) rather than string identity, so the t64 transition is not a false-failure trap"

requirements-completed: []

# Metrics
duration: 4min
completed: 2026-06-05
---

# Phase 19 Plan 04: End-to-End Verification Scripts Summary

**Two on-host proof scripts authored and structurally validated — `verify_depends.sh` (t64-adjusted 24.04 equivalence baseline + render-and-parse for both distros) and `smoke_install_2604.sh` (26.04 container apt-install proof) — with the four end-to-end on-host proofs DEFERRED to UAT because the macOS dev host cannot run them.**

## Performance

- **Duration:** ~4 min (Tasks 1–2 authoring; Task 3 is a human gate)
- **Started:** 2026-06-05T12:44:00Z (approx, Tasks 1–2 committed 15:45–15:46 +0300)
- **Completed:** 2026-06-05T12:48:07Z
- **Tasks:** 2 of 2 auto tasks complete; Task 3 checkpoint auto-approved (on-host proofs deferred)
- **Files modified:** 2 (both created)

## Accomplishments
- `scripts/verify_depends.sh` (0755) authored: sources functions.sh/config.sh, runs `detect_runtime_depends` on every built binary, asserts the detected 24.04 set is functionally equal to the t64-adjusted pre-v3.0 baseline (libgpgme11t64/libglib2.0-0t64 substituted; non-t64 names unchanged), records the 24.04 AND 26.04 detected sets to stdout, and render-and-parse-validates each nFPM YAML via `envsubst` + `nfpm pkg` for both DISTRO values. An undocumented 24.04 dep delta is a hard FAIL (T-19-10).
- `scripts/smoke_install_2604.sh` (0755) authored: selects a container runtime via `command -v docker`/`command -v podman` (overridable `SMOKE_RUNTIME`, validated to exactly docker|podman per T-19-09), pulls `ubuntu:26.04` with a `resolute` fallback (overridable `SMOKE_IMAGE`), `apt-get install`s the locally-built `podman-skopeo_*` .deb in a throwaway `--rm` container, and runs a post-install `skopeo --version` sanity check. Hard-errors (no silent skip) when no runtime is present (T-19-11).
- Both scripts pass all macOS-runnable structural verification (`bash -n`, executable bit, required-token greps).

## Task Commits

Each task was committed atomically:

1. **Task 1: verify_depends.sh — D-14 baseline + render/parse smoke** - `e0e2ab0` (feat)
2. **Task 2: smoke_install_2604.sh — 26.04 apt-install proof** - `90f17f8` (feat)
3. **Task 3: checkpoint:human-verify** — auto-approved under --auto chain; on-host proofs DEFERRED (see below). No code commit.

## Files Created/Modified
- `scripts/verify_depends.sh` - On-Ubuntu detector smoke + t64-adjusted D-14 functional-equivalence baseline + render-and-parse check for every nFPM YAML across both distros.
- `scripts/smoke_install_2604.sh` - 26.04 container apt-install proof that the renamed deps (libgpgme45/libsubid5) resolve from the 26.04 archive, runtime/image-overridable, hard-error on no runtime.

## Decisions Made
- **fuse-overlayfs.yaml / catatonit.yaml left UNCHANGED:** Plan 02 added both to COMPONENT_BINARIES so the detector runs on them, but whether they surface a real linked system lib (justifying a `${DETECTED_DEPENDS}` block) can only be determined by running `detect_runtime_depends` on a real Ubuntu host with built binaries. That run was not possible here, so neither YAML was edited. This is a conditional follow-up gated on the on-host detector run (see Open Items).
- **No empty depends block added** to either YAML — per the plan, an empty block is never added speculatively.

## Deviations from Plan

None - the two auto tasks were authored exactly as written. The only departure from the plan's happy path is the Task 3 checkpoint outcome, which is documented honestly below rather than recorded as a passed gate.

## Issues Encountered

- **macOS dev host cannot execute the end-to-end proofs (expected, environment-scoped):** This host has no `dpkg`, `ldd`, `nfpm`, and cannot run Ubuntu 24.04/26.04 builds or containers in a way that exercises a real Ubuntu userland. The four on-host proofs were therefore NOT executed. The Task 3 `checkpoint:human-verify` was auto-approved under `--auto` chain mode **only to unblock the chain** — this is explicitly NOT a record that the proofs passed.

## Task 3 — On-Host Proofs DEFERRED (NOT executed)

**Status:** checkpoint auto-approved under --auto chain; on-host proofs DEFERRED — NOT executed.

The following four proofs require a real Ubuntu userland with the build pipeline run for both distros. They are pending and must be performed as human-verification / UAT items before Phase 19 success criteria 1 and 4 can be marked satisfied:

1. **24.04 build + `DISTRO=24.04` verify_depends.sh exit 0:** `DISTRO=24.04 ./scripts/package_all.sh` (DESTDIR populated; version strings carry `~ubuntu24.04.podman1`), then `DISTRO=24.04 bash scripts/verify_depends.sh` — expect exit 0, detected set functionally equals the t64-adjusted baseline (libgpgme11t64/libglib2.0-0t64 present, non-t64 names unchanged), every nFPM YAML renders+parses.
2. **`verify_versions.sh` exit 0 on a dpkg host:** `bash scripts/verify_versions.sh` (Plan 03) — expect exit 0 (all dpkg orderings hold).
3. **26.04 container build + `smoke_install_2604.sh` clean apt-install:** Build packages for 26.04 inside an ubuntu:26.04 (or resolute) container, then `bash scripts/smoke_install_2604.sh` — expect skopeo (and podman) to apt-install cleanly, **pulling libgpgme45 / libsubid5**, and `skopeo --version` to print.
4. **26.04 detected set shows renamed packages with zero YAML edits:** Confirm the 26.04 detected set recorded by verify_depends.sh contains the renamed packages (libgpgme45, libsubid5) — proving the mechanism self-corrected without any nFPM YAML edit.

## Open Items

- **fuse-overlayfs / catatonit YAML follow-up (conditional):** If proof #1's on-host detector run surfaces one or more real linked system libs (after libc6/libgcc-s1 exclusion) for fuse-overlayfs or catatonit, add a `depends:` block with `${DETECTED_DEPENDS}` at column 0 to that component's YAML (same shape as Plan 02). If detection surfaces no system deps, leave both unchanged. This cannot be decided on the macOS dev host.

## User Setup Required

A verification host with a container runtime (docker or podman) able to pull `ubuntu:26.04` (or the `resolute` codename tag) is required to execute proof #3. See the plan's `user_setup` block. No service configuration beyond runtime availability.

## Next Phase Readiness
- Both proof scripts exist and are structurally sound; they are ready to run as Phase 21 CI gates and as UAT items on a real Ubuntu host.
- **Blocker for Phase 19 success criteria 1 and 4:** the four on-host proofs above are PENDING human/UAT execution. Phase 19 should not be marked verified until they pass on a real Ubuntu userland.

## Self-Check: PASSED (structural only)

Structural checks PASSED on macOS; end-to-end on-host proofs PENDING human verification (see Task 3 above).

- FOUND: scripts/verify_depends.sh (executable, `bash -n` clean, contains detect_runtime_depends/envsubst/t64 baseline)
- FOUND: scripts/smoke_install_2604.sh (executable, `bash -n` clean, contains apt-get install / ubuntu:26.04|resolute / command -v docker|podman)
- FOUND: .planning/phases/19-per-distro-versioning-dependency-mapping/19-04-SUMMARY.md
- FOUND: e0e2ab0 (feat Task 1)
- FOUND: 90f17f8 (feat Task 2)
- PENDING (NOT executed): 24.04 verify_depends.sh exit 0; verify_versions.sh exit 0; 26.04 smoke_install_2604.sh clean install; 26.04 detected set shows libgpgme45/libsubid5

---
*Phase: 19-per-distro-versioning-dependency-mapping*
*Completed: 2026-06-05 (on-host proofs deferred to UAT)*
