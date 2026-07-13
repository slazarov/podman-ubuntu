# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Component *package* versions track upstream Podman-stack releases and are listed
in the APT repository, not here; this file tracks the **pipeline** itself.

## [Unreleased]

Work landed since `v1.2`, slated for the next release, `v1.3`.

### Added
- **Debian packaging** — every component built into a `podman-*` `.deb` via nFPM,
  with `Conflicts`/`Replaces`/`Provides` against the official Ubuntu packages and
  auto-detected inter-package dependencies.
- **Hosted APT repository** — GPG-signed reprepro repo on GitHub Pages with
  `stable` / `v5` / `nightly` tracks and Acquire-By-Hash indexes.
- **Auto-updating release tracks** — a version resolver
  (`scripts/resolve_versions.sh`) materializes concrete component tags from a
  per-track policy file (`versions-stable.env` / `versions-v5.env`): exact-tag
  freeze > `*_SERIES` anchored-major cap > float, with buildah derived from
  podman's `go.mod` and a soak window (`STABLE_SOAK_DAYS`, default 7) that defers
  brand-new upstream tags. **stable** tracks Podman **6.x**; the former `edge`
  track is retired and replaced by **v5**, a Podman **5.x** maintenance line
  (held on the netavark/aardvark 1.x + buildah 1.43.x set that Podman 5.x
  requires). Both auto-updating tracks run on the daily cron, guarded by
  `check_republish_needed.sh`.
- **CI/CD** — GitHub Actions building natively on amd64 + arm64, scheduled
  daily builds per track (nightly/stable/v5), and gated atomic publish.
- **Ubuntu 26.04 support** — per-distro version suffixes
  (`~ubuntu24.04.podman1` / `~ubuntu26.04.podman1`) with dpkg-verified ordering,
  per-distro dependency mapping (direct `DT_NEEDED` soname detection), an 8-suite
  repo (`{stable,v5,nightly}-{2404,2604}` + the deprecated bare `stable`/`nightly`
  aliases; `v5` is distro-qualified only), a 4-cell distro×arch CI matrix, and a
  migration path for existing users.
- **Repo hardening** — ShellCheck + shfmt + unit-test CI gate (`lint.yml`),
  `.pre-commit-config.yaml`, `.editorconfig`, `.shellcheckrc`, Dependabot,
  `SECURITY.md`, PR/issue templates, and this changelog.

### Changed
- GitHub Actions pinned to commit SHAs (kept fresh by Dependabot).
- Generated APT landing page renamed "Podman for Debian" → "Podman for Ubuntu".

### Removed
- Stale, unused root `index.html` (the authoritative page is generated during publish).

## [1.2] - 2026-03-04
### Added
- Build `container-libs` from source with `seccomp.json` generation.
- Install runtime config files (seccomp, policy, registries, storage, default).
- Man pages for the container config files.
- Symmetric uninstall of all container-libs artifacts.

## [1.1] - 2026-03-04
### Added
- Pre-flight system validation (cgroups v2, subuid/subgid, `/dev/fuse`, kernel, noexec).
- Opt-in build caching: sccache (Rust), ccache (C), persistent Go cache, mold linker.
- Enhanced `containers.conf` (crun runtime, netavark network, seccomp).
### Removed
- Deprecated `runc` and `slirp4netns` (crun + pasta only).

## [1.0] - 2026-03-03
### Added
- Compile and install the Podman stack from source on Debian/Ubuntu.
- Automatic architecture detection (amd64 / arm64) and arch-aware toolchain installers (Go, Rust, protoc).
- Fully non-interactive/unattended builds with strict error handling, progress timing, and build logging.
- Parallel compilation, shallow clones, and Go/Cargo build optimizations.
- Clean, symmetric uninstall script.

[Unreleased]: https://github.com/slazarov/podman-ubuntu/compare/v1.2...HEAD
[1.2]: https://github.com/slazarov/podman-ubuntu/compare/v1.1...v1.2
[1.1]: https://github.com/slazarov/podman-ubuntu/compare/v1.0...v1.1
[1.0]: https://github.com/slazarov/podman-ubuntu/releases/tag/v1.0
