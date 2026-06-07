#!/bin/bash

# Test the Phase-21 CI build-matrix + publish-gating contract by parsing
# .github/workflows/build-packages.yml. Asserts:
#   - a single matrixed `build` job (no build-amd64/build-arm64)
#   - fail-fast: false under the build strategy
#   - exactly four distro×arch matrix cells (24.04/26.04 × amd64/arm64)
#   - 26.04 cells run inside ubuntu:26.04 containers; 24.04 cells do not
#   - distro-dimensioned Go cache key + artifact name
#   - publish job gated on the build job's aggregate result (atomic publish)
#   - no cross-distro download merge in the publish job
#   - ci_publish.sh invoked for both 2404 and 2604
#
# Runs on the macOS dev host with NO CI: prefers python3 + PyYAML for precise
# structural checks, falls back to grep/awk against the raw YAML text when
# PyYAML is unavailable. Both paths run so the test is green either way.
# Grep-path assertions strip comment lines so workflow comments cannot
# self-satisfy a gate. Pure bash + optional python3 — no reprepro/gpg/apt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

WORKFLOW="${PROJECT_ROOT}/.github/workflows/build-packages.yml"

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

# assert_contains <description> <haystack> <needle>
assert_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Expected to contain: ${needle}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# assert_true <description> <0-or-1>  (1 == condition holds)
assert_true() {
    local description="$1"
    local cond="$2"
    if [[ "${cond}" == "1" ]]; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo ""
echo "========================================"
echo "Test: CI build-matrix + publish-gating contract"
echo "========================================"
echo ""

# Defensive guard: SKIP cleanly only if the workflow file is entirely absent.
if [[ ! -f "${WORKFLOW}" ]]; then
    echo "SKIP: workflow file not found at ${WORKFLOW}"
    exit 0
fi

# Strip comment-only lines once for every grep-path assertion so workflow
# comments can never self-satisfy a gate (grep-gate hygiene).
NOCOMMENT="$(grep -v '^[[:space:]]*#' "${WORKFLOW}")"

HAVE_PYYAML=0
if python3 -c 'import yaml' 2>/dev/null; then
    HAVE_PYYAML=1
fi

# ============================================
# Path A: precise structural checks via PyYAML
# ============================================

run_python_assertions() {
    echo "--- Python/PyYAML structural assertions ---"

    # Each helper prints exactly "1" (holds) or "0" (fails) on stdout.
    py() { python3 -c "$1" "${WORKFLOW}"; }

    local r

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
jobs = d['jobs']
print('1' if ('build' in jobs and 'build-amd64' not in jobs and 'build-arm64' not in jobs) else '0')
")
    assert_true "py: single 'build' job (no build-amd64/build-arm64)" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print('1' if d['jobs']['build']['strategy']['fail-fast'] is False else '0')
")
    assert_true "py: build strategy fail-fast is False" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
inc = d['jobs']['build']['strategy']['matrix']['include']
print('1' if len(inc) == 4 else '0')
")
    assert_true "py: matrix include has exactly 4 cells" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
inc = d['jobs']['build']['strategy']['matrix']['include']
cells = {(str(c['distro']), str(c['arch'])) for c in inc}
want = {('2404','amd64'),('2404','arm64'),('2604','amd64'),('2604','arm64')}
print('1' if cells == want else '0')
")
    assert_true "py: all four distro×arch cells present" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
inc = d['jobs']['build']['strategy']['matrix']['include']
c2604 = [c for c in inc if str(c['distro']) == '2604']
c2404 = [c for c in inc if str(c['distro']) == '2404']
ok = (all(c.get('container') == 'ubuntu:26.04' for c in c2604)
      and all(not c.get('container') for c in c2404))
print('1' if ok else '0')
")
    assert_true "py: 2604 cells use ubuntu:26.04 container, 2404 cells do not" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print('1' if 'go-\${{ matrix.distro }}-\${{ matrix.arch }}' in open(sys.argv[1]).read() else '0')
")
    assert_true "py: Go cache key carries distro+arch dimension" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print('1' if 'debs-\${{ matrix.distro }}-\${{ matrix.arch }}' in open(sys.argv[1]).read() else '0')
")
    assert_true "py: artifact name carries distro+arch dimension" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
p = d['jobs']['publish']
ok = p['needs'] == ['build'] and \"needs.build.result == 'success'\" in p['if']
print('1' if ok else '0')
")
    assert_true "py: publish gated on needs.build.result == 'success'" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d['jobs']['publish']['steps']
pats = {s['with']['pattern'] for s in steps
        if isinstance(s.get('with'), dict) and 'pattern' in s['with']}
print('1' if pats == {'debs-2404-*','debs-2604-*'} else '0')
")
    assert_true "py: publish downloads are per-distro, no bare debs-* merge" "${r}"
}

# ============================================
# Path B: grep/awk floor (always runs)
# ============================================

run_grep_assertions() {
    echo "--- grep/awk floor assertions (comments stripped) ---"

    # 1. single build job, no build-amd64/build-arm64
    local has_build no_split
    has_build=$(printf '%s\n' "${NOCOMMENT}" | grep -Eqc '^[[:space:]]+build:' && echo 1 || echo 0)
    if printf '%s\n' "${NOCOMMENT}" | grep -Eq '^[[:space:]]+build-(amd64|arm64):'; then
        no_split=0
    else
        no_split=1
    fi
    assert_true "grep: 'build:' job present" "${has_build}"
    assert_true "grep: no build-amd64/build-arm64 jobs" "${no_split}"

    # 2. fail-fast: false
    local ff
    ff=$(printf '%s\n' "${NOCOMMENT}" | grep -Eqc 'fail-fast:[[:space:]]*false' && echo 1 || echo 0)
    assert_true "grep: fail-fast: false present" "${ff}"

    # 3. exactly four matrix cells (count '- distro:' lines)
    local cells
    cells=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec '^[[:space:]]*-[[:space:]]*distro:')
    assert_equals "grep: exactly 4 matrix '- distro:' cells" "4" "${cells}"

    # 4. two 2404 + two 2604, two amd64 + two arm64 among cells
    local d2404 d2604 aamd aarm
    d2404=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec "distro:[[:space:]]*'?2404'?")
    d2604=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec "distro:[[:space:]]*'?2604'?")
    aamd=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec '^[[:space:]]*arch:[[:space:]]*amd64')
    aarm=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec '^[[:space:]]*arch:[[:space:]]*arm64')
    assert_equals "grep: two distro 2404 cells" "2" "${d2404}"
    assert_equals "grep: two distro 2604 cells" "2" "${d2604}"
    assert_equals "grep: two amd64 cells" "2" "${aamd}"
    assert_equals "grep: two arm64 cells" "2" "${aarm}"

    # 5. ubuntu:26.04 container at least twice
    local cont
    cont=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec 'container:[[:space:]]*ubuntu:26\.04')
    assert_true "grep: container ubuntu:26.04 appears >= 2 times" \
        "$([[ "${cont}" -ge 2 ]] && echo 1 || echo 0)"

    # 6. Go cache key carries distro dimension
    assert_contains "grep: Go cache key has matrix.distro+arch" \
        "${NOCOMMENT}" 'go-${{ matrix.distro }}-${{ matrix.arch }}'

    # 7. artifact name carries distro+arch
    assert_contains "grep: artifact name has matrix.distro+arch" \
        "${NOCOMMENT}" 'debs-${{ matrix.distro }}-${{ matrix.arch }}'

    # 8. publish gating expression present
    assert_contains "grep: publish gating needs.build.result == 'success'" \
        "${NOCOMMENT}" "needs.build.result == 'success'"

    # 9. no cross-distro merge: both per-distro patterns, no bare debs-*
    local p2404 p2604 pbare
    p2404=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec 'pattern:[[:space:]]*debs-2404-\*')
    p2604=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec 'pattern:[[:space:]]*debs-2604-\*')
    if printf '%s\n' "${NOCOMMENT}" | grep -Eq 'pattern:[[:space:]]*debs-\*[[:space:]]*$'; then
        pbare=1
    else
        pbare=0
    fi
    assert_true "grep: pattern debs-2404-* present" "$([[ "${p2404}" -ge 1 ]] && echo 1 || echo 0)"
    assert_true "grep: pattern debs-2604-* present" "$([[ "${p2604}" -ge 1 ]] && echo 1 || echo 0)"
    assert_true "grep: no bare 'pattern: debs-*' (no cross-distro merge)" \
        "$([[ "${pbare}" -eq 0 ]] && echo 1 || echo 0)"

    # 10. ci_publish.sh invoked for both 2404 and 2604
    local l2404 l2604
    l2404=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec '"2404"')
    l2604=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec '"2604"')
    assert_true "grep: compact label \"2404\" present in publish" \
        "$([[ "${l2404}" -ge 1 ]] && echo 1 || echo 0)"
    assert_true "grep: compact label \"2604\" present in publish" \
        "$([[ "${l2604}" -ge 1 ]] && echo 1 || echo 0)"
    assert_contains "grep: ci_publish.sh invoked" "${NOCOMMENT}" "ci_publish.sh"
}

if [[ "${HAVE_PYYAML}" -eq 1 ]]; then
    run_python_assertions
    echo ""
else
    echo "--- PyYAML not available; running grep floor only ---"
fi
run_grep_assertions

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
