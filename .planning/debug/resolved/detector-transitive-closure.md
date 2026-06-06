---
status: resolved
trigger: "DISTRO=24.04 verify_depends.sh exits 1 with 23 Part-A FAIL lines on real Ubuntu 24.04 build — every binary-linking component over-reports the TRANSITIVE deps of its baseline libs, plus skopeo missing baseline dep libsqlite3-0"
created: 2026-06-06T00:00:00Z
updated: 2026-06-06T18:10:00Z
---

## Current Focus

hypothesis: "TWO independent root causes. (1) CODE BUG in functions.sh detect_runtime_depends(): it parses full `ldd` output (line 145), which resolves the ENTIRE transitive shared-library closure (deps of deps), whereas Debian policy (dpkg-shlibdeps) derives Depends from the binary's DIRECT DT_NEEDED entries only. This makes every component over-report (the 23 'unexpected dep' FAILs are exactly the NEEDED deps of the baseline libs). (2) DATA BUG in verify_depends.sh BASELINE_24_04: skopeo's entry includes libsqlite3-0 which is stale — skopeo v1.22.0 built with BUILDTAGS='seccomp apparmor systemd' (no sqlite tag) does not link sqlite, so the detector correctly omits it and the baseline's missing-direction check FAILs."
test: "CONFIRMED both. (1) functions.sh:145 uses ldd full closure. (2) skopeo build tags contain no sqlite; the libsqlite3-0 datum traces to commit e6cdba1 hardcoded list carried verbatim into the baseline."
expecting: "n/a — both confirmed."
next_action: "Diagnose-only mode (find_root_cause_only). Return ROOT CAUSE FOUND; plan-phase --gaps handles the fix (no source edits performed)."

## Symptoms

expected: "On Ubuntu 24.04 with populated DESTDIR from a real build, `DISTRO=24.04 bash scripts/verify_depends.sh` exits 0: each component's detected system-library deps equal the t64-adjusted pre-v3.0 hardcoded baseline (podman/buildah: libgpgme11t64 libseccomp2; skopeo: libgpgme11t64 libsubid4 libsqlite3-0; crun: libseccomp2 libsystemd0 libcap2 + one JSON parser; conmon: libglib2.0-0t64 libsystemd0)."
actual: "Exit 1, 23 Part-A FAIL lines. Every binary-linking component over-reports the TRANSITIVE deps of its baseline libs: podman/buildah +libassuan0,libgpg-error0; crun +libgcrypt20,libgpg-error0,liblz4-1,liblzma5,libzstd1; conmon +libcap2,libgcrypt20,libgpg-error0,liblz4-1,liblzma5,libpcre2-8-0,libzstd1; skopeo +libassuan0,libaudit1,libcap-ng0,libgpg-error0,libpcre2-8-0,libselinux1. PLUS skopeo MISSING baseline dep libsqlite3-0 (detected set: [libassuan0 libaudit1 libcap-ng0 libgpg-error0 libgpgme11t64 libpcre2-8-0 libselinux1 libsubid4] — no sqlite)."
errors: "23 lines of 'FAIL: {component} detected unexpected dep {name} not in the t64-adjusted D-14 baseline [...]' + 'FAIL: skopeo is missing expected baseline dep libsqlite3-0' + 'FAIL: Part A — 24.04 detected set diverged from the t64-adjusted D-14 baseline'."
reproduction: "Test 1 in 19-UAT.md. Lima VM ubuntu-24, repo at /opt/podman-debian: `sudo env HOME=/root PATH=... bash -c 'cd /opt/podman-debian && export DESTDIR=/root/podman-staging && DISTRO=24.04 bash scripts/verify_depends.sh'`."
started: "Always broken — verify_depends.sh authored on macOS (no ldd/dpkg), on-host proofs DEFERRED to UAT; first real run is this UAT (2026-06-06)."

## Eliminated

<!-- APPEND only -->

## Evidence

- timestamp: 2026-06-06T00:00:00Z
  checked: "functions.sh detect_runtime_depends() lines 108-158"
  found: "Line 145 feeds the loop from `ldd \"${bin}\" | awk '/=> \\// {print $3}'`. ldd resolves the ENTIRE transitive shared-object closure (every library loaded at runtime including deps-of-deps), not just the binary's direct DT_NEEDED entries. Every `=> /path` line — direct or transitive — is fed to realpath -> dpkg-query -S -> owning package. Comment at lines 97-99 explicitly says 'ldd enumerates resolved libraries' and treats the full set as the dep set."
  implication: "Confirms hypothesis (a): the detector walks the full transitive closure. The extras reported in the UAT are EXACTLY the NEEDED deps of the baseline libs (gpgme -> libassuan0+libgpg-error0; libsystemd0 -> libgcrypt20/liblz4-1/liblzma5/libzstd1; libsubid -> libaudit1/libcap-ng0/libselinux1; libglib/libselinux -> libpcre2-8-0). Debian policy via dpkg-shlibdeps derives Depends from DIRECT DT_NEEDED only and lets each dependency package declare ITS OWN transitive deps — so the over-reporting is a real correctness bug, not just noisy output."

- timestamp: 2026-06-06T00:00:00Z
  checked: "26.04 cross-check from 19-UAT.md Test 4 evidence"
  found: "On 26.04 the SAME detector reports crun = [libcap2 libseccomp2 libsystemd0 libyajl2] — clean, no compression libs — because systemd >=257 dlopens its compression libs instead of NEEDED-linking them, so they do not appear in ldd's closure on 26.04. On 24.04 (systemd <257) those same libs ARE NEEDED-linked by libsystemd0 and thus appear in ldd's closure."
  implication: "Independent confirmation that the extras come from walking the transitive closure of what the dependency libs themselves link — the detected set tracks the closure, not the component binary's direct links. The 26.04 'clean' result is an accident of systemd's dlopen change, not detector correctness."

- timestamp: 2026-06-06T00:00:00Z
  checked: "Why a transitive-closure walk cannot by itself explain skopeo's MISSING libsqlite3-0 (the one under-report FAIL, distinct from the 23 over-report FAILs)"
  found: "ldd's full closure can only ADD names (it is a superset of direct DT_NEEDED). A genuinely-linked lib — direct OR transitive — would therefore ALWAYS appear in the detected set. skopeo's detected set is [libassuan0 libaudit1 libcap-ng0 libgpg-error0 libgpgme11t64 libpcre2-8-0 libselinux1 libsubid4] with NO sqlite at any depth. So the skopeo failure is a SECOND, INDEPENDENT root cause: the baseline asserts a dep the binary does not have. The transitive-closure bug (cause 1) and the stale baseline (cause 2) are orthogonal — fixing one does not fix the other."
  implication: "Confirms attribution (c): BOTH a code bug (functions.sh) AND a data bug (verify_depends.sh BASELINE_24_04) must be named. Cause 1 produces all 23 'unexpected dep' over-report FAILs; cause 2 produces the single 'missing libsqlite3-0' under-report FAIL."

- timestamp: 2026-06-06T00:00:00Z
  checked: "scripts/build_skopeo.sh BUILDTAGS + SKOPEO_TAG in versions-stable.env + git origin of the libsqlite3-0 baseline datum"
  found: "build_skopeo.sh line 59: BUILDTAGS=\"seccomp apparmor systemd\" — NO sqlite-enabling tag (no libsqlite3, no containers_image_sqlite). SKOPEO_TAG=v1.22.0 (versions-stable.env:19). The libsqlite3-0 datum originated in commit e6cdba1 (2026-03-06 'add missing runtime library dependencies'), which hardcoded `- libgpgme11 / - libsubid4 / - libsqlite3-0` into skopeo.yaml with the comment 'runtime deps verified via ldd /usr/bin/skopeo'. That hardcoded inventory predates v1.22.0 (config.sh still carries commented SKOPEO_VERSION=1.19.0). Phase 19-02 (commit 5c6aa3b) dropped the hardcoded libs in favor of ${DETECTED_DEPENDS}, but Phase 19-04 lifted the SAME three names verbatim into BASELINE_24_04 (verify_depends.sh:122) WITHOUT re-verifying against the actual v1.22.0 binary. The 19-RESEARCH.md A2 assumption explicitly listed libsqlite3-0 as a skopeo baseline dep 'verify on host' — the on-host verification (this UAT) is what falsified it."
  implication: "libsqlite3-0 in BASELINE_24_04 is a stale data carryover, not a current direct link of skopeo v1.22.0. The fix for cause 2 is to remove libsqlite3-0 from skopeo's BASELINE_24_04 entry (skopeo baseline becomes: libgpgme11t64 libsubid4). NOTE: the live skopeo.yaml itself is already correct (it injects ${DETECTED_DEPENDS}, carries no hardcoded sqlite) — only the verification BASELINE is wrong."

## Resolution

root_cause: |
  TWO independent root causes produce the verify_depends.sh exit-1:

  (1) CODE BUG — transitive-closure over-reporting (accounts for all 23 'unexpected dep' FAILs).
  functions.sh detect_runtime_depends() (line 145) derives the dependency set from
  `ldd "${bin}" | awk '/=> \// {print $3}'`. ldd resolves the FULL transitive shared-object
  closure (every library loaded at runtime, including deps-of-deps), so each component's detected
  set is contaminated with the NEEDED deps of its OWN deps: gpgme -> libassuan0+libgpg-error0;
  libsystemd0 -> libgcrypt20/liblz4-1/liblzma5/libzstd1; libsubid -> libaudit1/libcap-ng0/libselinux1;
  libglib/libselinux -> libpcre2-8-0. Debian policy (dpkg-shlibdeps) derives Depends from a binary's
  DIRECT DT_NEEDED entries ONLY and relies on each dependency package to declare its own transitive
  deps. The fix is to enumerate direct DT_NEEDED sonames (objdump -p | awk '/NEEDED/{print $2}' or
  readelf -d) and resolve ONLY those sonames to packages (still via ldd/ldconfig -p -> realpath ->
  dpkg-query, just filtered to the direct-NEEDED soname set). The 26.04 'clean' crun result is an
  accident of systemd>=257 dlopening its compression libs, NOT detector correctness — confirming the
  extras come from the closure of the dep libs.

  (2) DATA BUG — stale skopeo baseline datum (accounts for the single 'missing libsqlite3-0' FAIL).
  scripts/verify_depends.sh BASELINE_24_04["skopeo"] (line 122) asserts libsqlite3-0, but skopeo
  v1.22.0 built with BUILDTAGS="seccomp apparmor systemd" (build_skopeo.sh:59 — no sqlite tag) does
  not link sqlite at any depth. ldd's closure can only ADD names, so the absence is conclusive: the
  binary genuinely has no sqlite linkage. libsqlite3-0 was carried verbatim from the pre-v3.0
  hardcoded skopeo.yaml (commit e6cdba1, written against an older skopeo) into the verification
  baseline without re-checking against v1.22.0. The fix is to drop libsqlite3-0 from
  BASELINE_24_04["skopeo"] (-> "libgpgme11t64 libsubid4").

  These are ORTHOGONAL: cause 1 is in functions.sh (the detector), cause 2 is in verify_depends.sh
  (the test data). Both must be fixed for Test 1 to pass.

fix: "(empty — diagnose-only mode; plan-phase --gaps handles fixes)"
verification: "(empty — diagnose-only mode)"
files_changed: []
