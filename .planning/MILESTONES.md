# Milestones

## v2.0 APT Packaging & CI/CD (Shipped: 2026-03-08)

**Phases completed:** 4 phases (14, 15, 16, 18 — Phase 17 superseded by Phase 18's nightly cron workflow), 7 plans
**Timeline:** 2026-03-04 → 2026-03-08
**Files modified:** 43 (+2,730, -106 lines)
**Git range:** feat(14-01) → fix(ci) 45b2c8a

**Key accomplishments:**
1. Built 12 component .deb packages + podman-suite meta-package via nFPM with DESTDIR staging, podman-* prefixing, and Conflicts/Replaces/Provides against official Ubuntu packages
2. GPG-signed (Ed25519) reprepro APT repository on GitHub Pages with three suites: stable, edge, nightly
3. GitHub Actions CI with native amd64 (ubuntu-24.04) + arm64 (ubuntu-24.04-arm) runners, atomic publish, and per-track artifact retention
4. Daily cron nightly builds from latest upstream commits with ~git snapshot versioning that dpkg-sorts below tagged releases
5. Renamed project podman-debian → podman-ubuntu; comprehensive README with APT install and build-from-source paths

**Scope notes:**
- Phase 17 (Upstream Automation) was absorbed into Phase 18 — upstream change detection runs in the cron workflow
- Plan 16-02's workflow was delivered via 18-02 (three-suite publish + nightly/cron triggers)

---

## v1.2 Include Common Libraries (Shipped: 2026-03-04)

**Phases completed:** 3 phases, 3 plans, 6 tasks
**Timeline:** 2026-03-04 (single-day execution)
**Files modified:** 17 (+1,477, -319 lines)
**Git range:** feat(11-01) → feat(13-01)

**Key accomplishments:**
1. Built container-libs from source — clones containers/container-libs monorepo and generates seccomp.json via Go codegen
2. Installed 6 runtime config files to system paths — seccomp.json, policy.json, registries.conf, storage.conf, registries.d/default.yaml, containers.conf
3. Built and installed 15 section-5 man pages from container-libs source using go-md2man
4. Extended uninstall.sh with symmetric cleanup for all new artifacts (man pages, config files, build directory)

**Resolved tech debt:**
- seccomp.json now installed to /usr/share/containers/seccomp.json (closed v1.1 open item)

---

## v1.1 Ecosystem Audit (Shipped: 2026-03-04)

**Phases completed:** 5 phases, 7 plans
**Timeline:** 2026-03-03 → 2026-03-04 (2 days)
**Files modified:** 18 (+524, -34 lines)

**Key accomplishments:**
1. Removed deprecated runc and slirp4netns build scripts — crun+pasta ecosystem only
2. Added pre-flight validation (cgroups v2, subuid/subgid, FUSE, kernel version, noexec)
3. Integrated sccache for 50-90% faster Rust rebuilds with opt-in feature flag
4. Enhanced containers.conf with runtime (crun), network (netavark), and seccomp defaults
5. Added persistent Go cache (GOCACHE + GOMODCACHE) shared across all Go component builds
6. Added opt-in ccache for C builds and mold linker for Rust builds

**Tech debt:**
- Minor: install_dependencies.sh lacks DEBIAN_FRONTEND (relies on setup.sh)
- Minor: Circular sourcing pattern config.sh ↔ functions.sh (guarded but fragile)
- Open: seccomp.json not installed — containers.conf references /usr/share/containers/seccomp.json but file not present (see debug session)

---

## v1.0 MVP (Shipped: 2026-03-03)

**Phases completed:** 5 phases, 13 plans, 12 tasks
**Timeline:** 2026-03-03 (single-day execution)
**Lines of code:** 67,872 shell code

**Key accomplishments:**
1. Cross-platform architecture support - Single script works on both amd64 and ARM64 with auto-detection
2. Zero-interaction installation - Fully unattended setup with DEBIAN_FRONTEND=noninteractive
3. Robust error handling - Strict mode (set -euo pipefail) in all 18 scripts with context-rich error reporting
4. User experience enhancements - Progress tracking with timing, build logging, and clean uninstall
5. Build performance optimization - Parallel compilation, shallow git clones, and Go compiler optimizations

**Tech debt:**
- Minor: install_dependencies.sh lacks DEBIAN_FRONTEND (relies on setup.sh)
- Minor: Circular sourcing pattern config.sh ↔ functions.sh (guarded but fragile)
- Minor: SCCACHE_ENABLED exported but unused (intentional for future use)

---

