#!/bin/bash

# Test that packaging/repo/conf/distributions declares the 9 reprepro
# distributions of the six-suite restructure (REPO-06 / REPO-07).
#
# Pure parse assertions over a static config file — no reprepro/gpg/apt needed,
# so this runs everywhere (including the macOS dev host).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

DISTRIBUTIONS="${PROJECT_ROOT}/packaging/repo/conf/distributions"

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

assert_contains_line() {
    local description="$1"
    local needle="$2"
    local haystack="$3"
    if printf '%s\n' "${haystack}" | grep -qx "${needle}"; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Missing line: ${needle}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_absent() {
    local description="$1"
    local token="$2"
    if grep -q "${token}" "${DISTRIBUTIONS}"; then
        echo "  FAIL: ${description}"
        echo "    Unexpected token present: ${token}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
}

echo ""
echo "========================================"
echo "Test: conf/distributions 9-suite parse"
echo "========================================"
echo ""

if [[ ! -f "${DISTRIBUTIONS}" ]]; then
    echo "FATAL: distributions file not found: ${DISTRIBUTIONS}"
    echo ""
    echo "RESULT: ALL TESTS FAILED (config not found)"
    exit 1
fi

# ----- stanza counts -----

echo "Test 1: exactly 9 Suite lines and 9 Codename lines"
suite_count="$(grep -c '^Suite:' "${DISTRIBUTIONS}")"
codename_count="$(grep -c '^Codename:' "${DISTRIBUTIONS}")"
assert_equals "9 Suite: lines" "9" "${suite_count}"
assert_equals "9 Codename: lines" "9" "${codename_count}"

echo ""
echo "Test 2: exactly 9 SignWith: yes lines (single-key signing, REPO-06)"
signwith_count="$(grep -c '^SignWith: yes$' "${DISTRIBUTIONS}")"
assert_equals "9 SignWith: yes lines" "9" "${signwith_count}"

echo ""
echo "Test 3: Suite == Codename for every stanza (D-03)"
suites="$(grep '^Suite:' "${DISTRIBUTIONS}" | sed 's/^Suite: //')"
codenames="$(grep '^Codename:' "${DISTRIBUTIONS}" | sed 's/^Codename: //')"
assert_equals "Suite list equals Codename list" "${suites}" "${codenames}"

echo ""
echo "Test 4: bare legacy aliases present (REPO-07 mechanism)"
suite_lines="$(grep '^Suite:' "${DISTRIBUTIONS}")"
for alias in "Suite: stable" "Suite: edge" "Suite: nightly"; do
    assert_contains_line "alias '${alias}' present unsuffixed" "${alias}" "${suite_lines}"
done

echo ""
echo "Test 5: all 6 versioned suites present"
for v in stable-2404 edge-2404 nightly-2404 stable-2604 edge-2604 nightly-2604; do
    assert_contains_line "versioned suite '${v}' present" "Suite: ${v}" "${suite_lines}"
done

echo ""
echo "Test 6: exactly 3 alias Descriptions carry DEPRECATED (D-04)"
deprecated_count="$(grep -c 'DEPRECATED' "${DISTRIBUTIONS}")"
assert_equals "3 DEPRECATED descriptions" "3" "${deprecated_count}"

echo ""
echo "Test 7: no createsymlinks token (real distributions only, D-01)"
assert_absent "createsymlinks absent" "createsymlinks"

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
