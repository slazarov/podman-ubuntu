---
status: resolved
trigger: "lima-home-unbound-variable"
created: 2026-03-01T12:00:00Z
updated: 2026-03-01T12:30:00Z
---

## Current Focus
Fix applied and verified. Home unbound variable issue resolved in build_aardvark_dns.sh and build_netavark.sh.

## Symptoms
expected: Lima provision completes successfully with podman installed via setup.sh
actual: Provision fails during build_aardvark_dns.sh execution with HOME unbound variable error
errors: /tmp/podman-debian/scripts/build_aardvark_dns.sh: line 11: HOME: unbound variable
reproduction: Start lima with the provided provision script (system mode cloud-init)
timeline: Works when done manually (shell, git clone, run setup), fails only during cloud-init provisioning

## Eliminated
- hypothesis: Issue is with cargo installation
  evidence: The error occurs before cargo installation, just when accessing HOME
  timestamp: 2026-03-01T12:15:00Z

- hypothesis: Issue is with build_aardvark_dns.sh script logic
  evidence: The same pattern appears in build_netavark.sh, indicating systematic issue
  timestamp: 2026-03-01T12:20:00Z

## Evidence
- timestamp: 2026-03-01T12:10:00Z
  checked: scripts/build_aardvark_dns.sh line 11
  found: Uses $HOME with set -euo pipefail but no check if HOME is set
  implication: Will fail if HOME is unset

- timestamp: 2026-03-01T12:15:00Z
  checked: scripts/build_netavark.sh line 11
  found: Same pattern as build_aardvark_dns.sh
  implication: Same issue will occur in both scripts

- timestamp: 2026-03-01T12:25:00Z
  checked: Tested fix with unset HOME
  found: Fix prevents the unbound variable error
  implication: Scripts will now work in cloud-init environment

## Resolution
root_cause: Scripts use $HOME without checking if it's set, causing "unbound variable" error when HOME is unset in cloud-init environment
fix: Changed [[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env" to if [ -n "${HOME:-}" ] && [ -f "$HOME/.cargo/env" ]; then . "$HOME/.cargo/env"; fi in both build_aardvark_dns.sh and build_netavark.sh
verification: Tested with both unset HOME (cloud-init scenario) and set HOME (manual shell scenario) - both work correctly
files_changed:
- scripts/build_aardvark_dns.sh: Fixed HOME unbound variable
- scripts/build_netavark.sh: Fixed HOME unbound variable