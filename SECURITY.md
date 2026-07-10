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

## Supported versions

Only the **latest published build of each track** (stable / edge / nightly) for
each supported Ubuntu release (24.04, 26.04) receives fixes. Older snapshots are
not maintained — update to the current build.
