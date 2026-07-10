# Project Overview

## What This Is

`podman-ubuntu` is a **shell-orchestrated build & publish pipeline** — not an
application. It compiles the Podman container stack (12 packaged components)
from upstream source on Ubuntu 24.04 and 26.04 (amd64 + arm64), packages each
into a `.deb` with nFPM, and publishes a GPG-signed reprepro APT repository to
GitHub Pages across three release tracks.

There is no `package.json`, no compiler of its own, no app server — everything
is Bash driving upstream toolchains (Go, Rust, C/autotools, Meson).

## Core Value

Give Ubuntu users a single APT repository from which they can install a current,
natively-built Podman stack (`apt install podman-*`) that installs and runs
cleanly on their OS version — without waiting on distro packaging lag and
without interactive prompts anywhere in the build.

## Release Tracks

| Track | Source selection | Versioning |
|-------|------------------|-----------|
| **stable** | `source versions-stable.env` → pins every `*_TAG` | e.g. `6.0.0~ubuntu24.04.podman1` |
| **edge** | no env → highest upstream tag auto-resolved | resolved from checked-out tag |
| **nightly** | `NIGHTLY_BUILD=true SHALLOW_CLONE=false` → upstream HEAD | `~git{YYYYMMDD}.{sha}` snapshot |

All three are published for both distros as a **9-suite** repo:
`{stable,edge,nightly}-{2404,2604}` plus three bare legacy aliases
(`stable`/`edge`/`nightly`, deprecated, kept for migration).

## Repository Type

**Monolith** — a single cohesive Bash codebase. Project classification:
infrastructure / build-and-release pipeline. No API surface, no data models, no
UI components (the only HTML is the generated APT-repo landing page).

## Tech Stack Summary

| Category | Technology |
|----------|-----------|
| Orchestration | Bash (`set -euo pipefail`), Make |
| Built languages | Go (podman, buildah, skopeo, conmon, toolbox), Rust (netavark, aardvark-dns, fuse-overlayfs v2+), C/autotools (crun, catatonit, pasta, fuse-overlayfs v1) |
| Toolchains | Go (auto-detected from podman `go.mod`), Rust (rustup at netavark MSRV), protoc, Meson, go-md2man |
| Build caching | sccache (Rust), ccache (C), Go build cache, mold linker |
| Packaging | nFPM (`.deb`), DESTDIR staging |
| Repository | reprepro, Acquire-By-Hash, GPG signing |
| Hosting / CI | GitHub Pages, GitHub Actions (native amd64 + arm64 runners) |
| Local testing | Lima VMs (`ubuntu-24`, `ubuntu-26`) |

## Current Milestone (as of scan)

**v3.0 — Ubuntu 26.04 support.** Per-distro APT suites with version-based
names, per-distro dependency mapping (direct `DT_NEEDED` soname detection),
CI build matrix extended to a 4-cell distro×arch grid, and a migration path
for existing users on the bare `stable`/`edge`/`nightly` suite names.

## Shipped History

- v1.0–v1.2 (Mar 2026): source compile + install, preflight validation, build caching, container-libs config generation.
- v2.0 (Mar 2026): full `.deb` packaging (nFPM), GPG-signed reprepro APT repo on GitHub Pages, GitHub Actions CI on native amd64+arm64, daily nightly builds.
- v3.0 (in progress): Ubuntu 26.04 support, per-distro versioning + dependency mapping, 4-cell CI matrix.

## Explicit Non-Goals

Version pinning of Podman for end users (always latest per track), GUI installer,
non-Debian/Ubuntu distros, 32-bit ARM, resumable builds, component selection,
CNI networking (removed upstream in Podman 5.0), custom seccomp modifications.
