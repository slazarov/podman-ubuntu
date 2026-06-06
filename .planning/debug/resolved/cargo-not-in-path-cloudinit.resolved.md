---
---
status: awaiting_human_verify
trigger: cargo-not-in-path-cloudinit
created: 2026-03-01T00:00:00.000Z
updated: 2026-03-01T00:00:00.000Z
---

## Current Focus
hypothesis: Cargo is not in PATH because HOME is not set in cloud-init, so ~/.cargo/bin is not added to PATH
test: Check if cargo is installed and verify PATH configuration
expecting: Cargo binary should be found in PATH or path explicitly added
next_action: Applied fix - need user verification

## Symptoms
expected: build_aardvark_dns.sh compiles aardvark-dns with cargo successfully
actual: make fails with "cargo: Not a directory" Error 127 at Makefile:53
errors: |
  cargo  build --release
  make: cargo: Not a directory
  make: *** [Makefile:53: build] Error 127
reproduction: Run lima provisioning with the podman-debian setup.sh
timeline: Previous HOME issue was fixed, now this new error appears. Works in manual shell.

## Eliminated

## Evidence
- timestamp: 2026-03-01T00:00:00.000Z
  checked: build_aardvark_dns.sh PATH handling
  found: Script sources $HOME/.cargo/env only if HOME is set
- timestamp: 2026-03-01T00:00:00.000Z
  checked: Other build scripts
  found: build_podman.sh exports PATH="$GOPATH:$PATH" explicitly
- timestamp: 2026-03-01T00:00:00.000Z
  checked: install_rust.sh
  found: No PATH configuration - assumes cargo will be in PATH after env sourcing
- timestamp: 2026-03-01T00:00:00.000Z
  checked: aardvark-dns Makefile line 53
  found: Calls $(CARGO) build $(release) where CARGO=cargo
- timestamp: 2026-03-01T00:00:00.000Z
  checked: applied fix
  found: Added explicit PATH checks for cargo bin directories in build_aardvark_dns.sh

## Resolution
root_cause: Cargo is not in PATH when running in cloud-init because HOME is unset, so ~/.cargo/env is never sourced
fix: Updated build_aardvark_dns.sh to add ~/.cargo/bin or /root/.cargo/bin to PATH explicitly
files_changed:
  - scripts/build_aardvark_dns.sh
verification: Added explicit PATH checks that will work in both regular shell and cloud-init environments