#!/bin/bash

# Test detect_distro_version_id() and detect_runtime_depends() in functions.sh
# TDD RED phase: These tests should FAIL until the functions are implemented.
#
# Platform note: detect_runtime_depends full behavior needs ldd + dpkg-query
# (Ubuntu host). On a dev host (macOS) those dpkg-dependent assertions are
# SKIPPED; the dpkg-free assertions (function existence, distro detection,
# regex validation, non-executable guard) run everywhere. The on-host smoke
# of detect_runtime_depends against a real ELF binary is exercised in Plan 04.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

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

# Asserts the given command exits 0 (in a clean subshell so set -e in the
# function body doesn't abort the test runner).
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

# Asserts the given command exits non-zero.
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
# Source the functions under test
# ============================================
# functions.sh sources config.sh at its tail, which reads /etc/os-release and
# composes VERSION_SUFFIX. To test the helpers in isolation we extract just the
# two function bodies (sed: from 'name()' to the first closing '}' at col 0),
# matching the extraction pattern used by test_extract_version_nightly.sh.

FUNCTIONS_SH="${PROJECT_ROOT}/functions.sh"

extract_fn() {
    local fn="$1"
    sed -n "/^${fn}()/,/^}/p" "${FUNCTIONS_SH}"
}

load_functions() {
    if ! grep -q "^detect_distro_version_id()" "${FUNCTIONS_SH}"; then
        echo "FATAL: detect_distro_version_id() not found in functions.sh"
        return 1
    fi
    if ! grep -q "^detect_runtime_depends()" "${FUNCTIONS_SH}"; then
        echo "FATAL: detect_runtime_depends() not found in functions.sh"
        return 1
    fi
    eval "$(extract_fn detect_distro_version_id)"
    eval "$(extract_fn detect_runtime_depends)"
}

# Helpers that run the function under override in a clean subshell.
distro_with() {
    local override="$1"
    ( unset DISTRO; export DISTRO="${override}"; detect_distro_version_id )
}

echo ""
echo "========================================"
echo "Test: detect_distro_version_id / detect_runtime_depends"
echo "========================================"
echo ""

if ! load_functions; then
    echo ""
    echo "RESULT: ALL TESTS FAILED (functions not found)"
    teardown 2>/dev/null || true
    exit 1
fi

# ----- detect_distro_version_id -----

echo "Test 1: DISTRO override (dotted VERSION_ID) echoes the value"
result="$(distro_with "26.04")"
assert_equals "DISTRO=26.04 -> 26.04" "26.04" "${result}"

echo ""
echo "Test 2: DISTRO override accepts 24.04"
result="$(distro_with "24.04")"
assert_equals "DISTRO=24.04 -> 24.04" "24.04" "${result}"

echo ""
echo "Test 3: Compact CI-label form is rejected by the regex"
assert_fails "DISTRO=2604 (no dot) rejected" distro_with "2604"

echo ""
echo "Test 4: Non-numeric / injection-shaped DISTRO is rejected"
assert_fails "DISTRO=26.04; rm -rf rejected" distro_with "26.04; rm"
assert_fails "DISTRO=ubuntu26.04 rejected" distro_with "ubuntu26.04"

echo ""
echo "Test 5: detect_runtime_depends hard-fails on a non-executable path"
assert_fails "non-executable binary path errors" \
    detect_runtime_depends "/nonexistent/definitely/not/a/binary"

# ----- detect_runtime_depends (dpkg-dependent) -----

echo ""
echo "Test 6: detect_runtime_depends on a real ELF binary (dpkg host only)"
if command -v dpkg-query &>/dev/null && command -v ldd &>/dev/null; then
    # Pick a guaranteed-present dynamically-linked ELF binary.
    target="/bin/cat"
    [[ -x "${target}" ]] || target="$(command -v cat)"
    result="$(detect_runtime_depends "${target}")"
    # Base packages must be excluded.
    if echo "${result}" | grep -qx "libc6"; then
        echo "  FAIL: libc6 should be excluded from output"
        echo "    Got: ${result}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "  PASS: libc6 excluded from detected depends"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
else
    echo "  SKIP: dpkg-query/ldd not available (non-Debian dev host)"
    echo "  NOTE: real-ELF resolution is exercised on an Ubuntu host in Plan 04"
fi

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
