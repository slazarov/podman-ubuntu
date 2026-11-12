# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Component *package* versions track upstream Podman-stack releases and are listed
in the APT repository, not here; this file tracks the **pipeline** itself.

## [Unreleased]

Work landed since `v1.2`, slated for the next release, `v1.3`.

### Security
- **Repository signing key replaced (2026-11-11)** — the previous key
  `B7F2FD0509240BDACD92B1D1E56CE5A0B9702F11` is considered compromised. All
  suites are now signed by `1C93692FE1498A4DCFFE11D3F5519D2D6171DB3F`; users
  must re-download `podman-ubuntu.gpg` (see the README notice).

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
- protoc now comes from Ubuntu's `protobuf-compiler` package (3.21.x on 24.04
  and 26.04) instead of a download from protobuf's GitHub releases.
  `install_protoc.sh`, `PROTOC_VERSION`/`PROTOC_TAG` and the nightly lookup of
  the latest release are gone. That lookup used the unauthenticated GitHub API
  and, when rate-limited, returned an empty version that failed the build.
- `podman-pasta` on stable/v5 is now built from a soaked passt release tag
  (`PASTA_TAG`, resolved by `resolve_versions.sh`) and versioned by that
  release's date (`2026_10_02.cba3570` → `20261002`; a later same-day release
  becomes `20261002.1`) instead of the build date,
  so rebuilds no longer bump it and the republish guard now compares it.
  Nightly still builds HEAD. (Version format superseded by the epoch entry
  below.)
- `podman-pasta` versions now carry Debian epoch `1` on every track, with the
  date dotted: `1:2026.10.02`, `1:2026.10.02.1` for a later same-day release,
  and `1:2026.11.02~git<sha>` on nightly. The release-date versions above sorted
  below the build-date (`20261101`) and already-published (`20261024`) versions,
  so apt never upgraded those installs; the epoch sorts above all of them. The
  epoch goes through nFPM's `epoch:` field, so filenames carry no colon, and the
  dotted date keeps them distinct from the old `20261002`-style pool files. The
  epoch is permanent.
- `podman-fuse-overlayfs` is now optional: `podman-podman` and `podman-suite`
  *Recommend* it instead of depending on it (native rootless overlay on kernel
  ≥ 5.13), packaging revision bumped to `podman3`, and the `/dev/fuse` preflight
  check (VAL-03) is a warning rather than a build error.
- GitHub Actions pinned to commit SHAs (kept fresh by Dependabot).
- Generated APT landing page renamed "Podman for Debian" → "Podman for Ubuntu".
- CI: each build cell runs `verify_depends.sh` after packaging, with a
  per-distro (24.04 + 26.04) dependency baseline. 24.04 skopeo may link
  `libsqlite3-0` (host-dependent), which is accepted but not required.
- CI: the lint workflow installs the integration-test tools and sets
  `REQUIRE_INTEGRATION_DEPS=1`, so the reprepro/gpg harnesses run on every PR
  instead of skipping.
- CI: least-privilege permissions (only publish can write Pages) and
  `persist-credentials: false` on every checkout.

- CI: Rust (sccache) and C (ccache) compiler caches, keyed by distro,
  architecture, track, Rust version and sccache version, with bounded sizes.
  `CACHE_STRICT=true` fails a build whose enabled wrapper is missing, and each
  build cell checks that the caches saw compile requests. The sccache download
  is checked against a SHA256 pinned per architecture.
- CI: `scripts/ci_helpers.sh` (shared, unit-tested CI logic) and
  `tests/lib/mock_http_server.py`, a mock server that injects HTTP errors and
  cut-off downloads.
- CI: workflow runs queue per track (`queue: max`) and build in parallel;
  publish jobs share one `pages-deploy` queue and wait until the deploy reaches
  the live site, so the next publish starts from what was deployed.
- CI: the stable/v5 resolver runs once per run, in `resolve-track`; the
  republish guard and the build cells validate and use its output. A resolver
  hold skips the build and publish cleanly, even with `force_rebuild`.
- CI: the nightly change detection keeps a checkpoint of the commits built and
  deployed per build cell, saved only after a confirmed deploy and only for the
  cells that were published.
- CI: publish reads each build cell's conclusion, publishes the cells that
  succeeded (a distro with one failed arch still publishes, keeping that arch's
  last-good packages) and fails if a successful cell's artifact is missing. The
  smoke test runs for the distros this run published.
- CI: the republish guard also compares `podman-suite`.

### Fixed
- toolbox builds again on Ubuntu 24.04. The `CC="ccache gcc"` a C component
  turns on no longer carries over into later components, and the toolbox build
  links with `-z lazy`. Before this, the completion step failed with
  `undefined symbol: nvmlGpuInstanceGetComputeInstanceProfileInfoV`.
- A network error, HTTP 5xx or 429, or a cut-off download from the live
  repository no longer makes a suite look unpublished, silently drops a
  package, or (when an arch's build failed) wipes that arch from the suite.
  Downloads are retried and then stop the publish.
- A rebuilt package with the same name, version and architecture as one in the
  live target suite no longer replaces the published file; the published bytes
  are kept.
- Regenerated suites keep the previous generation of their indexes under
  `by-hash/`, so a client holding the old `Release` during a deploy still finds
  them.
- A failing `gpg --clearsign` is no longer hidden; signing failures stop the
  publish, and the integrity gate checks every suite's signatures against the
  published key and the `Release` shape (`Suite`, `Codename`, `SHA256`, a
  `Packages` entry per architecture, `Size`/`SHA256` per stanza).
- The smoke test reads the assembled repository with `Signed-By` instead of
  `Trusted: yes`, fails on a network error while probing the live repository
  instead of skipping the upgrade scenario, and checks the installed versions
  after the upgrade.
- Scheduled runs are no longer dropped: the `pages` concurrency group uses
  `queue: max`. GitHub's default kept one pending run and cancelled the rest,
  so a stable or v5 cron could vanish behind a still-running nightly.
- `build_toolbox.sh` sets `TOOLBOX_PATH` for the compile step, so the shell
  completions build inside a podman container (toolbox refused to run when
  `/run/.containerenv` exists).
- `verify_depends.sh` requires `objdump`; without it the detector silently
  reported no dependencies.
- `setup.sh` now starts the per-script timer, so ">>> Completed:" reports each
  script's real duration instead of the time since the Unix epoch.

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
