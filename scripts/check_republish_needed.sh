#!/bin/bash
set -euo pipefail

# ============================================================================
# check_republish_needed.sh
# ============================================================================
# Decides whether a manually-dispatched `stable` or `edge` build would produce
# anything new, by comparing the versions that WOULD be built against what is
# already published in the live APT repository.
#
# Emits `skip=true`  -> every tagged component is already published at the
#                       target version (across both distros and both arches);
#                       the build+publish is a no-op and can be skipped.
# Emits `skip=false` -> at least one component differs, OR resolution/fetch was
#                       uncertain. ALWAYS the safe default: this guard can only
#                       ever prevent a redundant rebuild, never skip a needed
#                       one. Any error path falls through to skip=false.
#
# Usage:  check_republish_needed.sh <stable|edge> [repo-url]
# Output: writes `skip=<bool>` to stdout and to $GITHUB_OUTPUT when set.
#
# Scope / deliberate exclusions:
#   * `pasta` is NOT compared. build_pasta.sh versions it by `date +%Y%m%d`
#     (it has no upstream tag pin on any track), so it changes every day. A
#     stable/edge rebuild therefore always yields a fresh pasta even when every
#     pinned component is unchanged. Comparing it would make this guard never
#     fire. pasta still rides along on whatever build a real component change
#     triggers, and the nightly track refreshes it daily.
#   * `nightly` is out of scope — the workflow's `check-changes` job already
#     guards the scheduled nightly run via upstream HEAD SHAs.
#
# Canonical version-string logic lives in scripts/package_all.sh
# (extract_version, VERSION_SUFFIX). The minimal subset needed here is
# reproduced below and pinned by tests/test_check_republish.sh — keep the two
# in sync if package_all.sh's transformation changes.
# ============================================================================

REPO_URL_DEFAULT="https://slazarov.github.io/podman-ubuntu"

# component | deb package name | stable *_TAG var | upstream repo (edge resolve)
# pasta is intentionally absent (see header). container-configs uses the
# namespaced container-libs repo whose tags look like `common/vX.Y.Z`.
COMPONENT_ROWS=(
    "podman|podman-podman|PODMAN_TAG|https://github.com/containers/podman.git"
    "crun|podman-crun|CRUN_TAG|https://github.com/containers/crun.git"
    "conmon|podman-conmon|CONMON_TAG|https://github.com/containers/conmon.git"
    "netavark|podman-netavark|NETAVARK_TAG|https://github.com/containers/netavark.git"
    "aardvark-dns|podman-aardvark-dns|AARDVARK_DNS_TAG|https://github.com/containers/aardvark-dns.git"
    "fuse-overlayfs|podman-fuse-overlayfs|FUSE_OVERLAYFS_TAG|https://github.com/containers/fuse-overlayfs.git"
    "catatonit|podman-catatonit|CATATONIT_TAG|https://github.com/openSUSE/catatonit.git"
    "buildah|podman-buildah|BUILDAH_TAG|https://github.com/containers/buildah.git"
    "skopeo|podman-skopeo|SKOPEO_TAG|https://github.com/containers/skopeo.git"
    "toolbox|podman-toolbox|TOOLBOX_TAG|https://github.com/containers/toolbox.git"
    "container-configs|podman-container-configs|CONTAINER_LIBS_TAG|https://github.com/containers/container-libs.git"
)

# distro label -> dotted VERSION_ID used in the ~ubuntuXX.XX.podman1 suffix
DISTROS=("2404:24.04" "2604:26.04")
ARCHES=("amd64" "arm64")

# ----------------------------------------------------------------------------
# Helpers (pure — unit-tested via tests/test_check_republish.sh)
# ----------------------------------------------------------------------------

# extract_base <tag> <component> -> upstream base version with no distro suffix.
# Mirrors scripts/package_all.sh:extract_version for the stable/edge cases.
extract_base() {
    local ltag="$1"
    local lcomponent="$2"
    case "${lcomponent}" in
        container-configs)
            # namespaced tag: common/v0.67.1 -> 0.67.1
            echo "${ltag}" | sed 's|^.*/v||'
            ;;
        *)
            # standard: strip a leading v (v5.8.2 -> 5.8.2; 1.28 -> 1.28)
            echo "${ltag#v}"
            ;;
    esac
}

# get_pkg_version <packages-file> <package-name> -> Version field of the first
# matching stanza, or empty. reprepro keeps one version per package per suite.
get_pkg_version() {
    local lfile="$1"
    local lpkg="$2"
    awk -v p="${lpkg}" '
        /^Package:/ { cur = $2 }
        /^Version:/ { if (cur == p) { print $2; exit } }
    ' "${lfile}"
}

# resolve_edge_tag <repo-url> <component> -> highest stable upstream tag.
# Mirrors functions.sh:get_latest_tag selection (exclude rc, version-sort,
# pick highest) but over `git ls-remote` so no clone is required.
resolve_edge_tag() {
    local lurl="$1"
    local lcomponent="$2"
    local lrefs
    lrefs=$(git ls-remote --tags --refs "${lurl}" 2>/dev/null | awk '{print $2}' | sed 's|refs/tags/||') || return 1
    [[ -z "${lrefs}" ]] && return 1

    if [[ "${lcomponent}" == "container-configs" ]]; then
        # namespaced common/vX.Y.Z tags; rank by the numeric part
        echo "${lrefs}" \
            | grep -E '^common/v[0-9]' \
            | grep -v 'rc' \
            | while read -r t; do echo "${t#common/v} ${t}"; done \
            | sort --reverse --version-sort -k1 \
            | head -n1 | cut -d' ' -f2
    else
        echo "${lrefs}" \
            | grep -v 'rc' \
            | grep -E '^v?[0-9]' \
            | while read -r t; do echo "${t#v} ${t}"; done \
            | sort --reverse --version-sort -k1 \
            | head -n1 | cut -d' ' -f2
    fi
}

# emit_skip <true|false> [reason] — write the decision and exit 0. The guard
# itself never fails the workflow; an indecisive guard must default to building.
emit_skip() {
    local lvalue="$1"
    local lreason="${2:-}"
    [[ -n "${lreason}" ]] && echo ">>> ${lreason}" >&2
    echo ">>> Decision: skip=${lvalue}" >&2
    echo "skip=${lvalue}"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "skip=${lvalue}" >> "${GITHUB_OUTPUT}"
    fi
    exit 0
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

main() {
    local track="${1:-}"
    local repo_url="${2:-${REPO_URL_DEFAULT}}"

    case "${track}" in
        stable|edge) ;;
        *) emit_skip false "Track '${track}' is not stable/edge — not guarded; build proceeds." ;;
    esac

    echo ">>> Republish guard: track=${track} repo=${repo_url}" >&2

    # Resolve target tags per component.
    if [[ "${track}" == "stable" ]]; then
        if [[ ! -f versions-stable.env ]]; then
            emit_skip false "versions-stable.env not found — cannot resolve stable pins."
        fi
        # shellcheck disable=SC1091
        source versions-stable.env
    fi

    # Download the four published Packages indices once (2 distros x 2 arches).
    local tmpdir
    tmpdir=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '${tmpdir}'" EXIT

    local distro_entry distro dotted arch suite base_url pkgfile
    for distro_entry in "${DISTROS[@]}"; do
        distro="${distro_entry%%:*}"
        suite="${track}-${distro}"
        for arch in "${ARCHES[@]}"; do
            base_url="${repo_url}/dists/${suite}/main/binary-${arch}/Packages"
            pkgfile="${tmpdir}/${distro}_${arch}.Packages"
            # Prefer the gzipped index; fall back to the uncompressed Packages.
            if ! curl -sfL "${base_url}.gz" 2>/dev/null | gunzip -c > "${pkgfile}" 2>/dev/null \
                || [[ ! -s "${pkgfile}" ]]; then
                if ! curl -sfL "${base_url}" -o "${pkgfile}" 2>/dev/null || [[ ! -s "${pkgfile}" ]]; then
                    emit_skip false "Could not fetch ${base_url}{.gz,} (suite not published yet?) — build to populate it."
                fi
            fi
        done
    done

    # Compare every tagged component (pasta excluded) across all four indices.
    local row comp pkg tagvar repo tag base target published
    for row in "${COMPONENT_ROWS[@]}"; do
        IFS='|' read -r comp pkg tagvar repo <<< "${row}"

        if [[ "${track}" == "stable" ]]; then
            tag="${!tagvar:-}"
            [[ -z "${tag}" ]] && emit_skip false "Stable pin ${tagvar} is empty — build."
        else
            tag=$(resolve_edge_tag "${repo}" "${comp}") || tag=""
            [[ -z "${tag}" ]] && emit_skip false "Could not resolve latest edge tag for ${comp} — build."
        fi

        base=$(extract_base "${tag}" "${comp}")
        [[ -z "${base}" ]] && emit_skip false "Empty base version for ${comp} (tag '${tag}') — build."

        for distro_entry in "${DISTROS[@]}"; do
            distro="${distro_entry%%:*}"
            dotted="${distro_entry##*:}"
            target="${base}~ubuntu${dotted}.podman1"
            for arch in "${ARCHES[@]}"; do
                pkgfile="${tmpdir}/${distro}_${arch}.Packages"
                published=$(get_pkg_version "${pkgfile}" "${pkg}")
                if [[ "${published}" != "${target}" ]]; then
                    emit_skip false \
                        "${pkg} differs on ${track}-${distro}/${arch}: published='${published:-<absent>}' target='${target}' — build."
                fi
            done
        done
        echo ">>> ${pkg}: ${base} already published on both distros/arches." >&2
    done

    emit_skip true "All ${#COMPONENT_ROWS[@]} tagged components already published at target versions (pasta excluded)."
}

# Only run when executed directly, so tests can source the helpers.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
