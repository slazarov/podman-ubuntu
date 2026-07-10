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
# Tests 7-9: DT_NEEDED semantics (dpkg host + objdump + gcc only)
# These tests cover three behaviors introduced in Plan 05 (commit b1e43a3,
# requirements PKG-08/PKG-10) that had no unit-level regression coverage:
#   7 — static binary yields EMPTY dep set, exit 0 (not a hard-fail)
#   8 — direct DT_NEEDED only: libsystemd0 deps (libgcrypt20 etc.) must NOT
#       appear (the discriminating regression test for transitive-closure rollback)
#   9 — dynamic-loader pseudo-entry (ld-linux*.so) is skipped (implicit in
#       any passing dynamic-binary test on arm64, but tested here on amd64 via
#       the same fixture-B binary)
# ============================================

echo ""
echo "Tests 7-9: DT_NEEDED behavioral regression coverage (dpkg host only)"

if ! command -v dpkg-query &>/dev/null || ! command -v ldd &>/dev/null || ! command -v objdump &>/dev/null; then
    echo "  SKIP: dpkg-query / ldd / objdump not available (non-Debian dev host)"
    echo "  NOTE: run these tests in the Lima ubuntu-24 or ubuntu-26 VM"
else
    # All three tests need a temporary build directory; clean it up on exit.
    _tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${_tmp_dir}"' EXIT

    # ---- Fixture A: statically-linked binary (behavior 3) ----
    echo ""
    echo "Test 7: statically-linked binary -> empty dep set, exit 0"

    _fixture_a="${_tmp_dir}/static_hello"
    _static_ok=false
    if command -v gcc &>/dev/null; then
        cat > "${_tmp_dir}/hello.c" <<'EOF_C'
int main(void) { return 0; }
EOF_C
        if gcc -static "${_tmp_dir}/hello.c" -o "${_fixture_a}" 2>/dev/null; then
            _static_ok=true
        fi
    fi

    if [[ "${_static_ok}" == "true" ]]; then
        # The function must exit 0 and produce NO output.
        _static_result="$(detect_runtime_depends "${_fixture_a}")"
        _static_exit=0
        detect_runtime_depends "${_fixture_a}" >/dev/null 2>&1 || _static_exit=$?
        if [[ "${_static_exit}" -ne 0 ]]; then
            echo "  FAIL: static binary caused hard-fail (exit ${_static_exit}); expected exit 0 with empty output"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        elif [[ -n "${_static_result}" ]]; then
            echo "  FAIL: static binary produced non-empty dep set: ${_static_result}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            echo "  PASS: static binary -> empty dep set, exit 0"
            PASS_COUNT=$((PASS_COUNT + 1))
        fi
    else
        echo "  SKIP: gcc -static not available or libc6-dev static libs absent"
        echo "  NOTE: static-binary behavior is confirmed by the Plan 04/05 on-host proofs (fuse-overlayfs/catatonit)"
    fi

    # ---- Fixture B: dynamic binary linked to libsystemd (behaviors 1+2) ----
    echo ""
    echo "Test 8: direct DT_NEEDED only — transitive-closure deps of libsystemd0 must NOT appear"

    _fixture_b="${_tmp_dir}/dyn_systemd"
    _systemd_ok=false
    if command -v gcc &>/dev/null; then
        cat > "${_tmp_dir}/systemd_hello.c" <<'EOF_C'
#include <systemd/sd-daemon.h>
int main(void) { sd_notify(0, "READY=1"); return 0; }
EOF_C
        if gcc "${_tmp_dir}/systemd_hello.c" -lsystemd -o "${_fixture_b}" 2>/dev/null; then
            _systemd_ok=true
        fi
    fi

    if [[ "${_systemd_ok}" == "true" ]]; then
        _dyn_result="$(detect_runtime_depends "${_fixture_b}")"

        # MUST contain libsystemd0 (the direct dep).
        if ! printf '%s\n' "${_dyn_result}" | grep -qx "libsystemd0"; then
            echo "  FAIL: libsystemd0 not found in output for -lsystemd binary"
            echo "    Got: ${_dyn_result}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            echo "  PASS: libsystemd0 present in dep set"
            PASS_COUNT=$((PASS_COUNT + 1))
        fi

        # Must NOT contain any of libsystemd0's own transitive deps — these are
        # the false-positive packages that the old ldd-closure detector injected
        # (the direct-DT_NEEDED detector must not re-introduce them).
        # A regression back to transitive-closure logic would re-introduce them.
        _transitive_extras=( liblz4-1 liblzma5 libzstd1 libgcrypt20 libgpg-error0 )
        _found_transitive=()
        for _t in "${_transitive_extras[@]}"; do
            if printf '%s\n' "${_dyn_result}" | grep -qx "${_t}"; then
                _found_transitive+=( "${_t}" )
            fi
        done

        if [[ "${#_found_transitive[@]}" -gt 0 ]]; then
            echo "  FAIL: transitive deps of libsystemd0 found — detector regressed to full ldd closure"
            echo "    Unexpected: ${_found_transitive[*]}"
            echo "    Full output: ${_dyn_result}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            echo "  PASS: no transitive deps of libsystemd0 in output (direct DT_NEEDED only)"
            PASS_COUNT=$((PASS_COUNT + 1))
        fi

        # Test 9: dynamic-loader pseudo-entry skip (implicit — any passing dynamic
        # binary test on arm64 covers this, but assert it explicitly here too).
        echo ""
        echo "Test 9: dynamic-loader pseudo-entry (ld-linux*.so) not in dep output"
        if printf '%s\n' "${_dyn_result}" | grep -qE '^ld(-linux|\.so|-)'; then
            echo "  FAIL: dynamic loader entry leaked into dep output: $(printf '%s\n' "${_dyn_result}" | grep -E '^ld(-linux|\.so|-)')"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            echo "  PASS: dynamic-loader pseudo-entry absent from dep output"
            PASS_COUNT=$((PASS_COUNT + 1))
        fi
    else
        echo "  SKIP: libsystemd-dev not available for gcc -lsystemd (install libsystemd-dev to enable)"
        echo "  NOTE: falling back to /bin/ls as a known dynamic binary without transitive extras"
        echo ""
        echo "Test 8 (fallback): /bin/ls direct DT_NEEDED only — libc6 excluded, no spurious transitive deps"
        _fallback_bin="/bin/ls"
        [[ -x "${_fallback_bin}" ]] || _fallback_bin="$(command -v ls)"
        if [[ -x "${_fallback_bin}" ]]; then
            _fallback_result="$(detect_runtime_depends "${_fallback_bin}")"
            # libc6 must not appear (excluded by D-02)
            if printf '%s\n' "${_fallback_result}" | grep -qx "libc6"; then
                echo "  FAIL: libc6 present in output (should be excluded by D-02)"
                echo "    Got: ${_fallback_result}"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            else
                echo "  PASS: libc6 excluded; dep output: $(printf '%s' "${_fallback_result}" | tr '\n' ' ')"
                PASS_COUNT=$((PASS_COUNT + 1))
            fi

            echo ""
            echo "Test 9 (fallback): dynamic-loader pseudo-entry (ld-linux*.so) not in /bin/ls dep output"
            if printf '%s\n' "${_fallback_result}" | grep -qE '^ld(-linux|\.so|-)'; then
                echo "  FAIL: dynamic loader entry leaked into dep output: $(printf '%s\n' "${_fallback_result}" | grep -E '^ld(-linux|\.so|-)')"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            else
                echo "  PASS: dynamic-loader pseudo-entry absent from dep output"
                PASS_COUNT=$((PASS_COUNT + 1))
            fi
        else
            echo "  SKIP: /bin/ls not available"
        fi
    fi
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
