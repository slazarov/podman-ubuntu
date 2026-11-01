#!/bin/bash

# Abort on Error
set -euo pipefail

# verify_depends.sh - on-Ubuntu proof of the ldd->dpkg-query dependency detector
# (PKG-10) plus a per-distro (24.04, 26.04) functional-equivalence baseline and a
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
#   A. Detector baseline (PKG-10, D-14): run detect_runtime_depends on every
#      component's binaries, print the detected set, and assert it functionally
#      equals the baseline for this distro (24.04 or 26.04). An undocumented
#      delta is a FAIL. CI runs this in every build cell after packaging.
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
echo ">>> verify_depends.sh — detector baseline + render/parse"
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
for tool in dpkg-query ldd objdump realpath envsubst nfpm; do
    if ! command -v "${tool}" &>/dev/null; then
        echo "ERROR: required tool '${tool}' not found on PATH — verify_depends.sh must run on an Ubuntu build host." >&2
        exit 1
    fi
done

# Component maps (COMPONENT_BINARIES, INJECT_ONLY_DEPENDS) — shared with
# scripts/package_all.sh so the packaging and verification paths cannot drift.
source "${toolpath}/scripts/component_maps.sh"

# ---------------------------------------------------------------------------
# Expected system-library depends per distro and component.
#
# The detected set must equal the baseline (functional equivalence, not
# string order). A name detected that is not in the baseline (or the optional
# or alternative lists), or a baseline name that is not detected, is a FAIL,
# so a wrong detected set cannot pass. 24.04 carries the t64 names
# (libgpgme11t64, libglib2.0-0t64); 26.04 moved gpgme and subid to new
# sonames (libgpgme45, libsubid5).
#
# BASELINE_ALT: crun links exactly one JSON parser, chosen by the build host;
# either is accepted.
# BASELINE_OPTIONAL: accepted but not required, for links that depend on what
# the build host has installed. skopeo's Makefile adds the libsqlite3 build tag
# when pkg-config finds sqlite3: the 24.04 runner image ships libsqlite3-dev,
# a clean container does not.
#
# Components without an entry (netavark, aardvark-dns, pasta, fuse-overlayfs,
# catatonit) have their detected set printed for the record only.
# ---------------------------------------------------------------------------
declare -A BASELINE=(
    ["24.04:podman"]="libgpgme11t64 libseccomp2"
    ["24.04:buildah"]="libgpgme11t64 libseccomp2"
    ["24.04:skopeo"]="libgpgme11t64 libsubid4"
    ["24.04:crun"]="libseccomp2 libsystemd0 libcap2"
    ["24.04:conmon"]="libglib2.0-0t64 libsystemd0"
    ["26.04:podman"]="libgpgme45 libseccomp2"
    ["26.04:buildah"]="libgpgme45 libseccomp2"
    ["26.04:skopeo"]="libgpgme45 libsubid5"
    ["26.04:crun"]="libseccomp2 libsystemd0 libcap2"
    ["26.04:conmon"]="libglib2.0-0t64 libsystemd0"
)
declare -A BASELINE_ALT=(
    ["24.04:crun"]="libjson-c5 libyajl2"
    ["26.04:crun"]="libjson-c5 libyajl2"
)
declare -A BASELINE_OPTIONAL=(
    ["24.04:skopeo"]="libsqlite3-0"
    ["26.04:skopeo"]="libsqlite3-0"
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
# Part A — the detected set must equal the baseline for this distro.
# ---------------------------------------------------------------------------
echo ">>> Part A: detector baseline (${DISTRO_VERSION_ID})"
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

    key="${DISTRO_VERSION_ID}:${component}"
    if [[ ! -v "BASELINE[$key]" ]]; then
        echo "    (no baseline for ${component} on ${DISTRO_VERSION_ID}; detected set recorded only)"
        continue
    fi

    baseline="${BASELINE[$key]}"
    alt="${BASELINE_ALT[$key]:-}"
    optional="${BASELINE_OPTIONAL[$key]:-}"

    # Per-component failure flag (WR-03), so a later passing component still
    # prints its PASS line after an earlier one failed.
    comp_fail=0

    # Every detected name must be in the baseline, the accepted alternatives,
    # or the optional list.
    for name in ${detected}; do
        if in_list "${name}" "${baseline}"; then
            continue
        fi
        if [[ -n "${alt}" ]] && in_list "${name}" "${alt}"; then
            continue
        fi
        if [[ -n "${optional}" ]] && in_list "${name}" "${optional}"; then
            continue
        fi
        echo "    FAIL: ${component} detected unexpected dep '${name}' not in the ${DISTRO_VERSION_ID} baseline [${baseline}${alt:+ | alt: ${alt}}${optional:+ | optional: ${optional}}]" >&2
        comp_fail=1
    done

    # Every baseline name must be detected, else a dependency was silently
    # dropped.
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
            in_list "${name}" "${detected}" && found_alt=$((found_alt + 1))
        done
        if [[ "${found_alt}" -ne 1 ]]; then
            echo "    FAIL: ${component} must link exactly one JSON parser from [${alt}] (detected: [${detected}])" >&2
            comp_fail=1
        fi
    fi

    if [[ "${comp_fail}" -eq 0 ]]; then
        echo "    PASS: ${component} detected set equals the ${DISTRO_VERSION_ID} baseline"
    else
        partA_fail=1
    fi
done

if [[ "${partA_fail}" -ne 0 ]]; then
    echo "" >&2
    echo "FAIL: Part A — ${DISTRO_VERSION_ID} detected set diverged from its baseline (see above)." >&2
    exit 1
fi
# Part B reassigns DISTRO_VERSION_ID; keep the one Part A checked for the summary.
PARTA_DISTRO="${DISTRO_VERSION_ID}"
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
            detected_items="$(detect_runtime_depends "${cbins[@]}" | sed 's/^/  - /')"
            # WR-02: inject-only YAMLs get a self-contained depends: block
            # (header + items) only when non-empty; others get items only.
            if [[ -v "INJECT_ONLY_DEPENDS[$comp]" ]]; then
                if [[ -n "${detected_items}" ]]; then
                    fragment="depends:"$'\n'"${detected_items}"
                else
                    fragment=""
                fi
            else
                fragment="${detected_items}"
            fi
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
echo "  - Part A: ${PARTA_DISTRO} detected set functionally equals its baseline"
echo "  - Part B: every nFPM YAML renders + parses for DISTRO=24.04 and 26.04"
echo ""
exit 0
