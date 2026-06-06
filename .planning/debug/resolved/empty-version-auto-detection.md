---
status: resolved
trigger: "GOVERSION and PROTOC_VERSION are empty when they should be auto-detected to latest available versions. This causes double-slash paths like /opt/go//bin."
created: 2026-02-28T00:00:00Z
updated: 2026-02-28T00:00:00Z
---

## Current Focus

hypothesis: N/A - Fix has been applied
test: N/A
expecting: N/A
next_action: Wait for human verification in Linux environment

## Symptoms

expected: GOVERSION and PROTOC_VERSION should contain latest version strings (e.g., "1.22.0" or similar)
actual: GOVERSION= and PROTOC_VERSION= are empty strings, causing paths like GOPATH=/opt/go//bin
errors: No explicit error, but incorrect behavior. Scripts still run but with malformed paths.
reproduction: Run `sudo bash -x scripts/build_catatonit.sh` and observe the trace showing empty GOVERSION and PROTOC_VERSION
started: Related to quick-2 implementation which added auto-detection for PROTOC_VERSION and GOVERSION

## Eliminated

<!-- APPEND only -->

## Evidence

- timestamp: 2026-02-28T00:00:00Z
  checked: config.sh lines 57-59 and 125-128
  found: |
    GOVERSION is set with: `export GOVERSION="${GOVERSION:-}"`
    This defaults to EMPTY if GOVERSION is not already set in environment.
    GOPATH is immediately set to: `/opt/go/${GOVERSION}/bin` which becomes `/opt/go//bin`
    Same pattern for PROTOC_VERSION and PROTOC_PATH
  implication: The :-} syntax preserves existing env var or defaults to empty string, not auto-detected value

- timestamp: 2026-02-28T00:00:00Z
  checked: install_go.sh lines 19-23
  found: |
    Auto-detection IS implemented: `if [[ -z "${GOVERSION:-}" ]]; then export GOVERSION=$(get_latest_go_version); fi`
    But this only runs when install_go.sh is executed, NOT when config.sh is sourced
  implication: Auto-detection code exists but is in the wrong location - it's in install scripts, not config.sh

- timestamp: 2026-02-28T00:00:00Z
  checked: install_protoc.sh lines 19-23
  found: |
    Same pattern: `if [[ -z "${PROTOC_VERSION:-}" ]]; then export PROTOC_VERSION=$(get_latest_protoc_version); fi`
    Auto-detection only runs when install_protoc.sh is executed
  implication: Both GOVERSION and PROTOC_VERSION have the same architectural issue

- timestamp: 2026-02-28T00:00:00Z
  checked: functions.sh lines 59-75
  found: |
    get_latest_go_version() and get_latest_protoc_version() functions ARE defined in functions.sh
    They use curl to fetch latest versions from go.dev and GitHub API
    functions.sh is sourced by config.sh at line 12
  implication: The detection functions ARE available when config.sh runs, they're just not being called

- timestamp: 2026-02-28T00:00:00Z
  checked: build_catatonit.sh execution flow
  found: |
    1. Sources config.sh (which sources functions.sh)
    2. config.sh sets GOVERSION="" (empty default)
    3. config.sh sets GOPATH="/opt/go//bin" (using empty GOVERSION)
    4. No auto-detection happens because build_catatonit.sh doesn't call install_go.sh
  implication: ROOT CAUSE CONFIRMED - auto-detection logic is isolated in install scripts, but config.sh needs it for all scripts that use these variables

## Resolution

root_cause: Auto-detection functions (get_latest_go_version, get_latest_protoc_version) exist in functions.sh but were only called in install_go.sh and install_protoc.sh. When other scripts source config.sh, they get empty GOVERSION and PROTOC_VERSION because config.sh used `${VAR:-}` which defaults to empty string, not to the auto-detected value. The paths like GOPATH and PROTOC_PATH were constructed immediately in config.sh using these empty values.

fix: Moved auto-detection logic from install_go.sh and install_protoc.sh into config.sh where the variables are initialized. Changed:
- `export GOVERSION="${GOVERSION:-}"` to check if empty and call `get_latest_go_version`
- `export PROTOC_VERSION="${PROTOC_VERSION:-}"` to check if empty and call `get_latest_protoc_version`

verification: Human-verified in Linux environment - version variables now correctly populated with auto-detected values
files_changed:
  - /Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/config.sh
  - /Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/scripts/install_go.sh
  - /Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/scripts/install_protoc.sh
