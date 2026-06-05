#!/bin/bash

# Abort on Error
set -euo pipefail

# verify_depends.sh - on-Ubuntu proof of the ldd->dpkg-query dependency detector
# (PKG-10) plus the D-14 24.04 functional-equivalence baseline and a
# render-and-parse smoke of the ${DETECTED_DEPENDS} injection (Pitfall 3).
#
# This script MUST run on an Ubuntu host/container with:
#   - a populated DESTDIR staging tree (the freshly-built component binaries),
#   - dpkg / dpkg-query, ldd, realpath, envsubst, and nfpm on PATH.
# It cannot run on the macOS dev host (no dpkg/ldd) — it is the on-Ubuntu gate
# the Plan 04 human-verify checkpoint confirms.
#
# It sources functions.sh (which tail-sources config.sh) to reuse the exact
# detect_runtime_depends() the build uses, and replicates package_all.sh's
# COMPONENT_BINARIES map and envsubst render so the validation exercises the
# real injection path, not a parallel reimplementation.
#
# Parts:
#   A. Detector smoke + D-14 baseline (PKG-10, D-14): run detect_runtime_depends
#      on every component's binaries, print the detected set, and on DISTRO=24.04
#      assert it functionally equals the t64-adjusted pre-v3.0 hardcoded baseline.
#      The t64 transition (RESEARCH Pitfall 1) means the baseline is the OLD set
#      with libgpgme11->libgpgme11t64 and libglib2.0-0->libglib2.0-0t64; every
#      other name is unchanged (A2). An undocumented delta on 24.04 is a FAIL.
#   B. Render-and-parse (Pitfall 3): render each component YAML via envsubst and
#      confirm `nfpm pkg` parses it for both DISTRO=24.04 and DISTRO=26.04,
#      checking the empty-deps and mixed-static-deps cases.

# ---------------------------------------------------------------------------
# Bootstrap: locate the repo root and source the real detector + config.
# ---------------------------------------------------------------------------
relativepath="../"
if [[ ! -v toolpath ]]; then
    scriptpath=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    toolpath=$(realpath --canonicalize-missing "${scriptpath}/${relativepath}")
fi

# functions.sh tail-sources config.sh (which exports ARCH / DISTRO_VERSION_ID /
# VERSION_SUFFIX). detect_runtime_depends and detect_distro_version_id come from
# functions.sh.
# shellcheck source=/dev/null
source "${toolpath}/functions.sh"

# Set error trap AFTER sourcing (mirrors package_all.sh house style).
trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR

NFPM_DIR="${toolpath}/packaging/nfpm"

# Resolve the distro under test (DISTRO override -> /etc/os-release).
DISTRO_VERSION_ID="$(detect_distro_version_id)"

echo ""
echo "========================================"
echo ">>> verify_depends.sh — detector smoke + D-14 baseline + render/parse"
echo "========================================"
echo "DISTRO_VERSION_ID: ${DISTRO_VERSION_ID}"
echo "DESTDIR:           ${DESTDIR:-<unset>}"
echo "ARCH:              ${ARCH:-<unset>}"
echo ""

# ---------------------------------------------------------------------------
# Prerequisites — fail loud, never silently skip (this is a proof gate).
# ---------------------------------------------------------------------------
if [[ -z "${DESTDIR:-}" || ! -d "${DESTDIR}" ]]; then
    echo "ERROR: DESTDIR must point at a populated staging tree (got '${DESTDIR:-<unset>}')." >&2
    echo "  Run the build scripts with DESTDIR set before running verify_depends.sh." >&2
    exit 1
fi
for tool in dpkg-query ldd realpath envsubst nfpm; do
    if ! command -v "${tool}" &>/dev/null; then
        echo "ERROR: required tool '${tool}' not found on PATH — verify_depends.sh must run on an Ubuntu build host." >&2
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# COMPONENT_BINARIES — mirrors scripts/package_all.sh (DESTDIR-relative ELF
# paths). Keep in sync with that map; components with no native ELF binary
# (container-configs, toolbox) are intentionally absent.
# ---------------------------------------------------------------------------
declare -A COMPONENT_BINARIES=(
    ["podman"]="usr/bin/podman usr/bin/podman-remote"
    ["crun"]="usr/bin/crun"
    ["conmon"]="usr/bin/conmon"
    ["netavark"]="usr/bin/netavark"
    ["aardvark-dns"]="usr/bin/aardvark-dns"
    ["pasta"]="usr/bin/passt usr/bin/pasta"
    ["fuse-overlayfs"]="usr/bin/fuse-overlayfs"
    ["catatonit"]="usr/bin/catatonit"
    ["buildah"]="usr/bin/buildah"
    ["skopeo"]="usr/bin/skopeo"
)

# ---------------------------------------------------------------------------
# D-14 baseline (24.04, t64-adjusted). Per RESEARCH Pitfall 1 + Open Question 2:
# the pre-v3.0 hardcoded system-lib set, with the two t64-transitioned names
# substituted (libgpgme11 -> libgpgme11t64, libglib2.0-0 -> libglib2.0-0t64).
# Every other name is unchanged on 24.04 (assumption A2, verified by this run).
# crun's JSON-parser dep is host-dependent (libjson-c5 OR libyajl2, D-04); we
# accept either via the BASELINE_24_04_ALT map below rather than hard-coding one.
#
# Functional equivalence (NOT string identity): the detected set on 24.04 must
# equal this baseline. A name detected that is NOT in the baseline AND is not a
# documented t64 form is a FAIL (T-19-10 — the equivalence check cannot
# rubber-stamp a wrong detected set).
# ---------------------------------------------------------------------------
declare -A BASELINE_24_04=(
    ["podman"]="libgpgme11t64 libseccomp2"
    ["buildah"]="libgpgme11t64 libseccomp2"
    ["skopeo"]="libgpgme11t64 libsubid4 libsqlite3-0"
    ["crun"]="libseccomp2 libsystemd0 libcap2"
    ["conmon"]="libglib2.0-0t64 libsystemd0"
)
# crun links exactly one JSON parser; accept either mapping (D-04).
declare -A BASELINE_24_04_ALT=(
    ["crun"]="libjson-c5 libyajl2"
)
# The two names that legitimately gain t64 on 24.04 (RESEARCH Pitfall 1),
# mapped t64-name -> pre-substitution name. A t64 name is only accepted for a
# component when its PRE-substitution name is in that component's baseline
# (WR-04) — a global allowlist would rubber-stamp e.g. libgpgme11t64 reported
# by conmon (which should never link it), defeating T-19-10. Any OTHER
# unexpected name on 24.04 is still a regression FAIL.
declare -A T64_PRE_SUBST=(
    ["libgpgme11t64"]="libgpgme11"
    ["libglib2.0-0t64"]="libglib2.0-0"
)

# Helper: is $1 present in the space-separated list $2 ?
in_list() {
    local needle="$1" hay="$2" item
    for item in ${hay}; do
        [[ "${item}" == "${needle}" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Part A — detector smoke + D-14 24.04 functional-equivalence assertion.
# ---------------------------------------------------------------------------
echo ">>> Part A: detector smoke + D-14 baseline"
echo "----------------------------------------"

partA_fail=0
# Stable component ordering for deterministic output.
for component in podman crun conmon netavark aardvark-dns pasta fuse-overlayfs catatonit buildah skopeo; do
    [[ -v "COMPONENT_BINARIES[$component]" ]] || continue

    component_bins=()
    for rel_bin in ${COMPONENT_BINARIES[$component]}; do
        component_bins+=("${DESTDIR}/${rel_bin}")
    done

    # Run the REAL detector (no '|| true' — an unmapped soname aborts, D-03).
    detected="$(detect_runtime_depends "${component_bins[@]}" | tr '\n' ' ')"
    detected="${detected% }"
    echo "  ${component}: detected = [${detected}]"

    # Only 24.04 has an asserted baseline; on other distros we record + move on
    # (the 26.04 set is captured as new ground truth, e.g. libgpgme45/libsubid5).
    if [[ "${DISTRO_VERSION_ID}" != "24.04" ]]; then
        continue
    fi

    # fuse-overlayfs / catatonit have no pre-v3.0 hardcoded baseline; their real
    # detected set is the open item handled in the YAML follow-up below.
    if [[ ! -v "BASELINE_24_04[$component]" ]]; then
        echo "    (no D-14 baseline for ${component}; detected set recorded for YAML follow-up)"
        continue
    fi

    baseline="${BASELINE_24_04[$component]}"
    # Augment the baseline with the acceptable JSON-parser alternatives (crun).
    alt="${BASELINE_24_04_ALT[$component]:-}"

    # Per-component failure flag (WR-03): gate THIS component's PASS line on its
    # own status, not the global partA_fail accumulator — otherwise a later
    # passing component prints nothing once any earlier component failed.
    comp_fail=0

    # Every detected name must be in the baseline (or an accepted alt, or a
    # documented t64 form WHOSE pre-substitution name is in THIS component's
    # baseline). Anything else is an undocumented regression.
    for name in ${detected}; do
        if in_list "${name}" "${baseline}"; then
            continue
        fi
        if [[ -n "${alt}" ]] && in_list "${name}" "${alt}"; then
            continue
        fi
        # WR-04: accept a t64 name only when its pre-substitution form is the
        # documented baseline dep for THIS component.
        if [[ -v "T64_PRE_SUBST[$name]" ]] && in_list "${T64_PRE_SUBST[$name]}" "${baseline}"; then
            continue
        fi
        echo "    FAIL: ${component} detected unexpected dep '${name}' not in the t64-adjusted D-14 baseline [${baseline}${alt:+ | alt: ${alt}}]" >&2
        comp_fail=1
    done

    # Every baseline name (minus the parser-alt slot) must be detected, else a
    # dependency silently dropped — also a regression.
    for name in ${baseline}; do
        if ! in_list "${name}" "${detected}"; then
            echo "    FAIL: ${component} is missing expected baseline dep '${name}' (detected: [${detected}])" >&2
            comp_fail=1
        fi
    done

    # crun must link exactly one of the accepted JSON parsers.
    if [[ -n "${alt}" ]]; then
        found_alt=0
        for name in ${alt}; do
            in_list "${name}" "${detected}" && found_alt=1
        done
        if [[ "${found_alt}" -eq 0 ]]; then
            echo "    FAIL: ${component} linked no JSON parser from [${alt}] (detected: [${detected}])" >&2
            comp_fail=1
        fi
    fi

    if [[ "${comp_fail}" -eq 0 ]]; then
        echo "    PASS: ${component} detected set functionally equals t64-adjusted D-14 baseline"
    else
        partA_fail=1
    fi
done

if [[ "${partA_fail}" -ne 0 ]]; then
    echo "" >&2
    echo "FAIL: Part A — 24.04 detected set diverged from the t64-adjusted D-14 baseline (see above)." >&2
    exit 1
fi
echo ""

# ---------------------------------------------------------------------------
# Part B — render-and-parse smoke (Pitfall 3) for BOTH distros.
# Replicates package_all.sh's envsubst render per component and lets `nfpm pkg`
# parse it. Covers the mixed-static-deps case (podman/buildah/skopeo carry
# literal podman-* deps + the injected block) and the inject-only case
# (crun/conmon/pasta) and the no-binary case (container-configs/toolbox).
# ---------------------------------------------------------------------------
echo ">>> Part B: render-and-parse every nFPM YAML (DISTRO=24.04 and 26.04)"
echo "----------------------------------------"

tmp_render_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_render_dir}"; error_handler $? $LINENO "$BASH_SOURCE"' ERR

# All component YAMLs in NFPM_DIR (suite.yaml has no ${DETECTED_DEPENDS} but
# still must render; we render it too for completeness).
render_one() {
    local yaml="$1" comp="$2" detected_fragment="$3"
    local rendered="${tmp_render_dir}/nfpm-${comp}.yaml"

    # Mirror package_all.sh: export the same four vars and allowlist them.
    export VERSION="0.0.0~ubuntu${DISTRO_VERSION_ID}.podman1"
    export ARCH="${ARCH}"
    export DESTDIR="${DESTDIR}"
    export DETECTED_DEPENDS="${detected_fragment}"

    envsubst '${VERSION} ${ARCH} ${DESTDIR} ${DETECTED_DEPENDS}' < "${yaml}" > "${rendered}"

    # `nfpm pkg` parses+validates the config; a YAML error or garbled depends
    # block makes it exit non-zero. Target a throwaway dir.
    if ! nfpm pkg --config "${rendered}" --packager deb --target "${tmp_render_dir}" >/dev/null 2>"${tmp_render_dir}/nfpm.err"; then
        echo "    FAIL: nfpm rejected rendered ${comp}.yaml (DISTRO=${DISTRO_VERSION_ID})" >&2
        sed 's/^/      /' "${tmp_render_dir}/nfpm.err" >&2
        return 1
    fi

    # Assert the rendered depends block is well-formed: if the source YAML has a
    # `depends:` key, it must not be empty/garbled (no dangling `- ` or a
    # `depends:` immediately followed by a non-list line).
    if grep -q '^depends:' "${rendered}"; then
        # Collect the indented list items under depends:.
        local dep_lines
        dep_lines="$(awk '/^depends:/{f=1;next} f&&/^[^[:space:]]/{f=0} f&&/^[[:space:]]*-[[:space:]]*[^[:space:]]/{print}' "${rendered}")"
        if [[ -z "${dep_lines}" ]]; then
            echo "    FAIL: ${comp}.yaml has a depends: key but no well-formed list items after render (DISTRO=${DISTRO_VERSION_ID})" >&2
            return 1
        fi
    fi
    echo "    PASS: ${comp}.yaml renders + parses (DISTRO=${DISTRO_VERSION_ID})"
    return 0
}

partB_fail=0
for distro_under_test in 24.04 26.04; do
    DISTRO_VERSION_ID="${distro_under_test}"
    echo "  -- DISTRO=${DISTRO_VERSION_ID} --"
    for yaml in "${NFPM_DIR}"/*.yaml; do
        comp="$(basename "${yaml}" .yaml)"

        # Compute the injected fragment exactly as package_all.sh does: real
        # detection for components with binaries, empty otherwise. Detection is
        # distro-independent here (the binaries+host package DB are the 24.04
        # build host's), so we render the *shape* for both distro version
        # strings — the depends NAMES come from the host, which is the point of
        # the 24.04 baseline in Part A.
        if [[ -v "COMPONENT_BINARIES[$comp]" ]]; then
            cbins=()
            for rel_bin in ${COMPONENT_BINARIES[$comp]}; do
                cbins+=("${DESTDIR}/${rel_bin}")
            done
            fragment="$(detect_runtime_depends "${cbins[@]}" | sed 's/^/  - /')"
        else
            fragment=""
        fi

        if ! render_one "${yaml}" "${comp}" "${fragment}"; then
            partB_fail=1
        fi
    done
done

rm -rf "${tmp_render_dir}"
trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR

if [[ "${partB_fail}" -ne 0 ]]; then
    echo "" >&2
    echo "FAIL: Part B — one or more nFPM YAMLs failed to render+parse (see above)." >&2
    exit 1
fi
echo ""

echo "========================================"
echo ">>> verify_depends.sh: ALL CHECKS PASSED"
echo "========================================"
echo "  - Part A: 24.04 detected set functionally equals the t64-adjusted D-14 baseline"
echo "  - Part B: every nFPM YAML renders + parses for DISTRO=24.04 and 26.04"
echo ""
exit 0
