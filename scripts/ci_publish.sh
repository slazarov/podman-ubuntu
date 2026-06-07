#!/bin/bash

# CI-specific multi-suite APT repository publisher
# Builds a complete reprepro repository containing ALL suites:
# the newly-built suite from fresh .deb artifacts AND the other
# suites' packages imported from the live GitHub Pages repository.

# Abort on Error
set -euo pipefail

# Determine toolpath if not set already
relativepath="../" # Define relative path to go from this script to the root level of the tool
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing "${scriptpath}/${relativepath}"); fi

# Load Configuration
source "${toolpath}/config.sh"

# Load Functions
source "${toolpath}/functions.sh"

# Load the post-export Acquire-By-Hash helper (Plan 02). Sourced (not executed),
# so it only defines add_byhash_and_resign; it relies on repo_manage.sh having
# imported the GPG key earlier in the publish.
source "${toolpath}/scripts/repo_byhash.sh"

# Set error trap AFTER sourcing
trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR

# ============================================
# Usage and Argument Parsing
# ============================================

usage() {
    echo "Usage: $(basename "$0") <track> <distro> <deb-directory> <repo-url> <output-directory>"
    echo ""
    echo "  track            Release track being published: 'stable', 'edge', or 'nightly'"
    echo "  distro           Target distro: '2404' or '2604'"
    echo "  deb-directory    Path containing freshly built .deb files for this track"
    echo "  repo-url         Live repository URL (e.g., https://slazarov.github.io/podman-ubuntu)"
    echo "  output-directory Where to create the final multi-suite repository"
    echo ""
    echo "  The (track, distro) pair is resolved to its publish targets via"
    echo "  resolve_publish_targets (config.sh): the versioned '<track>-<distro>'"
    echo "  suite, plus the bare '<track>' legacy alias when distro is 2404 (D-12)."
    echo ""
    echo "Environment variables:"
    echo "  GPG_PRIVATE_KEY  If set, imports this GPG key before signing (for CI)"
    echo ""
    echo "This script:"
    echo "  1. Mirrors down the untouched suites' packages from the live repository"
    echo "  2. Builds the published target suite(s) from fresh .debs via repo_manage.sh"
    echo "  3. Re-includes the mirrored suites and exports each suite per-suite"
    echo "  4. Applies Acquire-By-Hash + re-sign to every suite (Plan 02)"
    echo "  5. Produces a complete 9-suite repository with no clobbering"
    exit 1
}

if [[ $# -lt 5 ]]; then
    usage
fi

TRACK="$1"
DISTRO="$2"
DEB_DIR="$3"
REPO_URL="$4"
OUTPUT_DIR="$5"

REPO_CONF="${toolpath}/packaging/repo"

# ============================================
# Validate Arguments
# ============================================

echo ""
echo "========================================"
echo ">>> CI Multi-Suite Repository Publisher"
echo "========================================"
echo ""

# Resolve the publish targets via the Plan-01 routing helper (config.sh). This
# validates track+distro and yields the versioned suite plus, for 24.04, the
# bare legacy alias (D-12).
mapfile -t PUBLISH_TARGETS < <(resolve_publish_targets "${TRACK}" "${DISTRO}")
# resolve_publish_targets runs in a subshell; its non-zero exit on bad input
# cannot abort us directly, so an invalid pair yields zero targets.
if [[ ${#PUBLISH_TARGETS[@]} -eq 0 ]]; then
    echo "ERROR: could not resolve publish targets for track='${TRACK}' distro='${DISTRO}'." >&2
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
# Step 1: Determine the OTHER (untouched) suites
# ============================================

# ALL_SUITES is the 9-element set sourced from config.sh — do NOT redeclare it.
# OTHER_SUITES = every member of ALL_SUITES that is NOT a publish target. For a
# 24.04 publish both '<track>-2404' and the bare '<track>' alias are publish
# targets, so both are excluded from mirror-down (D-12/D-13). The untouched
# suites are mirrored unchanged — this is the no-clobber guarantee (T-20-07).
OTHER_SUITES=()
for s in "${ALL_SUITES[@]}"; do
    is_target=false
    for t in "${PUBLISH_TARGETS[@]}"; do
        if [[ "$s" == "$t" ]]; then
            is_target=true
            break
        fi
    done
    if [[ "${is_target}" != "true" ]]; then
        OTHER_SUITES+=("$s")
    fi
done

echo "Track:          ${TRACK}"
echo "Distro:         ${DISTRO}"
echo "Publish targets:${PUBLISH_TARGETS[*]} (${deb_count} new packages)"
echo "Other suites:   ${OTHER_SUITES[*]} (will mirror from live repo)"
echo "Live repo:      ${REPO_URL}"
echo "Output dir:     ${OUTPUT_DIR}"
echo ""

# ============================================
# Step 2: Mirror other suites' metadata + .deb files from the live repo
# ============================================
#
# CR-02 (T-20-17): non-target suites whose live dists/<suite>/ tree already
# exists are served VERBATIM. We copy the live `dists/<suite>/` metadata tree
# (Release, InRelease, Release.gpg, per-arch Packages/Release, by-hash/) and the
# pool entries it references straight into ${OUTPUT_DIR} with their ORIGINAL
# signatures, then exclude the suite from the re-includedeb/re-export loop
# (Step 4) and the by-hash + re-sign loop (Step 4b). Re-exporting an unchanged
# suite would regenerate its Release Date + signature even though its package
# content is identical, reopening the Acquire-By-Hash CDN hash-mismatch window
# this bolt-on exists to prevent. Serving the tree verbatim keeps the suite's
# Release Date / InRelease / Release.gpg byte-identical.
#
# VERBATIM_SUITES holds the non-target suites we successfully mirrored verbatim
# (the bare aliases on a 26.04 publish, plus any versioned non-target suite with
# a live tree). On a 24.04 publish the bare alias is a PUBLISH TARGET (D-12) so
# it is never in OTHER_SUITES and never verbatim-mirrored — it is fed fresh by
# repo_manage.sh exactly as before. When the live alias tree 404s (first deploy /
# empty-2604, D-14) the verbatim copy no-ops cleanly and the suite stays empty.

declare -A OTHER_SUITE_DEBS_DIRS
declare -A OTHER_SUITE_COUNTS
declare -A IS_VERBATIM
VERBATIM_SUITES=()
total_other_count=0

# mirror_suite_verbatim <suite> [repo-url] [output-dir] — reconstruct the live
# dists/<suite>/ metadata tree byte-identically from the signed Release's own
# file manifest and place it into the output repo, preserving the original
# signatures. repo-url / output-dir default to the caller's REPO_URL /
# OUTPUT_DIR globals (overridable so tests can drive the function directly).
# Returns 0 if the live tree existed and was reconstructed verbatim, 1
# otherwise (first deploy / not published / CDN integrity mismatch). Never
# aborts the caller.
#
# T-20-17 fix history: the previous `wget -r` crawl broke two ways against
# GitHub Pages — `-nH --cut-dirs=0` kept the project-pages path segment, so
# the tree landed at <mirror>/<repo-name>/dists/... while the guard checked
# <mirror>/dists/..., and Pages serves no directory listings for a recursive
# crawl to enumerate anyway. The signed Release already lists every index it
# checksums, so fetch THAT manifest explicitly: top-level signed metadata
# verbatim, every listed index verified against its signed hash, and the
# adjacent by-hash/<ALGO>/<hash> copies reconstructed locally — by-hash files
# are byte-identical copies of the canonical indexes by definition (same
# parser and layout as add_byhash_and_resign, repo_byhash.sh). No crawling,
# no URL-shape dependency.
mirror_suite_verbatim() {
    local lsuite="$1"
    local lrepo_url="${2:-${REPO_URL}}"
    local loutdir="${3:-${OUTPUT_DIR}}"
    local lbase="${lrepo_url}/dists/${lsuite}"

    local lmirror
    lmirror=$(mktemp -d)
    local ldist="${lmirror}/dists/${lsuite}"
    mkdir -p "${ldist}"

    # The signed Release is both the existence probe and the file manifest. A
    # fetch failure means first deploy / suite not yet published (D-14) — no-op.
    if ! curl -sfL -o "${ldist}/Release" "${lbase}/Release" 2>/dev/null; then
        rm -rf "${lmirror}"
        return 1
    fi

    # The signatures must arrive verbatim — without them the suite cannot be
    # served unchanged, so fall back to the re-export path.
    local lf
    for lf in InRelease Release.gpg; do
        if ! curl -sfL -o "${ldist}/${lf}" "${lbase}/${lf}" 2>/dev/null; then
            echo "  WARNING: ${lsuite}: live ${lf} missing — not serving verbatim" >&2
            rm -rf "${lmirror}"
            return 1
        fi
    done

    # Fetch every checksummed index the Release lists (same "<hash> <size>
    # <relpath>" section parser as repo_byhash.sh), verify it against the
    # signed hash, and reconstruct the adjacent by-hash copy. `tr` instead of
    # ${algo,,} so the function stays runnable under macOS bash 3.2 in tests.
    local algo hash relpath src bhdir cmd rh
    for algo in SHA256 SHA512; do
        cmd="$(echo "${algo}" | tr '[:upper:]' '[:lower:]')sum"
        while read -r hash relpath; do
            [[ -n "${relpath}" ]] || continue
            src="${ldist}/${relpath}"
            if [[ ! -f "${src}" ]]; then
                mkdir -p "$(dirname "${src}")"
                # A listed-but-missing index means the live tree is incomplete
                # and cannot be reproduced verbatim.
                if ! curl -sfL -o "${src}" "${lbase}/${relpath}" 2>/dev/null; then
                    echo "  WARNING: ${lsuite}: listed index ${relpath} missing from live tree — not serving verbatim" >&2
                    rm -rf "${lmirror}"
                    return 1
                fi
            fi
            # Integrity: fetched bytes must match the signed manifest, or a
            # mid-deploy CDN race handed us a stale index — abort verbatim and
            # let the re-export path regenerate the suite consistently.
            if command -v "${cmd}" >/dev/null 2>&1; then
                rh="$(${cmd} "${src}" | awk '{print $1}')"
                if [[ "${rh}" != "${hash}" ]]; then
                    echo "  WARNING: ${lsuite}: ${relpath} does not match signed ${algo} hash — not serving verbatim" >&2
                    rm -rf "${lmirror}"
                    return 1
                fi
            fi
            bhdir="$(dirname "${src}")/by-hash/${algo}"
            mkdir -p "${bhdir}"
            cp -f "${src}" "${bhdir}/${hash}"
        done < <(awk -v a="${algo}:" '$0==a{f=1;next} /^[A-Za-z0-9-]+:/{f=0} f{print $1, $3}' "${ldist}/Release")
    done

    # by-hash copies of the served Release itself (parity with the live tree,
    # which carries them from add_byhash_and_resign step 3).
    for algo in SHA256 SHA512; do
        cmd="$(echo "${algo}" | tr '[:upper:]' '[:lower:]')sum"
        command -v "${cmd}" >/dev/null 2>&1 || continue
        rh="$(${cmd} "${ldist}/Release" | awk '{print $1}')"
        mkdir -p "${ldist}/by-hash/${algo}"
        cp -f "${ldist}/Release" "${ldist}/by-hash/${algo}/${rh}"
    done

    # Place the verbatim dists/<suite>/ tree into the output unchanged. Staged
    # under mktemp so a mid-fetch failure never leaves a partial tree behind.
    mkdir -p "${loutdir}/dists"
    rm -rf "${loutdir}/dists/${lsuite}"
    cp -a "${ldist}" "${loutdir}/dists/${lsuite}"
    rm -rf "${lmirror}"
    return 0
}

for other_suite in "${OTHER_SUITES[@]}"; do
    echo ">>> Mirroring existing '${other_suite}' suite from live repo..."

    # CR-02: attempt to serve this non-target suite's signed dists/ tree verbatim.
    if mirror_suite_verbatim "${other_suite}"; then
        IS_VERBATIM["${other_suite}"]=true
        VERBATIM_SUITES+=("${other_suite}")
        echo ">>> Mirrored '${other_suite}' dists/ tree verbatim (original signature preserved)"
    else
        IS_VERBATIM["${other_suite}"]=false
        echo ">>> No live tree for '${other_suite}' (first deploy / not published) — nothing to mirror"
    fi

    other_dir=$(mktemp -d)
    OTHER_SUITE_DEBS_DIRS["${other_suite}"]="${other_dir}"
    suite_count=0

    for arch in amd64 arm64; do
        packages_url="${REPO_URL}/dists/${other_suite}/main/binary-${arch}/Packages"
        echo "  Fetching: ${packages_url}"

        packages_content=$(curl -sfL "${packages_url}" 2>/dev/null || true)

        if [[ -z "${packages_content}" ]]; then
            echo "  No Packages file for ${other_suite}/binary-${arch} (first deploy or not published)"
            continue
        fi

        # Parse Filename: lines from the Packages index. We download the referenced
        # .deb files for two reasons: (a) for a verbatim-mirrored suite, the pool
        # entries its served Packages index references must exist under
        # ${OUTPUT_DIR}/pool/ so apt can fetch the packages; (b) for a non-verbatim
        # suite (no live tree to copy) the debs feed the legacy re-includedeb path.
        while IFS= read -r filename; do
            if [[ -n "${filename}" ]]; then
                deb_url="${REPO_URL}/${filename}"
                deb_basename=$(basename "${filename}")

                # For a verbatim-mirrored suite, place the pool entry at the exact
                # path its Packages index references (Filename:) so apt resolves it.
                if [[ "${IS_VERBATIM["${other_suite}"]}" == "true" ]]; then
                    pool_dest="${OUTPUT_DIR}/${filename}"
                    if [[ ! -f "${pool_dest}" ]]; then
                        mkdir -p "$(dirname "${pool_dest}")"
                        if curl -sfL -o "${pool_dest}" "${deb_url}"; then
                            suite_count=$((suite_count + 1))
                        else
                            echo "  WARNING: Failed to download pool entry ${deb_basename}" >&2
                            rm -f "${pool_dest}"
                        fi
                    fi
                    continue
                fi

                # Skip if already downloaded (same package may appear in both arch indices)
                if [[ -f "${other_dir}/${deb_basename}" ]]; then
                    continue
                fi

                echo "  Downloading: ${deb_basename}"
                if curl -sfL -o "${other_dir}/${deb_basename}" "${deb_url}"; then
                    suite_count=$((suite_count + 1))
                else
                    echo "  WARNING: Failed to download ${deb_basename}, skipping" >&2
                    rm -f "${other_dir}/${deb_basename}"
                fi
            fi
        done <<< "$(echo "${packages_content}" | grep "^Filename:" | sed 's/^Filename: *//')"
    done

    OTHER_SUITE_COUNTS["${other_suite}"]=${suite_count}
    # Verbatim-mirrored suites are NOT counted toward total_other_count: that
    # counter gates the re-includedeb/re-export loop (Step 4), which must never
    # run for a suite we are serving verbatim.
    if [[ "${IS_VERBATIM["${other_suite}"]}" != "true" ]]; then
        total_other_count=$((total_other_count + suite_count))
    fi
    echo ">>> Processed ${suite_count} packages for '${other_suite}' suite"
    echo ""
done

# ============================================
# Step 3: Build current suite with repo_manage.sh
# ============================================

echo ">>> Building target suite(s) [${PUBLISH_TARGETS[*]}] with repo_manage.sh..."
echo ""

# repo_manage.sh now resolves the same (track, distro) into PUBLISH_TARGETS and
# feeds the fresh .debs into each target (versioned suite + 24.04 alias) itself.
"${toolpath}/scripts/repo_manage.sh" "${TRACK}" "${DISTRO}" "${DEB_DIR}" "${OUTPUT_DIR}"

echo ""

# ============================================
# Step 4: Add other suites' packages (if any were downloaded)
# ============================================

if [[ ${total_other_count} -gt 0 ]]; then
    echo ">>> Adding other suites' packages to repository..."
    echo ""

    # Rebuild conf/ (repo_manage.sh cleans it up after running)
    mkdir -p "${OUTPUT_DIR}/conf"
    cp "${REPO_CONF}/conf/distributions" "${OUTPUT_DIR}/conf/"
    cp "${REPO_CONF}/conf/options" "${OUTPUT_DIR}/conf/"

    for other_suite in "${OTHER_SUITES[@]}"; do
        # CR-02: a verbatim-mirrored suite is served as-is (its signed dists/ tree
        # was copied in Step 2). Never re-includedeb + re-export it — that would
        # regenerate its Release Date + signature on byte-identical content.
        if [[ "${IS_VERBATIM["${other_suite}"]:-false}" == "true" ]]; then
            echo ">>> '${other_suite}' served verbatim — skipping re-includedeb/re-export"
            continue
        fi

        suite_count=${OTHER_SUITE_COUNTS["${other_suite}"]}
        if [[ ${suite_count} -eq 0 ]]; then
            echo ">>> No packages for '${other_suite}' suite (first deploy or not published)"
            continue
        fi

        echo ">>> Adding '${other_suite}' suite packages..."
        other_added=0
        for deb_file in "${OTHER_SUITE_DEBS_DIRS["${other_suite}"]}"/*.deb; do
            if [[ -f "${deb_file}" ]]; then
                echo "  Adding: $(basename "${deb_file}")"
                reprepro -Vb "${OUTPUT_DIR}" includedeb "${other_suite}" "${deb_file}"
                other_added=$((other_added + 1))
            fi
        done
        echo ">>> Added ${other_added} packages to '${other_suite}' suite"

        # Export only this suite (not all — exporting all would clobber the current
        # suite's Packages file since the fresh db doesn't know about it)
        echo ">>> Exporting metadata for '${other_suite}' suite..."
        reprepro -b "${OUTPUT_DIR}" export "${other_suite}"
        echo ""
    done

    # Clean up reprepro internals
    rm -rf "${OUTPUT_DIR}/db" "${OUTPUT_DIR}/conf"
    echo ">>> Cleaned up reprepro internals"
    echo ""
else
    echo ">>> No packages for other suites (first deploy or no live repo)"
    echo ">>> Only the target suite(s) [${PUBLISH_TARGETS[*]}] will be published"
    echo ""
fi

# ============================================
# Step 4b: Acquire-By-Hash + re-sign every exported suite (REPO-08 / D-07)
# ============================================
# Run AFTER all exports (target suites via repo_manage.sh, other suites in the
# re-include loop) but BEFORE temp-dir cleanup. add_byhash_and_resign reads the
# exported dists/ tree and re-signs in place; the GPG key is already in the
# keyring from repo_manage.sh's import. Suites without a Release (none materialized
# yet) are a no-op inside the helper, but we guard here too for clear logging.

echo ">>> Applying Acquire-By-Hash + re-sign to all exported suites..."
for suite in "${ALL_SUITES[@]}"; do
    # CR-02: verbatim-mirrored suites already carry their original by-hash dirs
    # and signature from the live repo — re-signing them would defeat the
    # verbatim preservation (new Release Date + signature on unchanged content).
    if [[ "${IS_VERBATIM["${suite}"]:-false}" == "true" ]]; then
        echo "  preserved verbatim (no re-sign): ${suite}"
        continue
    fi
    if [[ -f "${OUTPUT_DIR}/dists/${suite}/Release" ]]; then
        echo "  by-hash + re-sign: ${suite}"
        add_byhash_and_resign "${suite}" "${OUTPUT_DIR}"
    fi
done
echo ">>> Acquire-By-Hash post-processing complete"
echo ""

# Clean up all temp dirs
for other_suite in "${OTHER_SUITES[@]}"; do
    rm -rf "${OTHER_SUITE_DEBS_DIRS["${other_suite}"]}"
done

# ============================================
# Step 5: Generate index.html landing page
# ============================================

echo ">>> Generating index.html landing page..."

# WR-04 (T-20-18): HTML-escape dynamic values before interpolating them into the
# generated index.html. Package names/versions are parsed from the Packages index
# (versions derive from upstream HEAD for nightly builds, an attacker-influenceable
# source). Escape the four metacharacters in order — `&` first so already-escaped
# entities are not double-escaped.
esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }

# Collect available suites across the full 9-suite set. The empty-skip below
# (Step that appends suite info) hides suites whose Packages index is empty, so
# the as-yet-unpopulated -2604 suites stay hidden until they carry content (D-18).
available_suites=()
for s in "${ALL_SUITES[@]}"; do
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
.tracks { display: flex; gap: 1rem; margin: 1.5rem 0; flex-wrap: wrap; }
.track { flex: 1; min-width: 280px; padding: 1rem; border: 1px solid #ddd; border-radius: 6px; }
.track h3 { margin-top: 0; }
.track.recommended { border-color: #2ea44f; }
.track.recommended h3::after { content: " (recommended)"; font-size: 0.8em; color: #2ea44f; font-weight: normal; }
.tab-group { margin: 1.5rem 0; }
.tab-buttons { display: flex; gap: 0; }
.tab-btn { padding: 0.5rem 1.5rem; border: 1px solid #ddd; background: #f4f4f4; cursor: pointer; font-size: 0.95em; }
.tab-btn:first-child { border-radius: 6px 0 0 0; }
.tab-btn:last-child { border-radius: 0 6px 0 0; }
.tab-btn.active { background: #fff; border-bottom-color: #fff; font-weight: 600; }
.tab-content { display: none; border: 1px solid #ddd; border-top: none; border-radius: 0 0 6px 6px; padding: 1rem; }
.tab-content.active { display: block; }
a { color: #0366d6; }
table { border-collapse: collapse; width: 100%; margin: 0.5rem 0 1.5rem; }
th, td { text-align: left; padding: 0.4rem 0.8rem; border: 1px solid #ddd; font-size: 0.9em; }
th { background: #f4f4f4; }
</style>
</head>
<body>
<h1>Podman for Debian — APT Repository</h1>
<p>Pre-built <code>.deb</code> packages for Podman and its dependencies on Debian (amd64 &amp; arm64).</p>

<h2>Choose a Track</h2>
<div class="tracks">
  <div class="track recommended">
    <h3>stable</h3>
    <p>Pinned, tested versions. Best for production and daily use.</p>
  </div>
  <div class="track">
    <h3>edge</h3>
    <p>Latest upstream tags. For testing new features before they reach stable.</p>
  </div>
  <div class="track">
    <h3>nightly</h3>
    <p>Built from upstream main branch HEAD daily. Bleeding-edge, may break.</p>
  </div>
</div>

<h2>Setup</h2>

<p>1. Import the signing key:</p>
<pre><code>curl -fsSL https://REPO_URL_PLACEHOLDER/podman-ubuntu.gpg \
  | sudo tee /usr/share/keyrings/podman-ubuntu.gpg > /dev/null</code></pre>

<p>2. Add the repository — pick your track:</p>
<div class="tab-group">
  <div class="tab-buttons">
    <button class="tab-btn active" onclick="showTab('stable')">stable</button>
    <button class="tab-btn" onclick="showTab('edge')">edge</button>
    <button class="tab-btn" onclick="showTab('nightly')">nightly</button>
  </div>
  <div id="tab-stable" class="tab-content active">
    <pre><code>echo "deb [signed-by=/usr/share/keyrings/podman-ubuntu.gpg] https://REPO_URL_PLACEHOLDER stable main" \
  | sudo tee /etc/apt/sources.list.d/podman-ubuntu.list</code></pre>
  </div>
  <div id="tab-edge" class="tab-content">
    <pre><code>echo "deb [signed-by=/usr/share/keyrings/podman-ubuntu.gpg] https://REPO_URL_PLACEHOLDER edge main" \
  | sudo tee /etc/apt/sources.list.d/podman-ubuntu.list</code></pre>
  </div>
  <div id="tab-nightly" class="tab-content">
    <pre><code>echo "deb [signed-by=/usr/share/keyrings/podman-ubuntu.gpg] https://REPO_URL_PLACEHOLDER nightly main" \
  | sudo tee /etc/apt/sources.list.d/podman-ubuntu.list</code></pre>
  </div>
</div>

<p>3. Install:</p>
<pre><code>sudo apt-get update
sudo apt-get install podman-suite</code></pre>
<p><code>podman-suite</code> is a meta-package that installs Podman and all its dependencies
(crun, conmon, netavark, aardvark-dns, pasta, buildah, skopeo, and more).</p>

<h2>Available Suites</h2>
HTMLEOF

# Append suite info dynamically (only suites with actual packages)
for s in "${available_suites[@]}"; do
    packages_file="${OUTPUT_DIR}/dists/${s}/main/binary-amd64/Packages"
    pkg_count=$(grep -c "^Package:" "${packages_file}" 2>/dev/null || true)
    pkg_count=${pkg_count:-0}

    # Skip suites with no packages (reprepro export creates empty dists/ for all configured suites)
    if [[ ${pkg_count} -eq 0 ]]; then
        continue
    fi

    cat >> "${OUTPUT_DIR}/index.html" << SUITEEOF
<h3>${s} — ${pkg_count} packages <a href="dists/${s}/InRelease" style="font-size:0.8em;font-weight:normal">[InRelease]</a></h3>
<table>
<tr><th>Package</th><th>Version</th></tr>
SUITEEOF

    awk '/^Package:/{pkg=$2} /^Version:/{print pkg, $2}' "${packages_file}" \
    | sort \
    | while read -r pkg ver; do
        # WR-04: escape package name + version before HTML interpolation.
        pkg_e=$(printf '%s' "${pkg}" | esc)
        ver_e=$(printf '%s' "${ver}" | esc)
        cat >> "${OUTPUT_DIR}/index.html" << ROWEOF
<tr><td>${pkg_e}</td><td><code>${ver_e}</code></td></tr>
ROWEOF
    done

    cat >> "${OUTPUT_DIR}/index.html" << SUITEEOF
</table>
SUITEEOF
done

cat >> "${OUTPUT_DIR}/index.html" << 'HTMLEOF'

<h2>Resources</h2>
<ul>
<li><a href="podman-ubuntu.gpg">GPG signing key</a></li>
<li><a href="https://github.com/slazarov/podman-ubuntu">Source repository</a></li>
</ul>

<script>
function showTab(track) {
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
  document.querySelector('.tab-btn[onclick*="' + track + '"]').classList.add('active');
  document.getElementById('tab-' + track).classList.add('active');
}
</script>
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
echo "Published:      ${PUBLISH_TARGETS[*]} (${deb_count} packages from build)"
for other_suite in "${OTHER_SUITES[@]}"; do
    echo "Mirrored suite: ${other_suite} (${OTHER_SUITE_COUNTS["${other_suite}"]} packages from live repo)"
done
echo "Suite universe: ${ALL_SUITES[*]}"
echo "Output:         ${OUTPUT_DIR}"
echo ""

# List contents to confirm structure
echo "Repository structure:"
echo "----------------------------------------"
for suite_name in "${PUBLISH_TARGETS[@]}" "${OTHER_SUITES[@]}"; do
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
if [[ -f "${OUTPUT_DIR}/podman-ubuntu.gpg" ]]; then
    echo "  podman-ubuntu.gpg"
fi
echo "----------------------------------------"
