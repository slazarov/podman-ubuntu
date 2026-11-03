#!/bin/bash
set -euo pipefail

# ============================================================================
# check_republish_needed.sh
# ============================================================================
# Decides whether a `stable` or `v5` build (manual dispatch or daily cron) would
# produce anything new, by comparing the versions that WOULD be built — resolved by
# scripts/resolve_versions.sh from versions-${track}.env — against what is already
# published in the live APT repository.
#
# Emits `skip=true`  -> every tagged component is already published at the
#                       target version (across both distros and both arches);
#                       the build+publish is a no-op and can be skipped.
# Emits `skip=false` -> at least one component differs, OR resolution/fetch was
#                       uncertain. ALWAYS the safe default: this guard can only
#                       ever prevent a redundant rebuild, never skip a needed
#                       one. Any error path falls through to skip=false.
#
# Usage:  check_republish_needed.sh <stable|v5> [repo-url] [resolved-env-file]
# Output: writes `skip=<bool>` to stdout and to $GITHUB_OUTPUT when set.
#
# [resolved-env-file] is the output of resolve_versions.sh, captured once by
# the workflow's resolve-track job. When given, it is validated
# (validate_resolved_env in scripts/ci_helpers.sh) and used as is; the
# resolver does not run again, so the guard and the build cells compare and
# build exactly the same tags. An invalid file is an error (exit 1), not a
# skip decision. Without it, the guard runs the resolver itself.
#
# Scope / deliberate exclusions:
#   * `nightly` is out of scope — the workflow's `check-changes` job already
#     guards the scheduled nightly run via upstream HEAD SHAs.
#
# Canonical version-string logic lives in scripts/package_all.sh
# (extract_version, VERSION_SUFFIX). The minimal subset needed here is
# reproduced below and pinned by tests/test_check_republish.sh — keep the two
# in sync if package_all.sh's transformation changes. pasta's version is not
# reproduced: both call the shared functions.sh:pasta_version.
# ============================================================================

REPO_URL_DEFAULT="https://slazarov.github.io/podman-ubuntu"

# PACKAGE_REVISION (the N in ~ubuntuXX.XX.podmanN) — shared with config.sh.
# shellcheck source=scripts/package_revision.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/package_revision.sh"

# fetch_url and validate_resolved_env.
# shellcheck source=scripts/ci_helpers.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ci_helpers.sh"

# Shared tag helpers (pasta_version). Only the pure helpers are needed, so skip
# config.sh (Ubuntu-only detection + network toolchain lookups), like the resolver.
if [[ ! -v toolpath ]]; then
    toolpath="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
SKIP_CONFIG_SOURCE=1
# shellcheck source=functions.sh
source "${toolpath}/functions.sh"

# component | deb package name | resolved *_TAG var | upstream repo (provenance;
# pasta also reads it to order same-day passt releases)
# container-configs uses the namespaced container-libs repo whose tags look like
# `common/vX.Y.Z`; pasta uses passt release tags `YYYY_MM_DD.<sha>`.
#
# podman-suite is the meta-package; package_all.sh versions it as podman's
# base version plus the distro suffix, so it follows PODMAN_TAG.
COMPONENT_ROWS=(
    "podman|podman-podman|PODMAN_TAG|https://github.com/containers/podman.git"
    "podman-suite|podman-suite|PODMAN_TAG|https://github.com/containers/podman.git"
    "crun|podman-crun|CRUN_TAG|https://github.com/containers/crun.git"
    "conmon|podman-conmon|CONMON_TAG|https://github.com/containers/conmon.git"
    "netavark|podman-netavark|NETAVARK_TAG|https://github.com/containers/netavark.git"
    "aardvark-dns|podman-aardvark-dns|AARDVARK_DNS_TAG|https://github.com/containers/aardvark-dns.git"
    "fuse-overlayfs|podman-fuse-overlayfs|FUSE_OVERLAYFS_TAG|https://github.com/containers/fuse-overlayfs.git"
    "catatonit|podman-catatonit|CATATONIT_TAG|https://github.com/openSUSE/catatonit.git"
    "pasta|podman-pasta|PASTA_TAG|https://passt.top/passt"
    "buildah|podman-buildah|BUILDAH_TAG|https://github.com/containers/buildah.git"
    "skopeo|podman-skopeo|SKOPEO_TAG|https://github.com/containers/skopeo.git"
    "toolbox|podman-toolbx|TOOLBOX_TAG|https://github.com/containers/toolbox.git"
    "container-configs|podman-container-configs|CONTAINER_LIBS_TAG|https://github.com/containers/container-libs.git"
)

# distro label -> dotted VERSION_ID used in the ~ubuntuXX.XX.podmanN suffix
DISTROS=("2404:24.04" "2604:26.04")
ARCHES=("amd64" "arm64")

# ----------------------------------------------------------------------------
# Helpers (unit-tested via tests/test_check_republish.sh). Pure except
# extract_base for pasta, which queries the passt remote (pasta_version).
# ----------------------------------------------------------------------------

# extract_base <tag> <component> [repo-url] -> upstream base version with no
# distro suffix. Mirrors scripts/package_all.sh:extract_version for the
# resolved-tag cases. [repo-url] is only used by pasta (same-day release order);
# on failure pasta prints nothing and returns non-zero (caller -> skip=false).
extract_base() {
    local ltag="$1"
    local lcomponent="$2"
    local lurl="${3:-}"
    case "${lcomponent}" in
        container-configs)
            # namespaced tag: common/v0.67.1 -> 0.67.1
            echo "${ltag}" | sed 's|^.*/v||'
            ;;
        pasta)
            # passt release tag: 2026_10_02.cba3570 -> 1:2026.10.02 (or
            # 1:2026.10.02.N for a later same-day release) -- shared with
            # package_all.sh. The epoch is kept: nFPM writes it into the
            # published Version: field (1:2026.10.02~ubuntu...), so the target
            # must carry it to compare equal.
            pasta_version "${lurl}" "${ltag}"
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

# emit_skip <true|false> [reason] — write the decision and exit 0. An
# indecisive guard defaults to building. The only failure exit is an invalid
# resolved-env file, which is a pipeline bug rather than a decision.
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
    local resolved_env="${3:-}"

    case "${track}" in
        stable|v5) ;;
        *) emit_skip false "Track '${track}' is not stable/v5 — not guarded; build proceeds." ;;
    esac

    echo ">>> Republish guard: track=${track} repo=${repo_url}" >&2

    # A resolved environment from the workflow: validate it and use it as is.
    if [[ -n "${resolved_env}" ]]; then
        if ! validate_resolved_env "${resolved_env}"; then
            echo "ERROR: resolved environment '${resolved_env}' is invalid; refusing to guess." >&2
            exit 1
        fi
        # shellcheck disable=SC1090
        source "${resolved_env}"
    else
        resolve_targets "${track}"
    fi

    compare_with_live "${track}" "${repo_url}"
}

# resolve_targets <track> -> runs the resolver and evals its exports, or emits
# a decision and exits when it holds.
resolve_targets() {
    local track="$1"
    # Resolve target tags with the SAME resolver the build uses, so the guard's
    # targets are exactly what a build would produce (versions-${track}.env policy).
    # The resolver distinguishes its two HOLD causes by exit code:
    #   3 = deterministic (upstream reachable, nothing soaked yet) -> genuinely
    #       nothing to build -> skip=true (quiet).
    #   other non-zero = uncertain (upstream unreachable) -> we do NOT know, so honor
    #       this guard's "never skip a needed build" contract and build (skip=false).
    local script_dir repo_root policy resolver_out rrc
    script_dir="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)"
    repo_root="$(cd "${script_dir}/.." && pwd)"
    policy="${repo_root}/versions-${track}.env"
    if [[ ! -f "${policy}" ]]; then
        emit_skip false "Policy file ${policy} not found — cannot resolve ${track} targets."
    fi
    resolver_out="$( "${script_dir}/resolve_versions.sh" "${policy}" 2>/dev/null )" && rrc=0 || rrc=$?
    if [[ "${rrc}" -eq 3 ]]; then
        emit_skip true "Resolver: no soaked target yet for ${track} (upstream reachable) — nothing to build."
    elif [[ "${rrc}" -ne 0 ]]; then
        emit_skip false "Resolver uncertain for ${track} (upstream unreachable) — build to be safe."
    fi
    # shellcheck disable=SC1090
    eval "${resolver_out}"
}

# compare_with_live <track> <repo-url> -> emits the decision and exits.
compare_with_live() {
    local track="$1"
    local repo_url="$2"

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
            # Absent (404) means the suite is not published yet; any other
            # failure means we cannot tell. Both build.
            local rc=0
            fetch_url "${base_url}.gz" "${pkgfile}.gz" || rc=$?
            if [[ "${rc}" -eq 0 ]] && gunzip -c "${pkgfile}.gz" > "${pkgfile}" 2>/dev/null \
                && [[ -s "${pkgfile}" ]]; then
                continue
            fi
            [[ "${rc}" -eq 1 ]] && emit_skip false "Could not download ${base_url}.gz (network or server error) — build to be safe."
            rc=0
            fetch_url "${base_url}" "${pkgfile}" || rc=$?
            if [[ "${rc}" -eq 4 ]]; then
                emit_skip false "${suite}/${arch} is not published yet (${base_url} absent) — build to populate it."
            elif [[ "${rc}" -ne 0 || ! -s "${pkgfile}" ]]; then
                emit_skip false "Could not download ${base_url} (network or server error) — build to be safe."
            fi
        done
    done

    # Compare every tagged component across all four indices.
    local row comp pkg tagvar url tag base target published
    for row in "${COMPONENT_ROWS[@]}"; do
        # The 4th column (upstream repo URL) documents provenance; the resolver owns
        # tag resolution, so only extract_base reads it (pasta's same-day order).
        IFS='|' read -r comp pkg tagvar url <<< "${row}"

        # Tag comes from the resolver's materialized environment (eval'd above),
        # the single source of truth shared with the build.
        tag="${!tagvar:-}"
        [[ -z "${tag}" ]] && emit_skip false "Resolved ${tagvar} is empty for ${comp} — build."

        base=$(extract_base "${tag}" "${comp}" "${url}") || base=""
        [[ -z "${base}" ]] && emit_skip false "Empty base version for ${comp} (tag '${tag}') — build."

        for distro_entry in "${DISTROS[@]}"; do
            distro="${distro_entry%%:*}"
            dotted="${distro_entry##*:}"
            target="${base}~ubuntu${dotted}.podman${PACKAGE_REVISION}"
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

    emit_skip true "All ${#COMPONENT_ROWS[@]} tagged components already published at target versions."
}

# Only run when executed directly, so tests can source the helpers.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
