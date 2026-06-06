#!/bin/bash

# Test the suite-routing contract in config.sh: resolve_publish_targets(),
# is_valid_suite(), and the VALID_TRACKS/VALID_DISTROS/ALL_SUITES arrays
# (REPO-06 / REPO-07).
#
# config.sh reads /etc/os-release and composes VERSION_SUFFIX at load time, which
# hard-fails on a non-Ubuntu host. To test the routing helpers in isolation we
# extract just the array declarations and the two function bodies (the same
# sed-extraction pattern test_detect_distro_depends.sh uses), then eval them.
# Pure bash — runs on macOS with no reprepro/gpg/apt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

CONFIG_SH="${PROJECT_ROOT}/config.sh"

# ============================================
# Test Framework
# ============================================

PASS_COUNT=0
FAIL_COUNT=0

assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Expected: ${expected}"
        echo "    Got: ${actual}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_succeeds() {
    local description="$1"
    shift
    if ( "$@" ) >/dev/null 2>&1; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Command unexpectedly failed: $*"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_fails() {
    local description="$1"
    shift
    if ( "$@" ) >/dev/null 2>&1; then
        echo "  FAIL: ${description}"
        echo "    Command unexpectedly succeeded: $*"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
}

# ============================================
# Extract the routing helpers from config.sh
# ============================================

extract_fn() {
    local fn="$1"
    sed -n "/^${fn}()/,/^}/p" "${CONFIG_SH}"
}

load_routing() {
    if ! grep -q "^resolve_publish_targets()" "${CONFIG_SH}"; then
        echo "FATAL: resolve_publish_targets() not found in config.sh"
        return 1
    fi
    if ! grep -q "^is_valid_suite()" "${CONFIG_SH}"; then
        echo "FATAL: is_valid_suite() not found in config.sh"
        return 1
    fi
    eval "$(sed -n "/^VALID_TRACKS=/p; /^VALID_DISTROS=/p" "${CONFIG_SH}")"
    eval "$(sed -n "/^ALL_SUITES=/,/)/p" "${CONFIG_SH}")"
    eval "$(extract_fn resolve_publish_targets)"
    eval "$(extract_fn is_valid_suite)"
}

echo ""
echo "========================================"
echo "Test: resolve_publish_targets / is_valid_suite"
echo "========================================"
echo ""

if ! load_routing; then
    echo ""
    echo "RESULT: ALL TESTS FAILED (routing helpers not found)"
    exit 1
fi

# ----- resolve_publish_targets -----

echo "Test 1: resolve_publish_targets stable 2404 -> 'stable-2404' then 'stable'"
result="$(resolve_publish_targets stable 2404)"
assert_equals "stable 2404 targets" $'stable-2404\nstable' "${result}"

echo ""
echo "Test 2: resolve_publish_targets edge 2604 -> exactly 'edge-2604' (no alias)"
result="$(resolve_publish_targets edge 2604)"
assert_equals "edge 2604 single target" "edge-2604" "${result}"

echo ""
echo "Test 3: resolve_publish_targets nightly 2404 -> 'nightly-2404' then 'nightly'"
result="$(resolve_publish_targets nightly 2404)"
assert_equals "nightly 2404 targets" $'nightly-2404\nnightly' "${result}"

echo ""
echo "Test 4: invalid track / distro rejected (non-zero exit)"
assert_fails "track 'beta' rejected" resolve_publish_targets beta 2404
assert_fails "distro '2410' rejected" resolve_publish_targets stable 2410

# ----- is_valid_suite -----

echo ""
echo "Test 5: is_valid_suite whitelist enforcement"
assert_succeeds "is_valid_suite stable-2604 ok" is_valid_suite stable-2604
assert_succeeds "is_valid_suite stable (bare alias) ok" is_valid_suite stable
assert_fails "is_valid_suite bogus rejected" is_valid_suite bogus

# ============================================
# Summary
# ============================================

echo ""
echo "========================================"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "========================================"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    exit 1
fi
exit 0
