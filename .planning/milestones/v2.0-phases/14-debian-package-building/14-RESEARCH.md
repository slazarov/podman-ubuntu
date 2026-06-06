# Phase 14: Debian Package Building - Research

**Researched:** 2026-03-05
**Domain:** Debian packaging with nFPM, DESTDIR staging integration, shell scripting
**Confidence:** HIGH

## Summary

This phase transforms the existing build-from-source system into a packaging-ready pipeline. Two core workstreams: (1) adding DESTDIR support to all 12 build scripts so files stage to a temporary tree instead of installing directly, and (2) creating nFPM YAML configurations for 12 component packages plus a podman-suite meta-package that produces installable .deb files.

nFPM v2.45.0 is the current release and supports all required features: environment variable substitution for version/architecture, `type: config` for conffiles, Conflicts/Replaces/Provides declarations, and empty meta-packages (contents-free packages with only dependency declarations). The tool runs standalone via `nfpm pkg --config <yaml> --target <dir> --packager deb` without requiring GoReleaser.

**Primary recommendation:** Modify build scripts in-place for DESTDIR support, use `version_schema: none` in nFPM configs to handle non-semver versions (pasta date-based, container-libs namespaced tags), and declare Conflicts/Replaces/Provides only against the 10 Ubuntu packages that actually exist in noble.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Modify existing build scripts in-place to add DESTDIR support (no separate packaging layer)
- When DESTDIR is set, files stage to $DESTDIR/usr/...; when unset, direct-install behavior is unchanged
- Replace raw `cp` commands with `install -D -m 0755` for consistent DESTDIR support (netavark, pasta, aardvark-dns, etc.)
- Standardize all install prefixes to /usr (Debian convention) -- no more /usr/local in any component
- Drop sudo when DESTDIR is set (staging tree doesn't need root); keep sudo for direct-install mode
- Strip `v` prefix from tags (v5.5.2 -> 5.5.2), pass through date-based versions (pasta), extract from namespaced tags (container-libs common/v0.67.0 -> 0.67.0)
- Append `~podman1` suffix to all versions (e.g., 5.5.2~podman1) -- the `~` ensures official Ubuntu packages always upgrade over ours
- Read version from GIT_CHECKED_OUT_TAG after each build script runs, pass to nFPM via environment variable
- container-configs package uses container-libs common/ tag version (e.g., 0.67.0~podman1)
- nFPM YAML configs live in `packaging/nfpm/` directory at project root (one file per component)
- Version and architecture injected via nFPM's native environment variable substitution (${VERSION}, ${ARCH})
- Single orchestrator script (e.g., scripts/package_all.sh) iterates components, sets vars, invokes nFPM
- Built .deb files output to `output/` directory at project root (gitignored)
- go-md2man is a build-only tool -- no .deb package (keeps the 12-package list clean)
- Man pages bundled with their component package (podman-podman includes podman.1, etc.)
- container-configs: all 6 config files in /etc/containers/ declared as conffiles (preserved on upgrade)
- seccomp.json in /usr/share/containers/ is NOT a conffile (data file, overwritten on upgrade -- upstream changes are wanted)
- Conflicts/Replaces/Provides declared only against packages that actually exist in Ubuntu repos (research needed to identify which)

### Claude's Discretion
- Exact nFPM YAML structure and field ordering
- How the packaging orchestrator iterates components and handles errors
- DESTDIR variable naming convention (DESTDIR vs INSTALL_ROOT)
- Meta-package (podman-suite) nFPM config structure
- Order of operations: build all -> stage all -> package all, or build+stage+package per component

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PKG-01 | Each component as individual .deb with podman-* prefix | nFPM YAML configs per component, `name: podman-{component}` field |
| PKG-02 | Conflicts/Replaces/Provides against official Ubuntu packages | Ubuntu Noble package name mapping (10 packages identified), nFPM conflicts/replaces/provides fields |
| PKG-03 | Correct inter-package dependencies declared | Dependency tree documented, nFPM depends field with version constraints |
| PKG-04 | nFPM YAML config with version/architecture substitution | `${VERSION}` and `${ARCH}` env var substitution, `version_schema: none` for non-semver |
| PKG-05 | DESTDIR support in build scripts without breaking direct-install | DESTDIR pattern documented per script, conditional sudo/prefix logic |
| PKG-06 | Meta-package podman-suite installs full stack | Empty nFPM config with only depends list, no contents section needed |
| PKG-07 | Config files in /etc/containers/ declared as conffiles | nFPM `type: config` in contents section, dpkg conffiles mechanism verified |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| nFPM | 2.45.0 | .deb package builder from YAML configs | Zero-dependency Go binary, no Ruby/FPM needed, env var substitution built-in |
| bash | 5.x | Build script modifications, orchestrator | Already used by all existing scripts |
| install(1) | coreutils | File staging with permissions and directory creation | `install -D -m` creates parent dirs atomically, replaces raw `cp` |
| dpkg-deb | system | Package verification | Standard Debian tool to inspect built packages |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| dpkg | system | Test package installation | Verification: `dpkg -i`, `dpkg -c`, `dpkg --info` |
| ar | binutils | Inspect .deb internals | Debugging: extract control.tar and data.tar |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| nFPM | dpkg-deb + manual control files | nFPM handles conffiles, deps, scripts automatically from YAML |
| nFPM | fpm (Ruby) | fpm requires Ruby runtime; nFPM is a single Go binary |
| DESTDIR in scripts | Separate packaging overlay | In-place is simpler; user locked this decision |

**Installation:**
```bash
# nFPM via go install (Go is already present in the build environment)
go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.45.0

# Or download pre-built binary (for CI where Go may not be in PATH)
curl -sfL https://github.com/goreleaser/nfpm/releases/download/v2.45.0/nfpm_2.45.0_linux_amd64.tar.gz | tar xz -C /usr/local/bin nfpm
```

## Architecture Patterns

### Recommended Project Structure
```
packaging/
  nfpm/
    podman.yaml              # nFPM config for podman-podman
    crun.yaml                # nFPM config for podman-crun
    conmon.yaml              # nFPM config for podman-conmon
    netavark.yaml            # nFPM config for podman-netavark
    aardvark-dns.yaml        # nFPM config for podman-aardvark-dns
    pasta.yaml               # nFPM config for podman-pasta
    fuse-overlayfs.yaml      # nFPM config for podman-fuse-overlayfs
    catatonit.yaml           # nFPM config for podman-catatonit
    buildah.yaml             # nFPM config for podman-buildah
    skopeo.yaml              # nFPM config for podman-skopeo
    toolbox.yaml             # nFPM config for podman-toolbox
    container-configs.yaml   # nFPM config for podman-container-configs
    suite.yaml               # nFPM config for podman-suite meta-package
output/                      # Built .deb files (gitignored)
scripts/
  package_all.sh             # Packaging orchestrator script
```

### Pattern 1: DESTDIR Conditional Install
**What:** Modify install steps to prefix file destinations with DESTDIR when set, direct-install when unset.
**When to use:** Every build script's install step.
**Example:**
```bash
# For scripts using make install (podman, buildah, skopeo, crun, conmon, fuse-overlayfs, catatonit)
step_start "Installing"
if [[ -n "${DESTDIR:-}" ]]; then
    run_logged make install PREFIX=/usr DESTDIR="${DESTDIR}"
else
    run_logged sudo make install PREFIX=/usr
fi
step_done
```

```bash
# For scripts using raw cp (netavark, aardvark-dns, pasta)
step_start "Installing"
if [[ -n "${DESTDIR:-}" ]]; then
    install -D -m 0755 bin/netavark "${DESTDIR}/usr/bin/netavark"
    install -D -m 0755 bin/netavark-dhcp-proxy-client "${DESTDIR}/usr/bin/netavark-dhcp-proxy-client"
else
    sudo install -D -m 0755 bin/netavark /usr/bin/netavark
    sudo install -D -m 0755 bin/netavark-dhcp-proxy-client /usr/bin/netavark-dhcp-proxy-client
fi
step_done
```

```bash
# For toolbox (meson-based -- meson has native DESTDIR support)
step_start "Installing"
if [[ -n "${DESTDIR:-}" ]]; then
    DESTDIR="${DESTDIR}" run_logged meson install -C builddir
else
    run_logged meson install -C builddir
fi
step_done
```

### Pattern 2: nFPM Component Config
**What:** Standard YAML config for a binary component package.
**When to use:** All 11 binary component packages.
**Example:**
```yaml
# packaging/nfpm/netavark.yaml
name: podman-netavark
arch: "${ARCH}"
platform: linux
version: "${VERSION}"
version_schema: none
maintainer: "Podman Debian <maintainer@example.com>"
description: "Container network stack for Podman (compiled from source)"
vendor: "podman-debian"
homepage: "https://github.com/containers/netavark"
license: "Apache-2.0"
section: admin
priority: optional

depends:
  - podman-container-configs

conflicts:
  - netavark

replaces:
  - netavark

provides:
  - netavark

contents:
  - src: "${DESTDIR}/usr/bin/netavark"
    dst: /usr/bin/netavark
    file_info:
      mode: 0755
  - src: "${DESTDIR}/usr/bin/netavark-dhcp-proxy-client"
    dst: /usr/bin/netavark-dhcp-proxy-client
    file_info:
      mode: 0755
```

### Pattern 3: Config Package with conffiles
**What:** Package that installs configuration files to /etc/ with dpkg conffile protection.
**When to use:** podman-container-configs package only.
**Example:**
```yaml
# packaging/nfpm/container-configs.yaml
name: podman-container-configs
arch: "${ARCH}"
platform: linux
version: "${VERSION}"
version_schema: none
maintainer: "Podman Debian <maintainer@example.com>"
description: "Container configuration files for Podman ecosystem"
vendor: "podman-debian"
homepage: "https://github.com/containers/container-libs"
license: "Apache-2.0"
section: admin
priority: optional

conflicts:
  - golang-github-containers-common

replaces:
  - golang-github-containers-common

provides:
  - golang-github-containers-common

contents:
  # conffiles -- user modifications preserved on upgrade
  - src: "${DESTDIR}/etc/containers/containers.conf"
    dst: /etc/containers/containers.conf
    type: config
    file_info:
      mode: 0644
  - src: "${DESTDIR}/etc/containers/policy.json"
    dst: /etc/containers/policy.json
    type: config
    file_info:
      mode: 0644
  - src: "${DESTDIR}/etc/containers/registries.conf"
    dst: /etc/containers/registries.conf
    type: config
    file_info:
      mode: 0644
  - src: "${DESTDIR}/etc/containers/storage.conf"
    dst: /etc/containers/storage.conf
    type: config
    file_info:
      mode: 0644
  - src: "${DESTDIR}/etc/containers/registries.d/default.yaml"
    dst: /etc/containers/registries.d/default.yaml
    type: config
    file_info:
      mode: 0644
  # Data file -- NOT a conffile, overwritten on upgrade (upstream changes wanted)
  - src: "${DESTDIR}/usr/share/containers/seccomp.json"
    dst: /usr/share/containers/seccomp.json
    file_info:
      mode: 0644
```

### Pattern 4: Meta-Package (No Files)
**What:** Empty package that exists only to declare dependencies on all components.
**When to use:** podman-suite meta-package.
**Example:**
```yaml
# packaging/nfpm/suite.yaml
name: podman-suite
arch: "${ARCH}"
platform: linux
version: "${VERSION}"
version_schema: none
maintainer: "Podman Debian <maintainer@example.com>"
description: "Complete Podman container stack (meta-package)"
vendor: "podman-debian"
homepage: "https://github.com/your-repo/podman-debian"
license: "GPL-3.0"
section: admin
priority: optional

depends:
  - podman-podman
  - podman-crun
  - podman-conmon
  - podman-netavark
  - podman-aardvark-dns
  - podman-pasta
  - podman-fuse-overlayfs
  - podman-catatonit
  - podman-buildah
  - podman-skopeo
  - podman-toolbox
  - podman-container-configs

# No contents section -- meta-package has no files
```

### Pattern 5: Version Extraction
**What:** Extract clean version from GIT_CHECKED_OUT_TAG for nFPM.
**When to use:** Packaging orchestrator script.
**Example:**
```bash
extract_version() {
    local tag="$1"
    local component="$2"

    case "$component" in
        pasta)
            # Date-based: already numeric (e.g., 20250302)
            echo "${tag}"
            ;;
        container-configs)
            # Namespaced tag: common/v0.67.0 -> 0.67.0
            echo "${tag}" | sed 's|^.*/v||'
            ;;
        *)
            # Standard: strip v prefix (v5.5.2 -> 5.5.2)
            echo "${tag#v}"
            ;;
    esac
}

# Usage: VERSION=$(extract_version "$GIT_CHECKED_OUT_TAG" "podman")
# Then append suffix: VERSION="${VERSION}~podman1"
```

### Pattern 6: Packaging Orchestrator
**What:** Script that iterates all components, sets env vars, invokes nFPM.
**When to use:** The scripts/package_all.sh orchestrator.
**Example:**
```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_DIR="$(dirname "$SCRIPT_DIR")"
NFPM_DIR="${TOOL_DIR}/packaging/nfpm"
OUTPUT_DIR="${TOOL_DIR}/output"

mkdir -p "$OUTPUT_DIR"

# Architecture from existing config
source "${TOOL_DIR}/config.sh"

COMPONENTS=(
    "podman"
    "crun"
    "conmon"
    "netavark"
    "aardvark-dns"
    "pasta"
    "fuse-overlayfs"
    "catatonit"
    "buildah"
    "skopeo"
    "toolbox"
    "container-configs"
)

for component in "${COMPONENTS[@]}"; do
    echo ">>> Packaging: podman-${component}"

    config_file="${NFPM_DIR}/${component}.yaml"
    if [[ ! -f "$config_file" ]]; then
        echo "ERROR: nFPM config not found: $config_file" >&2
        exit 1
    fi

    # Version is read from a versions file or passed via env
    export VERSION="${PKG_VERSIONS[$component]}"
    export ARCH

    nfpm pkg \
        --config "$config_file" \
        --target "$OUTPUT_DIR" \
        --packager deb

    echo ">>> Done: podman-${component}"
done

# Build meta-package
echo ">>> Packaging: podman-suite"
export VERSION="${PKG_VERSIONS[podman]}"  # Use podman version for suite
nfpm pkg --config "${NFPM_DIR}/suite.yaml" --target "$OUTPUT_DIR" --packager deb
echo ">>> Done: podman-suite"
```

### Anti-Patterns to Avoid
- **Hardcoding /usr/local in install paths:** The project currently installs some binaries to /usr/local/bin (netavark, aardvark-dns, pasta). All must be standardized to /usr for Debian convention.
- **Using sudo with DESTDIR:** Staging to a user-owned directory never needs root. Conditional `sudo` must be removed when DESTDIR is set.
- **Forgetting version_schema:** Default is `semver` which fails on pasta's date-based versions. Always use `version_schema: none`.
- **Putting seccomp.json in conffiles:** seccomp.json is a data file under /usr/share/containers/, not a user-editable config. Do NOT use `type: config` for it.
- **Omitting Provides:** Without `provides: netavark`, other packages that `depends: netavark` (the official name) will not see our podman-netavark as satisfying that dependency.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| .deb package creation | Custom control/data tar assembly | nFPM YAML configs | nFPM handles conffiles, deps, maintainer scripts, compression correctly |
| Version parsing | Custom tag-to-version regex | extract_version function with case statement | Only 3 patterns (v-prefix, date, namespaced) -- simple switch is sufficient |
| Architecture detection | New detection logic | Existing `detect_architecture()` from functions.sh | Already returns `amd64`/`arm64` which maps directly to Debian arch names |
| DESTDIR staging | Custom copy scripts | `make install DESTDIR=` / `install -D -m` | Standard Unix convention supported by make, meson, and autotools natively |

**Key insight:** nFPM eliminates the need for hand-crafting debian/control, debian/conffiles, debian/rules, etc. A single YAML file per component replaces the entire debian/ directory structure.

## Common Pitfalls

### Pitfall 1: /usr/local vs /usr Prefix Mismatch
**What goes wrong:** Packages install binaries to /usr/local/bin but Debian convention expects /usr/bin. Other packages depending on standard paths cannot find binaries.
**Why it happens:** Current build scripts use /usr/local as the default prefix (netavark, aardvark-dns, pasta use raw `cp` to /usr/local/bin; fuse-overlayfs configures with `--prefix /usr/local`).
**How to avoid:** Audit every build script. For `make install`, set `PREFIX=/usr`. For raw `cp`, change destination to /usr/bin. For autotools, use `--prefix=/usr`. For meson, `--prefix /usr` is already set.
**Warning signs:** `dpkg -L podman-netavark` shows files in /usr/local instead of /usr.

### Pitfall 2: Conffiles Not Declared for /etc/ Files
**What goes wrong:** User edits /etc/containers/containers.conf, upgrades the package, and their changes are silently overwritten.
**Why it happens:** nFPM contents entries without `type: config` are treated as regular files. dpkg overwrites them without prompting.
**How to avoid:** Every file under /etc/ in the container-configs package MUST have `type: config` in the nFPM contents section. seccomp.json (under /usr/share/) must NOT have `type: config`.
**Warning signs:** `dpkg -c podman-container-configs.deb` shows files but `dpkg --info ... | grep conffiles` shows nothing under /etc/.

### Pitfall 3: Missing Conflicts/Replaces Causes dpkg File Conflicts
**What goes wrong:** `dpkg -i podman-netavark.deb` fails with "trying to overwrite '/usr/bin/netavark', which is also in package netavark".
**Why it happens:** Official Ubuntu package `netavark` owns /usr/bin/netavark. Without `conflicts: netavark` and `replaces: netavark`, dpkg refuses to overwrite.
**How to avoid:** Declare all three: conflicts, replaces, AND provides for every component that has a matching Ubuntu package.
**Warning signs:** dpkg -i errors mentioning file ownership conflicts.

### Pitfall 4: Semver Parsing Breaks Non-Standard Versions
**What goes wrong:** `nfpm pkg` fails with "could not parse version" for pasta (20250302) or container-libs (common/v0.67.0).
**Why it happens:** nFPM defaults to `version_schema: semver` which expects X.Y.Z format.
**How to avoid:** Set `version_schema: none` in ALL nFPM configs. This passes the version string through as-is. Ensure all versions start with a digit (strip `v` and namespace prefixes).
**Warning signs:** nfpm error output mentioning semver parsing failure.

### Pitfall 5: DESTDIR with sudo Creates Root-Owned Staging Tree
**What goes wrong:** `sudo make install DESTDIR=/tmp/staging` creates files owned by root. Subsequent nfpm pkg command fails because it cannot read the files (or packages with wrong ownership).
**Why it happens:** sudo elevates the entire command including DESTDIR writes.
**How to avoid:** When DESTDIR is set, never use sudo. The staging tree is a temporary user-space directory. Only direct-install mode (no DESTDIR) needs sudo.
**Warning signs:** Files in staging tree owned by root:root when the build runs as non-root user.

### Pitfall 6: Meson DESTDIR Requires Environment Variable Not Argument
**What goes wrong:** `meson install -C builddir --destdir=/tmp/staging` works in meson >= 0.57.0 but `DESTDIR=/tmp/staging meson install -C builddir` works everywhere.
**Why it happens:** The `--destdir` flag was added in meson 0.57.0; Ubuntu 24.04 ships meson 1.3.2 so both work, but using the environment variable is the standard POSIX approach consistent with make.
**How to avoid:** Use `DESTDIR="${DESTDIR}" meson install -C builddir` for consistency with make-based scripts.
**Warning signs:** Toolbox files not appearing in staging tree.

## Code Examples

### Complete DESTDIR Modification for netavark (cp-based script)
```bash
# Current (build_netavark.sh install step):
step_start "Installing"
cp bin/netavark /usr/local/bin/netavark
cp bin/netavark-dhcp-proxy-client /usr/local/bin/netavark-dhcp-proxy-client
step_done

# Modified:
step_start "Installing"
if [[ -n "${DESTDIR:-}" ]]; then
    install -D -m 0755 bin/netavark "${DESTDIR}/usr/bin/netavark"
    install -D -m 0755 bin/netavark-dhcp-proxy-client "${DESTDIR}/usr/bin/netavark-dhcp-proxy-client"
else
    sudo install -D -m 0755 bin/netavark /usr/bin/netavark
    sudo install -D -m 0755 bin/netavark-dhcp-proxy-client /usr/bin/netavark-dhcp-proxy-client
fi
step_done
```

### Complete DESTDIR Modification for podman (make-based script)
```bash
# Current (build_podman.sh):
step_start "Building"
run_logged make -j "$NPROC" GO="$GOPATH/go" GCFLAGS="${GO_GCFLAGS}" LDFLAGS="${GO_LDFLAGS}" BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr
step_done

step_start "Installing"
run_logged sudo make GO="$GOPATH/go" install PREFIX=/usr
step_done

# Modified:
step_start "Building"
run_logged make -j "$NPROC" GO="$GOPATH/go" GCFLAGS="${GO_GCFLAGS}" LDFLAGS="${GO_LDFLAGS}" BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr
step_done

step_start "Installing"
if [[ -n "${DESTDIR:-}" ]]; then
    run_logged make GO="$GOPATH/go" install PREFIX=/usr DESTDIR="${DESTDIR}"
else
    run_logged sudo make GO="$GOPATH/go" install PREFIX=/usr
fi
step_done
```

### nFPM CLI Invocation
```bash
# Build a single .deb package
VERSION="5.5.2~podman1" ARCH="amd64" \
    nfpm pkg \
    --config packaging/nfpm/podman.yaml \
    --target output/ \
    --packager deb
# Produces: output/podman-podman_5.5.2~podman1_amd64.deb

# Verify the built package
dpkg --info output/podman-podman_5.5.2~podman1_amd64.deb
dpkg -c output/podman-podman_5.5.2~podman1_amd64.deb
```

### Container-Configs DESTDIR Modification
```bash
# Current (install_container-configs.sh) uses raw install commands to /etc/containers
# Modified for DESTDIR:
step_start "Installing configuration files"

# Determine install prefix
local prefix="${DESTDIR:-}"

# Create directories (install -D handles this for files, but we need dirs for empty structure)
mkdir -p "${prefix}/etc/containers/registries.d"
mkdir -p "${prefix}/usr/share/containers"

# 1. containers.conf
install -m 0644 "${toolpath}/config/containers.conf" "${prefix}/etc/containers/containers.conf"

# 2. seccomp.json
install -m 0644 "${SECCOMP_SRC}" "${prefix}/usr/share/containers/seccomp.json"

# 3-6. Other config files
install -m 0644 "${BUILD_ROOT}/container-libs/image/default-policy.json" "${prefix}/etc/containers/policy.json"
install -m 0644 "${BUILD_ROOT}/container-libs/image/default.yaml" "${prefix}/etc/containers/registries.d/default.yaml"
install -m 0644 "${BUILD_ROOT}/container-libs/storage/storage.conf" "${prefix}/etc/containers/storage.conf"
install -m 0644 "${BUILD_ROOT}/container-libs/image/registries.conf" "${prefix}/etc/containers/registries.conf"
```

## Ubuntu Package Conflict Mapping

This is critical for PKG-02. The following table maps each podman-* package to the official Ubuntu Noble package it conflicts with.

| Our Package | Ubuntu Noble Package | Ubuntu Version | Exists? | Action |
|-------------|---------------------|----------------|---------|--------|
| podman-podman | `podman` | 4.9.3+ds1-1ubuntu0.2 | YES | Conflicts/Replaces/Provides |
| podman-crun | `crun` | (available) | YES | Conflicts/Replaces/Provides |
| podman-conmon | `conmon` | (available) | YES | Conflicts/Replaces/Provides |
| podman-netavark | `netavark` | (available) | YES | Conflicts/Replaces/Provides |
| podman-aardvark-dns | `aardvark-dns` | (available) | YES | Conflicts/Replaces/Provides |
| podman-pasta | `passt` | (available) | YES | Conflicts/Replaces/Provides (note: Ubuntu name is `passt`, not `pasta`) |
| podman-fuse-overlayfs | `fuse-overlayfs` | (available) | YES | Conflicts/Replaces/Provides |
| podman-catatonit | `catatonit` | (available) | YES | Conflicts/Replaces/Provides |
| podman-buildah | `buildah` | (available) | YES | Conflicts/Replaces/Provides |
| podman-skopeo | `skopeo` | (available) | YES | Conflicts/Replaces/Provides |
| podman-toolbox | `podman-toolbox` | 0.0.99.3+git... | YES | Conflicts/Replaces/Provides |
| podman-container-configs | `golang-github-containers-common` | 0.57.4+ds1-2ubuntu0.2 | YES | Conflicts/Replaces/Provides |
| podman-suite | (none) | - | NO | No conflict declarations needed |

**Confidence: MEDIUM** -- Package names confirmed via Ubuntu Noble package search and launchpad. The passt/pasta naming difference is notable: the upstream project is "passt" (the binary names are `passt` and `pasta`), and the Ubuntu package name is `passt`. Our podman-pasta package should declare `conflicts: passt`, `replaces: passt`, `provides: passt`.

### Dependency Tree for podman-podman

The podman-podman package should declare dependencies matching the runtime requirements:

```yaml
depends:
  - podman-crun
  - podman-conmon
  - podman-netavark
  - podman-aardvark-dns
  - podman-pasta
  - podman-fuse-overlayfs
  - podman-container-configs
```

Notes:
- catatonit is `Recommends` in Ubuntu's podman package, but we make it a hard dependency for complete stack
- buildah, skopeo, toolbox are NOT dependencies of podman-podman (they are independent tools)
- The podman-suite meta-package pulls in everything including buildah, skopeo, toolbox

## Build Script Audit: Install Step Categories

Each build script falls into one of these categories for DESTDIR modification:

### Category A: make install with PREFIX (supports DESTDIR natively)
| Script | Current Install | Modification Needed |
|--------|----------------|---------------------|
| build_podman.sh | `sudo make install PREFIX=/usr` | Add `DESTDIR="${DESTDIR}"`, conditional sudo |
| build_buildah.sh | `sudo make install` | Add `PREFIX=/usr DESTDIR="${DESTDIR}"`, conditional sudo |
| build_skopeo.sh | `sudo make install PREFIX=/usr` | Add `DESTDIR="${DESTDIR}"`, conditional sudo |
| build_crun.sh | `sudo make install` | Add `DESTDIR="${DESTDIR}"`, conditional sudo, add `--prefix=/usr` to configure |
| build_conmon.sh | `sudo make podman` | Investigate make target; add DESTDIR, conditional sudo |
| build_fuse-overlayfs.sh | `sudo make install` | Change `--prefix /usr/local` to `--prefix /usr`, add DESTDIR, conditional sudo |
| build_catatonit.sh | `sudo make install` | Add `DESTDIR="${DESTDIR}"`, conditional sudo, may need `--prefix=/usr` in configure |

### Category B: Raw cp commands (must switch to install -D)
| Script | Current Install | Files Installed |
|--------|----------------|-----------------|
| build_netavark.sh | `cp bin/netavark /usr/local/bin/` | netavark, netavark-dhcp-proxy-client |
| build_aardvark_dns.sh | `cp bin/aardvark-dns /usr/local/bin/` | aardvark-dns |
| build_pasta.sh | `cp passt /usr/local/bin/` + conditionals | passt, pasta, passt.avx2 (if exists), pasta.avx2 (if exists) |

### Category C: Meson-based (has native DESTDIR support)
| Script | Current Install | Modification Needed |
|--------|----------------|---------------------|
| build_toolbox.sh | `meson install -C builddir` | Set DESTDIR env var, conditional sudo not needed (meson handles) |

### Category D: Config file installer (custom script)
| Script | Current Install | Modification Needed |
|--------|----------------|---------------------|
| install_container-configs.sh | `install -m 0644` to /etc/ paths | Prefix all destinations with `${DESTDIR:-}` |

### Category E: Man page installer (custom script)
| Script | Current Install | Modification Needed |
|--------|----------------|---------------------|
| install_container-manpages.sh | `install -m 0644` to /usr/share/man/ | Prefix destinations with `${DESTDIR:-}`, man pages belong in podman-container-configs package |

## nFPM Configuration Reference

### Key nFPM Fields Used in This Phase

| Field | Purpose | Value Pattern |
|-------|---------|---------------|
| `name` | Package name | `podman-{component}` |
| `arch` | Debian architecture | `${ARCH}` (env var: amd64 or arm64) |
| `version` | Package version | `${VERSION}` (env var: e.g., 5.5.2~podman1) |
| `version_schema` | Version parsing mode | `none` (MUST use for non-semver support) |
| `platform` | Target OS | `linux` |
| `maintainer` | Package maintainer | Email format string |
| `description` | Package description | One-line summary |
| `section` | Debian archive section | `admin` |
| `priority` | Package priority | `optional` |
| `depends` | Runtime dependencies | List of package names |
| `conflicts` | Incompatible packages | Official Ubuntu package name |
| `replaces` | Packages we supersede | Official Ubuntu package name |
| `provides` | Virtual packages satisfied | Official Ubuntu package name |
| `contents` | Files to include | List of src/dst/type entries |
| `contents[].type` | File type | `config` for conffiles, omit for regular files |

### nFPM Environment Variable Expansion
nFPM expands `${VAR}` syntax in most string fields. The following env vars must be set before `nfpm pkg`:

- `VERSION` -- cleaned version with ~podman1 suffix (e.g., "5.5.2~podman1")
- `ARCH` -- Debian architecture (e.g., "amd64", "arm64")
- `DESTDIR` -- staging tree root (for src paths in contents)

### nFPM CLI Reference
```bash
# Package a single component
nfpm pkg --config <yaml-path> --target <output-dir> --packager deb

# nFPM infers packager from target extension when target is a filename
nfpm pkg --config packaging/nfpm/podman.yaml --target output/podman-podman.deb
```

## Discretion Recommendations

### DESTDIR Variable Naming
**Recommendation: Use `DESTDIR`** (not `INSTALL_ROOT`). Rationale: DESTDIR is the POSIX/GNU standard recognized by make, meson, CMake, and autotools. Using a non-standard name would require extra translation.

### Orchestrator Order of Operations
**Recommendation: Build all -> Stage all -> Package all.** Rationale: The existing setup.sh already builds all components sequentially. Adding DESTDIR makes each build script stage its files. A separate package_all.sh then runs nFPM for each component. This keeps build logic and packaging logic cleanly separated. The build scripts don't need to know about nFPM, and the packager doesn't need to know about compilation.

### Orchestrator Error Handling
**Recommendation: Fail-fast with component name in error.** Follow the existing `set -euo pipefail` + `error_handler` trap pattern. If any component fails to package, stop immediately and report which component failed. The packaging step is fast (nFPM is < 1 second per package), so fail-fast is appropriate.

### Meta-Package Version
**Recommendation: Use the podman component version for podman-suite.** The meta-package has no files, so its version is somewhat arbitrary. Using podman's version makes intuitive sense since podman is the primary component.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| fpm (Ruby-based) | nFPM (Go binary) | nFPM v1.0 ~2019 | No Ruby dependency, single binary, YAML config |
| dpkg-buildpackage | nFPM for binary wrapping | N/A | We wrap pre-built binaries, not building from source packages |
| `version_schema: semver` | `version_schema: none` | nFPM v2 | Required for non-semver versions like pasta dates |
| Manual conffiles file | `type: config` in contents | nFPM v2 | nFPM auto-generates conffiles list from type annotations |

## Open Questions

1. **conmon `make podman` target behavior with DESTDIR**
   - What we know: conmon's Makefile has a `podman` install target that's different from `install`
   - What's unclear: Whether `make podman DESTDIR=...` works correctly or if we need `make install DESTDIR=...`
   - Recommendation: Test during implementation. If `make podman` doesn't support DESTDIR, switch to `make install DESTDIR=...` with appropriate PREFIX

2. **Exact file list for podman `make install PREFIX=/usr`**
   - What we know: Installs binaries (podman, podman-remote, podmansh), man pages (podman*.1, quadlet.5), systemd units, libexec files (quadlet, rootlessport)
   - What's unclear: Complete exhaustive file list from the Makefile
   - Recommendation: Run `make install PREFIX=/usr DESTDIR=/tmp/test-staging` on a build system and inspect the tree. The nFPM contents section must enumerate every file.

3. **pasta/passt avx2 variant binaries**
   - What we know: Build produces optional passt.avx2 and pasta.avx2 binaries (conditional on CPU support)
   - What's unclear: Whether the avx2 variants should be included in the .deb package
   - Recommendation: Include them conditionally. If they exist in the staging tree, add them to the nFPM config. Since nFPM doesn't support conditional contents natively, the orchestrator may need to generate or modify the YAML before packaging, or simply always include them (nFPM errors if src file doesn't exist).

4. **containers.conf helper_binaries_dir path update**
   - What we know: Current containers.conf references `/usr/local/bin` in helper_binaries_dir
   - What's unclear: When standardizing to /usr, this path must be updated
   - Recommendation: Update the config/containers.conf file to remove /usr/local references since all binaries will be in /usr/bin

## Sources

### Primary (HIGH confidence)
- nFPM official documentation: https://nfpm.goreleaser.com/docs/configuration/ -- configuration fields, env var substitution, type: config
- nFPM GitHub: https://github.com/goreleaser/nfpm -- v2.45.0 release, go install command
- GNU DESTDIR standard: https://www.gnu.org/prep/standards/html_node/DESTDIR.html -- DESTDIR convention
- Meson DESTDIR: https://mesonbuild.com/Installing.html -- native DESTDIR support
- Debian Policy conffiles: https://www.debian.org/doc/debian-policy/ap-pkg-conffiles.html -- conffile behavior

### Secondary (MEDIUM confidence)
- Ubuntu Noble packages: https://launchpad.net/ubuntu/noble/+package/podman -- podman 4.9.3, package names confirmed
- Ubuntu Noble package search: https://packages.ubuntu.com -- individual package existence confirmed
- Debian version tilde convention: https://manpages.ubuntu.com/manpages/xenial/man5/deb-version.5.html -- tilde sorts lower
- nFPM conffiles discussion: https://github.com/goreleaser/nfpm/discussions/591 -- type: config generates conffiles entry

### Tertiary (LOW confidence)
- alvistack podman-* naming: http://download.opensuse.org/repositories/home:/alvistack/xUbuntu_24.04/ -- precedent for podman-* prefix pattern (not verified directly)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - nFPM is well-documented, version confirmed, all required features verified
- Architecture: HIGH - DESTDIR is a standard Unix convention, nFPM YAML patterns verified against official docs
- Pitfalls: HIGH - Conffiles, conflicts, and version parsing are well-documented Debian packaging concerns
- Ubuntu package mapping: MEDIUM - Package names confirmed via launchpad/packages.ubuntu.com but exact file lists not verified

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (30 days -- nFPM and Debian packaging conventions are stable)
