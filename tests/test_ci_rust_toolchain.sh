#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

export RUNNER_TEMP
RUNNER_TEMP="$(mktemp -d)"
trap 'rm -rf "${RUNNER_TEMP}"' EXIT
export GITHUB_OUTPUT="${RUNNER_TEMP}/outputs"
unset NIGHTLY_BUILD

# Simulate a manifest that still declares the minimum from the failed build.
curl() {
    printf '%s\n' "$*" >> "${RUNNER_TEMP}/manifest-requests"
    printf '%s\n' 'rust-version = "1.88"'
}
export -f curl

awk '
    /^        id: env$/ { found=1; next }
    found && /^      - / { exit }
    found && /^        run: \|/ { body=1; next }
    body && /^        [^ ]/ { exit }
    body { sub(/^          /, ""); print }
' .github/workflows/build-packages.yml > "${RUNNER_TEMP}/prepare.sh"

TRACK=nightly bash "${RUNNER_TEMP}/prepare.sh"
grep -qx 'NIGHTLY_BUILD=true' "${RUNNER_TEMP}/build-env"
grep -qx 'RUST_VERSION=stable' "${RUNNER_TEMP}/build-env"
grep -qx 'rust=stable' "${GITHUB_OUTPUT}"
[[ ! -e "${RUNNER_TEMP}/manifest-requests" ]]

source scripts/ci_helpers.sh
printf -v RESOLVED_ENV 'export %s="v2.0.0"\n' "${RESOLVED_ENV_REQUIRED_KEYS[@]}"
for track in stable v5; do
    : > "${GITHUB_OUTPUT}"
    : > "${RUNNER_TEMP}/manifest-requests"
    TRACK="${track}" RESOLVED_ENV="${RESOLVED_ENV}" bash "${RUNNER_TEMP}/prepare.sh"
    grep -qx 'RUST_VERSION=1.88' "${RUNNER_TEMP}/build-env"
    grep -qx 'rust=1.88' "${GITHUB_OUTPUT}"
    grep -q '/containers/netavark/v2.0.0/Cargo.toml' "${RUNNER_TEMP}/manifest-requests"
done

# Local setup shares the selector while allowing an explicit Rust override.
export NIGHTLY_BUILD=true ARCH=amd64 DISTRO=24.04 GOVERSION=1.26.8
export GOCACHE="${RUNNER_TEMP}/go-build" GOMODCACHE="${RUNNER_TEMP}/go-mod"
unset NETAVARK_TAG RUST_VERSION
(
    source ./config.sh > /dev/null
    [[ "${RUST_VERSION}" == stable ]]
)
(
    export NETAVARK_TAG=v2.0.0
    source ./config.sh > /dev/null
    [[ "${RUST_VERSION}" == 1.88 ]]
)
(
    export RUST_VERSION=1.90.0
    source ./config.sh > /dev/null
    [[ "${RUST_VERSION}" == 1.90.0 ]]
)

echo "PASS: nightly CI and local setup use stable Rust by default"
