#!/bin/bash

# Test the D-12 alias rule of resolve_publish_targets (REPO-07): every 24.04
# publish includes the bare legacy alias track; every 26.04 publish does NOT.
#
# Same sed-extraction approach as test_suite_routing.sh so config.sh's
# os-release/VERSION_SUFFIX load is never triggered. Pure bash — runs on macOS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

CONFIG_SH="${PROJECT_ROOT}/config.sh"

# ============================================
# Test Framework
# ============================================

PASS_COUNT=0
FAIL_COUNT=0

# Asserts the multi-line publish-target list CONTAINS the bare track name.
assert_contains_alias() {
    local description="$1"
    local track="$2"
    local targets="$3"
    if printf '%s\n' "${targets}" | grep -qx "${track}"; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Expected bare alias '${track}' in: ${targets}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Asserts the multi-line publish-target list does NOT contain the bare track.
assert_excludes_alias() {
    local description="$1"
    local track="$2"
    local targets="$3"
    if printf '%s\n' "${targets}" | grep -qx "${track}"; then
        echo "  FAIL: ${description}"
        echo "    Unexpected bare alias '${track}' in: ${targets}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
}

# ============================================
# Extract resolve_publish_targets from config.sh
# ============================================

load_routing() {
    if ! grep -q "^resolve_publish_targets()" "${CONFIG_SH}"; then
        echo "FATAL: resolve_publish_targets() not found in config.sh"
        return 1
    fi
    eval "$(sed -n "/^VALID_TRACKS=/p; /^VALID_DISTROS=/p" "${CONFIG_SH}")"
    eval "$(sed -n "/^resolve_publish_targets()/,/^}/p" "${CONFIG_SH}")"
}

echo ""
echo "========================================"
echo "Test: D-12 alias routing rule"
echo "========================================"
echo ""

if ! load_routing; then
    echo ""
    echo "RESULT: ALL TESTS FAILED (routing helper not found)"
    exit 1
fi

TRACKS=(stable edge nightly)

echo "Test 1: every 2404 track includes the bare alias + the versioned suite"
for track in "${TRACKS[@]}"; do
    targets="$(resolve_publish_targets "${track}" 2404)"
    assert_contains_alias "${track} 2404 includes versioned '${track}-2404'" \
        "${track}-2404" "${targets}"
    assert_contains_alias "${track} 2404 includes bare alias '${track}'" \
        "${track}" "${targets}"
done

echo ""
echo "Test 2: every 2604 track excludes the bare alias (versioned only)"
for track in "${TRACKS[@]}"; do
    targets="$(resolve_publish_targets "${track}" 2604)"
    assert_contains_alias "${track} 2604 includes versioned '${track}-2604'" \
        "${track}-2604" "${targets}"
    assert_excludes_alias "${track} 2604 excludes bare alias '${track}'" \
        "${track}" "${targets}"
done

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
