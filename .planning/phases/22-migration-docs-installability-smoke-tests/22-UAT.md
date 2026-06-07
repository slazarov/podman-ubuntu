---
status: complete
phase: 22-migration-docs-installability-smoke-tests
source: [22-VERIFICATION.md]
started: 2026-06-07T00:00:00Z
updated: 2026-06-07T15:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. CI Smoke Gate Execution (MIGR-04)
expected: Run bash scripts/smoke_repo_install.sh 2404 and 2604 in Lima VMs or via CI publish workflow. Both legs print SMOKE PASS ��� apt install podman-suite and podman info exit 0 inside real ubuntu:24.04 and ubuntu:26.04 containers.
result: pass
evidence: "2404 leg: SMOKE PASS — podman-suite installed from nightly-2404 suite, podman info exited 0 in ubuntu:24.04 container (ubuntu-26 Lima VM, SMOKE_RUNTIME=podman). 2604 leg: SMOKE PASS — podman-suite installed from nightly-2604 suite, podman info exited 0 in ubuntu:26.04 container. 26.04 debs built from source (stable track) on ubuntu-26 VM: 13 packages, ~ubuntu26.04.podman1 suffix. Both legs run by Claude Code."

### 2. index.html Distro Toggle Visual (MIGR-02)
expected: Open the generated index.html in a browser. Ubuntu 24.04 is active by default. Clicking Ubuntu 26.04 swaps all three track-tab snippets to -2604 suite names. JS behavior cannot be verified by grep alone.
result: pass
evidence: "Opened index.html (generated via ci_publish.sh heredoc, stub repo) in Safari. Default state: Ubuntu 24.04 active button, stable tab shows Suites: stable-2404. After setDistro('2604') via AppleScript JS injection: Ubuntu 26.04 button active, snippet swapped to Suites: stable-2604 across all tabs. Deprecation notice and Package Versions section render. Table empty (expected — test repo has no amd64/bare-suite Packages files)."

### 3. Live Signed APT Install from Docs (MIGR-01 live path)
expected: On a real Ubuntu 24.04 or 26.04 system, follow docs/apt-repository.md instructions verbatim using the HTTPS Signed-By path. apt install podman-suite succeeds. (The CI smoke gate uses Trusted: yes over file:// and does not exercise this GPG-signed HTTPS path — accepted limitation D-14.)
result: issue
reported: "apt install fails on ubuntu-24 Lima VM with hash mismatch on podman-pasta_20260607~ubuntu24.04.podman1_arm64.deb: Packages index (stable-2404, from 02:39 UTC workflow_dispatch run) says Size=322824/SHA256=1bd861c5..., but CDN serves Size=322886/SHA256=be7560ad... The 08:05 UTC nightly scheduled build picked up a new upstream pasta commit (ec96f01 -> 21f4d13), rebuilt pasta with the same version string 20260607~ubuntu24.04.podman1, published it to nightly-2404, and overwrote the shared pool file. stable-2404 Packages index now has a dangling hash reference. Users following the docs on stable-2404 cannot install podman-suite."
severity: major

## Summary

total: 3
passed: 2
issues: 1
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "apt install podman-suite succeeds on Ubuntu 24.04 following docs/apt-repository.md verbatim via HTTPS Signed-By path"
  status: failed
  reason: "User reported: apt install fails with hash mismatch on podman-pasta — stable-2404 Packages index has stale hash after nightly build overwrote shared pool file with same-version different-content pasta binary"
  severity: major
  test: 3
  root_cause: "Pool collision: nightly-2404 CI run (08:05 UTC Jun 7) rebuilt pasta from new upstream commit (21f4d13) with version string 20260607~ubuntu24.04.podman1 (same as stable-2404's entry), published to shared pool, overwriting the binary stable-2404 was indexed against. stable-2404 Packages index: Size=322824/SHA256=1bd861c5. CDN now serves: Size=322886/SHA256=be7560ad. Fix: include build-attempt or upstream git short-hash in nightly version string so nightly and stable never share the same version string for the same package."
  artifacts:
    - path: "scripts/ci_publish.sh"
      issue: "reprepro shared pool allows nightly includedeb to overwrite stable pool file when version strings collide"
    - path: ".github/workflows/build-packages.yml"
      issue: "nightly build uses date-only version (YYYYMMDD) which collides with stable if upstream changes intraday"
  missing:
    - "Nightly version string must differ from stable — append upstream git short-hash or build counter to nightly pasta version"
  debug_session: ""
