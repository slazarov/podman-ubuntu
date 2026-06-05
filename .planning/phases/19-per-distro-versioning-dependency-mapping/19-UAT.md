---
status: testing
phase: 19-per-distro-versioning-dependency-mapping
source: [19-VERIFICATION.md]
started: 2026-06-05T12:55:00Z
updated: 2026-06-05T12:55:00Z
---

## Current Test

number: 1
name: 24.04 functional equivalence (D-14, t64-aware)
expected: |
  On an Ubuntu 24.04 host with the build pipeline run (`DISTRO=24.04 ./scripts/package_all.sh` with populated DESTDIR), `DISTRO=24.04 bash scripts/verify_depends.sh` exits 0: the detected dependency set functionally equals the t64-adjusted baseline (libgpgme11t64/libglib2.0-0t64 present; libseccomp2/libsystemd0/libcap2/libsqlite3-0/libsubid4 unchanged), and every nFPM YAML renders+parses for both DISTRO=24.04 and 26.04.
awaiting: user response

## Tests

### 1. 24.04 functional equivalence (D-14, t64-aware)
expected: `DISTRO=24.04 bash scripts/verify_depends.sh` exits 0 on Ubuntu 24.04 with built DESTDIR — detected set functionally equals the t64-adjusted baseline; render-and-parse passes for all components (confirms PKG-10 + SC-4)
result: [pending]

### 2. Version ordering oracle (D-11)
expected: `bash scripts/verify_versions.sh` exits 0 on any dpkg host — all six `dpkg --compare-versions` assertions hold (suffixed < official, 24.04 < 26.04, nightly < tagged, legacy ~podman1 < ~ubuntu24.04.podman1, D-09/D-10 forms) (confirms PKG-09 + SC-2)
result: [pending]

### 3. 26.04 apt-install smoke (PKG-08)
expected: With 26.04-built .debs and a container runtime, `bash scripts/smoke_install_2604.sh` apt-installs skopeo cleanly inside ubuntu:26.04 (or resolute), pulling libgpgme45/libsubid5, and `skopeo --version` prints (confirms PKG-08 + SC-1)
result: [pending]

### 4. 26.04 self-corrected dependency set (PKG-10 → PKG-08 mechanism)
expected: The 26.04 detected set recorded by verify_depends.sh contains the renamed packages (libgpgme45, libsubid5) with ZERO nFPM YAML edits — proving the detector self-corrects on distro renames. Also note whether fuse-overlayfs/catatonit surface any real system dep (after libc6/libgcc-s1 exclusion); if so, their YAMLs need a ${DETECTED_DEPENDS} block added.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
