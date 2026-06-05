#!/bin/bash

# Abort on Error
set -euo pipefail

# verify_versions.sh - CI-agnostic proof of the per-distro version-suffix
# ordering (D-11) using `dpkg --compare-versions` as the authoritative oracle.
#
# This script is self-contained: every version below is a literal fixture, so
# it depends only on `dpkg` (no config.sh, no nfpm, no build output). It runs
# on any host with dpkg — including in CI before any package is built.
#
# It closes the Phase 19 STATE.md research flag (PKG-09): confirm the exact
# version suffix form sorts correctly before shipping — yields to official
# upstream, 24.04 < 26.04, the D-09 nightly form < tagged, and the legacy
# already-published `~podman1` form < the new `~ubuntu24.04.podman1` form so
# existing installs upgrade cleanly.

# assert_lt <lower> <higher>
# Succeeds (prints OK) when <lower> sorts strictly below <higher> per dpkg
# version semantics; otherwise prints FAIL to stderr and exits 1. All four
# mandatory D-11 orderings are `lt`, so this single wrapper suffices.
assert_lt() {
  if dpkg --compare-versions "$1" lt "$2"; then
    echo "OK: $1 < $2"
  else
    echo "FAIL: expected $1 < $2" >&2
    exit 1
  fi
}

# 1. D-08 suffixed form yields to the official upstream version.
assert_lt "5.5.2~ubuntu24.04.podman1" "5.5.2"

# 2. 24.04 sorts below 26.04 (dist-upgrade order): after the shared `~ubuntu`
#    prefix, 24 < 26 numerically.
assert_lt "5.5.2~ubuntu24.04.podman1" "5.5.2~ubuntu26.04.podman1"

# 3. D-09 nightly form ({base}~git{YYYYMMDD}.{sha}~ubuntu{VERSION_ID}.podman1)
#    sorts below the tagged release for the SAME distro (the extra `~git...`
#    tilde segment sorts below the plain suffix).
assert_lt "5.9.0~git20260306.abc1234~ubuntu24.04.podman1" "5.9.0~ubuntu24.04.podman1"

# 4. Legacy already-published `~podman1` form sorts below the new per-distro
#    `~ubuntu24.04.podman1` form, so existing installs upgrade cleanly: after
#    the shared `~`, `p`(0x70) < `u`(0x75).
assert_lt "5.5.2~podman1" "5.5.2~ubuntu24.04.podman1"

# --- Symmetry / robustness assertions ---

# 5. D-09 nightly form proven for 26.04 too: nightly < tagged on 26.04.
assert_lt "5.9.0~git20260306.abc1234~ubuntu26.04.podman1" "5.9.0~ubuntu26.04.podman1"

# 6. D-10 pasta-style date base form carries the same distro suffix on a date
#    base: 24.04 sorts below 26.04 for the date-versioned form.
assert_lt "20250302~ubuntu24.04.podman1" "20250302~ubuntu26.04.podman1"

echo "All version ordering assertions passed"
exit 0
