#!/bin/bash

# Abort on Error
set -euo pipefail

# smoke_install_2604.sh - PKG-08 proof: apt-install a 26.04-built .deb inside a
# real ubuntu:26.04 (or resolute) userland to prove the renamed runtime deps
# (libgpgme45, libsubid5) resolve from the 26.04 archive automatically — i.e.
# the ldd->dpkg-query detection self-corrected the deps with NO nFPM YAML edit.
#
# Mechanism: `apt-get install` of a LOCAL .deb makes apt pull that .deb's
# declared Depends from the distro archive. If a dep name is wrong for 26.04
# (e.g. a stale libgpgme11 / libsubid4), apt cannot satisfy it and FAILS here —
# that failure is the test signal. A clean install + a working `skopeo --version`
# is the pass.
#
# Runner-OS-agnostic: it shells out to a container runtime (docker or podman),
# so it runs identically in CI (Phase 21 calls it) and on any dev box with a
# runtime. There is NO silent skip — if no runtime or no built .deb is present,
# the script hard-errors, because this is the PKG-08 gate (T-19-11).
#
# Overrides (project env-override idiom):
#   SMOKE_RUNTIME=docker|podman   force the container runtime (validated)
#   SMOKE_IMAGE=<image[:tag]>      force the base image (default ubuntu:26.04,
#                                  falling back to ubuntu:resolute if 26.04 is
#                                  not pullable — RESEARCH Open Question 3)

# ---------------------------------------------------------------------------
# Locate repo root + output dir holding the built .debs.
# ---------------------------------------------------------------------------
relativepath="../"
if [[ ! -v toolpath ]]; then
    scriptpath=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    toolpath=$(realpath --canonicalize-missing "${scriptpath}/${relativepath}" 2>/dev/null \
        || (cd "${scriptpath}/${relativepath}" && pwd))
fi
OUTPUT_DIR="${toolpath}/output"

echo ""
echo "========================================"
echo ">>> smoke_install_2604.sh — 26.04 apt-install proof (PKG-08)"
echo "========================================"

# ---------------------------------------------------------------------------
# 1. Select + validate the container runtime.
#    SMOKE_RUNTIME override must be EXACTLY docker or podman (T-19-09): the
#    value is interpolated into a command invocation, so we reject anything else
#    before use. Without an override, prefer docker, else podman.
# ---------------------------------------------------------------------------
RUNTIME=""
if [[ -n "${SMOKE_RUNTIME:-}" ]]; then
    case "${SMOKE_RUNTIME}" in
        docker|podman)
            if ! command -v "${SMOKE_RUNTIME}" &>/dev/null; then
                echo "ERROR: SMOKE_RUNTIME='${SMOKE_RUNTIME}' requested but '${SMOKE_RUNTIME}' is not on PATH." >&2
                exit 1
            fi
            RUNTIME="${SMOKE_RUNTIME}"
            ;;
        *)
            echo "ERROR: SMOKE_RUNTIME must be exactly 'docker' or 'podman' (got '${SMOKE_RUNTIME}')." >&2
            exit 1
            ;;
    esac
elif command -v docker &>/dev/null; then
    RUNTIME="docker"
elif command -v podman &>/dev/null; then
    RUNTIME="podman"
else
    echo "ERROR: no container runtime found — install docker or podman." >&2
    echo "  This is the PKG-08 install proof gate; it cannot be silently skipped." >&2
    exit 1
fi
echo "Container runtime: ${RUNTIME}"

# ---------------------------------------------------------------------------
# 2. Select the base image. Default ubuntu:26.04; fall back to ubuntu:resolute
#    (the 26.04 codename) if 26.04 cannot be pulled (not GA-tagged yet). An
#    explicit SMOKE_IMAGE override wins and is validated against a conservative
#    image-name pattern (T-19-09 — it feeds the run invocation).
# ---------------------------------------------------------------------------
IMAGE_CANDIDATES=()
if [[ -n "${SMOKE_IMAGE:-}" ]]; then
    if [[ ! "${SMOKE_IMAGE}" =~ ^[A-Za-z0-9][A-Za-z0-9._/:-]*$ ]]; then
        echo "ERROR: SMOKE_IMAGE '${SMOKE_IMAGE}' is not a valid image name." >&2
        exit 1
    fi
    IMAGE_CANDIDATES=( "${SMOKE_IMAGE}" )
else
    IMAGE_CANDIDATES=( "ubuntu:26.04" "ubuntu:resolute" )
fi

IMAGE=""
for candidate in "${IMAGE_CANDIDATES[@]}"; do
    echo ">>> Trying to pull image: ${candidate}"
    if "${RUNTIME}" pull "${candidate}"; then
        IMAGE="${candidate}"
        break
    fi
    echo "    (pull failed for ${candidate}, trying next candidate if any)" >&2
done

if [[ -z "${IMAGE}" ]]; then
    echo "ERROR: could not pull any 26.04 image from: ${IMAGE_CANDIDATES[*]}" >&2
    echo "  Set SMOKE_IMAGE to a reachable 26.04 (resolute) image tag." >&2
    exit 1
fi
echo "Base image: ${IMAGE}"

# ---------------------------------------------------------------------------
# 3. Confirm the built .deb(s) exist. We glob the real filename (the version is
#    baked in) rather than hardcoding a version. skopeo is the primary proof
#    (carries libgpgme/libsubid renames); podman is an optional second proof.
# ---------------------------------------------------------------------------
if [[ ! -d "${OUTPUT_DIR}" ]]; then
    echo "ERROR: output directory not found: ${OUTPUT_DIR}" >&2
    echo "  Build the 26.04 packages first (DISTRO=26.04 ./scripts/package_all.sh)." >&2
    exit 1
fi

shopt -s nullglob
skopeo_debs=( "${OUTPUT_DIR}"/podman-skopeo_*_*.deb )
podman_debs=( "${OUTPUT_DIR}"/podman-podman_*_*.deb )
shopt -u nullglob

if [[ "${#skopeo_debs[@]}" -eq 0 ]]; then
    echo "ERROR: no podman-skopeo_*.deb found in ${OUTPUT_DIR}." >&2
    echo "  Build the 26.04 packages first (DISTRO=26.04 ./scripts/package_all.sh)." >&2
    exit 1
fi
echo "skopeo .deb: $(basename "${skopeo_debs[0]}")"
if [[ "${#podman_debs[@]}" -gt 0 ]]; then
    echo "podman .deb: $(basename "${podman_debs[0]}")"
fi

# ---------------------------------------------------------------------------
# 4. Run the install inside a throwaway (--rm) container. Mount output/ at /out.
#    apt-get install of the local .deb resolves its declared deps from the 26.04
#    archive; a wrong dep name fails the install (the test signal). After
#    install, a sanity `skopeo --version` confirms the binary is usable.
# ---------------------------------------------------------------------------
echo ""
echo ">>> Installing skopeo (and podman if present) inside ${IMAGE} via ${RUNTIME}"
echo "----------------------------------------"

"${RUNTIME}" run --rm \
    -v "${OUTPUT_DIR}:/out:ro" \
    -e DEBIAN_FRONTEND=noninteractive \
    "${IMAGE}" \
    bash -c '
        set -euo pipefail
        apt-get update

        # Primary proof: skopeo carries the renamed libgpgme/libsubid deps.
        # Glob inside the container so the exact built filename is used.
        shopt -s nullglob
        skopeo_deb=( /out/podman-skopeo_*_*.deb )
        configs_deb=( /out/podman-container-configs_*.deb )
        podman_deb=( /out/podman-podman_*_*.deb )
        shopt -u nullglob

        if [ "${#skopeo_deb[@]}" -eq 0 ]; then
            echo "ERROR: no skopeo .deb visible at /out inside the container" >&2
            exit 1
        fi
        # skopeo.yaml declares the static internal sibling dep
        # podman-container-configs, an internal-only suite package that is NOT
        # published in the Ubuntu/resolute archive — it exists only as a .deb in
        # /out. apt has [no choices] for it unless we hand it the local .deb, so
        # its absence is a real failure of the primary proof, not a soft skip.
        if [ "${#configs_deb[@]}" -eq 0 ]; then
            echo "ERROR: no /out/podman-container-configs_*.deb visible inside the container" >&2
            echo "  skopeo declares it as an internal sibling dep; it must be present for the PKG-08 proof." >&2
            exit 1
        fi

        # Install the sibling configs .deb AND the skopeo .deb in ONE apt-get
        # invocation so apt co-resolves the local .debs and needs the archive
        # only for the renamed SYSTEM deps (libgpgme45/libsubid5/libassuan9) —
        # the true PKG-08 signal. This install stays HARD (no || true): a wrong
        # renamed system-dep name must still fail the gate.
        echo ">>> apt-get install (local sibling + skopeo): ${configs_deb[0]} ${skopeo_deb[0]}"
        apt-get install -y "${configs_deb[0]}" "${skopeo_deb[0]}"

        # Optional second proof: podman, if it was built.
        if [ "${#podman_deb[@]}" -gt 0 ]; then
            echo ">>> apt-get install podman: ${podman_deb[0]}"
            # podman declares internal podman-* deps that are not in the archive;
            # install best-effort so the run still proves skopeo. A hard failure
            # purely from a sibling podman-* dep is not the PKG-08 signal.
            apt-get install -y "${podman_deb[0]}" || \
                echo "NOTE: podman install did not complete (likely sibling podman-* deps not in archive); skopeo proof stands." >&2
        fi

        # Sanity: the renamed system deps (libgpgme45, libsubid5) resolved and
        # skopeo is runnable.
        command -v skopeo
        skopeo --version
        echo ">>> SMOKE PASS: skopeo installed and runs on the 26.04 userland"
    '

echo ""
echo "========================================"
echo ">>> smoke_install_2604.sh: PASS"
echo "========================================"
echo "  A 26.04-built .deb apt-installed cleanly on ${IMAGE} —"
echo "  the renamed deps (libgpgme45, libsubid5) resolved with no nFPM YAML edit."
echo ""
exit 0
