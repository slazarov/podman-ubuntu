#!/bin/bash

# CI-specific two-suite APT repository publisher
# Builds a complete reprepro repository containing BOTH suites:
# the newly-built suite from fresh .deb artifacts AND the other
# suite's packages imported from the live GitHub Pages repository.

# Abort on Error
set -euo pipefail

# Determine toolpath if not set already
relativepath="../" # Define relative path to go from this script to the root level of the tool
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi

# Load Configuration
source "${toolpath}/config.sh"

# Load Functions
source "${toolpath}/functions.sh"

# Set error trap AFTER sourcing
trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR

# ============================================
# Usage and Argument Parsing
# ============================================

usage() {
    echo "Usage: $(basename "$0") <suite> <deb-directory> <repo-url> <output-directory>"
    echo ""
    echo "  suite            Target suite being published: 'stable' or 'edge'"
    echo "  deb-directory    Path containing freshly built .deb files for this suite"
    echo "  repo-url         Live repository URL (e.g., https://slazarov.github.io/podman-debian)"
    echo "  output-directory Where to create the final two-suite repository"
    echo ""
    echo "Environment variables:"
    echo "  GPG_PRIVATE_KEY  If set, imports this GPG key before signing (for CI)"
    echo ""
    echo "This script:"
    echo "  1. Builds the current suite using repo_manage.sh"
    echo "  2. Downloads the other suite's packages from the live repository"
    echo "  3. Adds the other suite's packages via reprepro includedeb"
    echo "  4. Produces a complete repository with both suites"
    exit 1
}

if [[ $# -lt 4 ]]; then
    usage
fi

SUITE="$1"
DEB_DIR="$2"
REPO_URL="$3"
OUTPUT_DIR="$4"

REPO_CONF="${toolpath}/packaging/repo"

# ============================================
# Validate Arguments
# ============================================

echo ""
echo "========================================"
echo ">>> CI Two-Suite Repository Publisher"
echo "========================================"
echo ""

# Validate suite name
if [[ "${SUITE}" != "stable" && "${SUITE}" != "edge" ]]; then
    echo "ERROR: Invalid suite '${SUITE}'. Must be 'stable' or 'edge'." >&2
    exit 1
fi

# Validate deb directory exists
if [[ ! -d "${DEB_DIR}" ]]; then
    echo "ERROR: deb-directory does not exist: ${DEB_DIR}" >&2
    exit 1
fi

# Validate deb directory contains .deb files
deb_count=$(find "${DEB_DIR}" -maxdepth 1 -name "*.deb" -type f | wc -l)
if [[ "${deb_count}" -eq 0 ]]; then
    echo "ERROR: No .deb files found in: ${DEB_DIR}" >&2
    exit 1
fi

# ============================================
# Step 1: Determine the OTHER suite
# ============================================

if [[ "${SUITE}" == "stable" ]]; then
    OTHER_SUITE="edge"
else
    OTHER_SUITE="stable"
fi

echo "Current suite: ${SUITE} (${deb_count} new packages)"
echo "Other suite:   ${OTHER_SUITE} (will import from live repo)"
echo "Live repo:     ${REPO_URL}"
echo "Output dir:    ${OUTPUT_DIR}"
echo ""

# ============================================
# Step 2: Download other suite's .deb files from live repo
# ============================================

echo ">>> Downloading existing packages for '${OTHER_SUITE}' suite..."

OTHER_SUITE_DEBS=$(mktemp -d)
other_suite_count=0

for arch in amd64 arm64; do
    packages_url="${REPO_URL}/dists/${OTHER_SUITE}/main/binary-${arch}/Packages"
    echo "  Fetching: ${packages_url}"

    packages_content=$(curl -sfL "${packages_url}" 2>/dev/null || true)

    if [[ -z "${packages_content}" ]]; then
        echo "  No Packages file for ${OTHER_SUITE}/binary-${arch} (first deploy or arch not published)"
        continue
    fi

    # Parse Filename: lines from the Packages index
    while IFS= read -r filename; do
        if [[ -n "${filename}" ]]; then
            deb_url="${REPO_URL}/${filename}"
            deb_basename=$(basename "${filename}")

            # Skip if already downloaded (same package may appear in both arch indices)
            if [[ -f "${OTHER_SUITE_DEBS}/${deb_basename}" ]]; then
                continue
            fi

            echo "  Downloading: ${deb_basename}"
            if curl -sfL -o "${OTHER_SUITE_DEBS}/${deb_basename}" "${deb_url}"; then
                other_suite_count=$((other_suite_count + 1))
            else
                echo "  WARNING: Failed to download ${deb_basename}, skipping" >&2
                rm -f "${OTHER_SUITE_DEBS}/${deb_basename}"
            fi
        fi
    done <<< "$(echo "${packages_content}" | grep "^Filename:" | sed 's/^Filename: *//')"
done

echo ""
echo ">>> Downloaded ${other_suite_count} packages for '${OTHER_SUITE}' suite"
echo ""

# ============================================
# Step 3: Build current suite with repo_manage.sh
# ============================================

echo ">>> Building '${SUITE}' suite with repo_manage.sh..."
echo ""

"${toolpath}/scripts/repo_manage.sh" "${SUITE}" "${DEB_DIR}" "${OUTPUT_DIR}"

echo ""

# ============================================
# Step 4: Add other suite's packages (if any were downloaded)
# ============================================

if [[ ${other_suite_count} -gt 0 ]]; then
    echo ">>> Adding '${OTHER_SUITE}' suite packages to repository..."
    echo ""

    # Rebuild conf/ (repo_manage.sh cleans it up after running)
    mkdir -p "${OUTPUT_DIR}/conf"
    cp "${REPO_CONF}/conf/distributions" "${OUTPUT_DIR}/conf/"
    cp "${REPO_CONF}/conf/options" "${OUTPUT_DIR}/conf/"

    # Add each .deb from the other suite
    other_added=0
    for deb_file in "${OTHER_SUITE_DEBS}"/*.deb; do
        if [[ -f "${deb_file}" ]]; then
            echo "  Adding: $(basename "${deb_file}")"
            reprepro -Vb "${OUTPUT_DIR}" includedeb "${OTHER_SUITE}" "${deb_file}"
            other_added=$((other_added + 1))
        fi
    done

    echo ""
    echo ">>> Added ${other_added} packages to '${OTHER_SUITE}' suite"

    # Re-export metadata for both suites
    echo ">>> Re-exporting repository metadata for both suites..."
    reprepro -b "${OUTPUT_DIR}" export
    echo ">>> Metadata exported (InRelease + Release.gpg for both suites)"
    echo ""

    # Clean up reprepro internals
    rm -rf "${OUTPUT_DIR}/db" "${OUTPUT_DIR}/conf"
    echo ">>> Cleaned up reprepro internals"
    echo ""
else
    echo ">>> No packages for '${OTHER_SUITE}' suite (first deploy or no live repo)"
    echo ">>> Only '${SUITE}' suite will be published"
    echo ""
fi

# Clean up temporary directory
rm -rf "${OTHER_SUITE_DEBS}"

# ============================================
# Step 5: Generate index.html landing page
# ============================================

echo ">>> Generating index.html landing page..."

# Collect available suites
available_suites=()
for s in stable edge; do
    if [[ -d "${OUTPUT_DIR}/dists/${s}" ]]; then
        available_suites+=("${s}")
    fi
done

cat > "${OUTPUT_DIR}/index.html" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Podman for Debian — APT Repository</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; max-width: 720px; margin: 2rem auto; padding: 0 1rem; color: #1a1a1a; line-height: 1.6; }
h1 { border-bottom: 2px solid #333; padding-bottom: 0.5rem; }
code, pre { background: #f4f4f4; border-radius: 4px; }
code { padding: 0.15em 0.4em; font-size: 0.9em; }
pre { padding: 1rem; overflow-x: auto; }
.suite { margin: 1.5rem 0; padding: 1rem; border: 1px solid #ddd; border-radius: 6px; }
.suite h3 { margin-top: 0; }
a { color: #0366d6; }
</style>
</head>
<body>
<h1>Podman for Debian — APT Repository</h1>
<p>Pre-built <code>.deb</code> packages for Podman and its dependencies on Debian (amd64 &amp; arm64).</p>

<h2>Quick Setup</h2>
<pre><code># Import the signing key
curl -fsSL https://REPO_URL_PLACEHOLDER/podman-debian.gpg | sudo tee /usr/share/keyrings/podman-debian.gpg > /dev/null

# Add the repository (stable track)
echo "deb [signed-by=/usr/share/keyrings/podman-debian.gpg] https://REPO_URL_PLACEHOLDER stable main" \
  | sudo tee /etc/apt/sources.list.d/podman-debian.list

# Install
sudo apt-get update
sudo apt-get install podman</code></pre>

<h2>Available Suites</h2>
HTMLEOF

# Append suite info dynamically
for s in "${available_suites[@]}"; do
    pkg_count=$(find "${OUTPUT_DIR}/pool" -name "*.deb" -path "*/${s}/*" 2>/dev/null | wc -l || echo "0")
    cat >> "${OUTPUT_DIR}/index.html" << SUITEEOF
<div class="suite">
<h3>${s}</h3>
<p>Packages: ${pkg_count} | <a href="dists/${s}/InRelease">InRelease</a></p>
</div>
SUITEEOF
done

cat >> "${OUTPUT_DIR}/index.html" << 'HTMLEOF'

<h2>Resources</h2>
<ul>
<li><a href="podman-debian.gpg">GPG signing key</a></li>
<li><a href="https://github.com/slazarov/podman-debian">Source repository</a></li>
</ul>
</body>
</html>
HTMLEOF

# Replace placeholder with actual repo URL
sed -i "s|REPO_URL_PLACEHOLDER|${REPO_URL#https://}|g" "${OUTPUT_DIR}/index.html"

echo ">>> index.html generated"
echo ""

# ============================================
# Step 6: Summary
# ============================================

echo "========================================"
echo ">>> CI Repository Build Complete"
echo "========================================"
echo ""
echo "Current suite: ${SUITE} (${deb_count} packages from build)"
echo "Other suite:   ${OTHER_SUITE} (${other_suite_count} packages from live repo)"
echo "Output:        ${OUTPUT_DIR}"
echo ""

# List contents to confirm structure
echo "Repository structure:"
echo "----------------------------------------"
for suite_name in "${SUITE}" "${OTHER_SUITE}"; do
    if [[ -d "${OUTPUT_DIR}/dists/${suite_name}" ]]; then
        echo "  dists/${suite_name}/"
        for f in "${OUTPUT_DIR}/dists/${suite_name}"/*; do
            if [[ -f "${f}" ]]; then
                echo "    $(basename "${f}")"
            elif [[ -d "${f}" ]]; then
                echo "    $(basename "${f}")/"
            fi
        done
    fi
done
if [[ -d "${OUTPUT_DIR}/pool" ]]; then
    echo "  pool/"
fi
if [[ -f "${OUTPUT_DIR}/podman-debian.gpg" ]]; then
    echo "  podman-debian.gpg"
fi
echo "----------------------------------------"
