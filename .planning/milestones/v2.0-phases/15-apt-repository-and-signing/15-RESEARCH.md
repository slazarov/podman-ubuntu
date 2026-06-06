# Phase 15: APT Repository and Signing - Research

**Researched:** 2026-03-05
**Domain:** APT repository management with reprepro, GPG Ed25519 signing, GitHub Pages hosting, DEB822 sources format
**Confidence:** HIGH

## Summary

This phase creates a GPG-signed APT repository that serves two suites (stable and edge) and is deployable to GitHub Pages. The repository consumes .deb files produced by Phase 14's `scripts/package_all.sh` (output to `output/` directory) and organizes them into a standard Debian repository structure with `dists/` and `pool/` directories using reprepro.

The key tools are reprepro (Debian repository generator), GPG with Ed25519 key (required by Ubuntu 24.04 for APT signing), and GitHub Pages for static hosting. Reprepro generates both InRelease (inline-signed) and Release.gpg (detached signature) automatically when SignWith is configured, satisfying the requirement that `apt update` works without `--allow-insecure-repositories` or `[trusted=yes]`.

The repository will be accessible at `https://slazarov.github.io/podman-debian/` once GitHub Pages is enabled on the repo. Users add the repo using a DEB822 `.sources` file with `signed-by` pointing to the downloaded public GPG key, which is the modern standard replacing the deprecated `apt-key` approach.

**Primary recommendation:** Use reprepro with Ed25519 GPG signing, two distribution stanzas in `conf/distributions` (codenames `stable` and `edge`), and a shell script that wraps reprepro commands for easy local and CI invocation. Public key published as binary `.gpg` file at the repository root URL. User instructions use DEB822 format targeting `/etc/apt/sources.list.d/podman-debian.sources`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| REPO-01 | APT repository hosted on GitHub Pages with reprepro-generated structure (dists/, pool/) | Reprepro generates standard dists/ and pool/ structure; GitHub Pages serves static files; script creates conf/distributions, runs reprepro includedeb, outputs deployable directory |
| REPO-02 | Repository is GPG-signed with Ed25519 key (InRelease + Release.gpg) | Reprepro with SignWith directive generates both InRelease and Release.gpg automatically; Ed25519 is supported by Ubuntu 24.04+ APT; GPG key generation documented |
| REPO-03 | Repository serves two suites in one URL: stable and edge | Two stanzas in conf/distributions with different Codename values (stable, edge) share the same repository root; reprepro createsymlinks handles suite aliases |
| REPO-04 | User setup instructions document DEB822 .sources config, GPG key import via signed-by, and install commands | DEB822 format documented with Signed-By field; instructions target /etc/apt/keyrings/ for key storage; under-5-command setup verified feasible |
| REPO-05 | Public GPG key is published in the repository root for user download | GPG key exported as binary .gpg file and copied to repository root alongside dists/ and pool/; accessible at repo URL/gpg.key or repo URL/podman-debian.gpg |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| reprepro | system (5.x) | Generate APT repository structure (dists/, pool/, Packages, Release) | De facto standard for personal/project APT repos; used by Debian wiki, morph027/apt-repo-action, and most GitHub Pages APT repos |
| gpg | system (2.2+) | Ed25519 key generation and repository signing | Ubuntu 24.04 requires Ed25519/Ed448/RSA-2048+ for APT signing; gpg is the standard tool |
| bash | 5.x | Repository management script wrapping reprepro commands | Consistent with all existing project scripts |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| morph027/apt-repo-action | v3.7 | GitHub Action for reprepro + GitHub Pages deployment | Phase 16 CI/CD integration (NOT Phase 15 scope -- but design must be compatible) |
| actions/upload-pages-artifact | v3 | Upload repository directory as GitHub Pages artifact | Phase 16 CI/CD deployment step |
| actions/deploy-pages | v4 | Deploy uploaded artifact to GitHub Pages | Phase 16 CI/CD deployment step |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| reprepro | aptly | aptly is more powerful (snapshots, mirrors) but heavier; reprepro is simpler and sufficient for this use case |
| reprepro | dpkg-scanpackages | dpkg-scanpackages generates only Packages file, no signing, no pool management |
| morph027/apt-repo-action | Manual reprepro in CI | Action handles import-from-repo-url (critical for immutable GH Actions cache); saves significant CI YAML complexity |
| peaceiris/actions-gh-pages | actions/deploy-pages | Official GitHub actions preferred; peaceiris is third-party but well-maintained |

**Installation:**
```bash
# reprepro (on Ubuntu build system)
sudo apt-get install -y reprepro

# GPG is pre-installed on Ubuntu runners
```

## Architecture Patterns

### Recommended Project Structure
```
packaging/
  repo/
    conf/
      distributions        # reprepro config: two stanzas (stable, edge)
      options               # reprepro options (verbose)
    pubkey.gpg              # Binary public GPG key (committed to repo)
scripts/
  repo_manage.sh            # Repository management script (add packages, export, sign)
```

### Generated Repository Structure (not committed -- output artifact)
```
repo-output/                # Created by repo_manage.sh
  dists/
    stable/
      InRelease             # Inline-signed Release
      Release               # Unsigned metadata
      Release.gpg           # Detached GPG signature
      main/
        binary-amd64/
          Packages
          Packages.gz
          Release
        binary-arm64/
          Packages
          Packages.gz
          Release
    edge/
      InRelease
      Release
      Release.gpg
      main/
        binary-amd64/
        binary-arm64/
  pool/
    main/
      p/podman-podman/
        podman-podman_5.5.2~podman1_amd64.deb
        podman-podman_5.5.2~podman1_arm64.deb
      c/podman-crun/
      ...
  podman-debian.gpg         # Public key at root for user download
```

### Pattern 1: Reprepro Configuration for Two Suites
**What:** Two distribution stanzas in `conf/distributions` sharing the same base directory
**When to use:** Always -- this is the core repository structure

```
# packaging/repo/conf/distributions
Origin: podman-debian
Label: Podman Debian
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: Podman compiled from source for Ubuntu 24.04 - stable releases
SignWith: ${GPG_KEY_ID}

Origin: podman-debian
Label: Podman Debian
Suite: edge
Codename: edge
Architectures: amd64 arm64
Components: main
Description: Podman compiled from source for Ubuntu 24.04 - latest upstream
SignWith: ${GPG_KEY_ID}
```

**Note:** Using Codename = Suite name (both `stable`/`edge`) is intentional. Since this repo serves a single Ubuntu release (noble) and uses suite names as the distinguishing identifier, Codename and Suite can be the same. This avoids needing createsymlinks and keeps the `dists/` structure clean: `dists/stable/` and `dists/edge/`.

### Pattern 2: GPG Ed25519 Key Generation (One-Time Setup)
**What:** Generate a passphrase-less Ed25519 signing key for CI use
**When to use:** Initial project setup (once)

```bash
# Generate Ed25519 key without passphrase (for CI/CD)
gpg --batch --passphrase '' --quick-gen-key \
  "Podman Debian <podman-debian@users.noreply.github.com>" \
  ed25519 default 0

# Get the fingerprint
GPG_KEY_ID=$(gpg --list-keys --with-colons "podman-debian@users.noreply.github.com" \
  | grep fpr | head -1 | cut -d: -f10)

# Export public key as binary (for repository root)
gpg --export "${GPG_KEY_ID}" > packaging/repo/pubkey.gpg

# Export private key as ASCII armor (for GitHub Secret)
gpg --armor --export-secret-keys "${GPG_KEY_ID}" > private.asc
# Upload private.asc content to GitHub Secret GPG_PRIVATE_KEY, then DELETE the file
```

### Pattern 3: Repository Management Script
**What:** Shell script wrapping reprepro commands for adding packages and exporting
**When to use:** Both locally (testing) and in CI (Phase 16)

```bash
#!/bin/bash
set -euo pipefail

# Usage: repo_manage.sh <suite> <deb-directory> <output-directory>
# Example: repo_manage.sh stable output/ repo-output/

SUITE="$1"
DEB_DIR="$2"
OUTPUT_DIR="$3"

REPO_CONF="${toolpath}/packaging/repo"
REPO_BASE="${OUTPUT_DIR}"

# Import GPG key if provided via environment
if [[ -n "${GPG_PRIVATE_KEY:-}" ]]; then
    echo "${GPG_PRIVATE_KEY}" | gpg --batch --import
fi

# Prepare reprepro base directory
mkdir -p "${REPO_BASE}/conf"
cp "${REPO_CONF}/conf/distributions" "${REPO_BASE}/conf/"
cp "${REPO_CONF}/conf/options" "${REPO_BASE}/conf/" 2>/dev/null || true

# Add all .deb files for the specified suite
for deb_file in "${DEB_DIR}"/*.deb; do
    if [[ -f "${deb_file}" ]]; then
        reprepro -Vb "${REPO_BASE}" includedeb "${SUITE}" "${deb_file}"
    fi
done

# Export generates InRelease + Release.gpg
reprepro -b "${REPO_BASE}" export

# Copy public key to repository root
cp "${REPO_CONF}/pubkey.gpg" "${REPO_BASE}/podman-debian.gpg"

# Remove db/ directory (not needed for serving)
rm -rf "${REPO_BASE}/db" "${REPO_BASE}/conf"
```

### Pattern 4: DEB822 User Setup Instructions
**What:** Modern APT source configuration format for Ubuntu 24.04+
**When to use:** User documentation and README

```bash
# 1. Download the GPG signing key
sudo wget -qO /etc/apt/keyrings/podman-debian.gpg \
  https://slazarov.github.io/podman-debian/podman-debian.gpg

# 2. Add the repository (DEB822 format)
sudo tee /etc/apt/sources.list.d/podman-debian.sources << 'EOF'
Types: deb
URIs: https://slazarov.github.io/podman-debian
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/podman-debian.gpg
EOF

# 3. Update and install
sudo apt update
sudo apt install podman-suite
```

That is 4 commands (wget, tee, apt update, apt install) -- meets the "under 5 commands" success criterion.

### Anti-Patterns to Avoid
- **Using apt-key:** Deprecated since Ubuntu 22.04, removed in 24.04. Always use `signed-by` in source entry pointing to key file in `/etc/apt/keyrings/`.
- **ASCII-armored public key for signed-by:** APT expects binary format for `signed-by` path. Export with `gpg --export` (no `--armor`). If you must distribute ASCII, users need `gpg --dearmor`.
- **Putting key in /etc/apt/trusted.gpg.d/:** This trusts the key for ALL repositories. Always use per-repo `signed-by` instead.
- **Using RSA-1024 keys:** Ubuntu 24.04 rejects keys weaker than RSA-2048. Ed25519 is preferred (smaller, faster, modern).
- **Committing the private GPG key:** Only the public key goes into the repository. Private key is stored as a GitHub Secret.
- **Committing the db/ directory:** Reprepro's `db/` is an internal database, not needed for serving. Only `dists/`, `pool/`, and the public key need deployment.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Repository metadata (Packages, Release, InRelease) | Custom scripts generating Packages/Release files | reprepro | Correct hashing (MD5Sum, SHA256), proper file layout, automatic InRelease generation |
| GPG signing of Release files | Manual `gpg --clearsign` / `gpg --detach-sign` | reprepro SignWith | Reprepro handles both InRelease (inline) and Release.gpg (detached) atomically |
| Package pool organization | Custom directory structure scripts | reprepro | Pool layout (pool/main/p/package-name/) follows Debian standards automatically |
| Repository import across CI runs | Custom download + re-add logic | morph027/apt-repo-action import-from-repo-url | Handles immutable GitHub Actions cache; re-imports existing packages before rebuilding |

**Key insight:** Reprepro does all the heavy lifting. The script layer is thin: configure, add packages, export. Do NOT try to generate Packages.gz, Release, InRelease, or Release.gpg manually.

## Common Pitfalls

### Pitfall 1: ASCII-Armored vs Binary GPG Key Format
**What goes wrong:** `apt update` fails with "NO_PUBKEY" or signature verification errors
**Why it happens:** The `signed-by` directive in APT sources expects a binary (dearmored) key file, but you exported with `gpg --armor --export`
**How to avoid:** Always export public key with `gpg --export` (binary format, no `--armor` flag). Name the file `.gpg` not `.asc`
**Warning signs:** Key file starts with `-----BEGIN PGP PUBLIC KEY BLOCK-----` instead of being binary

### Pitfall 2: Reprepro Architecture Mismatch
**What goes wrong:** `reprepro includedeb` rejects packages with "not found in architectures"
**Why it happens:** The `Architectures` field in conf/distributions doesn't include the architecture of the .deb being added
**How to avoid:** List ALL supported architectures in conf/distributions: `Architectures: amd64 arm64`
**Warning signs:** Error message like "skipping inclusion of [package] in [codename] because of wrong architecture"

### Pitfall 3: GPG Key Not Available in CI
**What goes wrong:** reprepro export fails with "gpg: signing failed: No secret key"
**Why it happens:** GPG private key not imported into the CI runner's keyring before reprepro runs
**How to avoid:** Import GPG key from GitHub Secret before any reprepro operations: `echo "$GPG_PRIVATE_KEY" | gpg --batch --import`
**Warning signs:** reprepro works locally but fails in GitHub Actions

### Pitfall 4: Immutable GitHub Actions Cache and Reprepro DB
**What goes wrong:** Newly published repository only contains packages from the latest build, losing previous packages
**Why it happens:** GitHub Actions caches are immutable; reprepro's db/ directory cannot persist between workflow runs. Each run starts fresh.
**How to avoid:** Use morph027/apt-repo-action's `import-from-repo-url` feature which downloads existing packages from the live GitHub Pages URL before rebuilding the repository
**Warning signs:** After publishing, `apt install` of a previously-available package fails with "has no installation candidate"

### Pitfall 5: GitHub Pages 404 on First Deployment
**What goes wrong:** GitHub Pages returns 404 after the first workflow run deploys
**Why it happens:** GitHub Pages must be enabled in repository settings (Settings > Pages > Source: GitHub Actions). First deployment may need manual enablement.
**How to avoid:** Enable GitHub Pages with "GitHub Actions" as the source before the first workflow run. If using peaceiris/actions-gh-pages, check their first-deployment docs.
**Warning signs:** Workflow succeeds but URL returns 404

### Pitfall 6: Suite vs Codename Confusion
**What goes wrong:** `apt update` fails because dists/ directory doesn't match what's in the .sources file
**Why it happens:** Codename is the directory name in dists/. If Codename is "noble" but your .sources says `Suites: stable`, APT looks for `dists/stable/` which doesn't exist (unless you used createsymlinks).
**How to avoid:** Set Codename to the value users will put in `Suites:` field. For this project, use `Codename: stable` and `Codename: edge` directly -- no symlinks needed.
**Warning signs:** `apt update` shows "404 Not Found [IP: ...] dists/stable/InRelease"

## Code Examples

### reprepro conf/distributions (Two Suites)
```
# Source: Debian Wiki - DebianRepository/SetupWithReprepro
# Adapted for podman-debian with Ed25519 signing

Origin: podman-debian
Label: Podman Debian
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: Podman compiled from source for Ubuntu 24.04 - stable releases
SignWith: yes

Origin: podman-debian
Label: Podman Debian
Suite: edge
Codename: edge
Architectures: amd64 arm64
Components: main
Description: Podman compiled from source for Ubuntu 24.04 - latest upstream
SignWith: yes
```

Using `SignWith: yes` tells reprepro to use the default GPG key. This is simpler than hardcoding a fingerprint and works when only one key is in the keyring (typical for CI runners).

### reprepro conf/options
```
verbose
basedir .
```

### Adding Packages to Repository
```bash
# Source: reprepro(1) manpage - includedeb command

# Add all amd64 packages to stable suite
for deb in output/*_amd64.deb; do
    reprepro -Vb repo-output includedeb stable "$deb"
done

# Add all arm64 packages to stable suite
for deb in output/*_arm64.deb; do
    reprepro -Vb repo-output includedeb stable "$deb"
done

# Export to regenerate metadata and signatures
reprepro -b repo-output export
```

### GPG Key Import in CI
```bash
# Source: morph027/apt-repo-action repo.sh pattern

# Import private key from GitHub Secret
echo "${GPG_PRIVATE_KEY}" | gpg --batch --import

# Set trust level (prevents "not ultimately trusted" warning)
GPG_KEY_ID=$(gpg --list-keys --with-colons | grep fpr | head -1 | cut -d: -f10)
echo "${GPG_KEY_ID}:6:" | gpg --batch --import-ownertrust
```

### User Installation Instructions (DEB822 format)
```bash
# Source: Debian Wiki - DebianRepository/UseThirdParty

# Download signing key
sudo mkdir -p /etc/apt/keyrings
sudo wget -qO /etc/apt/keyrings/podman-debian.gpg \
  https://slazarov.github.io/podman-debian/podman-debian.gpg

# Add repository source
sudo tee /etc/apt/sources.list.d/podman-debian.sources << 'EOF'
Types: deb
URIs: https://slazarov.github.io/podman-debian
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/podman-debian.gpg
EOF

# Install
sudo apt update
sudo apt install -y podman-suite
```

### Edge Suite Usage (Alternative)
```bash
# Same key, different suite
sudo tee /etc/apt/sources.list.d/podman-debian.sources << 'EOF'
Types: deb
URIs: https://slazarov.github.io/podman-debian
Suites: edge
Components: main
Signed-By: /etc/apt/keyrings/podman-debian.gpg
EOF
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `apt-key add` for GPG keys | `signed-by` in source entry + key in `/etc/apt/keyrings/` | Ubuntu 22.04 (deprecated), 24.04 (removed) | All instructions MUST use signed-by |
| `/etc/apt/sources.list.d/*.list` (one-line format) | `/etc/apt/sources.list.d/*.sources` (DEB822 format) | Ubuntu 24.04 default | DEB822 is now the standard; one-line still works but is legacy |
| RSA-4096 signing keys | Ed25519 signing keys | Ubuntu 24.04 (Ed25519 accepted; RSA-1024 rejected) | Ed25519 is smaller, faster, and future-proof |
| `trusted.gpg.d/` for all third-party keys | Per-repo `signed-by` in source entries | Debian/Ubuntu security hardening | Prevents key cross-contamination between repos |

**Deprecated/outdated:**
- `apt-key`: Fully removed from Ubuntu 24.04. Do not reference in user instructions.
- One-line format for sources: Still functional but DEB822 is the standard for new repos.
- RSA-1024 keys: Rejected by Ubuntu 24.04 APT with error.

## Phase Boundary Clarification

### In Scope (Phase 15)
- reprepro configuration files (conf/distributions, conf/options)
- GPG key generation instructions and public key committed to repo
- Repository management script (scripts/repo_manage.sh) for local use
- User documentation (DEB822 .sources setup instructions)
- Testing/verification that reprepro produces correct structure locally

### Out of Scope (Phase 16 - CI/CD Pipeline)
- GitHub Actions workflow YAML
- morph027/apt-repo-action integration
- GitHub Pages deployment automation
- import-from-repo-url for cross-run package persistence
- Multi-architecture CI matrix (amd64 + arm64 runners)

### Design Decisions Affecting Phase 16
Phase 15's reprepro configuration must be compatible with morph027/apt-repo-action. Key compatibility notes:
- morph027/apt-repo-action generates its own conf/distributions at runtime from action inputs. Phase 15's static conf/distributions is for local testing and documentation -- CI may use the action's generated config instead.
- The public key file name and location must be consistent between Phase 15 docs and Phase 16 deployment.
- The script must work both standalone (local testing) and be callable from CI.

## Open Questions

1. **GPG Key Ownership and Generation Timing**
   - What we know: An Ed25519 key is needed, must be passphrase-less for CI
   - What's unclear: Should the key be generated as part of Phase 15 execution (one-time manual step) or documented as a prerequisite? Key generation requires user action (storing private key in GitHub Secrets).
   - Recommendation: Document the key generation process and include it as a manual setup step in Phase 15. Commit only the public key. The planner should include a task for generating the key and uploading the private key to GitHub Secrets.

2. **morph027/apt-repo-action vs Custom reprepro Script**
   - What we know: morph027/apt-repo-action wraps reprepro and handles GitHub Pages deployment. It also generates conf/distributions from inputs, potentially overriding any committed config.
   - What's unclear: Should Phase 15 produce a standalone script that CI calls directly, or should it only produce configuration that the action consumes?
   - Recommendation: Produce a standalone `scripts/repo_manage.sh` that works locally (for testing and manual use). Phase 16 can choose between calling this script or using morph027/apt-repo-action. Both approaches are compatible because they use the same reprepro + GPG chain.

3. **Repository URL and GitHub Pages Branch**
   - What we know: The repo is at `github.com/slazarov/podman-debian`, so GitHub Pages URL would be `https://slazarov.github.io/podman-debian/`
   - What's unclear: GitHub Pages can deploy from a branch (gh-pages) or from GitHub Actions artifacts. The choice affects how Phase 16 integrates.
   - Recommendation: Design for GitHub Actions artifact deployment (actions/upload-pages-artifact + actions/deploy-pages) as it's the modern approach. Phase 15 just produces the directory structure; Phase 16 handles deployment.

## Sources

### Primary (HIGH confidence)
- [Debian Wiki - SetupWithReprepro](https://wiki.debian.org/DebianRepository/SetupWithReprepro) - reprepro configuration, directory structure, SignWith
- [Debian Wiki - UseThirdParty](https://wiki.debian.org/DebianRepository/UseThirdParty) - DEB822 format, signed-by, key storage recommendations
- [reprepro(1) manpage (bookworm)](https://manpages.debian.org/bookworm/reprepro/reprepro.1.en.html) - SignWith, includedeb, export, createsymlinks, InRelease/Release.gpg generation
- [Ubuntu 24.04 APT signing requirements](https://discourse.ubuntu.com/t/new-requirements-for-apt-repository-signing-in-24-04/42854) - Ed25519 requirement, algorithm policy
- [GnuPG documentation - quick-generate-key](https://www.gnupg.org/documentation/manuals/gnupg/OpenPGP-Key-Management.html) - Batch mode Ed25519 key generation

### Secondary (MEDIUM confidence)
- [morph027/apt-repo-action](https://github.com/morph027/apt-repo-action) - GitHub Action wrapping reprepro, import-from-repo-url feature, v3.7 latest
- [Building and Publishing Apt Repos to GitHub Pages (linsomniac, 2025-03)](https://linsomniac.com/post/2025-03-18-building_and_publishing_apt_repos_to_github_pages/) - Complete workflow example, GPG key setup for CI, reprepro in GitHub Actions
- [Ultimate Guide to Self-Hosting a Debian Repository (dario.griffo.io)](https://dario.griffo.io/posts/ultimate-guide-debian-repository-hosting/) - Complete dists/ structure, pool/ organization, GitHub Pages hosting

### Tertiary (LOW confidence)
- None -- all findings cross-verified with at least two sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - reprepro is the de facto standard, verified via Debian wiki and multiple production examples
- Architecture: HIGH - dists/pool structure is the Debian standard, reprepro generates it automatically
- Pitfalls: HIGH - Each pitfall documented from multiple sources (Debian wiki, production repos, action source code)
- GPG/Ed25519: HIGH - Ubuntu 24.04 signing requirements verified from official Ubuntu discourse announcement
- DEB822 format: HIGH - Verified from Debian wiki UseThirdParty page and Ubuntu 24.04 documentation

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (stable domain -- reprepro and GPG tooling change infrequently)
