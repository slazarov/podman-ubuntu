# APT Repository Setup

This project provides a custom APT repository for Podman and its ecosystem tools, compiled from source for **Ubuntu 24.04 (Noble Numbat)** and **Ubuntu 26.04 (Resolute Raccoon)** LTS. Packages are available for both amd64 and arm64 architectures.

The repository is hosted on GitHub Pages and serves three release tracks per Ubuntu version, selected by a distro-qualified suite name:

- **stable** -- tested, pinned release versions (`stable-2404` / `stable-2604`)
- **edge** -- latest upstream tags, rebuilt automatically (`edge-2404` / `edge-2604`)
- **nightly** -- upstream HEAD, built daily (`nightly-2404` / `nightly-2604`)

Pick the section below that matches your Ubuntu version.

> **Note:** Deprecated in v3.0 (June 2026). Bare suite names will be removed in a future v3.1 release. Monitor the changelog or watch the GitHub repository for the removal notice. The bare suite names `stable`, `edge`, and `nightly` are superseded by the distro-qualified names shown below. If you are an existing user with `Suites: stable` (or `edge`/`nightly`) in your `.sources` file, see [Migrating from Bare Suite Names](#migrating-from-bare-suite-names).

## Ubuntu 24.04 (Noble Numbat)

First install the GPG signing key (see [GPG Signing Key](#gpg-signing-key) below), then add the repository and install the full Podman stack:

```bash
# Add the repository (DEB822 format)
sudo tee /etc/apt/sources.list.d/podman-ubuntu.sources << 'EOF'
Types: deb
URIs: https://slazarov.github.io/podman-ubuntu
Suites: stable-2404
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
EOF

# Update and install
sudo apt update
sudo apt install -y podman-suite
```

To track a different release line on 24.04, change the `Suites:` line to `edge-2404` (latest upstream tags) or `nightly-2404` (daily HEAD builds).

## Ubuntu 26.04 (Resolute Raccoon)

First install the GPG signing key (see [GPG Signing Key](#gpg-signing-key) below), then add the repository and install the full Podman stack:

```bash
# Add the repository (DEB822 format)
sudo tee /etc/apt/sources.list.d/podman-ubuntu.sources << 'EOF'
Types: deb
URIs: https://slazarov.github.io/podman-ubuntu
Suites: stable-2604
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
EOF

# Update and install
sudo apt update
sudo apt install -y podman-suite
```

To track a different release line on 26.04, change the `Suites:` line to `edge-2604` (latest upstream tags) or `nightly-2604` (daily HEAD builds).

The `podman-suite` meta-package installs all components. See [Individual Packages](#installing-individual-packages) below for installing components separately.

## GPG Signing Key

The signing key is the same for every Ubuntu version and every track -- download it once. Both per-distro setup sections above reference the same `Signed-By` path (`/etc/apt/keyrings/podman-ubuntu.gpg`):

```bash
# Download the GPG signing key
sudo mkdir -p /etc/apt/keyrings
sudo wget -qO /etc/apt/keyrings/podman-ubuntu.gpg \
  https://slazarov.github.io/podman-ubuntu/podman-ubuntu.gpg
```

## Track Selection

Each track is published per Ubuntu version with a distro-qualified suite name. Swap the `Suites:` line in your `.sources` file to switch tracks:

| Track | Ubuntu 24.04 suite | Ubuntu 26.04 suite | Description |
|-------|--------------------|--------------------|-------------|
| stable | `stable-2404` | `stable-2604` | Tested, pinned release versions -- recommended for production |
| edge | `edge-2404` | `edge-2604` | Latest upstream release tags, rebuilt automatically |
| nightly | `nightly-2404` | `nightly-2604` | Upstream HEAD, built daily -- newest features, least tested |

Use stable for production systems; use edge or nightly if you want the newest features.

## Installing Individual Packages

The `podman-suite` meta-package pulls in all components. You can also install them individually:

| Package | Description |
|---------|-------------|
| `podman-podman` | Container engine (core) |
| `podman-crun` | OCI runtime |
| `podman-conmon` | Container monitor |
| `podman-netavark` | Container networking |
| `podman-aardvark-dns` | DNS for container networks |
| `podman-pasta` | User-mode networking (passt) |
| `podman-fuse-overlayfs` | Rootless overlay filesystem |
| `podman-catatonit` | Minimal init for containers |
| `podman-buildah` | OCI image builder |
| `podman-skopeo` | Container image utility |
| `podman-toolbox` | Containerized development environments |
| `podman-container-configs` | Configuration files for /etc/containers/ |

Example installing only the core runtime:

```bash
sudo apt install podman-podman
```

This automatically pulls in required dependencies (crun, conmon, netavark, aardvark-dns, pasta, fuse-overlayfs, and container-configs).

## Supported Architectures

- **amd64** (x86_64)
- **arm64** (aarch64)

Both architectures are built natively (not cross-compiled) for both Ubuntu 24.04 and Ubuntu 26.04, and included in the same repository. APT selects the correct architecture automatically.

## Migrating from Bare Suite Names

If you set up this repository before v3.0, your `.sources` file likely uses a bare suite name (`Suites: stable`, `edge`, or `nightly`). These bare names are **deprecated** and will be removed in a future v3.1 release. Switch to the distro-qualified name for your Ubuntu version.

The bare suite names continue to serve **Ubuntu 24.04** packages during the deprecation window, so 24.04 users are not broken immediately -- but you should still migrate. Ubuntu 26.04 users must switch to a `-2604` suite to receive 26.04 packages.

**Option 1 -- sed one-liner.** Replace the bare suite name in place (run the line matching your Ubuntu version and track; the example shows `stable`):

```bash
# Ubuntu 24.04 users
sudo sed -i 's/Suites: stable$/Suites: stable-2404/' /etc/apt/sources.list.d/podman-ubuntu.sources

# Ubuntu 26.04 users
sudo sed -i 's/Suites: stable$/Suites: stable-2604/' /etc/apt/sources.list.d/podman-ubuntu.sources
```

For the edge or nightly tracks, substitute `edge` or `nightly` for `stable` on both sides of the replacement (e.g. `s/Suites: edge$/Suites: edge-2404/`).

**Option 2 -- paste the full replacement block.** Overwrite the `.sources` file with the distro-qualified block. Ubuntu 24.04:

```bash
sudo tee /etc/apt/sources.list.d/podman-ubuntu.sources << 'EOF'
Types: deb
URIs: https://slazarov.github.io/podman-ubuntu
Suites: stable-2404
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
EOF
```

Ubuntu 26.04:

```bash
sudo tee /etc/apt/sources.list.d/podman-ubuntu.sources << 'EOF'
Types: deb
URIs: https://slazarov.github.io/podman-ubuntu
Suites: stable-2604
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
EOF
```

After editing, run `sudo apt update` to refresh the package lists.

## Troubleshooting

### GPG key not found or download fails

Verify the key was downloaded correctly:

```bash
file /etc/apt/keyrings/podman-ubuntu.gpg
```

Expected output should show "PGP/GPG key public ring" or similar binary key format. If it shows HTML or text, the download URL may have changed. Re-download:

```bash
sudo wget -qO /etc/apt/keyrings/podman-ubuntu.gpg \
  https://slazarov.github.io/podman-ubuntu/podman-ubuntu.gpg
```

### Signature verification errors on apt update

If you see errors like `The following signatures couldn't be verified` or `NO_PUBKEY`:

1. Ensure the key file is binary format (not ASCII-armored). Check with `file /etc/apt/keyrings/podman-ubuntu.gpg` -- it should not start with `-----BEGIN`.

2. If you have an ASCII-armored key (.asc file), convert it:

```bash
sudo gpg --dearmor -o /etc/apt/keyrings/podman-ubuntu.gpg /etc/apt/keyrings/podman-ubuntu.asc
```

3. Verify the `Signed-By` path in your sources file matches the key location:

```bash
cat /etc/apt/sources.list.d/podman-ubuntu.sources
```

### Repository returns 404

The repository URL is `https://slazarov.github.io/podman-ubuntu`. Ensure:

- The `URIs` line in your sources file has no trailing slash
- GitHub Pages is live (check the URL in a browser)
- The `Suites` value matches an available distro-qualified suite for your Ubuntu version (`stable-2404` / `edge-2404` / `nightly-2404` for 24.04; `stable-2604` / `edge-2604` / `nightly-2604` for 26.04)

### Packages conflict with official Ubuntu packages

The podman-ubuntu packages use `Conflicts`, `Replaces`, and `Provides` declarations to handle coexistence with official Ubuntu packages. Installing a `podman-*` package will replace the corresponding official package if present. This is by design -- the compiled-from-source versions are newer.

To revert to official packages, remove the podman-ubuntu packages and reinstall from the official repository:

```bash
sudo apt remove podman-suite
sudo apt install podman
```

## Important Notes

- This repository uses the modern DEB822 `.sources` format with `Signed-By` for per-repository key binding. Legacy one-line source format and global key trust are not supported.
- The GPG signing key is Ed25519, which is supported by Ubuntu 24.04 and later.
- Packages use a per-distro version suffix so the correct build is selected for your Ubuntu version: `~ubuntu24.04.podman1` on 24.04 and `~ubuntu26.04.podman1` on 26.04. This ensures official Ubuntu packages (when available at the same upstream version) take priority during upgrades, and keeps the two distros' builds distinct in the same repository.
