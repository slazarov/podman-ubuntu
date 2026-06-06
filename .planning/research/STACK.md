# Stack Research

**Domain:** Multi-distro APT packaging (add Ubuntu 26.04 alongside existing 24.04) for a from-source Podman build/publish pipeline
**Researched:** 2026-06-05 (v3.0 milestone)
**Confidence:** HIGH (package names verified on packages.ubuntu.com for `resolute` and `noble`; runner status verified on actions/runner-images issues)

**Scope note:** This is a SUBSEQUENT-milestone stack delta. The existing v2.0 stack (Bash, Go, Rust, Make, Cargo, Meson, sccache, ccache, mold, go-md2man, nFPM v2.45.0, reprepro, GitHub Actions native amd64+arm64 runners, GPG-signed reprepro APT repo on Pages, podman-* package naming with Conflicts/Replaces) is validated and NOT re-researched here. This document covers ONLY what changes or is added to build and publish Ubuntu 26.04 packages in parallel with 24.04.

---

## Headline Findings

1. **GitHub-hosted `ubuntu-26.04` and `ubuntu-26.04-arm` runners do NOT exist yet** (as of 2026-06-05). 26.04 is GA (released 2026-04-23), but the runner-images request (actions/runner-images #13964) is still OPEN with no GitHub commitment or timeline. **Build 26.04 inside a `ubuntu:26.04` container on the existing native runners** (`ubuntu-24.04` for amd64, `ubuntu-24.04-arm` for arm64). This preserves native arm64 (no QEMU emulation).
2. **Two runtime dependency packages were renamed by soname bumps** between 24.04 (noble) and 26.04 (resolute) — this is the verified v2.0 breakage:
   - gpgme: `libgpgme11t64` → **`libgpgme45`** (gpgme 1.18 → 2.0.1; soname libgpgme.so.11 → libgpgme.so.45)
   - shadow/subid: `libsubid4` → **`libsubid5`** (shadow 4.13 → 4.17.4)
3. **Most other libs keep the same package name** (libseccomp2, libsystemd0, libcap2, libdevmapper1.02.1, libjson-c5, libyajl2) — only versions changed. The per-distro mapping needed is small but mandatory.
4. **The existing `detect_crun_parser_depend` ldd-at-build-time pattern is the correct, low-maintenance solution** and should be extended to gpgme and subid rather than hardcoding distro tables. Building inside the target-distro container makes `ldd` report the correct soname automatically.

---

## Recommended Stack

### Core Technologies (additions / changes only)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `ubuntu:26.04` Docker image | resolute, GA 2026-04-23 | Build environment for 26.04 packages | GitHub-hosted `ubuntu-26.04` runner unavailable (#13964 open). Container on existing native runners gives correct 26.04 glibc/libs AND native arch (amd64 container on `ubuntu-24.04`, arm64 container on `ubuntu-24.04-arm`) with no QEMU. |
| `ubuntu-24.04-arm` runner | existing | Host for native arm64 26.04 container | Already in the matrix; running an arm64 `ubuntu:26.04` container on it preserves native arm64 builds — the single most important reason NOT to use `docker buildx`/QEMU. |
| nFPM | v2.45.0 (keep pin; v2.46.3 is latest) | .deb generation | Already in pipeline. Runs from the installed Go toolchain, fully distro-agnostic. No version bump required for multi-distro; keep the existing pin for reproducibility. |
| reprepro | host runner's apt (resolute ships 5.4.6+really5.3.2) | APT repo generation with per-distro suites | Already in pipeline. reprepro natively supports multiple Codename/Suite entries in one `conf/distributions`; per-distro suites are a config change, not a tooling change. Publish job runner unchanged. |

### Per-Distro Runtime Dependency Mapping (the core deliverable)

These are the nFPM `depends:` entries that must resolve per target distro. Verified on packages.ubuntu.com (noble = 24.04, resolute = 26.04).

| Component dep | 24.04 (noble) package | 26.04 (resolute) package | Changed? | Verification |
|---------------|-----------------------|--------------------------|----------|--------------|
| gpgme (podman/buildah/skopeo via container-libs link) | `libgpgme11t64` (1.18.0-4.1ubuntu4) | **`libgpgme45`** (2.0.1-2build1) | **YES — rename** | packages.ubuntu.com/noble + /resolute |
| subid (podman/buildah) | `libsubid4` (1:4.13+dfsg1-4ubuntu3) | **`libsubid5`** (1:4.17.4-2ubuntu3) | **YES — rename** | packages.ubuntu.com/noble + /resolute |
| seccomp (crun, conmon, podman) | `libseccomp2` | `libseccomp2` (2.6.0-2ubuntu5) | No (version only) | packages.ubuntu.com/resolute |
| systemd (crun, conmon, podman) | `libsystemd0` | `libsystemd0` (259.5-0ubuntu3) | No | packages.ubuntu.com/resolute |
| libcap (crun) | `libcap2` | `libcap2` (1:2.75-10ubuntu2) | No | packages.ubuntu.com/resolute |
| device-mapper (containers/storage) | `libdevmapper1.02.1` | `libdevmapper1.02.1` (2:1.02.205-2ubuntu3) | No | packages.ubuntu.com/resolute |
| json-c parser (crun) | `libjson-c5` | `libjson-c5` (0.18+ds-3) | No | packages.ubuntu.com/resolute |
| yajl parser (crun alt) | `libyajl2` | `libyajl2` (2.1.0-5.1) | No | packages.ubuntu.com/resolute |

**Implementation guidance:** Prefer detecting these at package time via `ldd` of the built binary inside the target-distro container — the existing `detect_crun_parser_depend` pattern in `scripts/package_all.sh` — rather than a static distro-codename → package lookup table. When the build runs in `ubuntu:26.04`, `ldd` reports `libgpgme.so.45` / `libsubid.so.5`; in `ubuntu:24.04` it reports `.so.11` / `.so.4`. A thin map from soname → package name (`libgpgme.so.45`→`libgpgme45`, `libgpgme.so.11`→`libgpgme11t64`, `libsubid.so.5`→`libsubid5`, `libsubid.so.4`→`libsubid4`) is more robust than a per-codename table and survives future soname bumps with a one-line edit. This makes the existing `${CRUN_PARSER_DEPEND}` envsubst mechanism the template for new `${GPGME_DEPEND}` / `${SUBID_DEPEND}` variables in the affected nFPM YAMLs (podman, buildah, skopeo).

### Toolchain Baseline (26.04 vs 24.04) — informational

The project installs its own pinned Go/Rust/protoc toolchain (architecture-aware installers), so distro toolchain versions are NOT used to build. They matter only for the container base and compatibility expectations.

| Tool | 24.04 (noble) | 26.04 (resolute) | Relevance |
|------|---------------|------------------|-----------|
| Codename | noble | **resolute** (Resolute Raccoon) | Suite name component + container tag |
| glibc | 2.39 | **2.43** | Binaries built on 26.04 require glibc ≥ 2.43; do NOT publish 26.04-built binaries into the 24.04 suite. Forward-compat only: 24.04→26.04 OK, reverse NOT. Per-distro builds keep each correct. |
| GCC | 14 | **15.2** | C components (crun, conmon, fuse-overlayfs, catatonit, pasta) build fine; ccache `COMPILERCHECK=content` already invalidates cache on GCC version change. |
| Go (distro) | 1.22 | 1.25 | Irrelevant — project installs its own pinned Go. Container does not need distro Go. |
| binutils | 2.42 | 2.46 | No action. |
| Rust (distro) | 1.75 | 1.93 | Irrelevant — project installs its own Rust/cargo. |
| APT | 2.7 | 3.1 (OpenSSL backend) | No action for building; user-side repo signing already uses `signed-by` keyring which APT 3.1 supports. |

---

## Installation (delta in CI)

```bash
# 26.04 build runs INSIDE a container on the EXISTING native runners.
# amd64 job: runs-on: ubuntu-24.04        -> container: ubuntu:26.04 (amd64)
# arm64 job: runs-on: ubuntu-24.04-arm    -> container: ubuntu:26.04 (arm64, native)

# Inside the container, the existing setup.sh installs the pinned Go/Rust/protoc
# toolchain and all build deps exactly as on the host. No new build tools required.

# nFPM (unchanged, runs from the Go toolchain inside the container):
go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.45.0

# reprepro (unchanged, publish job only — any runner):
sudo apt-get install -y reprepro
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `ubuntu:26.04` container on existing native runners | Native `ubuntu-26.04` / `ubuntu-26.04-arm` runners | Switch once GitHub ships them (track actions/runner-images #13964). Write the build logic runner/container-agnostic so going native is just dropping the `container:` key and changing `runs-on:`. |
| Native-arch container (arm64 container on arm64 runner) | `docker buildx` + QEMU emulation for arm64 | Never for this project — QEMU arm64 emulation is ~3-5x slower (as documented in the v2.0 research) and the entire CI design is native-arch. |
| Soname→package detection at build time (extend `detect_*_depend`) | Static per-codename dependency tables in each nFPM YAML | Acceptable fallback if a dep has no clean soname signal, but the ldd-detection pattern already exists and is proven for the crun parser. Prefer it. |
| Per-distro suites in one reprepro `conf/distributions` (stable-2404, stable-2604, ...) | Separate reprepro repos per distro | Never — one repo with multiple Codename/Suite entries is reprepro's native model and keeps one GPG key + one Pages site. v2.0 research already notes reprepro multi-codename support. |
| nFPM v2.45.0 (keep pin) | Bump to v2.46.3 | Only if a 26.04-specific deb feature is needed (none identified). Keeping the pin preserves cross-distro reproducibility. |

---

## What NOT to Use / NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Waiting for / assuming a hosted `ubuntu-26.04` runner | Not available 2026-06-05; #13964 open, no GitHub timeline | `ubuntu:26.04` container on existing 24.04 native runners |
| QEMU / `buildx --platform` for arm64 26.04 | Defeats the project's native-arch design; slow, flaky | arm64 container on `ubuntu-24.04-arm` |
| Publishing 26.04-built binaries into the 24.04 suite | glibc 2.43 binaries break on noble's 2.39 (reverse-compat does not hold) | Build each distro in its own container; publish to its own suite |
| Hardcoding `libgpgme11t64` / `libsubid4` for all distros | These packages do NOT exist in 26.04 (renamed) — this is the verified v2.0 failure | Detect via ldd/soname; map `libgpgme.so.45`→`libgpgme45`, `libsubid.so.5`→`libsubid5` |
| Renaming existing `stable`/`edge`/`nightly` suites with a hard cutover | Breaks every existing user's `.sources`/`.list` file | Add `stable-2404` etc. AND keep aliases or a migration path (PROJECT.md active requirement) — a packaging/repo-config concern, flagged for roadmap |
| New build tooling for 26.04 | None needed — same Go/Rust/Make/Meson/nFPM/reprepro | Reuse the existing toolchain inside the container |

---

## Stack Patterns by Variant

**If GitHub ships native `ubuntu-26.04` runners during this milestone:**
- Drop the `container: ubuntu:26.04` key, set `runs-on: ubuntu-26.04` / `ubuntu-26.04-arm`.
- Keep all build/package logic identical — write it container/runner-agnostic from the start so this is a near one-line switch.

**If a future component links a library that gets a soname bump (beyond gpgme/subid):**
- The ldd→soname→package detection catches it automatically; add one line to the soname→package map.
- Avoid per-codename tables that need editing for every new Ubuntu release.

**If the 26.04 container lacks a build dependency the host runner had pre-installed:**
- The container starts minimal — `setup.sh` must `apt-get install` ALL build deps explicitly (it largely does this for the from-source build). Verify no reliance on host-runner preinstalled tooling (e.g., a system Go) leaks into the 26.04 path.

---

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| 26.04-built .deb | glibc ≥ 2.43 (26.04+) | Do not install on 24.04. Suite separation enforces this. |
| 24.04-built .deb | glibc ≥ 2.39 (24.04, 26.04) | Forward-compatible to 26.04, but per-distro builds preferred for correct dep names (libgpgme45 vs libgpgme11t64). |
| `libgpgme45` dep | 26.04 only | Does not exist in 24.04; must be conditional on the 26.04 build. |
| `libsubid5` dep | 26.04 only | `libsubid4` is the 24.04 equivalent; does not exist in 26.04. |
| nFPM v2.45.0 | both distros | Distro-agnostic Go binary. |
| reprepro multi-Codename | both suites in one repo | One `conf/distributions` with stable-2404/edge-2404/nightly-2404 + stable-2604/edge-2604/nightly-2604. |
| `ubuntu:26.04` image on `ubuntu-24.04-arm` | native arm64 | Container arch follows host arch; no emulation. |

---

## Sources

### HIGH Confidence (Official / Verified)

- [packages.ubuntu.com/resolute/libgpgme45](https://packages.ubuntu.com/resolute/libgpgme45) — `libgpgme45` 2.0.1-2build1 exists in 26.04
- [packages.ubuntu.com/noble/libgpgme11t64](https://packages.ubuntu.com/noble/libgpgme11t64) — `libgpgme11t64` 1.18.0-4.1ubuntu4 in 24.04 (absent in resolute)
- [packages.ubuntu.com/resolute/libsubid5](https://packages.ubuntu.com/resolute/libsubid5) — `libsubid5` 1:4.17.4-2ubuntu3 in 26.04
- [packages.ubuntu.com/noble/libsubid4](https://packages.ubuntu.com/noble/libsubid4) — `libsubid4` 1:4.13+dfsg1-4ubuntu3 in 24.04 (no libsubid5 in noble)
- packages.ubuntu.com/resolute/{libseccomp2, libsystemd0, libcap2, libdevmapper1.02.1, libjson-c5, libyajl2} — unchanged names, new versions
- [actions/runner-images #13964](https://github.com/actions/runner-images/issues/13964) — Ubuntu 26.04 runner request OPEN, not implemented as of 2026-06-05
- [Ubuntu 26.04 LTS release notes — summary for LTS users](https://documentation.ubuntu.com/release-notes/26.04/summary-for-lts-users/) — GCC 15.2, glibc 2.43, Go 1.25, binutils 2.46, APT 3.1, Dracut; codename Resolute Raccoon, GA 2026-04-23
- [goreleaser/nfpm releases](https://github.com/goreleaser/nfpm/releases) — latest v2.46.3 (2026-04-18); project pins v2.45.0
- [packages.ubuntu.com/resolute/reprepro](https://packages.ubuntu.com/resolute/reprepro) — reprepro 5.4.6+really5.3.2-2build1 in 26.04

### MEDIUM Confidence (Community / Corroborating)

- [launchpad.net/ubuntu/+source/gpgme1.0](https://launchpad.net/ubuntu/+source/gpgme1.0) — gpgme 1.18 → 2.0.1 source transition across noble/resolute
- [GnuPG dev T7262](https://dev.gnupg.org/T7262) / [Arch gpgme 2.0.1](https://archlinux.org/packages/core/x86_64/gpgme/) — soname libgpgme.so.11 → libgpgme.so.45 on the 2.0 bump
- [community discussion #187595](https://github.com/orgs/community/discussions/187595) — no GitHub commitment/timeline for a hosted 26.04 runner as of mid-2026

---
*Stack research for: Ubuntu 26.04 multi-distro APT packaging (Podman from-source pipeline)*
*Researched: 2026-06-05 (v3.0 milestone)*
