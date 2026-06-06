# Feature Research: APT Packaging & Distribution

**Domain:** Debian packaging, APT repository hosting, CI/CD automation for custom-compiled Podman components
**Researched:** 2026-03-04
**Confidence:** HIGH (Debian Policy Manual, official dpkg documentation, verified community patterns)

## Executive Summary

This research covers the full user journey for distributing custom-compiled Podman components as .deb packages via a self-hosted APT repository on GitHub Pages. The domain is well-established with clear standards (Debian Policy Manual) and proven tooling (dpkg-deb, reprepro, GitHub Actions). The alvistack project on the openSUSE Build Service uses a `podman-*` prefix pattern for their packages (podman-netavark, podman-aardvark-dns, podman-gvproxy) with upstream version numbering, which validates our planned naming approach.

The user journey is: add GPG key and sources.list entry, run `apt update && apt install podman-podman`, get all dependencies pulled in automatically, receive updates via standard `apt upgrade`. Every feature below supports one step of this journey.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist when using an APT repository. Missing any of these breaks the "it just works" expectation.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Valid .deb packages with control files** | apt/dpkg refuse to install without proper Package, Version, Architecture, Maintainer, Description fields | MEDIUM | One control file per component; 12 packages total. Use `dpkg-deb --build --root-owner-group` to build. |
| **Correct file placement in packages** | Users expect binaries in /usr/bin, configs in /etc, man pages in /usr/share/man | LOW | Already solved -- v1.x installs to standard paths. Package just wraps the installed files. |
| **Inter-package dependency declarations** | `apt install podman-podman` must pull in podman-crun, podman-netavark, etc. automatically | MEDIUM | Depends field in control files. Runtime dependency graph already documented in v1.x FEATURES.md. |
| **Conflicts/Replaces/Provides against official Ubuntu packages** | Users with Ubuntu's podman installed must be able to cleanly switch to our packages | HIGH | Requires triple declaration: `Conflicts: netavark`, `Replaces: netavark`, `Provides: netavark`. Must match for all 12 components that overlap with Ubuntu repos. |
| **GPG-signed repository metadata** | apt refuses unsigned third-party repos by default (since Debian 9+). Users expect `signed-by=` in sources.list | MEDIUM | Generate GPG key, sign Release/InRelease with it, export public key as .gpg binary file. Use `Signed-By` in sources.list (not deprecated apt-key). |
| **Proper APT repository structure** | `apt update` must parse the repo without errors. Requires dists/, Packages, Release, InRelease | MEDIUM | Use reprepro to generate. Structure: `dists/<codename>/main/binary-{amd64,arm64}/Packages`. |
| **sources.list / .sources configuration** | Users need a one-liner or small script to add the repo | LOW | Provide both DEB822 format (.sources file) and legacy one-liner. Include `signed-by=/usr/share/keyrings/podman-debian.gpg`. |
| **amd64 and arm64 architecture support** | Ubuntu 24.04 runs on both; ARM servers are increasingly common | HIGH | Requires building on both architectures. QEMU emulation for ARM64 on GitHub Actions is slow; native arm64 runners now available for private repos. |
| **Version numbering following Debian conventions** | `apt upgrade` must correctly determine "newer" versions | LOW | Format: `<upstream_version>-<revision>`. Example: `5.8.0-1`. Revision resets to 1 on each upstream version bump. |
| **Debian changelog in each package** | dpkg-deb does not strictly require it, but lintian warns and users expect it for `apt changelog` | LOW | Minimal format: `package (version) noble; urgency=low`. Auto-generate from upstream git tags. |

### Differentiators (Competitive Advantage)

Features that distinguish this from manually compiling or using stale Ubuntu packages.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Meta-package for one-command install** | `apt install podman-suite` installs everything -- podman, buildah, skopeo, toolbox, all runtime deps | LOW | Empty package with only Depends field. Dramatically simplifies user experience. |
| **Automated upstream version detection and rebuild** | GitHub Actions cron checks upstream tags, triggers rebuild when new versions appear | MEDIUM | Already have `get_latest_tag()` logic in functions.sh. Workflow compares current repo version against upstream, triggers build if different. |
| **GitHub Actions CI/CD pipeline** | Fully automated: detect new version, build on amd64+arm64, package as .deb, publish to GitHub Pages repo | HIGH | The core automation. Scheduled cron + manual workflow_dispatch trigger. Matrix strategy for architectures. |
| **GitHub Pages hosting (zero cost)** | Free, reliable, HTTPS-enabled hosting with no infrastructure to maintain | MEDIUM | Push repo artifacts to gh-pages branch. reprepro generates metadata locally in the workflow. |
| **Package-level granularity** | Users can install only what they need (e.g., just podman-crun to replace an older crun) | LOW | Natural outcome of individual packages. Each package is independently installable. |
| **One-line repo setup script** | `curl -fsSL https://user.github.io/podman-debian/setup.sh | sudo bash` adds repo + key | LOW | Script downloads GPG key to /usr/share/keyrings/, writes .sources file, runs apt update. |
| **Manual workflow trigger** | Maintainer can trigger a rebuild on-demand without waiting for cron | LOW | `workflow_dispatch` event in GitHub Actions. Useful for urgent security updates. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems in this context.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Full debhelper/dh_make build system** | "Proper" Debian packaging uses debian/rules, dh sequences | Massive complexity for pre-compiled binaries. debhelper is designed for building FROM source inside the package build. We already compile from source separately. Adds dh_auto_configure, dh_auto_build steps that fight our existing build scripts. | Use dpkg-deb directly. We compile, then wrap the result. Simple, predictable, maintainable. |
| **Source packages (.dsc + .orig.tar.gz)** | Standard Debian repos include source packages for rebuilding | We are not a Debian mirror. Our value is pre-compiled binaries. Source packages double repo size and add complexity. Users who want source can clone the GitHub repo. | Binary-only repository (Architecture: amd64/arm64, no "source" component). |
| **Multi-distribution support** | Supporting Debian 12, Ubuntu 22.04, Ubuntu 24.04 simultaneously | Multiplies build matrix (3 distros x 2 arches = 6 builds). Library versions differ across distros causing runtime failures. Focus constraint says Ubuntu 24.04 only. | Single codename target: `noble` (Ubuntu 24.04). Expand later if needed. |
| **Epoch in version numbers** | Epoch (e.g., `1:5.8.0-1`) lets you "win" version comparison against any non-epoch version | Epochs are irreversible -- once set, you can never remove them. Creates permanent technical debt. Only needed for version scheme changes. | Use straight upstream versions: `5.8.0-1`. Our packages will naturally be newer than Ubuntu's because we track latest upstream. |
| **Package signing with debsigs** | Individual .deb file signatures in addition to repository-level signing | Repository-level signing (InRelease/Release.gpg) is sufficient for APT trust verification. debsigs adds complexity with no practical security benefit for our use case. | Repository-level GPG signing only (reprepro handles this automatically). |
| **Automatic conflict detection with dpkg triggers** | Using dpkg triggers to detect and resolve conflicts with system packages at install time | Triggers add fragility. Simple Conflicts/Replaces declarations handle this cleanly. Triggers are for coordinating between packages (like updating icon caches), not for conflict resolution. | Static Conflicts/Replaces/Provides in control files. |
| **Building inside Docker containers for reproducibility** | Ensures clean build environment | Adds Docker-in-Docker complexity to GitHub Actions. Our build scripts already handle dependency installation. The runner IS the build environment. QEMU for ARM64 inside Docker is painfully slow. | Build directly on the GitHub Actions runner (ubuntu-24.04). Install build deps via existing install_dependencies.sh. |
| **APT pinning / priority configuration** | Auto-configure apt preferences to prioritize our packages over Ubuntu's | Intrusive -- modifies user's apt configuration beyond adding the repo. If our packages have Conflicts/Replaces, apt handles priority automatically. Pinning is a user choice, not a repo provider choice. | Document pinning as optional in README. Let Conflicts/Replaces handle the common case. |

---

## Feature Dependencies

```
[GPG Key Generation]
    |
    v
[Repository Signing] ──requires──> [reprepro Configuration]
    |
    v
[APT Repository Structure on GitHub Pages]
    |
    v
[sources.list Configuration] ──requires──> [GPG Public Key Distribution]

[Existing Build Scripts (v1.x)]
    |
    v
[.deb Packaging Scripts]
    |-- wraps output of --> [Build Component X] --> [Package: podman-X]
    |
    v
[Control File Generation]
    |-- requires --> [Inter-Package Dependency Map]
    |-- requires --> [Conflicts/Replaces/Provides Declarations]
    |
    v
[reprepro includedeb] ──requires──> [Signed Repository]

[GitHub Actions Workflow]
    |-- requires --> [Build Scripts]
    |-- requires --> [.deb Packaging Scripts]
    |-- requires --> [reprepro Configuration]
    |-- requires --> [GPG Key as GitHub Secret]
    |-- requires --> [GitHub Pages Deployment]
    |
    v
[Upstream Version Check (cron)] ──triggers──> [Full Build + Publish Pipeline]

[Meta-Package: podman-suite]
    |-- requires --> [All Individual Packages Defined]
    |-- enhances --> [User Experience]
```

### Dependency Notes

- **Control files require the dependency map:** You cannot write correct Depends fields without knowing the runtime dependency graph (already documented).
- **reprepro requires GPG:** Repository metadata cannot be signed without a key. Key generation must happen first (once, stored as GitHub Secret).
- **GitHub Pages requires reprepro output:** The static site is the reprepro-generated repository structure pushed to the gh-pages branch.
- **Upstream version check requires baseline:** First build must be manual. Subsequent cron runs compare against the last published version.
- **ARM64 builds may block on runner availability:** If native arm64 runners are not available for public repos, QEMU emulation adds significant build time (potentially 3-5x slower).

---

## Package Inventory

### Individual Packages (12 total)

Based on the 12 components currently compiled by v1.x:

| Package Name | Upstream Package | Provides | Conflicts/Replaces | Key Dependencies |
|-------------|-----------------|----------|---------------------|-----------------|
| `podman-podman` | `podman` | `podman` | `podman` | podman-conmon, podman-crun, podman-netavark, podman-aardvark-dns, podman-fuse-overlayfs, podman-pasta, podman-catatonit |
| `podman-buildah` | `buildah` | `buildah` | `buildah` | podman-container-libs |
| `podman-skopeo` | `skopeo` | `skopeo` | `skopeo` | podman-container-libs |
| `podman-conmon` | `conmon` | `conmon` | `conmon` | libc6, libglib2.0-0 |
| `podman-crun` | `crun` | `crun` | `crun` | libc6, libseccomp2, libsystemd0 |
| `podman-catatonit` | `catatonit` | `catatonit` | `catatonit` | libc6 |
| `podman-fuse-overlayfs` | `fuse-overlayfs` | `fuse-overlayfs` | `fuse-overlayfs` | libc6, libfuse3-3, fuse3 |
| `podman-pasta` | `passt` | `passt` | `passt` | libc6 |
| `podman-netavark` | `netavark` | `netavark` | `netavark` | libc6, podman-aardvark-dns |
| `podman-aardvark-dns` | `aardvark-dns` | `aardvark-dns` | `aardvark-dns` | libc6 |
| `podman-container-libs` | `containers-common` | `containers-common` | `containers-common` | None (config files only) |
| `podman-toolbox` | `toolbox` | `toolbox` | `toolbox` | podman-podman |

### Meta-Package (1 total)

| Package Name | Purpose | Depends |
|-------------|---------|---------|
| `podman-suite` | Install everything | podman-podman, podman-buildah, podman-skopeo, podman-toolbox |

### Version Numbering Scheme

Format: `<upstream_version>-<revision>`

- **upstream_version:** Matches the upstream project tag (e.g., `5.8.0` for podman, `1.17.0` for netavark)
- **revision:** Starts at `1`, incremented only for packaging-only changes (no upstream version change). Resets to `1` on upstream version bump.
- **No epoch:** Not needed since we always track latest upstream (our versions are always higher than Ubuntu's).

Examples:
- `podman-podman_5.8.0-1_amd64.deb` (first build of podman 5.8.0)
- `podman-podman_5.8.0-2_amd64.deb` (packaging fix, same upstream)
- `podman-netavark_1.17.2-1_arm64.deb` (netavark 1.17.2 for ARM64)

---

## Control File Specification

### Required Fields (every package)

```
Package: podman-netavark
Version: 1.17.2-1
Architecture: amd64
Maintainer: Your Name <email@example.com>
Description: Netavark network backend for Podman containers
 Container network backend for Podman, built from source.
 Compiled with latest stable upstream release.
Depends: libc6 (>= 2.39), podman-aardvark-dns (= 1.17.0-1)
Conflicts: netavark
Replaces: netavark
Provides: netavark (= 1.17.2)
Section: admin
Priority: optional
Homepage: https://github.com/containers/netavark
```

### Conflicts/Replaces/Provides Pattern

The triple declaration pattern from Debian Policy Manual (verified HIGH confidence):

```
Conflicts: <official-package-name>
Replaces: <official-package-name>
Provides: <official-package-name> (= <upstream-version>)
```

This ensures:
1. **Conflicts:** apt will not install both simultaneously
2. **Replaces:** apt knows our package overwrites files from the official one
3. **Provides:** Other packages depending on the official name will accept ours as a substitute

### Maintainer Scripts (per package, where needed)

| Script | When Used | Purpose |
|--------|-----------|---------|
| `postinst` | After install/upgrade | Run `ldconfig` if shared libraries installed. Reload systemd if service files present. |
| `prerm` | Before removal | Stop services if running. |
| `postrm` | After removal | Run `ldconfig` cleanup. Remove generated config on purge. |

Most packages (binary-only like podman, crun, netavark) need no maintainer scripts. The `podman-container-libs` package may need a minimal postinst for config file handling.

---

## APT Repository Structure

### Repository Layout (reprepro-generated)

```
repo/
+-- dists/
|   +-- noble/                          # Ubuntu 24.04 codename
|       +-- InRelease                   # Signed release metadata (inline GPG)
|       +-- Release                     # Unsigned release metadata
|       +-- Release.gpg                 # Detached GPG signature
|       +-- main/
|           +-- binary-amd64/
|           |   +-- Packages            # Package index
|           |   +-- Packages.gz         # Compressed package index
|           +-- binary-arm64/
|               +-- Packages
|               +-- Packages.gz
+-- pool/
|   +-- main/
|       +-- p/
|       |   +-- podman-podman/
|       |       +-- podman-podman_5.8.0-1_amd64.deb
|       |       +-- podman-podman_5.8.0-1_arm64.deb
|       +-- n/
|           +-- podman-netavark/
|               +-- podman-netavark_1.17.2-1_amd64.deb
+-- podman-debian.gpg                   # Public GPG key (binary format)
```

### reprepro Configuration

```
# conf/distributions
Origin: podman-debian
Label: Podman Debian
Codename: noble
Architectures: amd64 arm64
Components: main
Description: Latest Podman compiled from source for Ubuntu 24.04
SignWith: <KEY_FINGERPRINT>
```

### Client Configuration (DEB822 format, preferred)

```
# /etc/apt/sources.list.d/podman-debian.sources
Types: deb
URIs: https://<user>.github.io/podman-debian
Suites: noble
Components: main
Signed-By: /usr/share/keyrings/podman-debian.gpg
```

---

## GPG Key Management

### Key Generation (one-time)

- **Algorithm:** Ed25519 (Curve 25519) -- fast, small, secure
- **Expiry:** No expiry (simplifies automation; repo is personal use)
- **No passphrase:** Required for non-interactive GitHub Actions usage
- **Storage:** Private key exported to GitHub Actions secret (`GPG_PRIVATE_KEY`). Public key committed to repo as `podman-debian.gpg` (binary format, not ASCII-armored).

### Signing Flow in CI

1. Import private key from secret: `echo "$GPG_PRIVATE_KEY" | gpg --batch --import`
2. Trust the key: `echo "<fingerprint>:6:" | gpg --import-ownertrust`
3. reprepro signs automatically via `SignWith` in distributions config

---

## Changelog Generation

### Minimal Format (meets dpkg requirements)

```
podman-podman (5.8.0-1) noble; urgency=low

  * Upstream release 5.8.0
  * Built from source: https://github.com/containers/podman/releases/tag/v5.8.0

 -- Maintainer Name <email@example.com>  Tue, 04 Mar 2026 12:00:00 +0000
```

### Automation Approach

Generate changelog automatically during the packaging step:
1. Get upstream version tag
2. Format date with `date -R`
3. Write template to `DEBIAN/changelog` (or better: use `install -m 644` to `/usr/share/doc/<package>/changelog.Debian.gz` after gzipping)

Do NOT use `dch` or `gbp dch` -- these tools are designed for source package workflows. Our binary-only approach just needs a formatted text file.

---

## MVP Definition

### Launch With (v2.0)

- [x] .deb packaging for all 12 components using dpkg-deb
- [x] Correct control files with Depends, Conflicts, Replaces, Provides
- [x] GPG-signed APT repository via reprepro
- [x] GitHub Pages hosting on gh-pages branch
- [x] GitHub Actions workflow: manual trigger, build both architectures
- [x] Client setup script (downloads key, writes sources file)
- [x] Meta-package `podman-suite` for one-command install

### Add After Validation (v2.1)

- [ ] Automated upstream version detection (cron schedule) -- add once manual pipeline is proven stable
- [ ] Changelog generation from upstream release notes -- nice for `apt changelog` but not blocking
- [ ] Package description improvements with proper long descriptions

### Future Consideration (v3+)

- [ ] Multi-distribution support (Debian 12, Ubuntu 22.04) -- only if demand exists
- [ ] Automated testing of installed packages (podman info, podman run hello-world) in CI
- [ ] Package linting with lintian in CI pipeline

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Valid .deb packages | HIGH | MEDIUM | P1 |
| Inter-package dependencies | HIGH | MEDIUM | P1 |
| Conflicts/Replaces/Provides | HIGH | HIGH | P1 |
| GPG-signed repository | HIGH | MEDIUM | P1 |
| GitHub Pages hosting | HIGH | MEDIUM | P1 |
| GitHub Actions CI/CD | HIGH | HIGH | P1 |
| sources.list config + setup script | HIGH | LOW | P1 |
| amd64 + arm64 support | HIGH | HIGH | P1 |
| Version numbering scheme | MEDIUM | LOW | P1 |
| Meta-package (podman-suite) | MEDIUM | LOW | P1 |
| Debian changelog | LOW | LOW | P2 |
| Upstream version auto-detection | MEDIUM | MEDIUM | P2 |
| Manual workflow trigger | MEDIUM | LOW | P1 |
| One-line setup script | MEDIUM | LOW | P2 |
| Lintian compliance | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for v2.0 launch
- P2: Should have, add in v2.1
- P3: Nice to have, future consideration

---

## Competitor Feature Analysis

| Feature | alvistack (OBS) | Ubuntu Official | Our Approach |
|---------|-----------------|-----------------|--------------|
| Package naming | `podman-netavark`, `podman-aardvark-dns` (prefixed) | `netavark`, `aardvark-dns` (unprefixed) | `podman-netavark`, `podman-aardvark-dns` (prefixed, matches alvistack) |
| Version currency | Tracks latest upstream within weeks | 6-12 months behind upstream | Tracks latest upstream (automated rebuild on new tags) |
| Build source | OBS build service | Debian/Ubuntu packaging infrastructure | GitHub Actions |
| Distribution | OBS download servers | Ubuntu archive mirrors | GitHub Pages |
| Signing | OBS key management | Ubuntu archive key | Per-repo GPG key with Signed-By |
| Conflicts handling | Reported issues with missing Conflicts (#7 on GitHub) | N/A (is the official package) | Explicit Conflicts/Replaces/Provides on all overlapping packages |
| Architecture | amd64 only (for Ubuntu 24.04) | amd64, arm64 | amd64 + arm64 |
| Source packages | Yes (.dsc, .orig.tar.gz) | Yes | No (binary-only, source on GitHub) |

### Key Differentiator vs alvistack

alvistack has known issues with missing Conflicts declarations (GitHub issue #7: "install fails if Debian official podman packages already installed"). Our explicit Conflicts/Replaces/Provides pattern prevents this. Additionally, alvistack relies on OBS infrastructure which has its own complexity; GitHub Pages is simpler and more accessible.

### Key Differentiator vs Ubuntu Official

Ubuntu's podman packages are typically 6-12 months behind upstream. Our packages track the latest stable release within the cron check interval (e.g., daily or weekly).

---

## User Journey: Complete Flow

### 1. Adding the Repository

```bash
# Download GPG key
curl -fsSL https://<user>.github.io/podman-debian/podman-debian.gpg \
  | sudo tee /usr/share/keyrings/podman-debian.gpg > /dev/null

# Add repository
sudo tee /etc/apt/sources.list.d/podman-debian.sources <<EOF
Types: deb
URIs: https://<user>.github.io/podman-debian
Suites: noble
Components: main
Signed-By: /usr/share/keyrings/podman-debian.gpg
EOF

# Update
sudo apt update
```

### 2. Installing Packages

```bash
# Option A: Install everything
sudo apt install podman-suite

# Option B: Install only what you need
sudo apt install podman-podman
# apt auto-installs: podman-conmon, podman-crun, podman-netavark,
#   podman-aardvark-dns, podman-fuse-overlayfs, podman-pasta,
#   podman-catatonit, podman-container-libs
```

### 3. Getting Updates

```bash
sudo apt update && sudo apt upgrade
# Updates any podman-* packages with newer versions
```

### 4. Switching from Ubuntu Official Packages

```bash
# If user already has Ubuntu's podman installed:
sudo apt install podman-podman
# apt automatically removes conflicting 'podman' package
# and installs podman-podman + dependencies
```

---

## Sources

### HIGH Confidence
- [Debian Policy Manual - Relationships](https://www.debian.org/doc/debian-policy/ch-relationships.html) -- Conflicts/Replaces/Provides semantics
- [Debian Policy Manual - Control Fields](https://www.debian.org/doc/debian-policy/ch-controlfields.html) -- Version numbering
- [Debian Policy Manual - Maintainer Scripts](https://www.debian.org/doc/debian-policy/ch-maintainerscripts.html) -- postinst/prerm behavior
- [dpkg-deb man page](https://www.man7.org/linux/man-pages/man1/dpkg-deb.1.html) -- Package building
- [deb-changelog man page](https://man7.org/linux/man-pages/man5/deb-changelog.5.html) -- Changelog format
- [SecureApt - Debian Wiki](https://wiki.debian.org/SecureApt) -- Repository signing
- [DebianRepository/UseThirdParty - Debian Wiki](https://wiki.debian.org/DebianRepository/UseThirdParty) -- signed-by best practices

### MEDIUM Confidence
- [alvistack OBS packages](http://download.opensuse.org/repositories/home:/alvistack/xUbuntu_24.04/) -- Package naming patterns (podman-netavark, podman-aardvark-dns confirmed in amd64/ listing)
- [Building and Publishing APT Repos to GitHub Pages](https://linsomniac.com/post/2025-03-18-building_and_publishing_apt_repos_to_github_pages/) -- GitHub Actions + reprepro workflow
- [morph027/apt-repo-action](https://github.com/morph027/apt-repo-action) -- GitHub Action for reprepro + GitHub Pages
- [Building binary deb packages - Internal Pointers](https://www.internalpointers.com/post/build-binary-deb-package-practical-guide) -- dpkg-deb practical guide
- [DebianRepository/SetupWithReprepro - Debian Wiki](https://wiki.debian.org/DebianRepository/SetupWithReprepro) -- reprepro configuration
- [Cloudflare: Don't use apt-key](https://blog.cloudflare.com/dont-use-apt-key/) -- Modern key management

### LOW Confidence (needs validation)
- GitHub Actions native arm64 runner availability for public repos -- reported available for private repos as of Jan 2026, public repo status unclear. Fallback: QEMU emulation via docker/setup-qemu-action.

---
*Feature research for: APT Packaging & Distribution (v2.0 milestone)*
*Researched: 2026-03-04*
