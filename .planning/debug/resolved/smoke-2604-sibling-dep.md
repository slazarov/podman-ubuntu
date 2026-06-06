---
status: resolved
trigger: "smoke_install_2604.sh exits 100 on ubuntu:26.04 — apt refuses 'podman-skopeo : Depends: podman-container-configs but it is not installable'; lib lines (libassuan9/libgpgme45/libsubid5) are cascade noise from the failed solve. Manual probe installing both podman-container-configs + podman-skopeo .debs together succeeds (skopeo 1.22.0 runs). PKG-08 mechanism works; this is a smoke-harness gap."
created: 2026-06-06T00:00:00Z
updated: 2026-06-06T18:10:00Z
---

## Current Focus

hypothesis: CONFIRMED — the smoke script feeds apt ONLY the podman-skopeo .deb, but skopeo.yaml declares a static internal sibling dep `podman-container-configs` that does not exist (by that name) in the Ubuntu/resolute archive. apt cannot satisfy it, fails the install, and the system-lib lines are cascade noise from the unsolvable graph.
test: Code reading of smoke_install_2604.sh step 4 + skopeo.yaml depends block + container-configs.yaml (the sibling package definition) + the UAT manual-probe evidence.
expecting: Confirmed — script must also install podman-container-configs_*.deb (ideally in the SAME apt-get invocation) so apt only needs the archive for SYSTEM deps.
next_action: return_diagnosis (goal: find_root_cause_only — do NOT fix)

## Symptoms

expected: With 26.04-built .debs in output/ and a container runtime, `bash scripts/smoke_install_2604.sh` exits 0 — apt-get install of the local podman-skopeo .deb inside ubuntu:26.04 resolves its declared Depends from the 26.04 archive (proving the renamed libgpgme45/libsubid5 names are correct) and `skopeo --version` prints. (PKG-08, SC-1)
actual: Exit 100 on Lima VM ubuntu-26 (SMOKE_RUNTIME=podman, image ubuntu:26.04 pulled fine, 13 26.04-built .debs present in output/ including podman-container-configs_0.67.0~ubuntu26.04.podman1_arm64.deb). apt refuses with podman-skopeo depending on podman-container-configs "but it is not installable", plus cascade noise on libassuan9/libgpgme45/libsubid5. Manual probe installing BOTH debs together (`apt-get install -y /out/podman-container-configs_*.deb /out/podman-skopeo_*.deb`) SUCCEEDS: libgpgme45 2.0.1-2build1, libsubid5 1:4.17.4-2ubuntu3, libassuan9 3.0.2-2build1 pulled from the archive, skopeo --version prints 1.22.0.
errors: |
  podman-skopeo : Depends: podman-container-configs but it is not installable
                  Depends: libassuan9 but it is not going to be installed
                  Depends: libgpgme45 but it is not going to be installed
                  Depends: libsubid5 but it is not going to be installed
  E: Unable to satisfy dependencies. Reached two conflicting assignments:
     1. podman-skopeo ...
     2. podman-skopeo:arm64 Depends podman-container-configs but none of the choices are installable: [no choices]
reproduction: Test 3 in 19-UAT.md. Lima VM ubuntu-26: `sudo env HOME=/root SMOKE_RUNTIME=podman bash -c "cd /root/podman-debian-build && bash scripts/smoke_install_2604.sh"`. (Diagnosed on macOS via code reading + UAT evidence; podman/apt cannot run on the dev box.)
started: Discovered during UAT 2026-06-06.

## Eliminated

- hypothesis: PKG-08 mechanism (ldd->dpkg-query rename self-correction) is broken — the renamed libgpgme45/libsubid5/libassuan9 names are wrong for 26.04.
  evidence: The UAT manual probe in the SAME ubuntu:26.04 image installing podman-container-configs + podman-skopeo together SUCCEEDS — apt pulls libgpgme45 2.0.1-2build1, libsubid5 1:4.17.4-2ubuntu3, libassuan9 3.0.2-2build1 straight from the resolute archive and skopeo --version prints 1.22.0. The renamed system-dep names are CORRECT. The lib lines in the failure output are cascade noise: apt reports the whole unsatisfiable closure once the graph has an unsolvable node (podman-container-configs), not separate failures. UAT Test 4 (PKG-10) independently passed and confirmed the detected set self-corrects with zero YAML edits.
  timestamp: 2026-06-06T00:00:00Z

- hypothesis: podman-container-configs is genuinely missing from output/ (build did not produce it), so the harness has nothing to install.
  evidence: UAT reports 13 26.04-built .debs present in output/, explicitly including podman-container-configs_0.67.0~ubuntu26.04.podman1_arm64.deb. The .deb IS present in the same /out mount the container sees; the script simply never globs/installs it. Not a build gap.
  timestamp: 2026-06-06T00:00:00Z

## Evidence

- timestamp: 2026-06-06T00:00:00Z
  checked: packaging/nfpm/skopeo.yaml depends block (lines 14-17)
  found: skopeo declares a STATIC, hardcoded first dependency `- podman-container-configs` (line 15), above the build-time-injected ${DETECTED_DEPENDS} (line 17). This is an internal suite sibling, not a system package.
  implication: Any standalone `apt-get install podman-skopeo.deb` will demand podman-container-configs by exact name from configured apt sources.

- timestamp: 2026-06-06T00:00:00Z
  checked: packaging/nfpm/container-configs.yaml
  found: podman-container-configs is an INTERNAL-only package (ships /etc/containers/*.conf, policy.json, registries.conf, storage.conf, seccomp.json, man5). It `provides`/`replaces`/`conflicts` golang-github-containers-common, but it is NOT published in the Ubuntu/resolute archive under either name reachable by apt during the smoke. It exists ONLY in output/.
  implication: apt has [no choices] to satisfy the literal `podman-container-configs` dependency name from the archive — it can only come from the local /out .deb, which the script never hands to apt.

- timestamp: 2026-06-06T00:00:00Z
  checked: scripts/smoke_install_2604.sh step 4 container block (lines 146-184)
  found: Inside the container it globs `skopeo_deb=( /out/podman-skopeo_*_*.deb )` and `podman_deb=( /out/podman-podman_*_*.deb )` ONLY (lines 156-158). The primary proof runs `apt-get install -y "${skopeo_deb[0]}"` ALONE (line 167) under `set -euo pipefail` (line 151). It never globs or installs `/out/podman-container-configs_*.deb`. With only skopeo handed to apt, podman-container-configs is unsatisfiable -> non-zero exit -> set -e aborts -> exit 100.
  implication: This is a harness gap: the sibling internal dep is sitting in the same /out mount but is never offered to apt, so apt treats it as an archive package it cannot find.

- timestamp: 2026-06-06T00:00:00Z
  checked: scripts/smoke_install_2604.sh podman best-effort block (lines 169-177)
  found: The script ALREADY anticipates this exact trap for podman: it installs the podman .deb best-effort with `|| echo "NOTE: ...sibling podman-* deps not in archive..."` and an explicit comment "podman declares internal podman-* deps that are not in the archive". The identical reasoning applies to skopeo's podman-container-configs dep, but skopeo is the PRIMARY (hard) proof with no best-effort guard — so its sibling-dep failure is fatal.
  implication: The fix pattern is already understood in the same file for podman; it was simply not applied to the primary skopeo install. Best-effort is the WRONG fix here though (it would mask real failures); the right fix is to also feed the sibling .deb to apt.

- timestamp: 2026-06-06T00:00:00Z
  checked: packaging/nfpm/buildah.yaml depends block (lines 14-17)
  found: buildah ALSO declares static `- podman-container-configs` (line 15), same pattern as skopeo. podman.yaml (lines 14-23) declares it plus seven other internal podman-* siblings.
  implication: If the smoke is ever extended to buildah, it would hit the identical wall. Any fix should be framed so it generalizes (install the sibling podman-container-configs .deb alongside whichever component .deb is being proved), not skopeo-special-cased in a brittle way.

- timestamp: 2026-06-06T00:00:00Z
  checked: PKG-08 intent vs. mechanism (script header lines 6-15) and UAT manual probe
  found: PKG-08 is meant to prove that the renamed SYSTEM deps (libgpgme45, libsubid5) resolve from the 26.04 archive with no nFPM YAML edit. apt accepts multiple local .debs in ONE invocation and co-resolves them. The manual probe `apt-get install -y /out/podman-container-configs_*.deb /out/podman-skopeo_*.deb` does exactly this and PASSES — apt then only needs the archive for the SYSTEM libs, which is precisely the PKG-08 signal.
  implication: Installing podman-container-configs together with (or before) skopeo in a single apt-get invocation makes apt need the archive ONLY for system deps — restoring the true PKG-08 test signal without weakening it.

## Resolution

root_cause: |
  Harness gap in scripts/smoke_install_2604.sh step 4. The primary-proof install hands apt ONLY the podman-skopeo .deb (line 167), but packaging/nfpm/skopeo.yaml line 15 declares a static internal sibling dependency `podman-container-configs`. That package is an internal-only suite package (packaging/nfpm/container-configs.yaml) that is NOT published in the Ubuntu/resolute archive under any name apt can resolve — it exists only as a .deb in output/ (the same /out mount, confirmed present). Because the script never offers /out/podman-container-configs_*.deb to apt, apt has [no choices] for the literal `podman-container-configs` name, the dependency solve fails, and the system-lib lines (libassuan9/libgpgme45/libsubid5) are cascade noise printed because the whole graph became unsatisfiable. Under `set -euo pipefail` the non-zero apt exit aborts the script -> exit 100. The script already anticipated this exact internal-sibling trap for podman (best-effort install + comment, lines 169-176) but did not apply the reasoning to the primary skopeo install. Manual probe installing both .debs together succeeds and skopeo 1.22.0 runs, so the PKG-08 rename-self-correction mechanism is sound — only the harness is wrong.
fix: ""  # find_root_cause_only — fix handled by plan-phase --gaps
verification: ""  # not fixed in this session
files_changed: []
