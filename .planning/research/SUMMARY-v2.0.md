# Project Research Summary

**Project:** Podman Debian Compiler — v2.0 APT Packaging & Distribution
**Domain:** Debian packaging, CI/CD automation, APT repository hosting
**Researched:** 2026-03-04
**Confidence:** HIGH

## Executive Summary

This project adds .deb packaging and automated distribution on top of an already-mature v1.2 build system that compiles 12+ Podman ecosystem components from source. The recommended approach is a minimal-dependency stack: nFPM (single Go binary) wraps pre-built binaries into .deb packages, reprepro manages the APT repository structure, and GitHub Actions with native ARM64 runners automates everything across both architectures. GitHub Pages serves the repository at zero infrastructure cost. The critical insight is that this project is "wrap pre-built binaries into .deb files," not "rebuild from source using Debian tooling." Tools like dpkg-buildpackage that expect to own the build are wrong for this project; nFPM + DESTDIR staging are correct.

The user journey is straightforward: add a GPG key and sources.list entry, run `apt install podman-suite`, and receive updates via standard `apt upgrade`. That simplicity requires getting the structural plumbing right upfront — specifically the `Conflicts/Replaces/Provides` triple declaration against official Ubuntu packages, the inter-package dependency graph, and the `conffiles` declaration for config files in `/etc/containers/`. These are not places for iteration; they must be correct before the first .deb is published because incorrect package metadata is expensive to fix after users have installed the packages.

The key risks are: (1) package naming and conflict strategy — packages named without the `podman-` prefix will collide with Ubuntu's official packages in ways that are expensive to fix after release; (2) GitHub Pages storage growth — the pool/ directory accumulates historical .deb files and will breach the 1 GB limit after 3-5 releases without active pruning; (3) ARM64 build approach — QEMU emulation is 10-30x slower than native and frequently times out on full Podman compilation. All three have clear mitigations documented in the research.

---

## Key Findings

### Recommended Stack

The packaging stack is purposefully lean. nFPM v2.45.0 is the correct tool for wrapping pre-built binaries: it requires only a single YAML file per component, handles Conflicts/Replaces/Provides natively, and installs as a single Go binary with zero runtime dependencies. reprepro manages the APT repository database, generates all required index files (Packages, Release, InRelease), handles GPG signing automatically, and supports incremental package addition. The morph027/apt-repo-action v3.7 wraps reprepro for GitHub Actions workflows and solves the "reprepro DB not persistent across runs" problem via `import-from-repo-url`. GitHub Actions with native `ubuntu-24.04-arm` runners builds both architectures without QEMU overhead.

**Core technologies:**
- **nFPM 2.45.0**: .deb creation from pre-built binaries — YAML-driven, zero deps, perfect for wrapping existing build output into .deb format
- **reprepro 5.4.x**: APT repository generation — generates correct Packages/Release/InRelease structure, handles GPG signing, supports incremental updates
- **morph027/apt-repo-action v3.7**: reprepro wrapper for GitHub Actions — solves DB persistence problem across CI runs via `import-from-repo-url`
- **GitHub Actions native ARM64 runners** (`ubuntu-24.04-arm`): Free for public repos since Jan 2025, GA since Aug 2025 — eliminates QEMU slowness (10-30x improvement)
- **GnuPG Ed25519 key**: Repository signing — Ed25519 is smaller and faster than RSA-4096 with equivalent security on Ubuntu 24.04; 2-year expiry with rotation documentation
- **actions/upload-pages-artifact v4 + actions/deploy-pages v4**: GitHub Pages deployment — official actions, v4 required (v3 deprecated Jan 2025)

**What to avoid:**
- checkinstall: unmaintained (2017 codebase), removed from Debian testing May 2024, produces broken packages, can brick systems
- dpkg-buildpackage: expects to own the build from source; requires 5+ config files per package (60+ total) and fights the existing build system
- QEMU emulation: 10-30x slower, frequent CI timeouts on Rust/Go compilation, can produce incorrect results
- apt-key (client-side): deprecated since apt 2.4 (2022); use `signed-by=` with per-repo keyring in `/usr/share/keyrings/`

### Expected Features

The research identifies a clear v2.0 scope — ship everything that enables the core "add repo, install, upgrade" user journey. Automated upstream version detection is deliberately deferred to v2.1 to validate the manual pipeline first.

**Must have (v2.0 table stakes):**
- Valid .deb packages for all 12 components with correct control files — apt/dpkg refuse malformed packages
- Inter-package dependency declarations — `apt install podman-podman` must auto-install crun, conmon, netavark, etc.
- Conflicts/Replaces/Provides against official Ubuntu packages — enables clean switchover from Ubuntu's official podman stack
- GPG-signed repository (InRelease + Release.gpg) — apt refuses unsigned third-party repos since Debian 9+
- Proper APT repository structure (dists/, pool/) — generated by reprepro, not manually
- amd64 + arm64 architecture packages — ARM servers are a primary target
- sources.list / DEB822 .sources configuration — users need a one-liner to add the repo
- Version numbering: `UPSTREAM_VERSION-REVISION` (e.g., `5.8.0-1`) — must sort correctly for upgrades
- Meta-package `podman-suite` — one-command install for entire Podman stack
- GitHub Actions CI/CD with manual workflow_dispatch trigger

**Should have (v2.1 additions after pipeline validation):**
- Automated upstream version detection via cron (daily GitHub API checks) — add once manual pipeline is proven stable
- Changelog generation from upstream release notes — enables `apt changelog`
- One-line setup script (`curl | bash`) — simplifies user onboarding

**Defer (v3+):**
- Multi-distribution support (Debian 12, Ubuntu 22.04) — only if demand materializes; multiplies build matrix
- Automated testing of installed packages in CI (podman run hello-world)
- Lintian compliance in CI pipeline

### Architecture Approach

The v2.0 architecture layers directly on the existing v1.2 system without restructuring it. The existing build scripts (build_*.sh) are modified minimally to support `DESTDIR` staging: instead of installing directly to `/usr/bin`, they install to a temporary staging directory that mirrors the filesystem layout. nFPM reads the nfpm.yaml config and packages the staging directory into a .deb. Three GitHub Actions workflows handle detection, building, and publishing as independent concerns connected by `workflow_call` / `needs:`. The `gh-pages` branch holds the APT repository with a completely separate git history from the source code.

**Major components:**
1. **DESTDIR-aware build scripts**: Existing build_*.sh modified to accept DESTDIR env var — same scripts work for direct install and packaging with minimal change to proven code
2. **nfpm/ config directory**: One nfpm.yaml per component with `${VERSION}` and `${ARCH}` placeholders substituted at build time — keeps packaging metadata in version control alongside build scripts
3. **GitHub Actions build workflow** (build-packages.yml): Matrix strategy across [amd64/ubuntu-24.04, arm64/ubuntu-24.04-arm], uploads .deb artifacts per architecture
4. **GitHub Actions repo workflow** (update-repo.yml): Downloads all arch artifacts, runs reprepro via morph027/apt-repo-action, deploys to GitHub Pages — MUST depend on ALL arch builds succeeding
5. **GitHub Actions version check workflow** (check-upstream.yml): Cron-scheduled, queries GitHub API for upstream tags, triggers build if new versions found (v2.1 feature, skeleton only in v2.0)
6. **APT repository on gh-pages branch**: reprepro-generated static files served by GitHub Pages — separate git history, never store .deb files in main branch

**Key patterns:**
- DESTDIR staging: build then package, not package then build — existing build scripts handle compilation, nFPM wraps output
- Package naming: `podman-*` prefix for all 12 + meta-package `podman-suite` — matches alvistack convention
- Atomic publishing: `needs: [build-amd64, build-arm64]` with `if: success()` — never publish partial repository
- Version tracking: `versions.json` records last-built version per component; upstream check compares against GitHub API

### Critical Pitfalls

1. **QEMU ARM64 emulation** — 10-30x slower than native, causes CI timeouts on Go+Rust compilation. Prevention: use `ubuntu-24.04-arm` native runners exclusively. Warning sign: workflow uses `docker/setup-qemu-action`.

2. **Package name conflicts with Ubuntu official packages** — naming packages `podman`, `crun`, etc. creates APT conflicts that are expensive to fix post-release (HIGH recovery cost). Prevention: `podman-*` prefix + `Conflicts/Replaces/Provides` triple declaration in every control file where the package overlaps with Ubuntu's official repo.

3. **Missing conffiles declaration** — config files in `/etc/containers/` silently overwritten on upgrade without user prompts. Prevention: `DEBIAN/conffiles` listing all files in `/etc/containers/` for the `podman-container-configs` package. Note: do NOT list `/usr/share/containers/seccomp.json` — it is generated data, not user-editable config.

4. **GPG key expiry** — breaks all user `apt update` simultaneously with EXPKEYSIG errors. Real-world example: GitHub CLI APT key expired in Sep 2022 (#6175) and again in 2024 (#9569), affecting thousands of users. Prevention: 5-year or no-expiry key for personal project, CI check warning at 90 days, documented rotation procedure.

5. **Broken APT indices from partial CI failure** — one architecture build fails but publish proceeds, leaving the other architecture with stale or missing packages. Prevention: `needs: [build-amd64, build-arm64]` + `if: success()` in publish step, pre-deploy validation counting packages per architecture.

6. **GitHub Pages 1 GB size limit** — each release adds 100-300 MB to the pool/ directory; limit exceeded after 3-5 releases without pruning. Prevention: reprepro version retention (keep only latest 2-3 versions per package per arch), CI size check warning at 800 MB.

---

## Implications for Roadmap

There is a clear dependency chain: the GPG key must exist before repository signing can work; the package naming and conflict strategy must be locked in before any .deb is built (renaming packages post-release is a HIGH recovery-cost operation); build scripts must support DESTDIR before packaging can run; and all packages must be verified before the repository is published. This dictates a linear phase structure where design decisions are front-loaded to avoid expensive rework.

### Phase 1: Foundation — Package Design, DESTDIR Support, and GPG Key

**Rationale:** All downstream work depends on three upfront decisions locked in: (1) package naming and Conflicts/Replaces/Provides strategy, (2) DESTDIR support in all build scripts, (3) GPG key generated and stored as GitHub secret. Getting the naming wrong is the highest recovery-cost pitfall in this project.

**Delivers:** Working DESTDIR support in all 12 build scripts, nfpm.yaml configs for all components with correct dependency graph and conflict declarations, conffiles list for container-configs package, GPG key generated and stored.

**Addresses features:** Package naming convention, inter-package dependency declarations, Conflicts/Replaces/Provides pattern, version numbering scheme (`UPSTREAM_VERSION-1`), conffiles declaration.

**Avoids pitfalls:** Package name conflicts (pitfall 3), missing conffiles (pitfall 5), version scheme breakage (pitfall 9), wrong inter-package dependencies (pitfall 7), `Architecture: all` mistake for binary packages.

### Phase 2: Local Package Building and Verification

**Rationale:** Before automating in CI, verify that nFPM + DESTDIR produces correct .deb packages for each component against a local Ubuntu 24.04 system. Catching errors here is far cheaper than discovering them in CI or after publishing to users.

**Delivers:** Verified .deb packages for all 12 components + `podman-suite` meta-package, buildable locally with `nfpm package --packager deb`, validated via install-upgrade-remove-purge cycles.

**Addresses features:** Valid .deb packages with control files, correct file placement, dependency auto-installation, meta-package one-command install.

**Avoids pitfalls:** Broken postinst scripts (pitfall 12), wrong architecture field (integration gotcha), missing Installed-Size, file permission issues, version comparison errors.

**Uses:** nFPM 2.45.0 CLI locally, `dpkg -I` / `dpkg -c` for inspection, `dpkg --compare-versions` for version validation, lintian for catching structural issues.

### Phase 3: APT Repository Setup

**Rationale:** Once packages are verified, set up the reprepro-managed APT repository structure. This includes the `conf/distributions` configuration, GPG signing integration, and the complete dists/ + pool/ directory structure. Validates that `apt update` and `apt install` work against the repository before any CI automation is built around it.

**Delivers:** Functioning local APT repository, `apt update` succeeds without `[trusted=yes]`, GPG signature chain verified (Release + Release.gpg + InRelease all present and valid), client setup documentation using DEB822 .sources format with `signed-by=`.

**Addresses features:** GPG-signed repository metadata, proper APT repository structure, sources.list configuration.

**Avoids pitfalls:** InRelease not generated (pitfall 11), publishing unsigned repository, deprecated `apt-key add` in user instructions (integration gotcha), signing key expiry — document rotation procedure and add CI expiry check.

**Uses:** reprepro 5.4.x, GnuPG Ed25519 key stored as GitHub secret `GPG_PRIVATE_KEY`, modern `signed-by=` sources.list format with keyring in `/usr/share/keyrings/`.

### Phase 4: GitHub Actions CI/CD Pipeline

**Rationale:** With verified packages and a working repository structure, automate the build-and-publish pipeline. Native ARM64 runners eliminate the QEMU trap. Atomic publishing (depends on both arch builds succeeding) prevents partial repository publication. This phase is the largest in scope and complexity.

**Delivers:** Three GitHub Actions workflows — build-packages.yml (matrix amd64+arm64), update-repo.yml (morph027/apt-repo-action + GitHub Pages deploy), check-upstream.yml skeleton (structure only, cron logic in v2.1). Both amd64 and arm64 packages built and published automatically on workflow_dispatch.

**Addresses features:** GitHub Actions CI/CD pipeline, amd64 + arm64 architecture support, GitHub Pages hosting at zero cost, manual workflow_dispatch trigger.

**Avoids pitfalls:** QEMU ARM64 slowness (pitfall 1), broken APT indices from partial failure (pitfall 6), secrets leaked in build logs (pitfall 8 — `set +x` before GPG steps, passphrase via fd 0), disk space exhaustion (pitfall 10 — free disk space at workflow start, clean artifacts between components), GitHub Pages size limit (pitfall 2 — add repo size check warning at 800 MB).

**Uses:** `ubuntu-24.04` + `ubuntu-24.04-arm` native runners, morph027/apt-repo-action v3.7, actions/upload-pages-artifact v4, actions/deploy-pages v4.

**Research flag:** The morph027/apt-repo-action `import-from-repo-url` configuration for multi-architecture repos and how it reconstructs the reprepro DB from an existing GitHub Pages repo should be verified against the action's v3.7 documentation during planning. The artifact upload/download pattern across matrix jobs needs careful design to avoid name collisions.

### Phase 5: Automated Upstream Version Detection (v2.1)

**Rationale:** Deferred from v2.0 to validate the manual pipeline first. Per FEATURES.md MVP definition, this is a v2.1 feature. Once the CI/CD pipeline is stable and has published at least one set of packages successfully, add the cron-based version detection.

**Delivers:** Daily cron workflow that queries GitHub API for each component's latest release tag, compares against `versions.json`, and triggers the build pipeline only when new versions exist. Selective rebuild support (only changed components).

**Addresses features:** Automated upstream version detection, rebuilds without manual intervention.

**Avoids pitfalls:** Scheduled workflows auto-disabled after 60 days of no repo activity (must have at least one commit per 60 days on default branch), pasta/passt date-based versioning special case (no GitHub Releases API — needs `git ls-remote` approach), crun no `v` prefix on tags (e.g., `1.25.1` not `v1.25.1`).

**Uses:** jq for GitHub API response parsing, `versions.json` for version state tracking, `repository_dispatch` or `workflow_dispatch` for triggering builds from the check workflow.

**Research flag:** pasta/passt version detection via `git ls-remote git://passt.top/passt` is documented in ARCHITECTURE.md but untested. Needs validation during Phase 5 planning. The `container-libs` namespaced tags (`common/vX.Y.Z`) also need specific parsing logic.

### Phase Ordering Rationale

- **Design before build:** Package naming conflicts (pitfall 3) and conffiles omissions (pitfall 5) have HIGH/MEDIUM recovery costs. Front-loading design decisions eliminates the most expensive rework scenarios.
- **Local validation before CI automation:** Catching package metadata errors locally (Phase 2) is faster and cheaper than debugging in GitHub Actions runs.
- **Repository before CI:** Validating the APT repository locally (Phase 3) ensures the CI pipeline's output target is correct before the automation is built around it.
- **Manual before automatic:** FEATURES.md explicitly recommends validating the manual pipeline before adding cron-based automation (Phase 5 deferred to v2.1).
- **Atomic publishing is foundational:** The `needs: [build-amd64, build-arm64]` structure must be designed into the CI from the start — retrofitting atomicity is harder than building it in correctly.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 4 (CI/CD Pipeline):** morph027/apt-repo-action `import-from-repo-url` behavior for multi-architecture repos needs validation against v3.7 docs. The artifact download pattern across matrix jobs (separate upload-artifact per arch, merge in publish job) needs careful design.
- **Phase 5 (Version Detection):** pasta/passt versioning is non-standard (date-based, self-hosted git server, no GitHub Releases API). `container-libs` uses namespaced tags (`common/vX.Y.Z`). Both need specific parsing logic validated before implementation.

Phases with standard patterns (skip research-phase):
- **Phase 1 (Foundation):** DESTDIR pattern is well-documented and used in containers/ ecosystem Makefiles. nFPM YAML syntax is stable with comprehensive official docs.
- **Phase 2 (Local Packaging):** nFPM package creation workflow is well-documented. dpkg inspection tools are standard.
- **Phase 3 (APT Repository):** reprepro + GitHub Pages is a well-documented pattern with multiple verified tutorials and the Debian Wiki as authoritative reference.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All tools verified against official sources: nFPM docs (goreleaser.com), GitHub Actions ARM64 runner changelogs (Jan 2025, Aug 2025, Jan 2026), reprepro Debian Wiki, morph027/apt-repo-action v3.7 release notes |
| Features | HIGH | Debian Policy Manual (primary source for Conflicts/Replaces/Provides, conffiles, version numbering), official dpkg docs, alvistack naming convention cross-verified against OBS package listing |
| Architecture | HIGH | Existing codebase fully analyzed + Debian packaging tutorial + GitHub Actions documentation. DESTDIR support in containers/ ecosystem Makefiles verified as standard. Three-workflow pattern (detect/build/publish) is well-established |
| Pitfalls | HIGH | Verified against Debian Policy, GitHub runner documentation, and documented real-world incidents (GitHub CLI GPG key expiry issues #6175 and #9569). QEMU slowness documented in docker/setup-qemu-action issue tracker |

**Overall confidence:** HIGH

### Gaps to Address

- **pasta/passt version detection:** passt uses date-based versions from a self-hosted git server (passt.top), not GitHub Releases. The `git ls-remote git://passt.top/passt` approach is documented in ARCHITECTURE.md but untested. Validate during Phase 5 planning.
- **Inter-package dependency version pinning:** ARCHITECTURE.md shows `podman-netavark` depends on `podman-aardvark-dns` but does not specify whether to use exact (`=`) or minimum (`>=`) version constraints. Decide during Phase 1 — exact pinning ensures known-good combinations but requires synchronized releases; minimum pinning allows independent upgrades.
- **`podman-container-configs` Architecture field:** Should be `Architecture: all` (config files and man pages only, no compiled binaries). Confirm reprepro correctly handles an `Architecture: all` package in a multi-arch repository (should appear in both amd64 and arm64 Packages indices).
- **ARM64 runner availability for private repos:** FEATURES.md noted this as LOW confidence. STACK.md and PITFALLS.md both confirm availability since Jan 2026. Resolved — gap is closed.
- **morph027/apt-repo-action multi-arch behavior:** The action's handling of separate amd64 and arm64 .deb files being added to the same reprepro instance needs verification during Phase 4 planning to ensure both architectures appear in the correct Packages indices.

---

## Sources

### Primary (HIGH confidence)
- nFPM official documentation (nfpm.goreleaser.com) — configuration reference, YAML schema, installation, Debian-specific options
- nFPM GitHub releases — v2.45.0 released Feb 4, 2026
- Debian Policy Manual (debian.org/doc/debian-policy) — Conflicts/Replaces/Provides, conffiles, maintainer scripts, version numbering (ch-relationships, ch-controlfields, ch-maintainerscripts, ap-pkg-conffiles)
- dpkg-deb man page (man7.org) — binary package building, `--root-owner-group` flag
- reprepro Debian Wiki (wiki.debian.org/DebianRepository/SetupWithReprepro) — repository configuration reference
- GitHub Actions ARM64 runners changelog — Jan 2025 (preview public repos), Aug 2025 (GA public repos), Jan 2026 (private repos available)
- actions/deploy-pages + actions/upload-pages-artifact — v4 required, v3 deprecated Jan 2025
- GitHub Pages limits documentation (docs.github.com/en/pages) — 1 GB site limit, 100 GB/month bandwidth
- SecureApt Debian Wiki — repository signing chain, signed-by pattern, deprecated apt-key
- CheckInstall Debian Wiki — explicit warnings about limitations and distribution unsuitability
- Existing project codebase (all 12 build scripts, config.sh, functions.sh) — DESTDIR support analysis, component inventory
- GPG signing deb packages and APT repositories (packagecloud.io) — InRelease/Release.gpg signing chain

### Secondary (MEDIUM confidence)
- morph027/apt-repo-action v3.7 (github.com/morph027/apt-repo-action) — reprepro wrapper, import-from-repo-url option, keyring package generation
- alvistack OBS packages (opensuse.org/repositories/home:/alvistack/xUbuntu_24.04/) — validated `podman-netavark`, `podman-aardvark-dns` naming convention in amd64/ listing; known issue with missing Conflicts (#7)
- Linsomniac: Building APT repos on GitHub Pages (Mar 2025) — complete workflow example with GPG setup
- Building binary deb packages practical guide (internalpointers.com) — dpkg-deb workflow
- Publishing APT and YUM/DNF repos on GitHub Pages (Feb 2026) — GitHub Actions + reprepro pattern
- Disk space management on GitHub Actions runners (geraldonit.com) — ARM64 runner disk space, cleanup strategies

### Tertiary (LOW confidence)
- pasta/passt version detection via `git ls-remote git://passt.top/passt` — documented approach in ARCHITECTURE.md, not yet validated
- uraimo/run-on-arch-action — QEMU fallback (documented as last resort only, not recommended)

---
*Research completed: 2026-03-04*
*Ready for roadmap: yes*
