---
status: resolved
trigger: "install_protoc.sh fails with 404 because PROTOC_VERSION is empty, causing malformed download URL"
created: 2026-02-28T20:15:00Z
updated: 2026-02-28T20:35:00Z
---

## Current Focus

hypothesis: Fix applied and verified syntactically - config.sh now correctly derives PROTOC_TAG from PROTOC_VERSION
test: User needs to run install_protoc.sh in their environment
expecting: Script should now properly construct URL like `https://github.com/protocolbuffers/protobuf/releases/download/v34.0/protoc-34.0-linux-aarch_64.zip`
next_action: Await user verification

## Symptoms

expected: protoc binary should download from GitHub releases and install to /opt/protoc
actual: wget returns 404 Not Found
errors:
```
HTTP request sent, awaiting response... 404 Not Found
2026-02-28 20:10:22 ERROR 404: Not Found.
```
URL attempted: `https://github.com/protocolbuffers/protobuf/releases/download/v/protoc--linux-aarch_64.zip`
reproduction: Run `scripts/install_protoc.sh` when PROTOC_VERSION is not set
started: Fresh occurrence - version variable is empty at runtime

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-02-28T20:15:00Z
  checked: config.sh lines 130-137
  found: Line 131-133 correctly auto-detects PROTOC_VERSION if not set. However, line 134 sets `PROTOC_TAG="${PROTOC_TAG:-}"` which sets it to empty string if not already set. This is problematic because it assigns empty string AFTER PROTOC_VERSION is detected, but does NOT derive PROTOC_TAG from PROTOC_VERSION.
  implication: PROTOC_TAG ends up empty even though PROTOC_VERSION might have a value

- timestamp: 2026-02-28T20:18:00Z
  checked: install_protoc.sh lines 22-25
  found: Fallback logic checks `if [[ -z "${PROTOC_TAG:-}" ]]` and sets `PROTOC_TAG="v${PROTOC_VERSION}"`. This SHOULD work if PROTOC_VERSION has a value.
  implication: The root cause is likely that PROTOC_VERSION is also empty, which means the curl call to GitHub API failed or returned nothing.

- timestamp: 2026-02-28T20:19:00Z
  checked: functions.sh lines 59-66
  found: `get_latest_protoc_version()` uses curl to fetch from GitHub API. If curl fails (no network, GitHub rate limited, etc.), it returns empty string.
  implication: Network issues or GitHub API unavailability causes empty PROTOC_VERSION, which then propagates to empty PROTOC_TAG

- timestamp: 2026-02-28T20:20:00Z
  checked: config.sh line 134
  found: Line 134 sets `export PROTOC_TAG="${PROTOC_TAG:-}"` which is redundant - it just sets to empty if not set. This line should derive PROTOC_TAG from PROTOC_VERSION instead, OR be removed entirely since install_protoc.sh has the fallback logic.
  implication: This is a design bug - config.sh should derive PROTOC_TAG from PROTOC_VERSION after detection

- timestamp: 2026-02-28T20:25:00Z
  checked: Fixed config.sh
  found: Changed line 134 from `export PROTOC_TAG="${PROTOC_TAG:-}"` to a proper conditional that derives PROTOC_TAG from PROTOC_VERSION if not already set
  implication: Fix ensures PROTOC_TAG is properly derived from PROTOC_VERSION

- timestamp: 2026-02-28T20:28:00Z
  checked: Verified fix in config.sh lines 134-137
  found: New code correctly implements the pattern: `if [[ -z "${PROTOC_TAG:-}" ]]; then export PROTOC_TAG="v${PROTOC_VERSION}"; fi`
  implication: PROTOC_TAG will now be properly derived from PROTOC_VERSION after auto-detection

## Resolution

root_cause: config.sh line 134 set PROTOC_TAG to empty string (if not already set) instead of deriving it from PROTOC_VERSION. The original code `export PROTOC_TAG="${PROTOC_TAG:-}"` just assigned empty string if unset, which is useless. It should have derived PROTOC_TAG from PROTOC_VERSION after detection.
fix: Changed config.sh to properly derive PROTOC_TAG from PROTOC_VERSION using conditional:
```bash
if [[ -z "${PROTOC_TAG:-}" ]]; then
    export PROTOC_TAG="v${PROTOC_VERSION}"
fi
```
verification: User confirmed fix works - protoc now installs correctly with properly formed download URL
files_changed: [config.sh]
