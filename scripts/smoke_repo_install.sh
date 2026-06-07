#!/bin/bash

# Abort on Error
set -euo pipefail

# smoke_repo_install.sh - MIGR-04 proof: apt-install the `podman-suite`
# meta-package BY NAME from the assembled on-disk APT repo (a file:// source)
# inside a real ubuntu:<distro> userland, then run `podman info` to prove the
# package is both installable AND runnable before the GitHub Pages publish.
#
# Mechanism: the assembled repo-output (the 9-suite signed tree produced by
# ci_publish.sh) is bind-mounted read-only into a throwaway container. A DEB822
# source pointing at file:///opt/podman-repo with `Trusted: yes` lets apt
# resolve and install `podman-suite` (the meta-package) by name. `podman info`
# exit 0 is the gate (D-15): a package that installs but whose runtime cannot
# introspect itself would still be a regression.
#
# Runner-OS-agnostic: it shells out to a container runtime (docker or podman),
# so it runs identically in CI (the publish job calls it twice) and on any dev
# box with a runtime. There is NO silent skip — if no runtime or no assembled
# repo is present, the script hard-errors, because this is the MIGR-04 gate.
#
# Usage: smoke_repo_install.sh <distro-label> [repo-dir]
#   distro-label   2404 or 2604 (required; exact-match validated, T-22-SMOKE-01)
#   repo-dir       path to the assembled repo (default: ${toolpath}/repo-output)
#
# Overrides (project env-override idiom):
#   SMOKE_RUNTIME=docker|podman   force the container runtime (validated)
#   TRACK=<track>                 suite track (default: nightly, mirrors the
#                                 workflow default); SUITE = "${TRACK}-<label>"
#
# SECURITY (T-22-SMOKE-01): the distro label, TRACK, and SMOKE_RUNTIME are
# interpolated into a container-run command / suite name. All three are
# exact-match-validated against closed whitelists ({2404,2604}, {stable,edge,nightly},
# and {docker,podman}) BEFORE any use.
# `Trusted: yes` is intentional here and CONFINED to this CI-internal file://
# smoke source — it does NOT exercise the GPG Signed-By path real users hit
# (accepted limitation, D-14) and MUST NEVER appear in user-facing docs or
# index.html.

# ---------------------------------------------------------------------------
# Locate repo root. Kept standalone (no config.sh/functions.sh source) so the
# helper runs in a minimal CI-runner env, matching smoke_install_2604.sh.
# ---------------------------------------------------------------------------
relativepath="../"
if [[ ! -v toolpath ]]; then
    scriptpath=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    toolpath=$(realpath --canonicalize-missing "${scriptpath}/${relativepath}" 2>/dev/null \
        || (cd "${scriptpath}/${relativepath}" && pwd))
fi

echo ""
echo "========================================"
echo ">>> smoke_repo_install.sh — file:// install + podman info proof (MIGR-04)"
echo "========================================"

# ---------------------------------------------------------------------------
# 1. Validate the distro-label arg (T-22-SMOKE-01). It is interpolated into the
#    suite name and the image tag, so it MUST be exactly 2404 or 2604 — anything
#    else is rejected before use.
# ---------------------------------------------------------------------------
LABEL="${1:-}"
case "${LABEL}" in
    2404|2604)
        ;;
    *)
        echo "ERROR: distro-label must be exactly '2404' or '2604' (got '${LABEL}')." >&2
        echo "  Usage: smoke_repo_install.sh <2404|2604> [repo-dir]" >&2
        exit 1
        ;;
esac

# Validate TRACK (T-22-SMOKE-01). TRACK is interpolated into the APT Suites:
# field; it MUST be exactly one of the three known tracks.
case "${TRACK:-nightly}" in
    stable|edge|nightly) ;;
    *)
        echo "ERROR: TRACK must be exactly 'stable', 'edge', or 'nightly' (got '${TRACK:-}')." >&2
        exit 1
        ;;
esac
SUITE="${TRACK:-nightly}-${LABEL}"
echo "Distro label: ${LABEL}"
echo "Suite:        ${SUITE}"

# ---------------------------------------------------------------------------
# 2. Select + validate the container runtime.
#    SMOKE_RUNTIME override must be EXACTLY docker or podman (T-22-SMOKE-01): the
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
    echo "  This is the MIGR-04 install proof gate; it cannot be silently skipped." >&2
    exit 1
fi
echo "Container runtime: ${RUNTIME}"

# ---------------------------------------------------------------------------
# 3. Select the base image (amd64-only, D-17 — no arch-specific image variants;
#    the runner is amd64 and that is sufficient for the installability proof).
#    2404 -> ubuntu:24.04. 2604 -> ubuntu:26.04, falling back to ubuntu:resolute
#    (the 26.04 codename) if 26.04 cannot be pulled (not GA-tagged yet). The
#    image strings are hardcoded literals — no user-controlled interpolation.
# ---------------------------------------------------------------------------
IMAGE=""
if [[ "${LABEL}" == "2404" ]]; then
    IMAGE="ubuntu:24.04"
    echo ">>> Trying to pull image: ${IMAGE}"
    if ! "${RUNTIME}" pull "${IMAGE}"; then
        echo "ERROR: could not pull ${IMAGE}." >&2
        exit 1
    fi
else
    # 2604: try ubuntu:26.04 first, fall back to its resolute codename.
    IMAGE_CANDIDATES=( "ubuntu:26.04" "ubuntu:resolute" )
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
        echo "  Neither ubuntu:26.04 nor ubuntu:resolute was pullable." >&2
        exit 1
    fi
fi
echo "Base image: ${IMAGE}"

# ---------------------------------------------------------------------------
# 4. Resolve + validate the assembled repo directory. Arg $2 if given, else
#    ${toolpath}/repo-output. It must exist and carry a dists/ tree (the signed
#    suite indexes) — an empty or wrong dir is a hard failure, not a soft skip.
# ---------------------------------------------------------------------------
REPO_DIR="${2:-${toolpath}/repo-output}"
if [[ ! -d "${REPO_DIR}" ]]; then
    echo "ERROR: assembled repo directory not found: ${REPO_DIR}" >&2
    echo "  Assemble the repo first (ci_publish.sh ... repo-output)." >&2
    exit 1
fi
if [[ ! -d "${REPO_DIR}/dists" ]]; then
    echo "ERROR: ${REPO_DIR} contains no dists/ tree — not an assembled APT repo." >&2
    exit 1
fi
# Canonicalize so the bind-mount source is absolute regardless of CWD.
REPO_DIR=$(realpath "${REPO_DIR}")
echo "Assembled repo: ${REPO_DIR}"

# ---------------------------------------------------------------------------
# 5. Run the install + `podman info` inside a throwaway (--rm) container.
#    --privileged + --device /dev/fuse give podman info enough to initialize its
#    storage graph driver (RESEARCH Pitfall 1). The container script is fed via
#    STDIN heredoc (`bash -s << INNEREOF`) to avoid the nested single-quote
#    hazard of `bash -c '...'`. The OUTER heredoc is UNQUOTED so the host shell
#    expands ${SUITE} into the body; container-side `$`-expansions are escaped
#    where needed. A DEB822 file:// source with `Trusted: yes` (CI-internal) is
#    written, then apt installs podman-suite BY NAME and podman info is the gate.
# ---------------------------------------------------------------------------
echo ""
echo ">>> Installing podman-suite from ${REPO_DIR} (suite ${SUITE}) inside ${IMAGE} via ${RUNTIME}"
echo "----------------------------------------"

if ! "${RUNTIME}" run --rm \
        --privileged \
        --device /dev/fuse \
        -v "${REPO_DIR}:/opt/podman-repo:ro" \
        -e DEBIAN_FRONTEND=noninteractive \
        "${IMAGE}" \
        bash -s << INNEREOF
set -e

# CI-internal file:// DEB822 source. Trusted: yes is the [trusted=yes]
# equivalent — confined to this smoke test (D-14); NOT a user-facing pattern.
cat > /etc/apt/sources.list.d/podman-smoke.sources << 'APTEOF'
Types: deb
URIs: file:///opt/podman-repo
Suites: ${SUITE}
Components: main
Trusted: yes
APTEOF

# VFS storage fallback (RESEARCH Pitfall 1): if 'podman info' below errors on
# the storage graph driver in real CI (stderr mentions overlay / fuse-overlayfs
# / "kernel does not support"), uncomment the two lines to force the VFS driver,
# which needs no special filesystem support. Do NOT enable pre-emptively — only
# if CI proves the storage probe fails.
# mkdir -p /etc/containers
# printf '[storage]\ndriver = "vfs"\n' > /etc/containers/storage.conf

apt-get update -qq
apt-get install -y -q podman-suite

# The real gate (D-15): podman must be runnable enough to introspect itself.
podman info --log-level=error

echo ">>> container: podman-suite installed and 'podman info' succeeded"
INNEREOF
then
    echo "SMOKE FAIL: ${IMAGE} — install or podman info failed for suite ${SUITE}" >&2
    exit 1
fi

echo ""
echo "========================================"
echo ">>> SMOKE PASS: ${IMAGE} suite=${SUITE}"
echo "========================================"
echo "  podman-suite installed from the assembled file:// repo and"
echo "  'podman info' exited 0 — installability + runnability proven (MIGR-04)."
echo ""
exit 0
