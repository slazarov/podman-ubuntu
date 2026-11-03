#!/bin/bash

# Non-Interactive Mode - MUST be set before ANY apt commands
export DEBIAN_FRONTEND=noninteractive

# Strict Mode - Exit on error, undefined vars, pipe failures
set -euo pipefail

# Determine toolpath if not set already
relativepath="./" # Define relative path to go from this script to the root level of the tool
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi

# Load Configuration
source "${toolpath}/config.sh"

# Load Functions
source "${toolpath}/functions.sh"

# Set error trap AFTER sourcing (config/functions may not support strict mode)
trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR

# ============================================
# Pre-flight Validation (before any build operations)
# ============================================
echo ""
echo ">>> Running pre-flight validation..."
# Source the preflight script (it runs checks when sourced from setup.sh context)
if ! source "${toolpath}/scripts/preflight_check.sh" || ! run_preflight_checks; then
    echo ""
    echo "Pre-flight validation failed. Please fix the issues above and retry."
    exit 1
fi
echo ">>> Pre-flight validation passed"

# Track installation progress
COMPONENTS_OK=()

# Wrapper function for running sub-scripts with error handling and timing
run_script() {
    local script="$1"

    script_start

    echo ""
    echo "========================================"
    echo ">>> Starting: ${script}"
    echo "========================================"

    # Sub-scripts are sourced, so their exports reach every later script.
    # enable_c_compiler_cache / enable_rust_compiler_cache export CC and
    # RUSTC_WRAPPER for ONE component's build; restore them afterwards so they
    # do not leak. A leaked CC="ccache gcc" makes Go link cgo binaries as PIE,
    # which Ubuntu's gcc links with "-z now", and toolbox (NVIDIA libraries
    # bound lazily) then fails at startup with "undefined symbol: nvml...".
    local cc_was_set="${CC+x}" cc_saved="${CC:-}"
    local rustc_wrapper_was_set="${RUSTC_WRAPPER+x}" rustc_wrapper_saved="${RUSTC_WRAPPER:-}"

    source "${toolpath}/scripts/${script}"

    if [[ -n "${cc_was_set}" ]]; then export CC="${cc_saved}"; else unset CC; fi
    if [[ -n "${rustc_wrapper_was_set}" ]]; then
        export RUSTC_WRAPPER="${rustc_wrapper_saved}"
    else
        unset RUSTC_WRAPPER
    fi

    COMPONENTS_OK+=("${script}")
    script_done "${script}"
}

# Install Requirements
run_script "install_dependencies.sh"

# Install RUST
run_script "install_rust.sh"

# Install Go
run_script "install_go.sh"

# Build AardVark DNS
run_script "build_aardvark_dns.sh"

# Build Buildah
run_script "build_buildah.sh"

# Build Catatonit
run_script "build_catatonit.sh"

# Build Conmon
run_script "build_conmon.sh"

# Build CRUN
run_script "build_crun.sh"

# Build Fuse-OverlayFS
run_script "build_fuse-overlayfs.sh"

# Build Go-MD2Man
run_script "build_go-md2man.sh"

# Build Container-Libs (containers-common config files)
run_script "build_container-libs.sh"

# Build Netavark
run_script "build_netavark.sh"

# Build Pasta
run_script "build_pasta.sh"

# Build Podman
run_script "build_podman.sh"

# Build Skopeo
run_script "build_skopeo.sh"

# Build Toolbox
run_script "build_toolbox.sh"

# Install Container Configuration Files
run_script "install_container-configs.sh"

# Install Container Man Pages
run_script "install_container-manpages.sh"
