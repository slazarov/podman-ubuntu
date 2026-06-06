---
status: complete
phase: 19-per-distro-versioning-dependency-mapping
source: [19-VERIFICATION.md]
started: 2026-06-05T12:55:00Z
updated: 2026-06-06T16:49:00Z
---

## Current Test

[testing complete]

## Tests

### 1. 24.04 functional equivalence (D-14, t64-aware)
expected: `DISTRO=24.04 bash scripts/verify_depends.sh` exits 0 on Ubuntu 24.04 with built DESTDIR — detected set functionally equals the t64-adjusted baseline; render-and-parse passes for all components (confirms PKG-10 + SC-4)
result: issue
reported: "verify_depends.sh exits 1 on ubuntu-24 (real build, DESTDIR=/root/podman-staging). 23 FAIL lines in Part A: every binary-linking component detects extra TRANSITIVE libs beyond its baseline (podman/buildah: +libassuan0,libgpg-error0; crun: +libgcrypt20,libgpg-error0,liblz4-1,liblzma5,libzstd1; conmon: +libcap2,libgcrypt20,libgpg-error0,liblz4-1,liblzma5,libpcre2-8-0,libzstd1; skopeo: +libassuan0,libaudit1,libcap-ng0,libgpg-error0,libpcre2-8-0,libselinux1). Also skopeo is MISSING baseline dep libsqlite3-0 (binary does not link sqlite). ldd resolves the full transitive closure, not direct DT_NEEDED. Build+packaging itself succeeded (13 debs, correct ~ubuntu24.04.podman1 suffix); Part B never ran."
severity: blocker

### 2. Version ordering oracle (D-11)
expected: `bash scripts/verify_versions.sh` exits 0 on any dpkg host — all six `dpkg --compare-versions` assertions hold (suffixed < official, 24.04 < 26.04, nightly < tagged, legacy ~podman1 < ~ubuntu24.04.podman1, D-09/D-10 forms) (confirms PKG-09 + SC-2)
result: pass
evidence: "Ran on ubuntu-24 Lima VM (24.04): all 6 OK lines printed, 'All version ordering assertions passed', EXIT=0"

### 3. 26.04 apt-install smoke (PKG-08)
expected: With 26.04-built .debs and a container runtime, `bash scripts/smoke_install_2604.sh` apt-installs skopeo cleanly inside ubuntu:26.04 (or resolute), pulling libgpgme45/libsubid5, and `skopeo --version` prints (confirms PKG-08 + SC-1)
result: issue
reported: "smoke_install_2604.sh exits 100 on ubuntu-26 (SMOKE_RUNTIME=podman, image ubuntu:26.04 pulled OK). apt refuses: 'podman-skopeo : Depends: podman-container-configs but it is not installable' — the script feeds apt ONLY the skopeo .deb, but skopeo.yaml declares the internal sibling dep podman-container-configs which is not in the Ubuntu archive. The script anticipated this trap for podman (best-effort install + comment) but not for skopeo. MECHANISM PROOF STILL HOLDS: manual probe installing podman-container-configs_*.deb + podman-skopeo_*.deb together in the same ubuntu:26.04 container succeeds — apt pulls libgpgme45 2.0.1-2build1, libsubid5 1:4.17.4-2ubuntu3, libassuan9 3.0.2-2build1 from the archive and 'skopeo --version' prints 1.22.0."
severity: major

### 4. 26.04 self-corrected dependency set (PKG-10 → PKG-08 mechanism)
expected: The 26.04 detected set recorded by verify_depends.sh contains the renamed packages (libgpgme45, libsubid5) with ZERO nFPM YAML edits — proving the detector self-corrects on distro renames. Also note whether fuse-overlayfs/catatonit surface any real system dep (after libc6/libgcc-s1 exclusion); if so, their YAMLs need a ${DETECTED_DEPENDS} block added.
result: pass
evidence: "verify_depends.sh DISTRO=26.04 exits 0 on ubuntu-26 with real 26.04 build. Detected sets: podman/buildah=[libassuan9 libgpg-error0 libgpgme45 libseccomp2], skopeo=[libassuan9 libaudit1 libcap-ng0 libgpg-error0 libgpgme45 libpcre2-8-0 libselinux1 libsubid5], crun=[libcap2 libseccomp2 libsystemd0 libyajl2], conmon=[libatomic1 libglib2.0-0t64 libpcre2-8-0 libsystemd0]. libgpgme45 + libsubid5 present with zero YAML edits; even transitive libassuan0->libassuan9 rename self-corrected. fuse-overlayfs/pasta are 'not a dynamic executable' (static) and netavark/aardvark-dns/catatonit detect [] — no YAML follow-up needed. All 26 render+parse checks (13 YAMLs x 2 distros) PASS. Live apt probe confirmed the detected names resolve from the resolute archive. Caveat: sets still include transitive extras (Test 1 issue) — does not affect the rename-self-correction proof."

## Summary

total: 4
passed: 2
issues: 2
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "DISTRO=24.04 verify_depends.sh exits 0 — detected dependency set functionally equals the t64-adjusted D-14 baseline"
  status: failed
  reason: "Tested on ubuntu-24 Lima VM with real build: exit 1, 23 Part-A FAIL lines. detect_runtime_depends (functions.sh) uses ldd, which returns the full TRANSITIVE shared-library closure, not the binary's direct DT_NEEDED entries — so every component over-reports deps of its deps (gpgme pulls libassuan0+libgpg-error0; libsystemd pulls libgcrypt20/liblz4-1/liblzma5/libzstd1; libsubid pulls libaudit1/libcap-ng0/libselinux1; libglib/libselinux pull libpcre2-8-0). Debian policy (dpkg-shlibdeps) derives Depends from direct NEEDED only. Separately: skopeo baseline expects libsqlite3-0 but the v1.22.0 binary does not link sqlite at all (baseline datum likely stale from pre-v3.0 hardcoded list)."
  severity: blocker
  test: 1
  artifacts: []  # Filled by diagnosis
  missing: []    # Filled by diagnosis

- truth: "smoke_install_2604.sh apt-installs skopeo cleanly inside ubuntu:26.04, pulling libgpgme45/libsubid5, and skopeo --version prints"
  status: failed
  reason: "Tested on ubuntu-26 Lima VM (SMOKE_RUNTIME=podman): exit 100. The container's apt-get install receives only the skopeo .deb, but skopeo.yaml declares internal sibling dep podman-container-configs which is not in the Ubuntu archive — apt refuses with 'podman-container-configs but it is not installable'. The script handles this trap for podman (best-effort) but not skopeo, even though podman-container-configs_*.deb is built and present in output/. Manual probe installing both .debs together PASSES (libgpgme45/libsubid5/libassuan9 pulled from archive, skopeo 1.22.0 runs) — so this is a smoke-script harness gap, not a PKG-08 mechanism failure."
  severity: major
  test: 3
  artifacts: []  # Filled by diagnosis
  missing: []    # Filled by diagnosis
