# Podman Debian Compiler

## What This Is

A shell script suite that compiles and installs the latest stable Podman from source on Debian/Ubuntu systems. Works on both amd64 and ARM64 architectures with automatic detection. Features fully unattended installation, pre-flight system validation, multi-layer build caching (sccache, Go cache, ccache, mold), production-ready container runtime configuration with seccomp profiles, and complete man page documentation.

## Core Value

Compile and install Podman on any Debian/Ubuntu system without user interaction.

## Requirements

### Validated

- ✓ Compile Podman from source on amd64 — existing
- ✓ Install compiled Podman to system — existing
- ✓ Auto-detect system architecture (amd64 vs ARM) — v1.0
- ✓ Compile Podman on ARM Ubuntu/Debian VMs — v1.0
- ✓ Run fully unattended/non-interactive — v1.0
- ✓ No blocking prompts during installation — v1.0
- ✓ Architecture-aware toolchain installers (Go, Protoc, Rust) — v1.0
- ✓ Robust error handling with immediate failure and context — v1.0
- ✓ Progress tracking with elapsed time — v1.0
- ✓ Build output logging — v1.0
- ✓ Clean uninstall script — v1.0
- ✓ Parallel compilation with make -j NPROC — v1.0
- ✓ Shallow git clones for faster downloads — v1.0
- ✓ Go compiler optimizations (GOGC, gcflags, ldflags) — v1.0
- ✓ Cargo parallelization — v1.0
- ✓ Remove deprecated runc and slirp4netns (crun+pasta only) — v1.1
- ✓ Pre-flight system validation (cgroups, subuid, FUSE, kernel, noexec) — v1.1
- ✓ sccache for Rust build caching (50-90% rebuild speedup) — v1.1
- ✓ Enhanced containers.conf (crun runtime, netavark network, seccomp) — v1.1
- ✓ Persistent Go cache shared across component builds — v1.1
- ✓ Opt-in ccache for C builds — v1.1
- ✓ Opt-in mold linker for Rust builds — v1.1
- ✓ Symmetric uninstall (removes everything install adds) — v1.1
- ✓ Build container-libs from source with seccomp.json generation — v1.2
- ✓ Install runtime config files (seccomp, policy, registries, storage) — v1.2
- ✓ Man pages for container config files — v1.2
- ✓ Symmetric uninstall of all container-libs artifacts — v1.2
- ✓ Debian packaging for all components as individual .deb packages — v2.0
- ✓ Package prefixing (podman-*) with Conflicts/Replaces on official Ubuntu packages — v2.0
- ✓ Inter-package dependency declarations — v2.0
- ✓ GitHub Actions CI/CD for automated builds (amd64 + ARM64 native runners) — v2.0
- ✓ APT repository hosted on GitHub Pages (GPG-signed, stable/edge/nightly) — v2.0
- ✓ Scheduled auto-rebuild on upstream releases + manual trigger — v2.0
- ✓ Nightly track built from latest upstream commits with snapshot versioning — v2.0

- ✓ Per-distro version suffixes (~ubuntu24.04.podman1 / ~ubuntu26.04.podman1) with dpkg-verified ordering — v3.0 (Validated in Phase 19: Per-Distro Versioning & Dependency Mapping)
- ✓ Per-distro dependency mapping via direct DT_NEEDED soname detection injected into nFPM configs (libgpgme45/libsubid5 self-correct on 26.04) — v3.0 (Validated in Phase 19)
- ✓ Per-distro APT suites with version-based names (9-suite repo: stable/edge/nightly × 2404/2604 + 3 bare legacy aliases, single URL, single GPG key, Acquire-By-Hash) — v3.0 (Validated in Phase 20: 62/62 integration harness + end-to-end ci_publish on Lima)
- ✓ Migration path for existing users on bare stable/edge/nightly suite names (verbatim-served bare aliases preserve cached Suite — no apt prompt, no .sources edit) — v3.0 (Validated in Phase 20: D-15 old→new swap simulation; production-CDN confirmation deferred to first publish)
- ✓ CI build matrix extended to Ubuntu 26.04 (4-cell distro×arch matrix, `ubuntu:26.04` containers on native runners with one-line GA-runner swap; distro-isolated caches/artifacts, publish gated on all four cells) — v3.0 (Validated in Phase 21: CI Build Matrix Extension to 26.04)

### Active

- [ ] All three tracks (stable/edge/nightly) published for both 24.04 and 26.04
- [ ] Docs/setup instructions covering both distro versions (incl. bare-suite deprecation timeline)

### Out of Scope

- Podman version pinning — always latest stable
- GUI installation wizard — CLI only
- Non-Debian/Ubuntu distributions — focus on Debian/Ubuntu
- ARM 32-bit support (armv7l) — focusing on 64-bit ARM only
- Resumable builds — complexity not needed for personal use
- Component selection — full installation is the goal
- Parallel build orchestration — complexity disproportionate to gain
- CNI networking — removed in Podman 5.0
- Building container-libs Go libraries as importable packages — only config files and generated artifacts needed
- Custom seccomp profile modifications — default upstream profile is sufficient

## Current Milestone: v3.0 Ubuntu 26.04 Support

**Goal:** Users on both Ubuntu 24.04 and 26.04 can add the APT repo, enable their distro's suite, and install Podman packages that install and run cleanly on their OS version.

**Target features:**
- Per-distro APT suites, version-based naming — stable-2404/edge-2404/nightly-2404 + stable-2604/edge-2604/nightly-2604 (amd64 + arm64 each)
- Per-distro dependency mapping in nFPM configs — fixes the verified failure: dependency packages renamed/replaced between 24.04 and 26.04
- CI build matrix extended to 26.04 on native GitHub runners (ubuntu-26.04 / ubuntu-26.04-arm), container fallback if unavailable
- All three tracks (stable/edge/nightly) built and published for both distros
- Migration path for existing users whose .sources files point at current stable/edge/nightly names
- Docs/setup instructions updated for both distros

## Context

Shipped v2.0 with full .deb packaging (nFPM), GPG-signed reprepro APT repo on GitHub Pages (stable/edge/nightly suites), and GitHub Actions CI on native amd64+arm64 runners with daily nightly builds.
Tech stack: Bash, Git, Go, Rust, Make, Cargo, Meson, sccache, ccache, mold, go-md2man, nFPM, reprepro, GitHub Actions.
v1.0 shipped 2026-03-03, v1.1 shipped 2026-03-04, v1.2 shipped 2026-03-04, v2.0 shipped 2026-03-08.

Ubuntu 26.04 verified broken with current packages: dependency packages used on 24.04 are renamed/replaced on 26.04 (user tested). nFPM configs declare distro-specific library deps (libseccomp2, libsystemd0, json-c parser dep via ${CRUN_PARSER_DEPEND}, etc.) that must resolve per-distro.

Binaries built on 24.04 are forward-compatible with 26.04 (older glibc), but the reverse is not true — per-distro builds keep each distro natively correct.

v2.0 decision "Codename = Suite name to avoid createsymlinks complexity" gets revisited in v3.0: suite renames (stable → stable-2404) break existing users unless aliases or a migration path is provided.

Build caching layers: sccache (Rust), ccache (C), Go cache (Go), mold linker (Rust linking). Fresh build ~15-20 min, cached rebuild dramatically faster.

container-libs (https://github.com/containers/container-libs) is the monorepo for containers-common: provides seccomp.json, policy.json, default.yaml, storage.conf, and man pages needed by Podman at runtime. Build requires Go and go-md2man (both already in our toolchain).

All v1.1 tech debt resolved: seccomp.json now properly built and installed.

Reference: alvistack (http://download.opensuse.org/repositories/home:/alvistack/xUbuntu_24.04/) uses podman-* prefix pattern for non-conflicting package names.

## Constraints

- **Platform:** Debian/Ubuntu only (amd64 and ARM64)
- **Interaction:** Zero interactive prompts (DEBIAN_FRONTEND=noninteractive, apt -y flags, etc.)
- **Architecture:** Must auto-detect and work on both amd64 and ARM64

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Auto-detect architecture | One script works everywhere, no branching needed | ✓ Good - Centralized detect_architecture() |
| Latest stable version only | Simplicity over flexibility for personal use | ✓ Good - No version pinning complexity |
| Non-interactive mode | Set-and-forget installation experience | ✓ Good - DEBIAN_FRONTEND=noninteractive throughout |
| Use uname -m for arch detection | More portable than dpkg-based methods | ✓ Good - Works on all systems |
| Circular sourcing config.sh <-> functions.sh | Enables shared utilities and config | ⚠️ Revisit - Guarded but fragile pattern |
| set -euo pipefail everywhere | Catch all errors immediately | ✓ Good - Consistent strict mode |
| Parallel make with NPROC | 2-4x build speedup on multi-core | ✓ Good - Auto-detects CPU count |
| Shallow git clones (--depth 1) | ~95% network transfer reduction | ✓ Good - User can override |
| Go compiler optimizations (GOGC=off) | ~30% faster Go compilation | ✓ Good - Uses more RAM but worth it |
| Environment variable overrides | User control over optimizations | ✓ Good - All settings configurable |
| Remove runc/slirp4netns | crun 50% faster, 8x less memory; pasta is documented successor | ✓ Good - Cleaner codebase, better defaults |
| Pre-flight validation | Fail early with clear messages vs cryptic build failures | ✓ Good - 5 checks in <5 seconds |
| sccache via pre-built binary | No compilation needed, musl binary works everywhere | ✓ Good - Clean install/uninstall |
| Opt-in build caching (default off) | Zero behavior change for existing users | ✓ Good - Progressive enhancement |
| Local disk caching for sccache | Simpler than S3/WebDAV, no external deps | ✓ Good - Matches personal use case |
| mold via .cargo/config.toml | Avoids RUSTFLAGS conflicts with sccache RUSTC_WRAPPER | ✓ Good - Clean integration |
| ccache with COMPILERCHECK=content | Correct cache invalidation on GCC upgrades | ✓ Good - Avoids stale cache hits |
| Centralized Go cache in config.sh | Single source of truth, no per-script overrides | ✓ Good - DRY principle |
| Target only make seccomp.json | Only seccomp profile needed, not full container-libs build | ✓ Good - Minimal build, fast execution |
| install -m 0644 for config files | Matches upstream Makefile conventions | ✓ Good - Consistent permissions |
| go-md2man for man pages | Already in toolchain from other builds | ✓ Good - No new dependencies |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-07 after Phase 21 completion (CI build matrix extension to 26.04)*
