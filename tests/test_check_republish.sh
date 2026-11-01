#!/bin/bash

# Tests for scripts/check_republish_needed.sh pure helpers
# (extract_base, get_pkg_version). Network-dependent resolution and the
# main() decision flow are exercised in CI, not here.
#
# The end-to-end section runs main() offline against file:// repositories,
# with and without a resolved-env file (the workflow's resolve-track output):
#   - every package (podman-suite included) current on every distro/arch -> skip
#   - one distro stale, or podman-suite alone differs -> build
#   - a distro not published at all -> build
#   - an invalid resolved-env file -> exit 1, not a decision
#   - with a resolved-env file the resolver is never run

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
TEST_TMPDIR=""

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
        echo "    Got:      ${actual}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

cleanup() {
    [[ -n "${TEST_TMPDIR}" && -d "${TEST_TMPDIR}" ]] && rm -rf "${TEST_TMPDIR}"
}
trap cleanup EXIT

# Source the helpers (BASH_SOURCE guard prevents main from running).
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/scripts/check_republish_needed.sh"

echo "=== extract_base ==="
assert_equals "v-prefixed tag strips v"            "5.8.2"  "$(extract_base 'v5.8.2' 'podman')"
assert_equals "numeric-only tag unchanged (crun)"  "1.28"   "$(extract_base '1.28' 'crun')"
assert_equals "numeric-only tag unchanged (toolbox)" "0.3"  "$(extract_base '0.3' 'toolbox')"
assert_equals "namespaced container-libs tag"      "0.67.1" "$(extract_base 'common/v0.67.1' 'container-configs')"
assert_equals "catatonit v-prefixed"               "0.2.1"  "$(extract_base 'v0.2.1' 'catatonit')"

echo "=== pasta: guard row + extract_base (shared pasta_version) ==="
assert_equals "guard COMPONENT_ROWS compares pasta (podman-pasta via PASTA_TAG)" \
    "1" "$(printf '%s\n' "${COMPONENT_ROWS[@]}" | grep -c '^pasta|podman-pasta|PASTA_TAG|' || true)"

# Offline passt fixture: one single-release date plus two same-day releases whose
# sha order is the REVERSE of their commit order (older commit = fff1111).
TEST_TMPDIR="$(mktemp -d)"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
PASST="${TEST_TMPDIR}/passt"
git init -q "${PASST}"
_epoch=1900000000
for _pt in 2026_09_25.ddd4444 2026_10_02.fff1111 2026_10_02.aaa2222; do
    _epoch=$((_epoch + 86400))
    echo "${_pt}" > "${PASST}/f"
    git -C "${PASST}" add -A
    GIT_COMMITTER_DATE="@${_epoch} +0000" GIT_AUTHOR_DATE="@${_epoch} +0000" \
        git -C "${PASST}" commit -q -m "${_pt}"
    git -C "${PASST}" tag "${_pt}"
done
PS="file://${PASST}"

assert_equals "pasta only release of its date -> YYYYMMDD" \
    "20260925" "$(extract_base '2026_09_25.ddd4444' 'pasta' "${PS}")"
assert_equals "pasta first same-day release -> YYYYMMDD" \
    "20261002" "$(extract_base '2026_10_02.fff1111' 'pasta' "${PS}")"
assert_equals "pasta later same-day release -> YYYYMMDD.1" \
    "20261002.1" "$(extract_base '2026_10_02.aaa2222' 'pasta' "${PS}")"
assert_equals "pasta unreachable remote -> empty base (guard builds)" \
    "" "$(extract_base '2026_10_02.aaa2222' 'pasta' "file://${TEST_TMPDIR}/nope" || true)"

echo "=== extract_base == package_all.sh:extract_version (pasta) ==="
# The guard's target must be byte-identical to what package_all.sh would build,
# or skip=true can never fire for pasta. Pull the real function out of
# package_all.sh (it cannot be sourced whole) and compare on the same tags.
eval "$(sed -n '/^extract_version()/,/^}/p' "${PROJECT_ROOT}/scripts/package_all.sh")"
for _pt in 2026_09_25.ddd4444 2026_10_02.fff1111 2026_10_02.aaa2222; do
    assert_equals "pasta ${_pt}: guard base == package_all version" \
        "$(extract_version "${_pt}" pasta "${PS}")" "$(extract_base "${_pt}" pasta "${PS}")"
done
assert_equals "package_all extract_version pasta same-day later release" \
    "20261002.1" "$(extract_version '2026_10_02.aaa2222' pasta "${PS}")"
assert_equals "package_all extract_version pasta failure is non-zero" \
    "fail" "$(extract_version '2026_10_02.aaa2222' pasta "file://${TEST_TMPDIR}/nope" 2>/dev/null || echo fail)"

echo "=== main(): end-to-end skip=true with pasta compared ==="
# Sandbox copy of the guard with a shimmed resolver and a policy file, so main()
# runs offline: every *_TAG is fixed, pasta's row URL points at the file:// passt
# fixture, and the Packages indices (file://) carry every package at its target.
E2E="${TEST_TMPDIR}/e2e"
mkdir -p "${E2E}/scripts" "${E2E}/repo"
cp "${PROJECT_ROOT}/scripts/check_republish_needed.sh" "${PROJECT_ROOT}/scripts/package_revision.sh" \
    "${PROJECT_ROOT}/scripts/ci_helpers.sh" "${E2E}/scripts/"
: > "${E2E}/versions-stable.env"
declare -A E2E_TAGS=()
for _row in "${COMPONENT_ROWS[@]}"; do
    IFS='|' read -r _comp _pkg _tagvar _ <<< "${_row}"
    case "${_comp}" in
        pasta) E2E_TAGS["${_tagvar}"]="2026_10_02.aaa2222" ;;
        container-configs) E2E_TAGS["${_tagvar}"]="common/v0.67.1" ;;
        *) E2E_TAGS["${_tagvar}"]="v1.2.3" ;;
    esac
done
{
    echo '#!/bin/bash'
    for _tv in "${!E2E_TAGS[@]}"; do
        echo "echo 'export ${_tv}=\"${E2E_TAGS[${_tv}]}\"'"
    done
} > "${E2E}/scripts/resolve_versions.sh"
chmod +x "${E2E}/scripts/resolve_versions.sh"
# write_e2e_repo <repo> [skip-distro] [override-distro override-arch override-pkg override-version]
# -> stable-<distro> Packages for every distro/arch with every package at its
# target version, except the overrides. [skip-distro] is left unpublished.
write_e2e_repo() {
    local repo="$1" skip="${2:-}" od="${3:-}" oa="${4:-}" opkg="${5:-}" over="${6:-}"
    local _d _a _dir _row _comp _pkg _tagvar _base _ver
    for _d in 2404:24.04 2604:26.04; do
        [[ "${_d%%:*}" == "${skip}" ]] && continue
        for _a in amd64 arm64; do
            _dir="${repo}/dists/stable-${_d%%:*}/main/binary-${_a}"
            mkdir -p "${_dir}"
            for _row in "${COMPONENT_ROWS[@]}"; do
                IFS='|' read -r _comp _pkg _tagvar _ <<< "${_row}"
                case "${_comp}" in
                    pasta) _base="20261002.1" ;;
                    container-configs) _base="0.67.1" ;;
                    *) _base="1.2.3" ;;
                esac
                _ver="${_base}~ubuntu${_d##*:}.podman${PACKAGE_REVISION}"
                if [[ "${_d%%:*}" == "${od}" && "${_a}" == "${oa}" && "${_pkg}" == "${opkg}" ]]; then
                    _ver="${over}"
                fi
                printf 'Package: %s\nVersion: %s\nArchitecture: %s\n\n' "${_pkg}" "${_ver}" "${_a}"
            done > "${_dir}/Packages"
        done
    done
}
write_e2e_repo "${E2E}/repo"
_e2e_out="$(
    unset GITHUB_OUTPUT
    # shellcheck disable=SC1091
    source "${E2E}/scripts/check_republish_needed.sh"
    for _i in "${!COMPONENT_ROWS[@]}"; do
        [[ "${COMPONENT_ROWS[_i]}" == pasta\|* ]] && COMPONENT_ROWS[_i]="pasta|podman-pasta|PASTA_TAG|${PS}"
    done
    main stable "file://${E2E}/repo" 2>/dev/null
)" || true
assert_equals "main(): all packages (pasta at 20261002.1) published -> skip=true" "skip=true" "${_e2e_out}"

echo "=== main(): decision flow with a resolved-env file ==="
# The same tags as the shimmed resolver, in resolve_versions.sh's output form.
ENVF="${TEST_TMPDIR}/resolved.env"
for _tv in "${!E2E_TAGS[@]}"; do
    echo "export ${_tv}=\"${E2E_TAGS[${_tv}]}\""
done | sort > "${ENVF}"

# decide <repo> [env-file] -> main()'s skip=... line, or "exit N" when it
# exits non-zero. The resolver is replaced by a failure, so a decision that
# needed it would show up as an exit code.
decide() {
    local out rc=0
    out="$(
        unset GITHUB_OUTPUT
        # shellcheck disable=SC1091
        source "${E2E}/scripts/check_republish_needed.sh"
        for _i in "${!COMPONENT_ROWS[@]}"; do
            [[ "${COMPONENT_ROWS[_i]}" == pasta\|* ]] && COMPONENT_ROWS[_i]="pasta|podman-pasta|PASTA_TAG|${PS}"
        done
        resolve_targets() { echo "resolver called" >&2; exit 9; }
        main stable "file://$1" "${2:-${ENVF}}" 2>/dev/null
    )" || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        echo "exit ${rc}"
    else
        echo "${out}"
    fi
}

assert_equals "env file: all current on every distro/arch -> skip" "skip=true" "$(decide "${E2E}/repo")"

R2="${TEST_TMPDIR}/repo-2604-stale"
write_e2e_repo "${R2}" "" 2604 arm64 podman-podman "1.2.2~ubuntu26.04.podman${PACKAGE_REVISION}"
assert_equals "env file: 2604 arm64 podman stale -> build" "skip=false" "$(decide "${R2}")"

R3="${TEST_TMPDIR}/repo-suite-differs"
write_e2e_repo "${R3}" "" 2404 amd64 podman-suite "1.2.2~ubuntu24.04.podman${PACKAGE_REVISION}"
assert_equals "env file: only podman-suite differs -> build" "skip=false" "$(decide "${R3}")"

R4="${TEST_TMPDIR}/repo-2604-absent"
write_e2e_repo "${R4}" 2604
assert_equals "env file: 2604 not published -> build" "skip=false" "$(decide "${R4}")"

BAD="${TEST_TMPDIR}/bad.env"
{ cat "${ENVF}"; echo 'export PODMAN_TAG="v9.9.9"'; } > "${BAD}"
assert_equals "invalid resolved env -> exit 1, not a decision" "exit 1" "$(decide "${E2E}/repo" "${BAD}")"

echo "=== pasta dpkg ordering (same-day releases, nightly) ==="
if command -v dpkg >/dev/null 2>&1; then
    _sfx="~ubuntu24.04.podman1"
    for _pair in "20261002 20261002.1" "20261002.1 20261003" "20261002~gitcba3570 20261002"; do
        read -r _lo _hi <<< "${_pair}"
        _ord="no"
        dpkg --compare-versions "${_lo}${_sfx}" lt "${_hi}${_sfx}" && _ord="yes"
        assert_equals "dpkg: ${_lo} < ${_hi}" "yes" "${_ord}"
    done
else
    echo "  SKIP: dpkg not available"
fi

echo "=== get_pkg_version ==="
PKGFILE="${TEST_TMPDIR}/Packages"
cat > "${PKGFILE}" <<'EOF'
Package: podman-crun
Version: 1.28~ubuntu24.04.podman1
Architecture: amd64

Package: podman-podman
Version: 5.8.2~ubuntu24.04.podman1
Architecture: amd64

Package: podman-buildah
Version: 1.43.1~ubuntu24.04.podman1
Architecture: amd64
EOF

assert_equals "finds podman version"          "5.8.2~ubuntu24.04.podman1" "$(get_pkg_version "${PKGFILE}" 'podman-podman')"
assert_equals "finds crun version (first stanza)" "1.28~ubuntu24.04.podman1" "$(get_pkg_version "${PKGFILE}" 'podman-crun')"
assert_equals "absent package -> empty"       ""                          "$(get_pkg_version "${PKGFILE}" 'podman-missing')"
# Guard against substring false-positives (podman vs podman-podman).
assert_equals "exact package match only"      ""                          "$(get_pkg_version "${PKGFILE}" 'podman')"

echo ""
echo "========================================"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "========================================"
[[ ${FAIL_COUNT} -eq 0 ]]
