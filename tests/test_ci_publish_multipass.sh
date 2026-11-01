#!/bin/bash

# Regression test: multi-distro publish must NOT clobber an earlier pass.
#
# The publish job runs ci_publish.sh once per distro into ONE accumulating
# output dir (2404 then 2604). The bug (fixed in "preserve earlier-pass suites
# in multi-distro publish"): the 2604 pass listed stable-2404 + the bare
# `stable` alias — freshly built to the NEW version by the 2404 pass — as
# "other suites" and re-mirrored them VERBATIM from the live repo (the OLD
# version), overwriting the fresh indices. Net effect: the first-published
# distro reverted to the previously-published version.
#
# This harness reproduces the exact two-pass flow end to end:
#   1. Build a "live" repo at an OLD version and serve it over HTTP.
#   2. Run the real ci_publish.sh twice (stable 2404, then stable 2604) at a
#      NEW version, into one output dir, with REPO_URL pointing at the mock.
#   3. Assert every stable suite ends at the NEW version — in particular
#      stable-2404 / bare stable, which the bug reverted to OLD — that every
#      regenerated suite keeps the previous by-hash generation of its
#      indexes, and that the result verifies against the signing key.
#
# Without the fix, the stable-2404 assertion fails (it reads the OLD version).
#
# Then the failure paths, each against the same live repo:
#   4. A pool .deb that the live server keeps answering with HTTP 503, cuts
#      off mid-transfer, or answers with 404 although the index lists it,
#      stops ci_publish.sh (no suite is published). So does a persistent 503
#      on the live target suite's Packages or Release. One 503 followed by
#      success is retried and the publish goes through.
#   5. A failing `gpg --clearsign` or detached sign stops ci_publish.sh.
#
# Platform note: Ubuntu-only (reprepro + gpg + gpgv + dpkg-deb). On the macOS
# dev host it prints SKIP and exits 0, mirroring
# tests/test_repo_assemble_byhash.sh (a failure under
# REQUIRE_INTEGRATION_DEPS=1). Run it on the Lima ubuntu-24 VM / CI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck source=tests/lib/mock_http.sh
source "${SCRIPT_DIR}/lib/mock_http.sh"

# ============================================
# Test framework
# ============================================

PASS_COUNT=0
FAIL_COUNT=0

assert_equals() {
    local description="$1" expected="$2" actual="$3"
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

# ============================================
# Platform skip (macOS dev host has no reprepro/dpkg-deb)
# ============================================

if ! command -v reprepro &>/dev/null \
   || ! command -v gpg &>/dev/null \
   || ! command -v gpgv &>/dev/null \
   || ! command -v dpkg-deb &>/dev/null \
   || ! command -v sha256sum &>/dev/null \
   || ! command -v sha512sum &>/dev/null \
   || ! command -v python3 &>/dev/null \
   || ! command -v curl &>/dev/null; then
    require_integration_deps "reprepro/gpg/gpgv/dpkg-deb/sha256sum/sha512sum/python3/curl"
    echo "  SKIP: reprepro/gpg/gpgv/dpkg-deb/sha256sum/sha512sum/python3/curl not all available."
    echo "        This is an Ubuntu-only integration harness. Run it on the"
    echo "        ubuntu-24 VM / CI. Install reprepro and re-run there:"
    echo "          sudo apt-get update && sudo apt-get install -y reprepro"
    echo ""
    echo "========================================"
    echo "Results: 0 passed, 0 failed (SKIPPED on this host)"
    echo "========================================"
    exit 0
fi

# ============================================
# Isolated fixture: throwaway GNUPGHOME + temp dirs + mock HTTP server
# ============================================

TMP_ROOT="$(mktemp -d)"
export GNUPGHOME="${TMP_ROOT}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"
HTTP_PID=""
cleanup() {
    [[ -n "${HTTP_PID}" ]] && kill "${HTTP_PID}" >/dev/null 2>&1 || true
    stop_mock_http
    gpgconf --homedir "${GNUPGHOME}" --kill all >/dev/null 2>&1 || true
    rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

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
TEST_KEY_FPR="$(gpg --list-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')"
echo "${TEST_KEY_FPR}:6:" | gpg --batch --import-ownertrust >/dev/null 2>&1
echo "  key: ${TEST_KEY_FPR}"
# ci_publish.sh checks every signature against REPO_KEYRING; here that is
# the throwaway key, not the project's published one.
export REPO_KEYRING="${TMP_ROOT}/test-key.gpg"
gpg --batch --export "${TEST_KEY_FPR}" > "${REPO_KEYRING}"
export FETCH_RETRY_DELAY=0 FETCH_ATTEMPTS=3
echo ""

# build_fixture_deb <pkg> <version> <arch> <out-dir>
build_fixture_deb() {
    local lpkg="$1" lver="$2" larch="$3" lout="$4"
    local lstage="${TMP_ROOT}/stage-${lpkg}-${lver}-${larch}"
    rm -rf "${lstage}"
    mkdir -p "${lstage}/DEBIAN" "${lstage}/usr/share/doc/${lpkg}"
    cat > "${lstage}/DEBIAN/control" <<EOF_CTL
Package: ${lpkg}
Version: ${lver}
Architecture: ${larch}
Maintainer: Repo Test <repo-test@example.invalid>
Section: admin
Priority: optional
Description: Fixture ${lpkg} for the multi-pass publish harness
 Not a real package; exercises ci_publish.sh's two-pass accumulation.
EOF_CTL
    echo "fixture ${lpkg} ${lver}" > "${lstage}/usr/share/doc/${lpkg}/README"
    mkdir -p "${lout}"
    dpkg-deb --build --root-owner-group "${lstage}" \
        "${lout}/${lpkg}_${lver}_${larch}.deb" >/dev/null
}

# pkg_version <packages-file> <package> -> Version field of first matching stanza
pkg_version() {
    awk -v p="$2" '/^Package:/{cur=$2} /^Version:/{if(cur==p){print $2;exit}}' "$1"
}

PKG="podman-podman"
OLD_2404="5.8.0~ubuntu24.04.podman1"
OLD_2604="5.8.0~ubuntu26.04.podman1"
NEW_2404="5.8.2~ubuntu24.04.podman1"
NEW_2604="5.8.2~ubuntu26.04.podman1"

# ============================================
# Step 1: Build the "live" repo at the OLD version, serve it over HTTP
# ============================================

echo ">>> Building mock live repo at OLD version (${OLD_2404} / ${OLD_2604})..."
LIVE="${TMP_ROOT}/live"
mkdir -p "${LIVE}"
LIVE_DEBS_2404="${TMP_ROOT}/live-debs-2404"
LIVE_DEBS_2604="${TMP_ROOT}/live-debs-2604"
for arch in amd64 arm64; do
    build_fixture_deb "${PKG}" "${OLD_2404}" "${arch}" "${LIVE_DEBS_2404}"
    build_fixture_deb "${PKG}" "${OLD_2604}" "${arch}" "${LIVE_DEBS_2604}"
done

# Assemble live stable-2404 + bare alias, then stable-2604 (same path the real
# pipeline uses), and apply by-hash + signatures so mirror_suite_verbatim can
# serve them verbatim.
"${PROJECT_ROOT}/scripts/repo_manage.sh" stable 2404 "${LIVE_DEBS_2404}" "${LIVE}" >/dev/null
"${PROJECT_ROOT}/scripts/repo_manage.sh" stable 2604 "${LIVE_DEBS_2604}" "${LIVE}" >/dev/null
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/scripts/repo_byhash.sh"
for s in stable-2404 stable stable-2604; do
    [[ -f "${LIVE}/dists/${s}/Release" ]] && add_byhash_and_resign "${s}" "${LIVE}" >/dev/null
done

# Sanity: the live repo really is at the OLD version before we publish over it.
live_2404="$(pkg_version "${LIVE}/dists/stable-2404/main/binary-amd64/Packages" "${PKG}")"
assert_equals "live repo seeded at OLD stable-2404" "${OLD_2404}" "${live_2404}"

PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
python3 -m http.server "${PORT}" --bind 127.0.0.1 --directory "${LIVE}" >/dev/null 2>&1 &
HTTP_PID=$!
REPO_URL="http://127.0.0.1:${PORT}"
# Wait until the server answers.
for _ in $(seq 1 50); do
    curl -sf "${REPO_URL}/dists/stable-2404/Release" >/dev/null 2>&1 && break
    sleep 0.1
done
if ! curl -sf "${REPO_URL}/dists/stable-2404/Release" >/dev/null 2>&1; then
    echo "  FAIL: mock HTTP server never came up at ${REPO_URL}"
    echo "Results: ${PASS_COUNT} passed, $((FAIL_COUNT + 1)) failed"
    exit 1
fi
echo "  serving live repo at ${REPO_URL}"
echo ""

# ============================================
# Step 2: Publish the NEW version via two sequential passes into ONE output dir
# ============================================

echo ">>> Publishing NEW version (${NEW_2404} / ${NEW_2604}) — 2404 then 2604..."
NEW_DEBS_2404="${TMP_ROOT}/new-debs-2404"
NEW_DEBS_2604="${TMP_ROOT}/new-debs-2604"
for arch in amd64 arm64; do
    build_fixture_deb "${PKG}" "${NEW_2404}" "${arch}" "${NEW_DEBS_2404}"
    build_fixture_deb "${PKG}" "${NEW_2604}" "${arch}" "${NEW_DEBS_2604}"
done

OUT="${TMP_ROOT}/out"
mkdir -p "${OUT}"

run_pass() {
    local distro="$1" debdir="$2" log="$3"
    if ! bash "${PROJECT_ROOT}/scripts/ci_publish.sh" stable "${distro}" "${debdir}" "${REPO_URL}" "${OUT}" >"${log}" 2>&1; then
        echo "  FAIL: ci_publish.sh stable ${distro} exited non-zero. Tail:"
        tail -20 "${log}" | sed 's/^/      /'
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

run_pass 2404 "${NEW_DEBS_2404}" "${TMP_ROOT}/pass1.log" || true
run_pass 2604 "${NEW_DEBS_2604}" "${TMP_ROOT}/pass2.log" || true
echo ""

# ============================================
# Step 3: Assert no clobber — every stable suite ends at the NEW version
# ============================================

echo ">>> Verifying final repository (no clobber of the first pass)..."
got_2404_amd="$(pkg_version "${OUT}/dists/stable-2404/main/binary-amd64/Packages" "${PKG}" 2>/dev/null || true)"
got_2404_arm="$(pkg_version "${OUT}/dists/stable-2404/main/binary-arm64/Packages" "${PKG}" 2>/dev/null || true)"
got_bare="$(pkg_version "${OUT}/dists/stable/main/binary-amd64/Packages" "${PKG}" 2>/dev/null || true)"
got_2604="$(pkg_version "${OUT}/dists/stable-2604/main/binary-amd64/Packages" "${PKG}" 2>/dev/null || true)"

# The regression assertions: the 2404 pass (published FIRST) must survive the
# 2604 pass's mirror-down. Pre-fix these read OLD (5.8.0).
assert_equals "stable-2404 amd64 kept fresh (not clobbered by 2604 pass)" "${NEW_2404}" "${got_2404_amd}"
assert_equals "stable-2404 arm64 kept fresh (not clobbered by 2604 pass)" "${NEW_2404}" "${got_2404_arm}"
assert_equals "bare 'stable' alias kept fresh (not clobbered)"            "${NEW_2404}" "${got_bare}"
# Control: the last pass's own suite is fresh too.
assert_equals "stable-2604 published fresh"                               "${NEW_2604}" "${got_2604}"

# Previous by-hash generation: a client holding the OLD Release asks for the
# OLD Packages by hash. Every regenerated suite (including the bare alias)
# must still serve it.
for s in stable-2404 stable stable-2604; do
    old_hash="$(awk '$0=="SHA256:"{f=1;next} /^[A-Za-z0-9-]+:/{f=0} f && $3=="main/binary-amd64/Packages"{print $1}' "${LIVE}/dists/${s}/Release")"
    new_hash="$(awk '$0=="SHA256:"{f=1;next} /^[A-Za-z0-9-]+:/{f=0} f && $3=="main/binary-amd64/Packages"{print $1}' "${OUT}/dists/${s}/Release")"
    assert_equals "${s}: old and new Packages differ (fixture sanity)" "yes" "$([[ "${old_hash}" != "${new_hash}" ]] && echo yes || echo no)"
    assert_equals "${s}: previous Packages kept under by-hash" "yes" \
        "$(cmp -s "${LIVE}/dists/${s}/main/binary-amd64/Packages" "${OUT}/dists/${s}/main/binary-amd64/by-hash/SHA256/${old_hash}" && echo yes || echo no)"
    assert_equals "${s}: new Packages under by-hash" "yes" \
        "$([[ -f "${OUT}/dists/${s}/main/binary-amd64/by-hash/SHA256/${new_hash}" ]] && echo yes || echo no)"
    old_rel="$(sha256sum "${LIVE}/dists/${s}/Release" | awk '{print $1}')"
    assert_equals "${s}: previous Release kept under by-hash" "yes" \
        "$(cmp -s "${LIVE}/dists/${s}/Release" "${OUT}/dists/${s}/by-hash/SHA256/${old_rel}" && echo yes || echo no)"
    # Only those two generations: every by-hash file is listed by the old or
    # the new Release.
    known="$(cat "${LIVE}/dists/${s}/Release" "${OUT}/dists/${s}/Release" \
        | awk '$0=="SHA256:"{f=1;next} /^[A-Za-z0-9-]+:/{f=0} f && $3 ~ /^main\/binary-amd64\//{print $1}' | sort -u)"
    extra="$(find "${OUT}/dists/${s}/main/binary-amd64/by-hash/SHA256" -type f -exec basename {} \; | sort -u \
        | comm -23 - <(printf '%s\n' "${known}"))"
    assert_equals "${s}: by-hash holds only the previous and the new generation" "" "${extra}"
done

rc=0
bash "${PROJECT_ROOT}/scripts/verify_repo_integrity.sh" --keyring "${REPO_KEYRING}" "${OUT}" >/dev/null 2>&1 || rc=$?
assert_equals "assembled repo verifies against the signing key" "0" "${rc}"

# ============================================
# Step 4: Transient and persistent download failures
# ============================================

echo ""
echo ">>> Download failures while mirroring the live repo..."
kill "${HTTP_PID}" >/dev/null 2>&1 || true
HTTP_PID=""
OLD_DEB_PATH="$(awk '/^Filename:/{print $2; exit}' "${LIVE}/dists/stable-2604/main/binary-amd64/Packages")"

# publish_with_rule <label> <rule> [deb-dir] -> runs the 2404 pass (which
# mirrors the 2604 suite) against a server with <rule>; prints the exit code.
# [deb-dir] defaults to the full amd64 + arm64 build.
publish_with_rule() {
    local label="$1" rule="$2" debs="${3:-${NEW_DEBS_2404}}"
    local out="${TMP_ROOT}/out-${label}"
    rm -rf "${out}"
    mkdir -p "${out}"
    start_mock_http "${LIVE}" "${TMP_ROOT}/hits-${label}.log" --rule "${rule}" || return 1
    local rc=0
    bash "${PROJECT_ROOT}/scripts/ci_publish.sh" stable 2404 "${debs}" "${MOCK_URL}" "${out}" \
        > "${TMP_ROOT}/${label}.log" 2>&1 || rc=$?
    stop_mock_http
    echo "${rc}"
}

rc="$(publish_with_rule deb503 "/${OLD_DEB_PATH}\$=503")"
assert_equals "pool .deb answering 503 every time stops the publish" "1" "${rc}"
assert_equals "the 503 was retried FETCH_ATTEMPTS times" "3" "$(mock_hits "${TMP_ROOT}/hits-deb503.log" "/${OLD_DEB_PATH}\$")"
assert_equals "no suite published after the 503" "absent" \
    "$([[ -e "${TMP_ROOT}/out-deb503/index.html" ]] && echo present || echo absent)"

rc="$(publish_with_rule debcut "/${OLD_DEB_PATH}\$=truncate")"
assert_equals "pool .deb cut off every time stops the publish" "1" "${rc}"

rc="$(publish_with_rule deb404 "/${OLD_DEB_PATH}\$=404")"
assert_equals "listed pool .deb answering 404 stops the publish (no silently smaller suite)" "1" "${rc}"
assert_equals "the 404 is reported" "yes" \
    "$(grep -q 'the live site does not have it (HTTP 404)' "${TMP_ROOT}/deb404.log" && echo yes || echo no)"

rc="$(publish_with_rule target-packages503 "/dists/stable-2404/main/binary-amd64/Packages\$=503")"
assert_equals "live target Packages answering 503 stops the publish" "yes" "$([[ "${rc}" -ne 0 ]] && echo yes || echo no)"

rc="$(publish_with_rule target-release503 "/dists/stable-2404/Release\$=503")"
assert_equals "live target Release answering 503 stops the publish" "yes" "$([[ "${rc}" -ne 0 ]] && echo yes || echo no)"

rc="$(publish_with_rule release503 "/dists/stable-2604/Release\$=503")"
assert_equals "live Release answering 503 stops the publish (not treated as unpublished)" "1" "${rc}"

rc="$(publish_with_rule deb503once "/${OLD_DEB_PATH}\$=503:1")"
assert_equals "one 503 then success is retried and the publish completes" "0" "${rc}"

# A missing arch (its build cell failed): preserve_missing_arches carries the
# arch's last-good packages over from the live target suite. A download
# failure there must stop the publish, not wipe the arch from the suite.
echo ""
echo ">>> Missing arch: last-good packages carried over, download failures stop it..."
AMD64_ONLY_2404="${TMP_ROOT}/new-debs-2404-amd64-only"
mkdir -p "${AMD64_ONLY_2404}"
cp "${NEW_DEBS_2404}"/*_amd64.deb "${AMD64_ONLY_2404}/"
OLD_ARM64_DEB_PATH="$(awk '/^Filename:/{print $2; exit}' "${LIVE}/dists/stable-2404/main/binary-arm64/Packages")"

rc="$(publish_with_rule arm64-preserved "/no-such-file\$=503" "${AMD64_ONLY_2404}")"
assert_equals "amd64-only publish completes" "0" "${rc}"
assert_equals "stable-2404 amd64 at the new version" "${NEW_2404}" \
    "$(pkg_version "${TMP_ROOT}/out-arm64-preserved/dists/stable-2404/main/binary-amd64/Packages" "${PKG}" 2>/dev/null || true)"
assert_equals "stable-2404 arm64 kept at its last-good version" "${OLD_2404}" \
    "$(pkg_version "${TMP_ROOT}/out-arm64-preserved/dists/stable-2404/main/binary-arm64/Packages" "${PKG}" 2>/dev/null || true)"

rc="$(publish_with_rule arm64-deb503 "/${OLD_ARM64_DEB_PATH}\$=503" "${AMD64_ONLY_2404}")"
assert_equals "a 503 on the last-good arm64 .deb stops the publish (arm64 not wiped)" "1" "${rc}"
assert_equals "the preservation failure is reported" "yes" \
    "$(grep -q 'for arm64 preservation' "${TMP_ROOT}/arm64-deb503.log" && echo yes || echo no)"

# ============================================
# Step 5: Signing failures
# ============================================

echo ""
echo ">>> Signing failures..."
REAL_GPG="$(command -v gpg)"
SHIM_DIR="${TMP_ROOT}/gpg-shim"
mkdir -p "${SHIM_DIR}"
cat > "${SHIM_DIR}/gpg" <<EOF_SHIM
#!/bin/bash
for a in "\$@"; do
    case "\$a" in
        --clearsign) [[ "\${FAIL_GPG_MODE:-}" == clearsign ]] && exit 2 ;;
        -abs) [[ "\${FAIL_GPG_MODE:-}" == detach ]] && exit 2 ;;
    esac
done
exec "${REAL_GPG}" "\$@"
EOF_SHIM
chmod +x "${SHIM_DIR}/gpg"
start_mock_http "${LIVE}" "${TMP_ROOT}/hits-sign.log"
for mode in clearsign detach; do
    out="${TMP_ROOT}/out-sign-${mode}"
    mkdir -p "${out}"
    rc=0
    PATH="${SHIM_DIR}:${PATH}" FAIL_GPG_MODE="${mode}" bash "${PROJECT_ROOT}/scripts/ci_publish.sh" \
        stable 2404 "${NEW_DEBS_2404}" "${MOCK_URL}" "${out}" > "${TMP_ROOT}/sign-${mode}.log" 2>&1 || rc=$?
    assert_equals "ci_publish.sh exits non-zero when ${mode} signing fails" "yes" "$([[ "${rc}" -ne 0 ]] && echo yes || echo no)"
    assert_equals "the ${mode} failure is reported" "yes" \
        "$(grep -q 'signing failed\|gpg --clearsign failed' "${TMP_ROOT}/sign-${mode}.log" && echo yes || echo no)"
done
stop_mock_http

echo ""
echo "========================================"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "========================================"
[[ ${FAIL_COUNT} -eq 0 ]]
