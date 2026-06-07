---
status: resolved
trigger: "2604 CI container build failure — ubuntu:26.04 container job bash/fuse fix not landing"
created: 2026-06-07
updated: 2026-06-07
---

## Symptoms

- **Expected:** `build (2604, amd64, ubuntu-24.04, ubuntu:26.04)` CI cell succeeds — all components compile, debs are packaged.
- **Actual:** Job fails immediately at "Build all components" step with:
  - `[[: not found` at lines 20, 30, 34 of the generated step script (sh treating `[[` as unknown command)
  - `[ERROR] VAL-03: FUSE kernel support not available` — `/dev/fuse not found or not accessible` — setup.sh preflight hard-fails
- **Timeline:** Always failing. The 2604 cell runs inside a bare `ubuntu:26.04` Docker container on the `ubuntu-24.04` runner. 2404 cells run directly on the host runner and succeed.
- **Reproduction:** Trigger `Build and Publish Packages` workflow on `main`.

## What Has Been Tried

1. **Add `bash` to bootstrap apt-get install** (commit `a969932`) — did NOT fix `[[: not found`. Root issue: GHA container jobs use `/bin/sh` for `run:` steps even when bash is installed, unless `shell: bash` is set explicitly.
2. **Add "Ensure /dev/fuse exists" step using `[[` syntax** (commit `a969932`) — the step itself used `[[`, so it failed under `sh` too, meaning `/dev/fuse` was never created before setup.sh ran.
3. **Fix "Ensure /dev/fuse exists" to use POSIX `[ ]`** and add `shell: bash` to "Build all components" and "Package all components" steps (commit `c688523`) — run #141 was triggered with this commit but was cancelled accidentally before result was known.
4. **Current state:** commit `f84b1c6` has all three fixes + only 1 cell (2604 amd64) + publish disabled. Run #142 was triggered but user cancelled before completion.

## Current Focus

RESOLVED — see Resolution below. 2604 amd64 cell green in run 27095419712; full 4-cell matrix + publish restored.

## Evidence

- timestamp: 2026-06-07T12:52Z
  run: "#138 / job 79960247185"
  finding: "`[[: not found` at step script lines 20/30/34. `/dev/fuse not found`. Both 2604 amd64 and arm64 fail identically."

- timestamp: 2026-06-07T13:10Z
  run: "#139 / job 79961353755"
  finding: "Same failures after adding bash to bootstrap and [[ in fuse step. bootstrap installed bash but step still ran under sh. fuse step failed silently under sh so /dev/fuse was never created."

- timestamp: 2026-06-07T13:32Z
  run: "27094004269 (f84b1c6)"
  finding: "shell: bash CONFIRMED working — no more [[: not found. Fuse step CONFIRMED printing 'Created /dev/fuse'. VAL-03 STILL fails. Also: bootstrap log shows 'bash is already the newest version' — bash was in the image all along; GHA container jobs simply default run: to sh regardless."

- timestamp: 2026-06-07T13:39Z
  run: "27094169631 (5871495, job-level shell: bash default)"
  finding: "Same VAL-03 failure. Fuse step 'Created /dev/fuse' at 13:39:13, VAL-03 ERROR at 13:39:15."

- timestamp: 2026-06-07T13:48Z
  run: "27094382361 (716f11d, /dev/fuse re-created inside Build step + pid1 fingerprints)"
  finding: "DECISIVE: pid1 starttime identical (3460) in both steps — same container, no restart. Build step's own ls shows 'crw-rw-rw- 1 root root 10, 229 /dev/fuse' EXISTS milliseconds before setup.sh — yet VAL-03 fails inside 'sudo env ... ./setup.sh'. The sudo'd process cannot see the device. ubuntu:26.04 ships sudo-rs (and uutils coreutils)."

- timestamp: 2026-06-07T13:52Z
  run: "local Lima ubuntu-26 VM, podman --cap-add MKNOD, ubuntu:26.04"
  finding: "NOT reproducible under podman: mknod'd /dev/fuse fully visible under sudo-rs (sudo bash [[ -c ]] OK, sudo env bash OK). Whatever hides /dev/fuse under sudo is specific to the GHA docker environment, not sudo-rs per se."

- timestamp: 2026-06-07T13:55Z
  run: "27094544749 (2c23cc2, in-sudo diagnostics)"
  finding: "ROOT CAUSE ISOLATED: under sudo, [[ -c /dev/fuse ]] → OK but [[ -r /dev/fuse ]] → FAIL. Docker's default device cgroup allows mknod (c *:* m) but denies read/write on 10:229; the kernel consults the device cgroup (devcgroup_inode_permission) on every permission check of a device inode, even for root with mode 666. stat/ls pass (not device-mediated), access(R_OK) fails. sudo was a red herring — -r fails in the step shell too (only -c/stat had ever been tested there). Also caught: 2c23cc2's preflight edit swallowed the else keyword, so WARN and ERROR both fired; fixed in 8ac8397."

## Eliminated

- hypothesis: "bash not installed in container"
  eliminated_because: "bash IS installed by bootstrap. The problem is GHA uses sh for run: steps in container jobs unless shell: bash is specified."

- hypothesis: "transient CDN/runner issue"
  eliminated_because: "Both amd64 and arm64 2604 cells fail identically across multiple runs."

## Key Files

- `.github/workflows/build-packages.yml` — workflow with matrix, bootstrap step, build step
- `scripts/preflight_check.sh` — VAL-03 fuse check (hard error, exits non-zero)
- `scripts/setup.sh` — calls preflight before any build work

## Current Workflow State (commit f84b1c6)

```yaml
# Matrix: only 1 cell active
- distro: '2604'
  arch: amd64
  runner: ubuntu-24.04
  container: ubuntu:26.04

# Bootstrap step (if: matrix.container != ''):
apt-get install -y --no-install-recommends sudo git curl ca-certificates bash

# Fuse step (if: matrix.container != ''):
if [ ! -c /dev/fuse ]; then   # POSIX [ ] — works under sh
  mknod /dev/fuse c 10 229
  chmod 666 /dev/fuse
fi

# Build step:
shell: bash                    # explicit bash
run: |
  ...
  if [[ "${{ steps.track.outputs.track }}" == "stable" ]]; then ...

# Package step:
shell: bash                    # explicit bash
```

## Resolution

root_cause: "Four stacked issues. (1) GHA container jobs default run: steps to sh -e even when bash exists in the image — every [[ ]] failed with '[[: not found'. (2) VAL-03 /dev/fuse: mknod inside the job container succeeds (Docker's default device cgroup whitelist includes 'c *:* m') but read/write on 10:229 stays DENIED — the kernel calls devcgroup_inode_permission() on every permission check of a device inode, even for root on a 0666 node. So [[ -c /dev/fuse ]] passes while [[ -r /dev/fuse ]] fails, and VAL-03 can never pass inside the container; no amount of mknod'ing helps. sudo/container-restart/tmpfs theories were red herrings — -r fails in the step shell too (only -c/stat had ever been tested there). (3+4) Long tail of host-runner-preinstalled tools missing from the bare ubuntu:26.04 image: wget (install_rust.sh line 20, exit 127), envsubst/gettext-base (package_all.sh line 411), and bash-completion (toolbox's meson build silently skips installing completions without it, then nfpm's toolbox* completion glob fails)."
fix: "(1) defaults.run.shell: bash at build-job level; bootstrap step overrides to shell: sh (runs before bash install). (2) New SKIP_FUSE_CHECK env var (preflight_check.sh) downgrades a failed VAL-03 to a warning; workflow sets it for container cells only — legitimate because compilation never opens /dev/fuse (runtime-only requirement of fuse-overlayfs). All mknod machinery removed as useless. (3) wget, gettext-base, bash-completion added to install_dependencies.sh. Bonus: all actions bumped to Node 24 majors (checkout@v5, cache@v5, upload-artifact@v6, download-artifact@v7, configure-pages@v6, upload-pages-artifact@v5, deploy-pages@v5) and FORCE_JAVASCRIPT_ACTIONS_TO_NODE24 removed, killing the Node 20 deprecation warning."
verification: "Run 27095419712 (commit cacc01e): build (2604, amd64) completed/success — all 12 components compiled on ubuntu:26.04, all packages created, debs-2604-amd64 artifact uploaded. Full 4-cell matrix + publish re-enabled afterwards."
files_changed:
  - ".github/workflows/build-packages.yml"
  - "scripts/preflight_check.sh"
  - "scripts/install_dependencies.sh"
  - "docs/CONFIGURATION.md"
