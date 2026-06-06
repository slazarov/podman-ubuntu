---
status: awaiting_human_verify
trigger: "seccomp-json-missing - podman run fails with Error: opening seccomp profile failed: open /usr/share/containers/seccomp.json: no such file or directory"
created: 2026-03-04T00:00:00Z
updated: 2026-03-04T00:02:00Z
---

## Current Focus

hypothesis: CONFIRMED - containers.conf references /usr/share/containers/seccomp.json but setup.sh never copies this file into place
test: n/a - fix applied
expecting: After re-running setup.sh (or manually copying seccomp.json), podman run should work without seccomp errors
next_action: Awaiting human verification that the fix resolves the issue on the target system

## Symptoms

expected: Container should start normally - containers.conf should reference a seccomp profile that exists on the system
actual: Podman fails immediately with seccomp profile not found error
errors: Error: opening seccomp profile failed: open /usr/share/containers/seccomp.json: no such file or directory
reproduction: podman run docker.io/library/postgres:16-alpine (any container would fail)
started: After recent GSD phase changes that modified containers.conf installation

## Eliminated

## Evidence

- timestamp: 2026-03-04T00:00:30Z
  checked: config/containers.conf line 10
  found: seccomp_profile = "/usr/share/containers/seccomp.json" is set explicitly
  implication: Podman will look for this file at startup when running any container

- timestamp: 2026-03-04T00:00:40Z
  checked: setup.sh lines 111-113 (config installation section)
  found: Only /etc/containers/containers.conf is copied; no seccomp.json is installed
  implication: The file referenced in containers.conf is never created during installation

- timestamp: 2026-03-04T00:00:50Z
  checked: Podman Makefile SHAREDIR_CONTAINERS variable and install targets
  found: SHAREDIR_CONTAINERS defined as ${PREFIX}/share/containers but never used in any install target; make install does NOT install seccomp.json
  implication: Podman's make install relies on containers-common package to provide seccomp.json

- timestamp: 2026-03-04T00:00:55Z
  checked: build/podman/vendor/go.podman.io/common/pkg/seccomp/seccomp.json
  found: The seccomp.json profile exists in the vendored containers/common library inside the podman source tree
  implication: The correct seccomp profile is available locally; just needs to be copied to /usr/share/containers/

- timestamp: 2026-03-04T00:01:00Z
  checked: build/podman/vendor/go.podman.io/common/pkg/config/default.go lines 200-202
  found: SeccompDefaultPath = _installPrefix + "/share/containers/seccomp.json" - Podman's own code expects the file at /usr/share/containers/seccomp.json
  implication: This is the canonical expected location; our containers.conf matches what Podman itself expects

- timestamp: 2026-03-04T00:01:00Z
  checked: containers-common package reference in buildah/install.md
  found: "seccomp.json contains the list of seccomp rules... This file is usually provided by the containers-common package."
  implication: Since we build from source (no containers-common package), we must install this file ourselves

- timestamp: 2026-03-04T00:01:30Z
  checked: Vendored containers.conf default (line 302)
  found: seccomp_profile is COMMENTED OUT by default; our containers.conf explicitly uncomments it
  implication: When explicitly set, Podman requires the file to exist (fails hard). When commented out, Podman falls back to compiled-in path search (fails soft).

- timestamp: 2026-03-04T00:01:40Z
  checked: libpod/util.go DefaultSeccompPath() function
  found: When SeccompProfile is set in config, it returns that path directly without checking if file exists first
  implication: The error occurs when the runtime later tries to open the returned path

## Resolution

root_cause: setup.sh copies containers.conf with seccomp_profile="/usr/share/containers/seccomp.json", but never installs the actual seccomp.json file. On distro-packaged Podman, the containers-common package provides this file. Since this project builds everything from source (no containers-common package), the file is missing. The seccomp.json profile exists in the vendored source tree at build/podman/vendor/go.podman.io/common/pkg/seccomp/seccomp.json but was never copied to the expected system location.

fix: |
  1. setup.sh: Added seccomp.json installation after containers.conf copy. Copies from vendored podman source tree to /usr/share/containers/seccomp.json. Includes warning if source file not found.
  2. uninstall.sh: Added cleanup of /usr/share/containers/seccomp.json and empty directory removal.
  3. config/containers.conf: Updated comment to reflect that seccomp.json is installed by setup.sh (not from containers-common package).

verification: Awaiting human verification on target system

files_changed:
  - setup.sh (added seccomp.json installation logic)
  - uninstall.sh (added seccomp.json cleanup)
  - config/containers.conf (updated comment)
