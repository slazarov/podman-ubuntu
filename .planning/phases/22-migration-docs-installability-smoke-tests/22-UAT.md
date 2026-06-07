---
status: testing
phase: 22-migration-docs-installability-smoke-tests
source: [22-VERIFICATION.md]
started: 2026-06-07T00:00:00Z
updated: 2026-06-07T00:00:00Z
---

## Current Test

number: 1
name: CI Smoke Gate Execution (MIGR-04)
expected: |
  Run bash scripts/smoke_repo_install.sh 2404 <repo-output> and 2604 in a Lima ubuntu-24/ubuntu-26 VM
  (or trigger the publish workflow). Both legs must print SMOKE PASS with apt install podman-suite
  and podman info exiting 0.
awaiting: user response

## Tests

### 1. CI Smoke Gate Execution (MIGR-04)
expected: Run bash scripts/smoke_repo_install.sh 2404 and 2604 in Lima VMs or via CI publish workflow. Both legs print SMOKE PASS — apt install podman-suite and podman info exit 0 inside real ubuntu:24.04 and ubuntu:26.04 containers.
result: [pending]

### 2. index.html Distro Toggle Visual (MIGR-02)
expected: Open the generated index.html in a browser. Ubuntu 24.04 is active by default. Clicking Ubuntu 26.04 swaps all three track-tab snippets to -2604 suite names. JS behavior cannot be verified by grep alone.
result: [pending]

### 3. Live Signed APT Install from Docs (MIGR-01 live path)
expected: On a real Ubuntu 24.04 or 26.04 system, follow docs/apt-repository.md instructions verbatim using the HTTPS Signed-By path. apt install podman-suite succeeds. (The CI smoke gate uses Trusted: yes over file:// and does not exercise this GPG-signed HTTPS path — accepted limitation D-14.)
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
