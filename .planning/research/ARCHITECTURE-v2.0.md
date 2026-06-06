# Architecture Research: v2.0 APT Packaging & CI/CD Integration

**Domain:** Debian packaging, CI/CD automation, APT repository distribution for existing Podman-from-source build system
**Researched:** 2026-03-04
**Confidence:** HIGH (existing build system fully analyzed, Debian packaging and GitHub Actions patterns well-documented)

## System Overview

### Current Architecture (v1.2)

```
setup.sh (orchestrator)
    |
    +-- config.sh + functions.sh (shared config/utilities)
    |
    +-- scripts/install_dependencies.sh   (apt packages)
    +-- scripts/install_rust.sh           (Rust toolchain)
    +-- scripts/install_protoc.sh         (protoc binary)
    +-- scripts/install_go.sh             (Go toolchain)
    +-- scripts/build_*.sh (x12)          (clone -> build -> install to /usr or /usr/local)
    +-- scripts/install_container-*.sh    (config files + man pages)
    |
    +-- uninstall.sh                      (reverse of install)
```

**Current output:** Binaries, libraries, config files, and man pages installed directly to system paths (`/usr/bin`, `/usr/local/bin`, `/etc/containers`, `/usr/share/`).

### v2.0 Target Architecture

```
+===========================================================================+
|                     GitHub Actions CI/CD Layer                             |
|                                                                           |
|  schedule (cron) / workflow_dispatch (manual)                             |
|       |                                                                   |
|       v                                                                   |
|  .github/workflows/                                                       |
|  +-- check-upstream.yml         (detect new upstream tags)                |
|  +-- build-packages.yml         (matrix: component x arch)               |
|  +-- update-repo.yml            (reprepro + deploy to Pages)             |
|                                                                           |
+===========================+===============================================+
                            |
                            v
+===========================+===============================================+
|                     Build & Package Layer                                  |
|                                                                           |
|  For each component (matrix):                                             |
|  1. Run existing build_*.sh  -->  make install DESTDIR=<staging>          |
|  2. Package staging dir      -->  dpkg-deb --build --> .deb               |
|                                                                           |
|  debian/ metadata per component:                                          |
|  +-- debian/<component>/DEBIAN/control                                    |
|  +-- debian/<component>/DEBIAN/postinst (optional)                        |
|  +-- debian/<component>/DEBIAN/postrm (optional)                          |
|                                                                           |
+===========================+===============================================+
                            |
                            v
+===========================+===============================================+
|                     APT Repository Layer (GitHub Pages)                    |
|                                                                           |
|  repo/                                                                    |
|  +-- dists/noble/main/binary-amd64/Packages.gz                           |
|  +-- dists/noble/main/binary-arm64/Packages.gz                            |
|  +-- dists/noble/Release  (signed)                                        |
|  +-- dists/noble/Release.gpg                                              |
|  +-- dists/noble/InRelease                                                |
|  +-- pool/main/p/podman-podman/podman-podman_5.5.2-1_amd64.deb           |
|  +-- pool/main/p/podman-crun/podman-crun_1.25.1-1_amd64.deb              |
|  +-- ...                                                                  |
|  +-- pubkey.gpg                                                           |
|                                                                           |
+===========================================================================+
```

## Integration Points: Existing to New

### What Changes vs What Stays

| Existing Component | Change Type | Details |
|---|---|---|
| `config.sh` | **Modify** | Add `DESTDIR` support, `PACKAGE_VERSION` vars, package naming prefix |
| `functions.sh` | **Modify** | Add `package_component()` helper function |
| `scripts/build_*.sh` | **Modify** | Replace `make install` with `make install DESTDIR=<staging>`, replace `cp` with staged copies |
| `setup.sh` | **No change** | Still works for direct installs; packaging workflow calls build scripts individually |
| `uninstall.sh` | **No change** | Users with .deb packages use `apt remove` instead |
| `scripts/install_container-configs.sh` | **Modify** | Support DESTDIR staging for packaging |
| `scripts/install_container-manpages.sh` | **Modify** | Support DESTDIR staging for packaging |

### New Components

| New Component | Purpose |
|---|---|
| `debian/` directory tree | DEBIAN/control files per component |
| `scripts/package_component.sh` | Wraps dpkg-deb --build for a single component |
| `scripts/check_upstream.sh` | Checks upstream repos for new release tags |
| `.github/workflows/check-upstream.yml` | Scheduled cron job to detect new versions |
| `.github/workflows/build-packages.yml` | Matrix build: component x architecture |
| `.github/workflows/update-repo.yml` | Generates APT repo metadata, deploys to Pages |
| `repo/conf/distributions` | reprepro configuration |

## Recommended Project Structure (New Files)

```
podman-debian/
+-- (existing files unchanged)
|
+-- debian/                              # Package metadata per component
|   +-- podman-podman/
|   |   +-- DEBIAN/
|   |       +-- control                  # Package: podman-podman, Depends, Conflicts, etc.
|   |       +-- postinst                 # Post-install script (optional)
|   |       +-- postrm                   # Post-removal script (optional)
|   +-- podman-crun/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-conmon/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-netavark/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-aardvark-dns/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-buildah/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-skopeo/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-pasta/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-fuse-overlayfs/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-catatonit/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-toolbox/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-go-md2man/
|   |   +-- DEBIAN/
|   |       +-- control
|   +-- podman-container-configs/
|       +-- DEBIAN/
|           +-- control
|           +-- postinst                 # Create dirs, set permissions
|           +-- postrm                   # Clean up dirs on purge
|
+-- scripts/
|   +-- package_component.sh            # NEW: dpkg-deb wrapper
|   +-- check_upstream.sh               # NEW: Version comparison
|
+-- .github/
|   +-- workflows/
|       +-- check-upstream.yml          # Scheduled upstream check
|       +-- build-packages.yml          # Build + package (reusable)
|       +-- update-repo.yml             # APT repo update + deploy
|
+-- repo/                               # APT repository (gh-pages branch)
|   +-- conf/
|   |   +-- distributions               # reprepro config
|   +-- pubkey.gpg                      # Public GPG key for apt
```

### Structure Rationale

- **debian/ at project root:** Keeps packaging metadata separate from build logic. Each component gets its own subdirectory mirroring the `podman-*` package name.
- **DEBIAN/ not debian/:** We use `dpkg-deb --build` (binary packaging) not `dpkg-buildpackage` (source packaging). Binary packaging uses uppercase `DEBIAN/`. This is the right approach because we already have a custom build system -- we just need to wrap the output into .deb format.
- **repo/ on gh-pages branch:** The APT repository content lives on the `gh-pages` branch, not in `main`. The `repo/conf/` directory with reprepro config can live in `main` as a template.
- **.github/workflows/ with three files:** Clear separation of concerns -- detection, building, and publishing are independent workflow steps connected by `workflow_dispatch` or `workflow_call`.

## Component Catalog: Package Definitions

### Package Map

Each existing build script maps to exactly one .deb package. The table below shows the critical details for each package.

| Package Name | Build Script | Build System | Install Prefix | Key Files Installed | Conflicts/Replaces |
|---|---|---|---|---|---|
| `podman-podman` | `build_podman.sh` | Go (make) | `/usr` | `/usr/bin/podman`, `/usr/libexec/podman/`, man pages, systemd units | `podman` |
| `podman-buildah` | `build_buildah.sh` | Go (make) | `/usr` | `/usr/bin/buildah`* (check), man pages | `buildah` |
| `podman-skopeo` | `build_skopeo.sh` | Go (make) | `/usr` | `/usr/bin/skopeo`, man pages | `skopeo` |
| `podman-conmon` | `build_conmon.sh` | Go (make) | `/usr/local` | `/usr/local/bin/conmon` | `conmon` |
| `podman-crun` | `build_crun.sh` | C (autotools) | `/usr/local` | `/usr/local/bin/crun`, man pages | `crun` |
| `podman-netavark` | `build_netavark.sh` | Rust (cargo/make) | `/usr/local` | `/usr/local/bin/netavark`, `/usr/local/bin/netavark-dhcp-proxy-client` | `netavark` |
| `podman-aardvark-dns` | `build_aardvark_dns.sh` | Rust (cargo/make) | `/usr/local` | `/usr/local/bin/aardvark-dns` | `aardvark-dns` |
| `podman-pasta` | `build_pasta.sh` | C (make) | `/usr/local` | `/usr/local/bin/passt`, `/usr/local/bin/pasta`, `.avx2` variants | `passt` |
| `podman-fuse-overlayfs` | `build_fuse-overlayfs.sh` | C (autotools) | `/usr/local` | `/usr/local/bin/fuse-overlayfs`, man pages | `fuse-overlayfs` |
| `podman-catatonit` | `build_catatonit.sh` | C (autotools) | `/usr/local` | `/usr/local/bin/catatonit` | `catatonit` |
| `podman-toolbox` | `build_toolbox.sh` | Go (meson) | `/usr` | `/usr/bin/toolbox`, configs, man pages | `toolbox` |
| `podman-go-md2man` | `build_go-md2man.sh` | Go (make) | `/usr/local` | `/usr/local/bin/go-md2man` | `go-md2man` |
| `podman-container-configs` | `install_container-configs.sh` + `install_container-manpages.sh` | Configs + man pages | `/etc`, `/usr/share` | seccomp.json, policy.json, registries.conf, storage.conf, containers.conf, man5 pages | `containers-common` |

### Inter-Package Dependencies

```
podman-podman
    Depends: podman-conmon, podman-crun, podman-netavark,
             podman-aardvark-dns, podman-pasta, podman-catatonit,
             podman-container-configs, podman-fuse-overlayfs,
             iptables, libseccomp2, libgpgme11, libapparmor1
    Recommends: podman-buildah, podman-skopeo

podman-buildah
    Depends: podman-container-configs, libseccomp2, libgpgme11
    Recommends: podman-podman

podman-skopeo
    Depends: podman-container-configs, libgpgme11

podman-netavark
    Depends: (none -- static binary)

podman-aardvark-dns
    Depends: (none -- static binary)

podman-crun
    Depends: libseccomp2

podman-conmon
    Depends: (none)

podman-pasta
    Depends: (none)

podman-fuse-overlayfs
    Depends: libfuse3-3

podman-catatonit
    Depends: (none)

podman-toolbox
    Depends: podman-podman

podman-go-md2man
    Depends: (none -- build tool only)

podman-container-configs
    Depends: (none)
```

## Architectural Patterns

### Pattern 1: DESTDIR Staging for Package Creation

**What:** Instead of installing directly to system paths, build scripts install to a temporary staging directory that mirrors the filesystem layout. The staging directory becomes the .deb package content.

**When to use:** Every build script that installs files to the system.

**Trade-offs:**
- Pros: Clean separation between building and installing; same scripts work for both direct install and packaging
- Cons: Requires modifying every build script's install step

**How to modify existing scripts:**

Most build scripts use `make install` or `cp`. The modification is straightforward:

```bash
# Current: build_podman.sh
run_logged sudo make GO="$GOPATH/go" install PREFIX=/usr

# Modified for packaging support:
if [[ -n "${DESTDIR:-}" ]]; then
    run_logged make GO="$GOPATH/go" install PREFIX=/usr DESTDIR="${DESTDIR}"
else
    run_logged sudo make GO="$GOPATH/go" install PREFIX=/usr
fi
```

For scripts that use `cp` directly (netavark, aardvark-dns, pasta, go-md2man):

```bash
# Current: build_netavark.sh
cp bin/netavark /usr/local/bin/netavark

# Modified:
INSTALL_PREFIX="${DESTDIR:-}/usr/local"
mkdir -p "${INSTALL_PREFIX}/bin"
cp bin/netavark "${INSTALL_PREFIX}/bin/netavark"
```

**Key detail:** Most Makefiles in the containers/ ecosystem already support `DESTDIR`. The Go `make install` targets (`podman`, `buildah`, `skopeo`) pass it through. The autotools builds (`crun`, `fuse-overlayfs`, `catatonit`) support it natively. Only the manual `cp` installs need wrapper logic.

### Pattern 2: dpkg-deb Binary Packaging (Not dpkg-buildpackage)

**What:** Use `dpkg-deb --build --root-owner-group` to create .deb packages directly from a staged filesystem tree, rather than using the full Debian source packaging toolchain (`dpkg-buildpackage`, `debuild`, `pbuilder`).

**When to use:** When you already have a custom build system and just need to wrap the output into .deb format.

**Trade-offs:**
- Pros: Simple, minimal dependencies, works with existing build scripts, no need for debian/rules or debian/changelog in Debian source format
- Cons: Not suitable for official Debian archive submission (not needed for personal APT repo), no source package generated

**Example `scripts/package_component.sh`:**

```bash
#!/bin/bash
set -euo pipefail

# Usage: package_component.sh <component-name> <version> <architecture>
# Example: package_component.sh podman-podman 5.5.2 amd64

COMPONENT="$1"
VERSION="$2"
ARCH="$3"

PACKAGE_DIR="/tmp/packaging/${COMPONENT}_${VERSION}-1_${ARCH}"
DEBIAN_TEMPLATE="${toolpath}/debian/${COMPONENT}/DEBIAN"

# Create package directory structure
mkdir -p "${PACKAGE_DIR}/DEBIAN"

# Copy control file with version/arch substitution
sed -e "s/@VERSION@/${VERSION}/g" \
    -e "s/@ARCH@/${ARCH}/g" \
    "${DEBIAN_TEMPLATE}/control" > "${PACKAGE_DIR}/DEBIAN/control"

# Copy maintainer scripts if present
for script in postinst preinst postrm prerm; do
    if [[ -f "${DEBIAN_TEMPLATE}/${script}" ]]; then
        install -m 0755 "${DEBIAN_TEMPLATE}/${script}" "${PACKAGE_DIR}/DEBIAN/${script}"
    fi
done

# Build scripts install to this directory via DESTDIR
export DESTDIR="${PACKAGE_DIR}"

# Run the build script (which uses DESTDIR)
source "${toolpath}/scripts/build_${COMPONENT#podman-}.sh"

# Build the .deb
dpkg-deb --build --root-owner-group "${PACKAGE_DIR}"

# Move to output directory
mkdir -p "${toolpath}/output"
mv "${PACKAGE_DIR}.deb" "${toolpath}/output/"
```

### Pattern 3: DEBIAN/control Template with Variable Substitution

**What:** Store control files with placeholder variables (`@VERSION@`, `@ARCH@`) that get substituted at build time.

**When to use:** Every component package.

**Example `debian/podman-podman/DEBIAN/control`:**

```
Package: podman-podman
Version: @VERSION@-1
Architecture: @ARCH@
Maintainer: Your Name <your@email.com>
Section: admin
Priority: optional
Depends: podman-conmon, podman-crun, podman-netavark, podman-aardvark-dns, podman-pasta, podman-catatonit, podman-container-configs, podman-fuse-overlayfs, iptables, libseccomp2, libgpgme11, libapparmor1
Conflicts: podman
Replaces: podman
Provides: podman
Description: Podman - manage pods, containers and images (compiled from source)
 A tool for managing OCI containers and pods, compiled from latest
 upstream source. Includes rootless container support.
```

**Key fields explained:**
- `Conflicts: podman` -- Cannot coexist with Ubuntu's `podman` package
- `Replaces: podman` -- Can overwrite files from Ubuntu's `podman` package
- `Provides: podman` -- Satisfies other packages that depend on `podman`

### Pattern 4: Reusable GitHub Actions Workflows with Matrix Strategy

**What:** Use `workflow_call` for reusable workflows and matrix strategy for cross-architecture builds.

**When to use:** The build-packages workflow.

**Example `.github/workflows/build-packages.yml`:**

```yaml
name: Build Packages

on:
  workflow_dispatch:
    inputs:
      components:
        description: 'Comma-separated components to build (or "all")'
        default: 'all'
  workflow_call:
    inputs:
      components:
        type: string
        default: 'all'

jobs:
  build:
    strategy:
      matrix:
        arch: [amd64, arm64]
        include:
          - arch: amd64
            runner: ubuntu-24.04
          - arch: arm64
            runner: ubuntu-24.04-arm
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4
      - name: Install build dependencies
        run: |
          sudo apt-get update
          sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            build-essential git pkg-config libseccomp-dev \
            libgpgme-dev libapparmor-dev libsystemd-dev \
            libfuse3-dev libbtrfs-dev go-md2man autoconf \
            automake libtool libcap-dev meson
      - name: Install toolchains
        run: |
          source ./config.sh
          source ./scripts/install_go.sh
          source ./scripts/install_rust.sh
          source ./scripts/install_protoc.sh
      - name: Build and package components
        run: |
          # For each component, build with DESTDIR and package
          for component in podman-crun podman-conmon ...; do
            ./scripts/package_component.sh "$component" "$VERSION" "${{ matrix.arch }}"
          done
      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: debs-${{ matrix.arch }}
          path: output/*.deb
```

**Runner selection:** GitHub now offers native `ubuntu-24.04-arm` runners (GA since August 2025, available in private repos since January 2026). Use native runners, not QEMU emulation. QEMU is 3-10x slower and can produce incorrect results for complex builds like Rust and Go compilation.

### Pattern 5: APT Repository via reprepro + GitHub Pages

**What:** Use reprepro to manage the APT repository structure and deploy via GitHub Pages.

**When to use:** The update-repo workflow, after all packages are built.

**`repo/conf/distributions` configuration:**

```
Origin: podman-debian
Label: podman-debian
Codename: noble
Suite: stable
Architectures: amd64 arm64
Components: main
Description: Podman compiled from latest upstream source for Ubuntu 24.04
SignWith: <GPG-KEY-FINGERPRINT>
```

**Example `.github/workflows/update-repo.yml`:**

```yaml
name: Update APT Repository

on:
  workflow_call:
  workflow_dispatch:

permissions:
  pages: write
  contents: write
  id-token: write

jobs:
  update-repo:
    runs-on: ubuntu-24.04
    environment:
      name: github-pages
    steps:
      - uses: actions/checkout@v4
        with:
          ref: gh-pages

      - name: Download all .deb artifacts
        uses: actions/download-artifact@v4
        with:
          path: incoming/
          pattern: debs-*
          merge-multiple: true

      - name: Import GPG key
        run: |
          echo "${{ secrets.GPG_PRIVATE_KEY }}" | gpg --batch --import
          echo "${{ secrets.GPG_PASSPHRASE }}" | gpg --batch --yes --passphrase-fd 0 ...

      - name: Update repository with reprepro
        run: |
          sudo apt-get install -y reprepro
          for deb in incoming/*.deb; do
            reprepro -b repo/ includedeb noble "$deb"
          done

      - name: Deploy to GitHub Pages
        uses: actions/deploy-pages@v4
        with:
          artifact_name: repo
```

## Data Flow

### End-to-End Build Pipeline

```
[Scheduled Cron / Manual Trigger]
        |
        v
[check-upstream.yml]
  - For each component:
    curl GitHub API -> get latest tag
    Compare with last-built version (stored in repo metadata or git tags)
  - If any component has new version:
        |
        v
[build-packages.yml] (triggered via workflow_dispatch)
  - Matrix: [component] x [amd64, arm64]
  - Per job:
    1. Checkout podman-debian repo
    2. Install system deps (apt)
    3. Install toolchains (Go, Rust, protoc)
    4. Run build_*.sh with DESTDIR=/tmp/staging
    5. Copy DEBIAN/control (with version substitution) into staging
    6. dpkg-deb --build --root-owner-group /tmp/staging
    7. Upload .deb as GitHub Actions artifact
        |
        v
[update-repo.yml] (triggered after build-packages completes)
  1. Download all .deb artifacts
  2. Import GPG signing key from secrets
  3. Run reprepro includedeb for each .deb
  4. Commit and push to gh-pages branch
  5. GitHub Pages serves the APT repository
        |
        v
[End User]
  sudo curl -fsSL https://<user>.github.io/podman-debian/pubkey.gpg | sudo apt-key add -
  echo "deb https://<user>.github.io/podman-debian noble main" | \
    sudo tee /etc/apt/sources.list.d/podman-debian.list
  sudo apt update && sudo apt install podman-podman
```

### Version Detection Flow

```
[check-upstream.yml - runs on cron schedule, e.g., daily]
        |
        v
[For each upstream repo (containers/podman, containers/crun, etc.)]
  - Call: curl -s https://api.github.com/repos/<owner>/<repo>/releases/latest
  - Parse: jq -r '.tag_name'
  - Compare with: stored version in versions.json or git tag in this repo
        |
        +-- No new versions --> Exit (no build triggered)
        |
        +-- New version(s) found:
            - Update versions.json
            - Trigger build-packages.yml via repository_dispatch or workflow_dispatch
            - Pass changed components as input
```

### DESTDIR Integration Flow (per component)

```
[build_*.sh called with DESTDIR set]
        |
        v
[git clone + checkout tag] (unchanged)
        |
        v
[make / cargo build] (unchanged -- compilation is identical)
        |
        v
[make install DESTDIR=$DESTDIR PREFIX=/usr]
  Instead of:  /usr/bin/podman
  Installs to: $DESTDIR/usr/bin/podman
        |
        v
[DEBIAN/control copied into $DESTDIR/DEBIAN/]
        |
        v
[dpkg-deb --build --root-owner-group $DESTDIR]
        |
        v
[Output: podman-podman_5.5.2-1_amd64.deb]
```

## GPG Key Management

### Where Keys Live

| Key Type | Location | Purpose |
|---|---|---|
| GPG private key | GitHub Actions secret `GPG_PRIVATE_KEY` | Sign Release and InRelease files |
| GPG passphrase | GitHub Actions secret `GPG_PASSPHRASE` | Unlock private key during signing |
| GPG public key | `repo/pubkey.gpg` on gh-pages branch | Users download this to verify packages |

### Key Generation (One-Time Setup)

```bash
# Generate a dedicated key (no passphrase for CI, or use passphrase with secrets)
gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: Podman Debian Compiler
Name-Email: podman-debian@example.com
Expire-Date: 2y
%no-protection
EOF

# Export private key (store as GitHub secret)
gpg --export-secret-keys --armor <KEY-ID> > private.key

# Export public key (commit to repo)
gpg --export --armor <KEY-ID> > pubkey.gpg
```

### Key Rotation

Set key expiration to 2 years. When rotating:
1. Generate new key
2. Update GitHub secret
3. Update `pubkey.gpg` on gh-pages
4. Re-sign all packages with new key
5. Users must re-import the new public key

## GitHub Pages APT Repository Structure

### Target Layout (gh-pages branch)

```
/                                          # GitHub Pages root
+-- index.html                            # Optional: instructions page
+-- pubkey.gpg                            # Public GPG key
+-- dists/
|   +-- noble/                            # Ubuntu 24.04 codename
|       +-- main/
|       |   +-- binary-amd64/
|       |   |   +-- Packages
|       |   |   +-- Packages.gz
|       |   |   +-- Release
|       |   +-- binary-arm64/
|       |       +-- Packages
|       |       +-- Packages.gz
|       |       +-- Release
|       +-- Release                       # Signed release metadata
|       +-- Release.gpg                   # Detached signature
|       +-- InRelease                     # Inline-signed release
+-- pool/
|   +-- main/
|       +-- p/
|       |   +-- podman-podman/
|       |   |   +-- podman-podman_5.5.2-1_amd64.deb
|       |   |   +-- podman-podman_5.5.2-1_arm64.deb
|       |   +-- podman-pasta/
|       |       +-- podman-pasta_20260304-1_amd64.deb
|       |       +-- podman-pasta_20260304-1_arm64.deb
|       +-- c/
|           +-- podman-crun/
|           |   +-- podman-crun_1.25.1-1_amd64.deb
|           |   +-- podman-crun_1.25.1-1_arm64.deb
|           +-- podman-conmon/
|           |   +-- podman-conmon_2.1.13-1_amd64.deb
|           |   +-- podman-conmon_2.1.13-1_arm64.deb
|           +-- podman-catatonit/
|           |   +-- podman-catatonit_0.2.0-1_amd64.deb
|           |   +-- podman-catatonit_0.2.0-1_arm64.deb
|           +-- podman-container-configs/
|               +-- podman-container-configs_0.67.0-1_all.deb
+-- db/                                   # reprepro internal database
+-- conf/
    +-- distributions                     # reprepro config (can be on main branch too)
```

**Note on `podman-container-configs`:** This package should be `Architecture: all` since it contains only config files and man pages, not architecture-specific binaries.

### GitHub Pages Limits

| Limit | Value | Impact |
|---|---|---|
| Repository size | 1 GB soft limit | ~13 packages x 2 arches x ~5MB avg = ~130MB per release. Keep 3-4 releases max. |
| Bandwidth | 100 GB/month | Sufficient for personal/small team use (~2000 downloads/month) |
| Build time | 10 min | reprepro runs fast; not a concern |

## Upstream Version Detection

### Component-to-Repository Mapping

```bash
# versions.json -- tracks last-built versions
{
  "podman":         { "repo": "containers/podman",         "tag_prefix": "v"  },
  "buildah":        { "repo": "containers/buildah",        "tag_prefix": "v"  },
  "skopeo":         { "repo": "containers/skopeo",         "tag_prefix": "v"  },
  "conmon":         { "repo": "containers/conmon",         "tag_prefix": "v"  },
  "crun":           { "repo": "containers/crun",           "tag_prefix": ""   },
  "netavark":       { "repo": "containers/netavark",       "tag_prefix": "v"  },
  "aardvark-dns":   { "repo": "containers/aardvark-dns",   "tag_prefix": "v"  },
  "fuse-overlayfs": { "repo": "containers/fuse-overlayfs", "tag_prefix": "v"  },
  "catatonit":      { "repo": "openSUSE/catatonit",        "tag_prefix": "v"  },
  "toolbox":        { "repo": "containers/toolbox",        "tag_prefix": ""   },
  "go-md2man":      { "repo": "cpuguy83/go-md2man",        "tag_prefix": "v"  },
  "container-libs": { "repo": "containers/container-libs", "tag_prefix": "common/v" },
  "pasta":          { "repo": null, "note": "passt uses date-based versions, check git HEAD" }
}
```

**Special cases:**
- `container-libs` uses namespaced tags (`common/vX.Y.Z`). Only `common/*` tags are relevant.
- `pasta/passt` does not use GitHub releases. Use `git ls-remote git://passt.top/passt` and compare HEAD or check for new date-tagged builds.
- `crun` tags do NOT have a `v` prefix (e.g., `1.25.1` not `v1.25.1`).

### Detection Strategy

```yaml
# check-upstream.yml
on:
  schedule:
    - cron: '0 6 * * *'   # Daily at 6 AM UTC
  workflow_dispatch:       # Manual trigger

jobs:
  check:
    runs-on: ubuntu-24.04
    outputs:
      changed: ${{ steps.check.outputs.changed }}
      components: ${{ steps.check.outputs.components }}
    steps:
      - uses: actions/checkout@v4
      - name: Check upstream versions
        id: check
        run: |
          changed=""
          # For each component in versions.json:
          for component in $(jq -r 'keys[]' versions.json); do
            repo=$(jq -r ".${component}.repo" versions.json)
            [[ "$repo" == "null" ]] && continue

            latest=$(curl -s "https://api.github.com/repos/${repo}/releases/latest" \
                     | jq -r '.tag_name')
            current=$(jq -r ".${component}.current // empty" versions.json)

            if [[ "$latest" != "$current" ]]; then
              changed="${changed},${component}"
              # Update versions.json
              jq ".${component}.current = \"${latest}\"" versions.json > tmp && mv tmp versions.json
            fi
          done

          if [[ -n "$changed" ]]; then
            echo "changed=true" >> "$GITHUB_OUTPUT"
            echo "components=${changed#,}" >> "$GITHUB_OUTPUT"
          else
            echo "changed=false" >> "$GITHUB_OUTPUT"
          fi

  trigger-build:
    needs: check
    if: needs.check.outputs.changed == 'true'
    uses: ./.github/workflows/build-packages.yml
    with:
      components: ${{ needs.check.outputs.components }}
```

## Build Order for Packaging

The packaging workflow does NOT need to follow the same sequential build order as `setup.sh` because packages are built independently. However, **within a single runner**, toolchains must be installed before components that need them.

### Per-Runner Build Sequence

```
1. Install apt build dependencies (once)
2. Install Go toolchain (once)
3. Install Rust toolchain (once)
4. Install protoc (once)
5. For each component assigned to this runner:
   a. Run build script with DESTDIR
   b. Run package_component.sh
   c. Upload .deb artifact
```

### Optimal Matrix Strategy

Group components by their primary build toolchain to minimize setup overhead:

| Group | Components | Required Toolchains |
|---|---|---|
| Go group | podman, buildah, skopeo, conmon, toolbox, go-md2man, container-libs | Go |
| Rust group | netavark, aardvark-dns | Rust |
| C group | crun, fuse-overlayfs, catatonit, pasta | GCC, autotools |
| Config group | container-configs | Go (for seccomp.json generation), go-md2man |

However, for simplicity and to avoid complex job dependencies, building all components on a single runner per architecture is acceptable. Total build time on a GitHub runner is ~15-20 minutes for a fresh build, which is well within the 6-hour job limit.

## Anti-Patterns

### Anti-Pattern 1: Using dpkg-buildpackage for Custom Build Systems

**What people do:** Create full `debian/` source packages with `debian/rules`, `debian/changelog`, `debian/compat`, etc., and use `dpkg-buildpackage` to compile and package.

**Why it is wrong:** The existing build system already handles compilation. Duplicating build logic in `debian/rules` creates maintenance overhead and divergence between direct install and packaged builds.

**Do this instead:** Use `dpkg-deb --build` with the existing build scripts. Build scripts handle compilation; dpkg-deb just wraps the output.

### Anti-Pattern 2: QEMU Emulation for Cross-Architecture Builds

**What people do:** Use QEMU emulation on amd64 runners to build arm64 packages.

**Why it is wrong:** Go and Rust compilation under QEMU is 3-10x slower and can produce incorrect results due to emulation quirks. The existing build system compiles from source with architecture-specific optimizations (GOGC, parallel make, sccache).

**Do this instead:** Use native `ubuntu-24.04-arm` runners on GitHub Actions. These are GA for public repos and available in private repos since January 2026.

### Anti-Pattern 3: Committing .deb Files to main Branch

**What people do:** Store generated .deb packages in the main branch alongside source code.

**Why it is wrong:** Binary packages are large (5-50MB each), pollute git history, and make the repo slow to clone.

**Do this instead:** Store packages on the `gh-pages` branch (separate git history) or use GitHub Releases as artifact storage.

### Anti-Pattern 4: Single Monolithic Package

**What people do:** Package all Podman components into a single `podman-all` .deb.

**Why it is wrong:** Users cannot upgrade individual components, cannot skip unwanted components (e.g., toolbox), and the Conflicts/Replaces cannot be granular.

**Do this instead:** One package per component, matching the alvistack naming convention (`podman-*` prefix). Use a meta-package `podman-all` that depends on all individual packages if desired.

### Anti-Pattern 5: Hardcoded Versions in DEBIAN/control

**What people do:** Write literal version numbers in control files, requiring manual updates for each release.

**Why it is wrong:** Version drift, forgotten updates, version mismatches between package and actual binary.

**Do this instead:** Use `@VERSION@` placeholders in control templates, substituted at build time from the git tag of the upstream component.

## Scaling Considerations

| Scale | Architecture Adjustments |
|---|---|
| Personal use (current) | Single GitHub Pages repo, daily cron, both arches |
| Small team (10 users) | Same architecture, add Slack/email notification on new builds |
| Wider distribution (100+ users) | Move to CloudFront/S3 for bandwidth, add apt-mirror support |
| Enterprise | Self-hosted GitHub runners, private APT repo with access control |

### Scaling Priorities

1. **First bottleneck: GitHub Pages bandwidth** (100 GB/month). At ~50MB per full install x 2000 installs = 100GB. Solution: CloudFront CDN in front.
2. **Second bottleneck: Build time for Rust components** (netavark, aardvark-dns ~5-8 min each on fresh build). Solution: GitHub Actions cache for Rust/Go build caches.

## Sources

- [Debian Packaging Tutorial](https://www.debian.org/doc/manuals/packaging-tutorial/packaging-tutorial.en.pdf) - HIGH confidence
- [Debian Policy: Package Relationships](https://www.debian.org/doc/debian-policy/ch-relationships.html) - HIGH confidence
- [Building binary deb packages: practical guide](https://www.internalpointers.com/post/build-binary-deb-package-practical-guide) - HIGH confidence
- [dpkg-deb manual page](https://www.man7.org/linux/man-pages/man1/dpkg-deb.1.html) - HIGH confidence
- [Debian Wiki: SetupWithReprepro](https://wiki.debian.org/DebianRepository/SetupWithReprepro) - HIGH confidence
- [GitHub Actions: ARM64 runners GA](https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/) - HIGH confidence
- [Publishing APT repos on GitHub Pages (Feb 2026)](https://blog.thestateofme.com/2026/02/27/publishing-apt-and-yum-dnf-repos-on-github-pages/) - MEDIUM confidence
- [morph027/apt-repo-action](https://github.com/morph027/apt-repo-action) - MEDIUM confidence
- [GPG signing deb packages and APT repositories](https://blog.packagecloud.io/how-to-gpg-sign-and-verify-deb-packages-and-apt-repositories/) - HIGH confidence
- [jtdor/build-deb-action](https://github.com/jtdor/build-deb-action) - MEDIUM confidence (reference, not recommended for this project)
- [Alvistack Podman packages](http://download.opensuse.org/repositories/home:/alvistack/xUbuntu_24.04/) - MEDIUM confidence (naming convention reference)
- Existing project codebase analysis (all build scripts, config.sh, functions.sh) - HIGH confidence

---
*Architecture research for: Podman Debian Compiler v2.0 APT Packaging & CI/CD*
*Researched: 2026-03-04*
