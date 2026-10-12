#!/bin/bash

# Abort on Error
set -euo pipefail

# smoke_repo_install.sh - MIGR-04 proof: apt-install the `podman-suite`
# meta-package BY NAME from the assembled on-disk APT repo (a file:// source)
# inside a real ubuntu:<distro> userland and exercise it the way users do —
# fresh install + rootless bridge networking, migration from Ubuntu's own
# podman, and upgrade from the live repo (see section 6) — before the GitHub
# Pages publish.
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
#   LIVE_REPO_URL=https://...     published repo to upgrade FROM; unset skips
#                                 the upgrade scenario
#
# SECURITY (T-22-SMOKE-01): the distro label, TRACK, and SMOKE_RUNTIME are
# interpolated into a container-run command / suite name. All three are
# exact-match-validated against closed whitelists ({2404,2604}, {stable,v5,nightly},
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
    stable|v5|nightly) ;;
    *)
        echo "ERROR: TRACK must be exactly 'stable', 'v5', or 'nightly' (got '${TRACK:-}')." >&2
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
# 5. Validate the optional live-repo URL (T-22-SMOKE-01). It is interpolated into
#    an apt source inside the container, so only a plain https URL is accepted.
#    Unset = the upgrade scenario is skipped.
# ---------------------------------------------------------------------------
LIVE_REPO_URL="${LIVE_REPO_URL:-}"
if [[ -n "${LIVE_REPO_URL}" && ! "${LIVE_REPO_URL}" =~ ^https://[A-Za-z0-9.-]+(/[A-Za-z0-9._-]+)*/?$ ]]; then
    echo "ERROR: LIVE_REPO_URL must be a plain https:// URL (got '${LIVE_REPO_URL}')." >&2
    exit 1
fi
LIVE_REPO_URL="${LIVE_REPO_URL%/}"

# ---------------------------------------------------------------------------
# 6. Scenario scripts. Each runs in its own throwaway ubuntu container and covers
#    a path a real user takes (each one caught a shipped bug when added):
#      fresh    install podman-suite, podman info, then a ROOTLESS user with their
#               own ~/.config/containers/containers.conf runs a container on a
#               bridge network and resolves its own name via aardvark-dns
#               (missing uidmap; helpers outside helper_binaries_dir).
#      migrate  install Ubuntu's own podman first, then podman-suite over it
#               (dpkg "trying to overwrite" from an incomplete Conflicts list).
#      upgrade  install from the LIVE published repo, then full-upgrade to the
#               assembled one (package renames, new Depends). Skipped when
#               LIVE_REPO_URL is unset or the suite is not published there yet.
#    Scripts are written to a temp dir and bind-mounted, avoiding nested-quoting
#    hazards. Trusted: yes is confined to the CI-internal file:// source (D-14).
# ---------------------------------------------------------------------------
SCENARIO_DIR=$(mktemp -d)
trap 'rm -rf "${SCENARIO_DIR}"' EXIT

cat > "${SCENARIO_DIR}/lib.sh" << 'EOF'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

add_local_repo() {
    cat > /etc/apt/sources.list.d/podman-smoke.sources << APTEOF
Types: deb
URIs: file:///opt/podman-repo
Suites: ${SUITE}
Components: main
Trusted: yes
APTEOF
}

# dpkg --audit prints any half-installed/unconfigured package; must be empty.
assert_dpkg_clean() {
    local laudit
    laudit=$(dpkg --audit)
    if [[ -n "${laudit}" ]]; then
        echo "${laudit}" >&2
        echo "FAIL: dpkg reports broken packages" >&2
        return 1
    fi
}

rootless_network_check() {
    useradd -m smoke
    grep -q '^smoke:' /etc/subuid || usermod --add-subuids 100000-165535 --add-subgids 100000-165535 smoke
    su - smoke -s /bin/bash << 'USEREOF'
set -euo pipefail
export XDG_RUNTIME_DIR="/tmp/xdg-$(id -u)"
mkdir -p -m 0700 "${XDG_RUNTIME_DIR}"
# A user containers.conf replaces /etc/containers/containers.conf entirely;
# nothing podman needs may depend on settings in the system file.
mkdir -p ~/.config/containers
printf '[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' > ~/.config/containers/containers.conf
podman network create smokenet > /dev/null
podman run --rm --name smokectr --network smokenet quay.io/libpod/alpine:latest \
    nslookup smokectr
echo ">>> rootless bridge network + aardvark-dns OK"
USEREOF
}
EOF

cat > "${SCENARIO_DIR}/fresh.sh" << 'EOF'
source /smoke/lib.sh
add_local_repo
apt-get update -qq
apt-get install -y -q podman-suite
assert_dpkg_clean
podman info --log-level=error > /dev/null
echo ">>> rootful podman info OK"
rootless_network_check
EOF

cat > "${SCENARIO_DIR}/migrate.sh" << 'EOF'
source /smoke/lib.sh
apt-get update -qq
apt-get install -y -q podman
echo ">>> distro podman installed: $(dpkg-query -W -f='${Version}' podman)"
add_local_repo
apt-get update -qq
apt-get install -y -q podman-suite
assert_dpkg_clean
podman info --log-level=error > /dev/null
echo ">>> migrated from distro podman OK"
EOF

cat > "${SCENARIO_DIR}/upgrade.sh" << 'EOF'
source /smoke/lib.sh
apt-get update -qq
apt-get install -y -q curl ca-certificates
mkdir -p /etc/apt/keyrings
curl -fsSL "${LIVE_REPO_URL}/podman-ubuntu.gpg" -o /etc/apt/keyrings/podman-ubuntu.gpg
if ! curl -fsSI "${LIVE_REPO_URL}/dists/${SUITE}/InRelease" > /dev/null; then
    echo ">>> SKIP upgrade: ${SUITE} is not published at ${LIVE_REPO_URL} yet"
    exit 0
fi
cat > /etc/apt/sources.list.d/podman-live.sources << APTEOF
Types: deb
URIs: ${LIVE_REPO_URL}
Suites: ${SUITE}
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
APTEOF
apt-get update -qq
apt-get install -y -q podman-suite
echo ">>> live podman-suite installed: $(dpkg-query -W -f='${Version}' podman-suite)"
add_local_repo
apt-get update -qq
apt-get full-upgrade -y -q
assert_dpkg_clean
echo ">>> upgraded podman-suite: $(dpkg-query -W -f='${Version}' podman-suite)"
podman info --log-level=error > /dev/null
echo ">>> upgrade from live repo OK"
EOF

# ---------------------------------------------------------------------------
# 7. Run each scenario. --privileged + --device /dev/fuse let podman initialize
#    storage and user namespaces (RESEARCH Pitfall 1). -v /home puts the rootless
#    user's storage on a real volume: overlay-on-overlay is refused, and the
#    container root is itself an overlay.
# ---------------------------------------------------------------------------
FAILED=()
for scenario in fresh migrate upgrade; do
    if [[ "${scenario}" == "upgrade" && -z "${LIVE_REPO_URL}" ]]; then
        echo ">>> SKIP scenario upgrade: LIVE_REPO_URL not set"
        continue
    fi
    echo ""
    echo ">>> Scenario ${scenario}: ${IMAGE} suite=${SUITE} via ${RUNTIME}"
    echo "----------------------------------------"
    if ! "${RUNTIME}" run --rm \
            --privileged \
            --device /dev/fuse \
            -v /home \
            -v "${REPO_DIR}:/opt/podman-repo:ro" \
            -v "${SCENARIO_DIR}:/smoke:ro" \
            -e SUITE="${SUITE}" \
            -e LIVE_REPO_URL="${LIVE_REPO_URL}" \
            "${IMAGE}" \
            bash "/smoke/${scenario}.sh"; then
        echo "SMOKE FAIL: scenario ${scenario} (${IMAGE}, suite ${SUITE})" >&2
        FAILED+=("${scenario}")
    fi
done

echo ""
echo "========================================"
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ">>> SMOKE FAIL: ${IMAGE} suite=${SUITE} — failed: ${FAILED[*]}"
    echo "========================================"
    exit 1
fi
echo ">>> SMOKE PASS: ${IMAGE} suite=${SUITE}"
echo "========================================"
exit 0
