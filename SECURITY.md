# Security Policy

This project builds and publishes a signed APT repository of the Podman
container stack. Two classes of issue matter here:

1. **Issues in this pipeline** — the build scripts, packaging, CI, or the
   repository-signing/publish path.
2. **Issues in upstream components** (podman, crun, conmon, buildah, skopeo,
   netavark, aardvark-dns, fuse-overlayfs, catatonit, pasta, toolbox,
   containers-common). Report those to the respective upstream project; we
   rebuild from upstream source and will pick up their fixes.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Use GitHub's private vulnerability reporting:
**Security → Report a vulnerability** on this repository
(<https://github.com/slazarov/podman-ubuntu/security/advisories/new>).

If that is unavailable, email **stanislav@lazarov.group** with:

- affected component/script and version or suite (e.g. `stable-2604`, arm64)
- a description and, if possible, reproduction steps
- the impact you observed

You can expect an acknowledgement within a few days. Fixes are prioritized by
severity; coordinated disclosure is appreciated.

## Package integrity

- All published suites are **GPG-signed**; the public key is distributed as
  `podman-ubuntu.gpg` and installed to `/etc/apt/keyrings/`.
- Indexes use **Acquire-By-Hash** to avoid mismatches during CDN propagation.
- Report any signature, key, or index-integrity concern through the private
  channel above.

## Signing key rotation

The repository signing key lives only as the `GPG_PRIVATE_KEY` GitHub Actions
secret; its public half ships in the repo as `packaging/repo/pubkey.gpg` and is
published as `podman-ubuntu.gpg` (installed by users into
`/etc/apt/keyrings/`).

Because `apt` will reject a suite signed by a key it doesn't already trust,
rotation is done with a transition window rather than a hard swap:

1. Generate the new keypair; add its public key to `packaging/repo/pubkey.gpg`
   **alongside** the current one so the published `podman-ubuntu.gpg` carries
   both.
2. Publish once with the combined keyring so every user's next `apt update`
   picks up the new public key while the old signature is still trusted.
3. After a transition window (announce it in the README/release notes), replace
   the `GPG_PRIVATE_KEY` secret with the new private key so suites are signed by
   the new key only.
4. Drop the retired public key from `pubkey.gpg` in a later release.

Rotate promptly (skipping the window) if the private key is believed
compromised, and disclose via the channel above. Never commit a private key.

## Supported versions

Only the **latest published build of each track** (stable / v5 / nightly) for
each supported Ubuntu release (24.04, 26.04) receives fixes. Older snapshots are
not maintained — update to the current build.
