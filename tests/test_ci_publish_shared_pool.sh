#!/bin/bash

# Regression test: the shared-pool overwrite bug ("File has unexpected size").
#
# reprepro shares ONE pool across all suites keyed by (source, version, arch), so
# a component version shipped by MORE THAN ONE track (e.g. skopeo, shared by the
# stable 6.x and v5 5.x lines) lives at a single pool path. The bug: when one
# track republishes and its freshly-compiled — non-reproducible — rebuild of that
# shared version has DIFFERENT bytes, reprepro overwrote the shared pool .deb out
# from under the OTHER track's already-signed, verbatim-served index. That index
# then advertised a stale Size/SHA256 and apt refused the download.
#
# Two scenarios, both driving the real ci_publish.sh against a mock live repo:
#
#   A. PREVENT — a consistent live repo, then a v5 publish whose skopeo rebuild
#      differs byte-for-byte from the already-published skopeo of the SAME version.
#      The fix (pool immutability) must adopt the published bytes so stable-2404's
#      verbatim index stays valid. Assert the assembled repo passes the integrity
#      guard and stable-2404's skopeo pool bytes are unchanged.
#
#   B. HEAL — an ALREADY-corrupted live repo (pool .deb bytes no longer match the
#      signed index, reproducing the production incident), then any publish. The
#      fix (verbatim integrity check + demote-to-re-export) must regenerate the
#      affected suites' indexes from the real pool bytes so the result is
#      consistent again. Assert the assembled repo passes the integrity guard.
#
# Pre-fix, ci_publish.sh's own integrity gate (or the standalone guard) fails
# both. Post-fix, both pass.
#
#   E. ADOPT: a stable republish whose rebuild of an UNCHANGED package (same
#      name, version and architecture as the live stable index) has different
#      bytes. Only the target suite lists that package, so the output pool
#      cannot help; the published bytes must be downloaded and adopted, and
#      the fresh rebuild dropped. Without that, E overwrites published bytes.
#
# Ubuntu-only (reprepro + gpg + gpgv + dpkg-deb). Prints SKIP + exits 0 on
# macOS (a failure under REQUIRE_INTEGRATION_DEPS=1).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
# shellcheck source=tests/lib/integration_deps.sh
source "${SCRIPT_DIR}/lib/integration_deps.sh"

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
    echo "        Ubuntu-only integration harness — run on the ubuntu-24 VM / CI:"
    echo "          sudo apt-get update && sudo apt-get install -y reprepro"
    echo ""
    echo "Results: 0 passed, 0 failed (SKIPPED on this host)"
    exit 0
fi

# ============================================
# Isolated fixture
# ============================================

TMP_ROOT="$(mktemp -d)"
export GNUPGHOME="${TMP_ROOT}/gnupg"
mkdir -p "${GNUPGHOME}"
chmod 700 "${GNUPGHOME}"
HTTP_PID=""
cleanup() {
    [[ -n "${HTTP_PID}" ]] && kill "${HTTP_PID}" >/dev/null 2>&1 || true
    gpgconf --homedir "${GNUPGHOME}" --kill all >/dev/null 2>&1 || true
    rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

echo ">>> Generating throwaway GPG signing key..."
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
# ci_publish.sh checks every signature against REPO_KEYRING; here that is
# the throwaway key, not the project's published one.
export REPO_KEYRING="${TMP_ROOT}/test-key.gpg"
gpg --batch --export "${TEST_KEY_FPR}" > "${REPO_KEYRING}"
export FETCH_RETRY_DELAY=0 FETCH_ATTEMPTS=3
echo ""

# build_deb <pkg> <version> <arch> <out-dir> <payload>
# <payload> forces the .deb byte content: two builds of the same version with
# different payloads produce different bytes (a non-reproducible rebuild).
build_deb() {
    local lpkg="$1" lver="$2" larch="$3" lout="$4" lpayload="$5"
    local lstage="${TMP_ROOT}/stage-${lpkg}-${lver}-${larch}-$(echo "${lpayload}" | cksum | awk '{print $1}')"
    rm -rf "${lstage}"
    mkdir -p "${lstage}/DEBIAN" "${lstage}/usr/share/doc/${lpkg}"
    cat > "${lstage}/DEBIAN/control" <<EOF_CTL
Package: ${lpkg}
Version: ${lver}
Architecture: ${larch}
Maintainer: Repo Test <repo-test@example.invalid>
Section: admin
Priority: optional
Description: Fixture ${lpkg} for the shared-pool regression harness
 Not a real package.
EOF_CTL
    printf '%s\n' "${lpayload}" > "${lstage}/usr/share/doc/${lpkg}/payload"
    mkdir -p "${lout}"
    dpkg-deb --build --root-owner-group "${lstage}" \
        "${lout}/${lpkg}_${lver}_${larch}.deb" >/dev/null
}

pkg_size() {  # <packages-file> <package> -> Size field of first matching stanza
    awk -v p="$2" '/^Package:/{cur=$2} /^Size:/{if(cur==p){print $2;exit}}' "$1"
}

pkg_version() {  # <packages-file> <package> -> Version field, or MISSING
    [[ -f "$1" ]] || { echo "MISSING"; return; }
    awk -v p="$2" '/^Package:/{cur=$2} /^Version:/{if(cur==p){print $2;found=1;exit}} END{if(!found)print "MISSING"}' "$1"
}

# Distro-aware helpers: the shared skopeo version and its pool path carry the
# per-distro suffix (~ubuntu24.04 / ~ubuntu26.04). The collision this harness
# reproduces is SAME-distro cross-track (stable-<D> vs v5-<D> sharing skopeo),
# so every fixture is parameterized by distro to prove the fix on both cells.
dotted() { case "$1" in 2404) echo 24.04;; 2604) echo 26.04;; esac; }
skopeo_ver() { echo "1.23.0~ubuntu$(dotted "$1").podman1"; }   # shared across stable + v5
skopeo_filename() { echo "pool/main/p/podman-skopeo/podman-skopeo_$(skopeo_ver "$1")_amd64.deb"; }

# build_live only assembles via repo_manage.sh (a separate process); each
# scenario signs the suites right after it with add_byhash_and_resign.
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/scripts/repo_byhash.sh"

# ============================================
# Build a consistent mock live repo for distro <D>: stable-<D> and v5-<D> both
# ship podman-skopeo $(skopeo_ver D) — the SAME shared pool .deb (payload "A").
# ============================================

build_live() {
    local live="$1" skopeo_payload="$2" distro="$3"
    local d; d="$(dotted "${distro}")"
    local sk; sk="$(skopeo_ver "${distro}")"
    local stable_debs="${TMP_ROOT}/live-stable-${distro}-$$-${RANDOM}"
    local v5_debs="${TMP_ROOT}/live-v5-${distro}-$$-${RANDOM}"
    local shared_debs="${TMP_ROOT}/live-shared-${distro}-$$-${RANDOM}"
    rm -rf "${stable_debs}" "${v5_debs}" "${shared_debs}"
    for arch in amd64 arm64; do
        # podman is track-specific (6.x vs 5.x) — distinct pool paths.
        build_deb "podman-podman" "6.0.0~ubuntu${d}.podman1" "${arch}" "${stable_debs}" "podman-6"
        build_deb "podman-podman" "5.0.0~ubuntu${d}.podman1" "${arch}" "${v5_debs}" "podman-5"
        # skopeo is SHARED across both tracks at ONE version. Build it exactly once
        # and feed the SAME file to both tracks, so the live repo has a single
        # canonical binary per version (what a real published repo looks like).
        # Building it twice would embed different dpkg-deb mtimes => byte-different
        # .debs for the same version => an already-inconsistent live fixture.
        build_deb "podman-skopeo" "${sk}" "${arch}" "${shared_debs}" "${skopeo_payload}"
        cp "${shared_debs}/podman-skopeo_${sk}_${arch}.deb" "${stable_debs}/"
        cp "${shared_debs}/podman-skopeo_${sk}_${arch}.deb" "${v5_debs}/"
    done
    "${PROJECT_ROOT}/scripts/repo_manage.sh" stable "${distro}" "${stable_debs}" "${live}" >/dev/null
    "${PROJECT_ROOT}/scripts/repo_manage.sh" v5     "${distro}" "${v5_debs}"     "${live}" >/dev/null
}

# Suites to sign for a given distro's live repo (2404 also carries the bare alias).
live_suites() {
    case "$1" in
        2404) echo "stable-2404 stable v5-2404";;
        2604) echo "stable-2604 v5-2604";;
    esac
}

serve() {  # <dir> <probe-suite> -> sets REPO_URL / HTTP_PID
    local dir="$1" probe="$2"
    [[ -n "${HTTP_PID}" ]] && kill "${HTTP_PID}" >/dev/null 2>&1 || true
    local port
    port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
    python3 -m http.server "${port}" --bind 127.0.0.1 --directory "${dir}" >/dev/null 2>&1 &
    HTTP_PID=$!
    REPO_URL="http://127.0.0.1:${port}"
    local i
    for i in $(seq 1 50); do
        curl -sf "${REPO_URL}/dists/${probe}/Release" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    echo "  FAIL: mock HTTP server never came up"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
}

# assert_prevent <distro> <live> — a v5 publish whose shared-skopeo rebuild has
# DIFFERENT bytes must NOT overwrite the published pool .deb; every suite stays
# consistent.
assert_prevent() {
    local distro="$1" live="$2"
    local d; d="$(dotted "${distro}")"
    local sk; sk="$(skopeo_ver "${distro}")"
    local live_size
    live_size="$(pkg_size "${live}/dists/stable-${distro}/main/binary-amd64/Packages" "podman-skopeo")"
    echo "  live stable-${distro} skopeo Size: ${live_size}"

    # Fresh v5 debs: podman bumped, skopeo SAME version but a DIFFERENT (longer)
    # payload => different bytes/size. Pre-fix this overwrites the shared pool.
    local v5new="${TMP_ROOT}/v5-new-${distro}"
    local arch
    for arch in amd64 arm64; do
        build_deb "podman-podman" "5.0.1~ubuntu${d}.podman1" "${arch}" "${v5new}" "podman-5-0-1"
        build_deb "podman-skopeo" "${sk}" "${arch}" "${v5new}" \
            "skopeo-REBUILT-different-nonreproducible-bytes-XXXXXXXXXXXXXXXXX"
    done

    local out="${TMP_ROOT}/out-prevent-${distro}"
    mkdir -p "${out}"
    local rc=0
    bash "${PROJECT_ROOT}/scripts/ci_publish.sh" v5 "${distro}" "${v5new}" "${REPO_URL}" "${out}" \
        > "${TMP_ROOT}/prevent-${distro}.log" 2>&1 || rc=$?
    if [[ "${rc}" -ne 0 ]]; then
        echo "  (ci_publish.sh exited ${rc}; tail:)"
        tail -25 "${TMP_ROOT}/prevent-${distro}.log" | sed 's/^/      /'
    fi
    assert_equals "[${distro}] ci_publish v5 exits 0 (internal integrity gate passes)" "0" "${rc}"
    assert_equals "[${distro}] stable-${distro} skopeo Size unchanged (published bytes preserved)" \
        "${live_size}" "$(pkg_size "${out}/dists/stable-${distro}/main/binary-amd64/Packages" "podman-skopeo" 2>/dev/null || true)"
    assert_equals "[${distro}] v5-${distro} skopeo Size equals the shared published bytes" \
        "${live_size}" "$(pkg_size "${out}/dists/v5-${distro}/main/binary-amd64/Packages" "podman-skopeo" 2>/dev/null || true)"
    rc=0
    bash "${PROJECT_ROOT}/scripts/verify_repo_integrity.sh" "${out}" >/dev/null 2>&1 || rc=$?
    assert_equals "[${distro}] assembled repo passes standalone integrity guard" "0" "${rc}"
}

# ============================================
# Scenario A: PREVENT on 24.04 — cross-track overwrite of the shared pool .deb.
# ============================================

echo "========================================"
echo "Scenario A: pool immutability prevents cross-track overwrite (24.04)"
echo "========================================"
LIVE_A="${TMP_ROOT}/live-a"
build_live "${LIVE_A}" "skopeo-canonical-payload-AAAA" 2404
for s in $(live_suites 2404); do   # top-level signing (see note above build_live)
    [[ -f "${LIVE_A}/dists/${s}/Release" ]] && add_byhash_and_resign "${s}" "${LIVE_A}" >/dev/null
done
serve "${LIVE_A}" "stable-2404" || true
assert_prevent 2404 "${LIVE_A}"
echo ""

# ============================================
# Scenario C: PREVENT on 26.04 — identical mechanism, ~ubuntu26.04 suffix.
# ============================================

echo "========================================"
echo "Scenario C: pool immutability prevents cross-track overwrite (26.04)"
echo "========================================"
LIVE_C="${TMP_ROOT}/live-c"
build_live "${LIVE_C}" "skopeo-canonical-payload-AAAA" 2604
for s in $(live_suites 2604); do
    [[ -f "${LIVE_C}/dists/${s}/Release" ]] && add_byhash_and_resign "${s}" "${LIVE_C}" >/dev/null
done
serve "${LIVE_C}" "stable-2604" || true
assert_prevent 2604 "${LIVE_C}"
echo ""

# ============================================
# Scenario B: HEAL — the live repo is ALREADY inconsistent (production incident).
# ============================================

echo "========================================"
echo "Scenario B: verbatim integrity check heals an already-corrupted live repo (24.04)"
echo "========================================"

SKOPEO_VER="$(skopeo_ver 2404)"
SKOPEO_FILENAME="$(skopeo_filename 2404)"

LIVE_B="${TMP_ROOT}/live-b"
build_live "${LIVE_B}" "skopeo-canonical-payload-AAAA" 2404
for s in $(live_suites 2404); do
    [[ -f "${LIVE_B}/dists/${s}/Release" ]] && add_byhash_and_resign "${s}" "${LIVE_B}" >/dev/null
done

# Corrupt the live repo exactly as the incident did: overwrite the shared pool
# skopeo .deb with byte-different content of the SAME version, WITHOUT updating
# any signed index. Now stable-2404 / v5-2404 indexes advertise the old Size/SHA
# but the pool serves different bytes.
build_deb "podman-skopeo" "${SKOPEO_VER}" "amd64" "${TMP_ROOT}/corrupt" \
    "skopeo-CORRUPTED-live-pool-bytes-YYYYYYYYYYYYYYYYYYYYYYYYYY"
cp -f "${TMP_ROOT}/corrupt/podman-skopeo_${SKOPEO_VER}_amd64.deb" "${LIVE_B}/${SKOPEO_FILENAME}"

# Sanity: the live repo is now internally inconsistent (guard must fail on it).
rc=0
bash "${PROJECT_ROOT}/scripts/verify_repo_integrity.sh" "${LIVE_B}" >/dev/null 2>&1 || rc=$?
assert_equals "corrupted live repo fails the guard (fixture is valid)" "1" "${rc}"

serve "${LIVE_B}" "stable-2404" || true

# A nightly publish (unrelated versions) must HEAL the corrupted stable/v5 suites
# by re-exporting their indexes from the real (corrupted-but-now-canonical) pool.
NIGHTLY_DEBS="${TMP_ROOT}/nightly-debs"
for arch in amd64 arm64; do
    build_deb "podman-podman" "99.0.0~ubuntu24.04.podman1" "${arch}" "${NIGHTLY_DEBS}" "nightly-podman"
done

OUT_B="${TMP_ROOT}/out-b"
mkdir -p "${OUT_B}"
rc=0
bash "${PROJECT_ROOT}/scripts/ci_publish.sh" nightly 2404 "${NIGHTLY_DEBS}" "${REPO_URL}" "${OUT_B}" \
    > "${TMP_ROOT}/b.log" 2>&1 || rc=$?
if [[ "${rc}" -ne 0 ]]; then
    echo "  (ci_publish.sh exited ${rc}; tail:)"
    tail -25 "${TMP_ROOT}/b.log" | sed 's/^/      /'
fi
assert_equals "ci_publish nightly exits 0 after healing corrupted suites" "0" "${rc}"

assert_equals "heal was triggered for a corrupted verbatim suite" \
    "yes" "$(grep -q '^>>> HEAL:' "${TMP_ROOT}/b.log" && echo yes || echo no)"

rc=0
bash "${PROJECT_ROOT}/scripts/verify_repo_integrity.sh" "${OUT_B}" >/dev/null 2>&1 || rc=$?
assert_equals "healed repo passes the integrity guard (stable/v5 reconciled)" "0" "${rc}"

# NO-DROP regression: heal must not drop any suite. A demoted suite whose pool
# .debs were already present (placed by an earlier demoted suite sharing the same
# pool paths — the bare `stable` alias is byte-identical to stable-2404) carried
# suite_count=0 and was skipped by the Step 4 gate, 404-ing the suite on the live
# repo. Every corrupted suite must still be present with its skopeo package.
SK_2404="$(skopeo_ver 2404)"
for s in stable-2404 stable v5-2404; do
    assert_equals "healed suite '${s}' still present with podman-skopeo (no-drop)" \
        "${SK_2404}" \
        "$(pkg_version "${OUT_B}/dists/${s}/main/binary-amd64/Packages" podman-skopeo)"
    # arm64 too — the drop hit both arches.
    assert_equals "healed suite '${s}' still present on arm64 (no-drop)" \
        "${SK_2404}" \
        "$(pkg_version "${OUT_B}/dists/${s}/main/binary-arm64/Packages" podman-skopeo)"
    # A healed suite is regenerated, so it keeps the previous by-hash
    # generation for clients still holding the old Release.
    old_rel="$(sha256sum "${LIVE_B}/dists/${s}/Release" | awk '{print $1}')"
    assert_equals "healed suite '${s}' keeps the previous Release under by-hash" "yes" \
        "$(cmp -s "${LIVE_B}/dists/${s}/Release" "${OUT_B}/dists/${s}/by-hash/SHA256/${old_rel}" && echo yes || echo no)"
done

echo ""

# ============================================
# Scenario D: NON-DESTRUCTIVE per-arch — a missing arch build must NOT wipe the
# suite's already-published packages for that arch.
# ============================================
# Reproduces the stable-2604 arm64 wipe: a flaky arm64 build produces no arm64
# .debs, and a target-suite rebuild from amd64-only debs would emit an empty
# arm64 index. The fix preserves the live last-good arm64 packages.

echo "========================================"
echo "Scenario D: missing-arch build preserves last-good arch (26.04)"
echo "========================================"

LIVE_D="${TMP_ROOT}/live-d"
build_live "${LIVE_D}" "skopeo-canonical-payload-AAAA" 2604
for s in $(live_suites 2604); do
    [[ -f "${LIVE_D}/dists/${s}/Release" ]] && add_byhash_and_resign "${s}" "${LIVE_D}" >/dev/null
done
serve "${LIVE_D}" "stable-2604" || true

# Precondition: live stable-2604 carries arm64 packages worth preserving.
assert_equals "live stable-2604 arm64 has podman-podman (precondition)" \
    "6.0.0~ubuntu26.04.podman1" \
    "$(pkg_version "${LIVE_D}/dists/stable-2604/main/binary-arm64/Packages" podman-podman)"

# Fresh stable-2604 build with ONLY amd64 debs (arm64 build "failed"), podman
# bumped to 6.1.0.
STABLE_NEW_AMD64="${TMP_ROOT}/stable-new-amd64"
build_deb "podman-podman" "6.1.0~ubuntu26.04.podman1" "amd64" "${STABLE_NEW_AMD64}" "podman-6-1-0"
build_deb "podman-skopeo" "$(skopeo_ver 2604)"        "amd64" "${STABLE_NEW_AMD64}" "skopeo-canonical-payload-AAAA"

OUT_D="${TMP_ROOT}/out-d"
mkdir -p "${OUT_D}"
rc=0
bash "${PROJECT_ROOT}/scripts/ci_publish.sh" stable 2604 "${STABLE_NEW_AMD64}" "${REPO_URL}" "${OUT_D}" \
    > "${TMP_ROOT}/d.log" 2>&1 || rc=$?
if [[ "${rc}" -ne 0 ]]; then
    echo "  (ci_publish.sh exited ${rc}; tail:)"
    tail -25 "${TMP_ROOT}/d.log" | sed 's/^/      /'
fi
assert_equals "ci_publish stable 2604 (amd64-only build) exits 0" "0" "${rc}"

# amd64 refreshed to the new build.
assert_equals "stable-2604 amd64 podman refreshed to new build" \
    "6.1.0~ubuntu26.04.podman1" \
    "$(pkg_version "${OUT_D}/dists/stable-2604/main/binary-amd64/Packages" podman-podman)"
# arm64 PRESERVED at last-good — the whole point (pre-fix it would be MISSING/empty).
assert_equals "stable-2604 arm64 podman preserved at last-good (not wiped)" \
    "6.0.0~ubuntu26.04.podman1" \
    "$(pkg_version "${OUT_D}/dists/stable-2604/main/binary-arm64/Packages" podman-podman)"
assert_equals "stable-2604 arm64 skopeo preserved (not wiped)" \
    "$(skopeo_ver 2604)" \
    "$(pkg_version "${OUT_D}/dists/stable-2604/main/binary-arm64/Packages" podman-skopeo)"
rc=0
bash "${PROJECT_ROOT}/scripts/verify_repo_integrity.sh" "${OUT_D}" >/dev/null 2>&1 || rc=$?
assert_equals "preserved-arch repo passes the integrity guard" "0" "${rc}"

# ============================================
# Scenario E: ADOPT the published bytes of an unchanged target package.
# ============================================

echo "========================================"
echo "Scenario E: an unchanged package in the target suite keeps its published bytes (2404)"
echo "========================================"

LIVE_E="${TMP_ROOT}/live-e"
STABLE_E="${TMP_ROOT}/live-e-stable"
build_deb "podman-podman" "6.0.0~ubuntu24.04.podman1" amd64 "${STABLE_E}" "podman-6"
build_deb "podman-skopeo" "${SK_2404}" amd64 "${STABLE_E}" "skopeo-published-bytes-DDDD"
"${PROJECT_ROOT}/scripts/repo_manage.sh" stable 2404 "${STABLE_E}" "${LIVE_E}" >/dev/null
for s in stable-2404 stable; do
    add_byhash_and_resign "${s}" "${LIVE_E}" >/dev/null
done
serve "${LIVE_E}" "stable-2404" || true
published_sha="$(sha256sum "${STABLE_E}/podman-skopeo_${SK_2404}_amd64.deb" | awk '{print $1}')"

# The rebuild: podman moves on, skopeo is the same version with new bytes.
NEW_E="${TMP_ROOT}/new-e"
build_deb "podman-podman" "6.0.1~ubuntu24.04.podman1" amd64 "${NEW_E}" "podman-6-0-1"
build_deb "podman-skopeo" "${SK_2404}" amd64 "${NEW_E}" "skopeo-REBUILT-with-other-bytes-EEEEEEEE"
fresh_sha="$(sha256sum "${NEW_E}/podman-skopeo_${SK_2404}_amd64.deb" | awk '{print $1}')"
assert_equals "fixture: rebuild differs from the published skopeo" "yes" "$([[ "${fresh_sha}" != "${published_sha}" ]] && echo yes || echo no)"

OUT_E="${TMP_ROOT}/out-e"
mkdir -p "${OUT_E}"
rc=0
bash "${PROJECT_ROOT}/scripts/ci_publish.sh" stable 2404 "${NEW_E}" "${REPO_URL}" "${OUT_E}" \
    > "${TMP_ROOT}/e.log" 2>&1 || rc=$?
if [[ "${rc}" -ne 0 ]]; then
    tail -25 "${TMP_ROOT}/e.log" | sed 's/^/      /'
fi
assert_equals "ci_publish stable exits 0" "0" "${rc}"
assert_equals "published skopeo bytes adopted into the pool" "${published_sha}" \
    "$(sha256sum "${OUT_E}/$(skopeo_filename 2404)" | awk '{print $1}')"
assert_equals "stable-2404 podman advanced" "6.0.1~ubuntu24.04.podman1" \
    "$(pkg_version "${OUT_E}/dists/stable-2404/main/binary-amd64/Packages" podman-podman)"
assert_equals "the adoption is logged" "yes" \
    "$(grep -q 'adopting the published podman-skopeo' "${TMP_ROOT}/e.log" && echo yes || echo no)"
assert_equals "input artifact dir left untouched" "${fresh_sha}" \
    "$(sha256sum "${NEW_E}/podman-skopeo_${SK_2404}_amd64.deb" | awk '{print $1}')"

echo ""
echo "========================================"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "========================================"
[[ ${FAIL_COUNT} -eq 0 ]]
