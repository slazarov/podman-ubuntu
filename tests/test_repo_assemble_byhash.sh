#!/bin/bash

# Ubuntu-only integration harness: real reprepro/gpg assemble of the multi-suite
# repository, by-hash + re-sign post-processing, and the no-clobber property.
#
# This proves the production-critical behaviors that Plans 01-03 could only
# author on macOS (no reprepro/gpg/apt there):
#   - REPO-08: Acquire-By-Hash: yes in every populated suite's Release, a
#     by-hash/<ALGO>/<hash> copy adjacent to each index, and a valid GPG
#     signature chain (InRelease clearsign + Release.gpg detached) AFTER the
#     by-hash mutation re-signs Release.
#   - Criterion 4 (no-clobber): publishing one suite leaves another populated
#     suite's Packages index byte-identical.
#   - REPO-06: the empty-but-signed -2604 suite (stable-2604) exports a Release
#     and verifies even with zero packages (D-14).
#   - A1 confirmation: record which hash algorithms reprepro actually emitted and
#     assert by-hash exists for at least the strongest one.
#
# Platform note: this harness is Ubuntu-only. reprepro + gpg + dpkg-deb are
# required. On the macOS dev host (no reprepro/dpkg-deb) the harness prints SKIP
# and exits 0 — mirroring the dpkg-dependent skip convention in
# tests/test_detect_distro_depends.sh. Run it on the Lima ubuntu-24 VM / CI.

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

assert_file_exists() {
    local description="$1"
    local path="$2"
    if [[ -f "${path}" ]]; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Missing file: ${path}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Asserts the given command exits 0 (clean subshell so set -e in callee bodies
# does not abort the runner).
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

assert_grep() {
    local description="$1"
    local pattern="$2"
    local file="$3"
    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Pattern not found: ${pattern}"
        echo "    In file: ${file}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo ""
echo "========================================"
echo "Test: repo assemble + by-hash + no-clobber (integration)"
echo "========================================"
echo ""

# ============================================
# Platform skip (macOS dev host has no reprepro/dpkg-deb)
# ============================================

if ! command -v reprepro &>/dev/null \
   || ! command -v gpg &>/dev/null \
   || ! command -v dpkg-deb &>/dev/null \
   || ! command -v sha256sum &>/dev/null; then
    echo "  SKIP: reprepro/gpg/dpkg-deb/sha256sum not all available."
    echo "  NOTE: this Ubuntu-only integration harness runs on the Lima"
    echo "        ubuntu-24 VM / CI. Install reprepro and re-run there:"
    echo "          sudo apt-get update && sudo apt-get install -y reprepro"
    echo ""
    echo "========================================"
    echo "Results: 0 passed, 0 failed (SKIPPED on this host)"
    echo "========================================"
    exit 0
fi

# ============================================
# Isolated fixture: throwaway GNUPGHOME + temp output dirs (no host mutation)
# ============================================

TMP_ROOT="$(mktemp -d)"
export GNUPGHOME="${TMP_ROOT}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"
# Cleanup everything (key material + assembled trees) on exit. gpg-agent spawned
# under the throwaway GNUPGHOME is killed so the temp dir can be removed cleanly.
trap 'gpgconf --homedir "${GNUPGHOME}" --kill all >/dev/null 2>&1 || true; rm -rf "${TMP_ROOT}"' EXIT

echo ">>> Generating throwaway GPG signing key in isolated GNUPGHOME..."
cat > "${TMP_ROOT}/keygen" <<'EOF_KEYGEN'
%no-protection
Key-Type: eddsa
Key-Curve: ed25519
Subkey-Type: ecdh
Subkey-Curve: cv25519
Name-Real: Podman Repo Test Key
Name-Email: repo-test@example.invalid
Expire-Date: 0
%commit
EOF_KEYGEN
if ! gpg --batch --gen-key "${TMP_ROOT}/keygen" >/dev/null 2>&1; then
    # Fallback to RSA in case the gpg build lacks ed25519 batch support.
    cat > "${TMP_ROOT}/keygen" <<'EOF_KEYGEN_RSA'
%no-protection
Key-Type: RSA
Key-Length: 3072
Name-Real: Podman Repo Test Key
Name-Email: repo-test@example.invalid
Expire-Date: 0
%commit
EOF_KEYGEN_RSA
    gpg --batch --gen-key "${TMP_ROOT}/keygen" >/dev/null 2>&1
fi
# Trust the key ultimately to avoid signing/verify warnings.
TEST_KEY_FPR="$(gpg --list-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')"
echo "${TEST_KEY_FPR}:6:" | gpg --batch --import-ownertrust >/dev/null 2>&1
echo "  key: ${TEST_KEY_FPR}"
echo ""

# ============================================
# Build tiny fixture .deb files (two distinct packages, 24.04-suffixed version)
# ============================================
#
# build_fixture_deb <pkgname> <version> <arch> <out-dir>
build_fixture_deb() {
    local lpkg="$1" lver="$2" larch="$3" lout="$4"
    local lstage="${TMP_ROOT}/stage-${lpkg}-${larch}"
    rm -rf "${lstage}"
    mkdir -p "${lstage}/DEBIAN" "${lstage}/usr/share/doc/${lpkg}"
    cat > "${lstage}/DEBIAN/control" <<EOF_CTL
Package: ${lpkg}
Version: ${lver}
Architecture: ${larch}
Maintainer: Repo Test <repo-test@example.invalid>
Section: admin
Priority: optional
Description: Fixture package ${lpkg} for the repo assemble harness
 Not a real package; used only to exercise reprepro includedeb + by-hash.
EOF_CTL
    echo "fixture ${lpkg} ${lver}" > "${lstage}/usr/share/doc/${lpkg}/README"
    mkdir -p "${lout}"
    dpkg-deb --build --root-owner-group "${lstage}" \
        "${lout}/${lpkg}_${lver}_${larch}.deb" >/dev/null
}

# The version carries the per-distro suffix the project uses (~ubuntu24.04.podman1)
# so the legacy-client D-15 proof (apt-cache policy) has a 24.04 candidate.
STABLE_DEB_DIR="${TMP_ROOT}/debs-stable"
EDGE_DEB_DIR="${TMP_ROOT}/debs-edge"
echo ">>> Building fixture .deb packages..."
build_fixture_deb "podman-suite" "5.0.0~ubuntu24.04.podman1" "amd64" "${STABLE_DEB_DIR}"
build_fixture_deb "podman-suite" "5.0.0~ubuntu24.04.podman1" "arm64" "${STABLE_DEB_DIR}"
build_fixture_deb "conmon-suite" "2.1.0~ubuntu24.04.podman1" "amd64" "${EDGE_DEB_DIR}"
build_fixture_deb "conmon-suite" "2.1.0~ubuntu24.04.podman1" "arm64" "${EDGE_DEB_DIR}"
echo "  stable debs: $(find "${STABLE_DEB_DIR}" -name '*.deb' | wc -l | tr -d ' ')"
echo "  edge debs:   $(find "${EDGE_DEB_DIR}" -name '*.deb' | wc -l | tr -d ' ')"
echo ""

# ============================================
# Assemble: drive the real Plan-03 path (repo_manage.sh) + Plan-02 by-hash
# ============================================
#
# We assemble directly via repo_manage.sh (the assemble core ci_publish.sh
# invokes) then source repo_byhash.sh and apply add_byhash_and_resign per suite.
# This is the plan's documented direct-assemble alternative to driving the full
# ci_publish.sh against a file:// URL, and keeps the proof focused on the
# assemble + by-hash + signature behaviors.

OUT="${TMP_ROOT}/out"
mkdir -p "${OUT}"

# repo_manage.sh signs with the keyring key (no GPG_PRIVATE_KEY env) — our
# throwaway key in GNUPGHOME is the only secret key present.
echo ">>> Assembling stable (2404): versioned stable-2404 + bare 'stable' alias..."
"${PROJECT_ROOT}/scripts/repo_manage.sh" stable 2404 "${STABLE_DEB_DIR}" "${OUT}" >/dev/null

echo ">>> Assembling edge (2404): versioned edge-2404 + bare 'edge' alias..."
"${PROJECT_ROOT}/scripts/repo_manage.sh" edge 2404 "${EDGE_DEB_DIR}" "${OUT}" >/dev/null

# Empty-but-signed -2604 suite (REPO-06 / D-14): reprepro export with no packages.
# repo_manage.sh requires .deb files, so export the empty suite directly. The
# conf/ dir is removed by repo_manage.sh after each run, so restore it first.
echo ">>> Exporting empty-but-signed stable-2604 (REPO-06 / D-14)..."
mkdir -p "${OUT}/conf"
cp "${PROJECT_ROOT}/packaging/repo/conf/distributions" "${OUT}/conf/"
cp "${PROJECT_ROOT}/packaging/repo/conf/options" "${OUT}/conf/"
reprepro -b "${OUT}" export stable-2604 >/dev/null
rm -rf "${OUT}/db" "${OUT}/conf"

# Apply by-hash + re-sign to every populated/exported suite (Plan-03 Step 4b).
echo ">>> Applying add_byhash_and_resign per suite (Plan-02 helper)..."
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/scripts/repo_byhash.sh"
ASSEMBLED_SUITES=(stable-2404 stable edge-2404 edge stable-2604)
for suite in "${ASSEMBLED_SUITES[@]}"; do
    if [[ -f "${OUT}/dists/${suite}/Release" ]]; then
        add_byhash_and_resign "${suite}" "${OUT}"
    fi
done
echo ""

# ============================================
# Assertions
# ============================================

# Populated suites we expect to carry real Packages content.
POPULATED_SUITES=(stable-2404 stable edge-2404 edge)
ARCHES=(amd64 arm64)

echo "Test group A: REPO-08 — Acquire-By-Hash on every populated suite"
echo ""
for suite in "${POPULATED_SUITES[@]}"; do
    rel="${OUT}/dists/${suite}/Release"
    assert_file_exists "Release exists for ${suite}" "${rel}"
    assert_grep "Acquire-By-Hash: yes present in ${suite} Release" \
        '^Acquire-By-Hash: yes' "${rel}"
done

echo ""
echo "Test group B: REPO-08 — by-hash copy adjacent to each Packages index (strongest algo)"
echo ""
# A1: record which checksum algorithms reprepro emitted in a sample Release.
SAMPLE_REL="${OUT}/dists/stable-2404/Release"
echo "  reprepro emitted checksum sections in stable-2404 Release:"
grep -E '^(MD5Sum|SHA1|SHA256|SHA512):' "${SAMPLE_REL}" | sed 's/^/    /' || true
# SHA256 is the strongest universally-emitted algo (SHA512 optional, A1).
STRONG_ALGO="SHA256"
if grep -q '^SHA512:' "${SAMPLE_REL}"; then
    STRONG_ALGO="SHA512"
fi
echo "  strongest-available algo asserted: ${STRONG_ALGO}"
STRONG_CMD="$(echo "${STRONG_ALGO}" | tr '[:upper:]' '[:lower:]')sum"
echo ""

for suite in "${POPULATED_SUITES[@]}"; do
    for arch in "${ARCHES[@]}"; do
        idx="${OUT}/dists/${suite}/main/binary-${arch}/Packages"
        if [[ -f "${idx}" ]]; then
            h="$(${STRONG_CMD} "${idx}" | awk '{print $1}')"
            bh="${OUT}/dists/${suite}/main/binary-${arch}/by-hash/${STRONG_ALGO}/${h}"
            assert_file_exists "by-hash/${STRONG_ALGO} for ${suite} ${arch} Packages" "${bh}"
            # The by-hash copy must be byte-identical to the served index.
            if [[ -f "${bh}" ]]; then
                assert_equals "by-hash copy byte-identical to ${suite} ${arch} Packages" \
                    "$(${STRONG_CMD} "${idx}" | awk '{print $1}')" \
                    "$(${STRONG_CMD} "${bh}" | awk '{print $1}')"
            fi
        fi
    done
done

echo ""
echo "Test group C: REPO-08 — GPG signature chain valid AFTER by-hash re-sign"
echo ""
for suite in "${POPULATED_SUITES[@]}"; do
    dist="${OUT}/dists/${suite}"
    assert_file_exists "InRelease exists for ${suite}" "${dist}/InRelease"
    assert_file_exists "Release.gpg exists for ${suite}" "${dist}/Release.gpg"
    assert_succeeds "gpg --verify InRelease for ${suite}" \
        gpg --verify "${dist}/InRelease"
    assert_succeeds "gpg --verify Release.gpg Release for ${suite}" \
        gpg --verify "${dist}/Release.gpg" "${dist}/Release"
done

echo ""
echo "Test group D: Criterion 4 — no-clobber across suites on a single-suite publish"
echo ""
# Capture edge-2404's Packages hashes, then re-publish ONLY stable-2404 with the
# edge tree mirrored-unchanged in place. edge-2404 must remain byte-identical.
declare -A EDGE_BEFORE
NOCLOBBER_OK=true
for arch in "${ARCHES[@]}"; do
    edge_idx="${OUT}/dists/edge-2404/main/binary-${arch}/Packages"
    if [[ -f "${edge_idx}" ]]; then
        EDGE_BEFORE["${arch}"]="$(${STRONG_CMD} "${edge_idx}" | awk '{print $1}')"
    fi
done

# Re-publish stable-2404 only (fresh debs). reprepro's per-suite export and the
# preserved pool mean edge-2404's dists/ index is not touched.
"${PROJECT_ROOT}/scripts/repo_manage.sh" stable 2404 "${STABLE_DEB_DIR}" "${OUT}" >/dev/null
add_byhash_and_resign "stable-2404" "${OUT}"
add_byhash_and_resign "stable" "${OUT}"

for arch in "${ARCHES[@]}"; do
    edge_idx="${OUT}/dists/edge-2404/main/binary-${arch}/Packages"
    if [[ -f "${edge_idx}" ]]; then
        after="$(${STRONG_CMD} "${edge_idx}" | awk '{print $1}')"
        assert_equals "edge-2404 ${arch} Packages byte-identical after stable-2404-only publish" \
            "${EDGE_BEFORE["${arch}"]}" "${after}"
        [[ "${EDGE_BEFORE["${arch}"]}" == "${after}" ]] || NOCLOBBER_OK=false
    fi
done
# edge-2404 signature must still verify (untouched, still valid).
assert_succeeds "edge-2404 InRelease still verifies after stable-only publish" \
    gpg --verify "${OUT}/dists/edge-2404/InRelease"

echo ""
echo "Test group E: REPO-06 — empty-but-signed stable-2604 (D-14)"
echo ""
S2604="${OUT}/dists/stable-2604"
assert_file_exists "stable-2604 Release exists (empty-but-signed)" "${S2604}/Release"
assert_file_exists "stable-2604 InRelease exists" "${S2604}/InRelease"
assert_succeeds "gpg --verify InRelease for empty stable-2604" \
    gpg --verify "${S2604}/InRelease"
assert_succeeds "gpg --verify Release.gpg Release for empty stable-2604" \
    gpg --verify "${S2604}/Release.gpg" "${S2604}/Release"
assert_grep "Acquire-By-Hash: yes present in empty stable-2604 Release" \
    '^Acquire-By-Hash: yes' "${S2604}/Release"

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
