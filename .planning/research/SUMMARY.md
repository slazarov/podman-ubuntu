# Project Research Summary

**Project:** Podman Debian Compiler — v3.0 "Ubuntu 26.04 Support"
**Domain:** Multi-distro from-source APT packaging pipeline (nFPM + reprepro + GitHub Actions + GitHub Pages)
**Researched:** 2026-06-05
**Confidence:** HIGH

## Executive Summary

This milestone adds Ubuntu 26.04 (Resolute Raccoon) alongside the existing Ubuntu 24.04 pipeline without replacing it. The fundamental driver is a verified install failure: two runtime libraries were renamed between 24.04 and 26.04 — `libgpgme11t64` → `libgpgme45` (gpgme 1.18 → 2.0.1 soname bump) and `libsubid4` → `libsubid5` (shadow 4.13 → 4.17.4). The existing nFPM configs hardcode 24.04 names, so 26.04 users get "Depends: X but it is not installable" on every Podman package. Fixing this requires per-distro dependency mapping — which in turn demands per-distro builds, per-distro suites in the APT repo, and per-distro version suffixes to avoid a reprepro shared-pool checksum collision.

The recommended approach is: one repo with six versioned suites (`stable-2404`, `edge-2404`, `nightly-2404`, `stable-2604`, `edge-2604`, `nightly-2604`), a distro×arch CI matrix (4 build cells), per-distro env files driving nFPM dependency substitution via the existing `envsubst` mechanism, and a version suffix extended to `~ubuntu24.04.podman1` / `~ubuntu26.04.podman1` for pool-path uniqueness. Existing users are protected by aliasing the bare `stable`/`edge`/`nightly` suite names to the 24.04 suites during a deprecation window. No new tools are required: the same Go/Rust/Make/Meson/nFPM/reprepro stack runs identically inside a `ubuntu:26.04` container on the existing `ubuntu-24.04[-arm]` native runners (native `ubuntu-26.04` GitHub-hosted runners are not yet GA as of 2026-06-05).

The dominant implementation risk is the reprepro shared-pool collision: two builds of the same upstream version with identical filenames but different binary contents cause a hard publish failure, exactly as Docker experienced with `containerd.io` across jammy/noble. The per-distro version suffix is the keystone fix — every other piece of the architecture depends on it. Implementation must follow a strict dependency order: versioning and dependency mapping first, repo restructure second, CI matrix third, migration aliases and docs last. Each step leaves the 24.04 pipeline fully shippable.

## Key Findings

### Recommended Stack

The existing v2.0 stack (nFPM v2.45.0, reprepro, GitHub Actions native amd64+arm64 runners, GPG-signed reprepro APT repo on Pages) is unchanged. The only new element is building 26.04 packages inside a `ubuntu:26.04` container on the existing `ubuntu-24.04` and `ubuntu-24.04-arm` runners, because GitHub-hosted `ubuntu-26.04` runner labels are not yet available (actions/runner-images #13964 is open with no timeline as of the research date). This container approach preserves native arm64 — the arm64 container runs on the `ubuntu-24.04-arm` host with no QEMU emulation.

**Core technologies (additions/changes only):**
- `ubuntu:26.04` container on existing native runners — build environment for 26.04 packages; GitHub-hosted label unavailable; native-arch preserved
- `deps-2404.env` / `deps-2604.env` (new files) — declarative per-distro dependency name maps consumed by envsubst in `package_all.sh`
- reprepro multi-Codename config — already supports multiple suite stanzas in one `conf/distributions`; a config change, not a tooling change
- nFPM v2.45.0 (keep pin) — distro-agnostic; no version bump required for multi-distro support

**Verified dependency renames (the concrete breakage):**
- `libgpgme11t64` (24.04) → `libgpgme45` (26.04)
- `libsubid4` (24.04) → `libsubid5` (26.04)
- All other linked libraries (`libseccomp2`, `libsystemd0`, `libcap2`, `libdevmapper1.02.1`, `libjson-c5`, `libyajl2`) keep the same package name across both releases

### Expected Features

**Must have (v3.0 table stakes):**
- Per-distro suites published (`stable/edge/nightly` × `-2404/-2604`) — without this, "26.04 support" is false
- Per-distro dependency mapping in nFPM — fixes the verified install failure; the concrete reason for the milestone
- Per-distro version suffix (`~ubuntu24.04.podman1` / `~ubuntu26.04.podman1`) — prevents reprepro pool collision; enables correct dist-upgrade ordering
- CI matrix extended to distro×arch (4 build cells) — enables building 26.04-native packages
- Backward-compatible legacy suite aliases — existing `Suites: stable` clients must keep working during deprecation window
- Updated per-distro docs and setup snippets — users need copy-paste `.sources` blocks for each distro

**Should have (differentiators):**
- Single repo root for all distros (one `URIs:`, one differing `Suites:` token) — simpler than OBS-style per-distro paths
- Native builds per distro, not forward-compat shims — 26.04 packages link 26.04 libs; higher quality than publishing 24.04-built binaries for 26.04 users
- Zero-touch migration for existing 24.04 users — suite aliasing during deprecation window

**Defer to v3.x / post-v3:**
- Time-boxed removal of legacy `stable`/`edge`/`nightly` aliases — remove after deprecation window elapses
- Codename-aliased suites (`noble`/`resolute` → `-2404`/`-2604`) for `$VERSION_CODENAME` auto-detect — only if users request it
- Generalized N-distro templating — defer until a third distro is actually needed

**Anti-features (do not implement):**
- Codename-in-version-string (`~noble`) — Docker's mistake; codenames sort alphabetically and break dist-upgrades
- Separate repo path per distro (OBS-style) — forces per-distro `URIs:` line; breaks the single-root setup
- Hard suite rename cutover without aliases — breaks every existing user's `apt update` silently

### Architecture Approach

The existing pipeline is a fan-out/fan-in shape: N build jobs emit per-arch `.deb` sets, one publish job merges them into a single reprepro repo and deploys to Pages. v3.0 adds a distro dimension, expanding the build fan-out from 2 cells (arch) to 4 cells (distro × arch) and the suite count from 3 to 6, while leaving the fan-in shape and the atomic Pages-deploy contract unchanged.

**Major components and changes:**
1. `.github/workflows/build-packages.yml` — MODIFY: collapse two hand-written build jobs into a `strategy.matrix` of `distro × arch`; publish loops over both distros
2. `scripts/package_all.sh` — MODIFY: accept `DISTRO` env var; source `deps-${DISTRO}.env`; extend `VERSION_SUFFIX` with distro token
3. `packaging/nfpm/deps-2404.env` + `deps-2604.env` — NEW: per-distro dependency name maps
4. `packaging/nfpm/*.yaml` — MODIFY (small): replace hardcoded dep names with `${DEPEND_*}` vars for renamed packages
5. `packaging/repo/conf/distributions` — MODIFY: 3 → 6 stanzas; versioned Codenames; legacy Suite aliases; add `Acquire-By-Hash: yes`
6. `scripts/ci_publish.sh` — MODIFY: accept distro arg; target `<track>-<distro>` suite; iterate 5 other suites; per-distro artifact routing
7. `scripts/repo_manage.sh` — MODIFY: accept full composite suite name (`stable-2404`)

**Key patterns:**
- Distro as a first-class matrix axis: one job definition, 4 cells via `strategy.matrix`
- Per-distro dependency mapping via env files + envsubst (extends the existing `${CRUN_PARSER_DEPEND}` pattern)
- Suite name = `<track>-<distro>`; Codename is canonical; legacy bare name is a `Suite:` alias + physical dists copy
- Artifact names tagged `debs-<distro>-<arch>`; downloaded into per-distro dirs in publish; never `merge-multiple: true` across distros

### Critical Pitfalls

1. **reprepro shared-pool checksum collision** — Two distros building the same upstream version produce `.deb` files with identical filenames but different contents. reprepro hard-fails. Prevention: per-distro version suffix so pool paths are distinct. Keystone fix. (Real precedent: Docker/containerd.io moby#48306.)

2. **Hardcoded library dependency names broken by t64 transition and soname bumps** — `libgpgme11t64` does not exist in 26.04; `libsubid4` does not exist in 26.04. Prevention: env-file-driven dependency mapping (`deps-2604.env`) consumed via envsubst; extend the existing `detect_crun_parser_depend()` pattern.

3. **`merge-multiple: true` artifact download mixes distros** — With a second distro leg, a 26.04-built `.deb` (glibc 2.43) can overwrite the same-named 24.04 `.deb`, causing silent cross-distro binary leaks that crash at runtime. Prevention: name artifacts `debs-<distro>-<arch>`; never merge across distros.

4. **Suite rename breaks every existing user's `.sources`** — Renaming `stable` → `stable-2404` without an alias causes `apt update` to 404 silently. Prevention: physically copy `dists/stable-2404` → `dists/stable` in the publish step during deprecation window (symlinks may not survive the Pages artifact tarball).

5. **CDN Hash Sum mismatch on publish** — GitHub Pages CDN can serve stale `Packages` against a newly-deployed `InRelease`. Prevention: add `Acquire-By-Hash: yes` to all stanzas in `conf/distributions`. One-line fix; current config omits it.

6. **CI cache key collision** — Go/Rust/C cache keys currently key on `(arch, track)`. Adding a second distro makes both distros share a cache namespace. Prevention: add `${distro}` to every cache key.

## Implications for Roadmap

### Phase 1: Per-Distro Versioning and Dependency Mapping
**Rationale:** The keystone. Pool collision and dep rename failures both originate here. Every other phase depends on artifacts having distinct version strings and correct dep names. Independently verifiable against the existing 24.04 pipeline.
**Delivers:** `deps-2404.env`, `deps-2604.env`; updated `package_all.sh` with DISTRO awareness; nFPM YAML templates with `${DEPEND_LIBGPGME}` / `${DEPEND_SUBID}` vars; `VERSION_SUFFIX` extended with distro token.
**Addresses:** Per-distro dependency mapping, per-distro tilde version suffix
**Avoids:** Pool checksum collision (pitfall 1), hardcoded dep names (pitfall 2)

### Phase 2: Repository Restructure and Publish Script Updates
**Rationale:** Publish scripts must speak the new suite vocabulary before 26.04 cells exist. Done as a 24.04-only change, it keeps the pipeline shippable. Migration aliases must land here — not later — to protect existing users from the moment the repo restructure deploys.
**Delivers:** `conf/distributions` rewritten to 6 stanzas with versioned Codenames and legacy Suite aliases; `repo_manage.sh` and `ci_publish.sh` updated; `Acquire-By-Hash: yes` added; physical `dists/stable` alias copy in publish step.
**Addresses:** Backward-compatible legacy aliases, per-distro suites published
**Avoids:** Suite rename user breakage (pitfall 4), CDN Hash Sum mismatch (pitfall 5), ci_publish cross-distro clobber

### Phase 3: CI Matrix Extension to 26.04
**Rationale:** Can only produce correct 26.04 artifacts after Phases 1 and 2 are in place. The matrix rewrite collapses two existing build jobs into one `strategy.matrix: distro × arch`. 26.04 cells use `container: ubuntu:26.04` on existing native runners.
**Delivers:** 4-cell build matrix; `debs-<distro>-<arch>` artifact naming; per-distro download routing in publish; distro dimension in all cache keys; `fail-fast: false` so 26.04 failure does not kill 24.04.
**Addresses:** CI matrix → 26.04 (enabler)
**Avoids:** Artifact merge clobber (pitfall 3), cache key collision (pitfall 6), runner label assumption

### Phase 4: Migration Aliases, Docs, and Smoke Tests
**Rationale:** Purely additive UX. The system is fully functional after Phase 3; this phase finalizes the user-facing story.
**Delivers:** Updated `docs/apt-repository.md` with per-distro `.sources` blocks; regenerated `index.html` with distro selector; deprecation notice for bare suite names; smoke test (install + `podman info` in real 24.04 and 26.04 containers); confirmed GPG key path unchanged.
**Addresses:** Updated per-distro docs, zero-touch migration (differentiator)
**Avoids:** GPG path divergence

### Phase Ordering Rationale

- Version suffix before repo restructure: reprepro cannot safely hold both distros until pool paths are distinct.
- Repo restructure before CI matrix: publish scripts must speak composite suite vocabulary before 26.04 artifacts exist to route into them.
- Migration aliases in Phase 2, not Phase 4: the alias must exist from the first deploy of the new suite layout. Deploying without it creates a window where existing users are broken.
- Docs and smoke tests last: testable only once CI produces real 26.04 artifacts.

### Research Flags

Phases needing validation during planning:
- **Phase 2:** The `createsymlinks` vs physical-copy alias strategy needs a live test on GitHub Pages — Pages artifact tarballs may not preserve symlinks. Plan explicitly for the physical-copy fallback.
- **Phase 3:** Verify whether `ubuntu-26.04` / `ubuntu-26.04-arm` runner labels are GA at implementation time. If GA, the `container:` key can be dropped — write build logic runner/container-agnostic from the start so this is a one-line switch.

Phases with well-documented patterns (skip research-phase):
- **Phase 1:** The `envsubst` + env-file pattern is already proven in the codebase. Package names are verified on packages.ubuntu.com. No new research needed.
- **Phase 4:** Documentation work; no novel technical territory.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Package names verified on packages.ubuntu.com for noble and resolute; runner status verified against actions/runner-images #13964; toolchain versions from official Ubuntu 26.04 release notes |
| Features | HIGH | Structural patterns verified against Docker, GitHub CLI, OBS/alvistack; reprepro/APT behavior from official Debian manpages; Docker dist-upgrade breakage from moby/for-linux #1315 |
| Architecture | HIGH | Grounded in existing repo code (direct inspection); reprepro Suite/Codename confirmed against Debian manpages |
| Pitfalls | HIGH | Pool collision confirmed by Docker/containerd.io precedent (moby#48306) and reprepro maintainer (Debian #477708); t64 transition from Debian Wiki; acquire-by-hash from Packagecloud + LLVM incident |

**Overall confidence:** HIGH

### Gaps to Address

- **`createsymlinks` vs physical copy on GitHub Pages:** Validate in Phase 2 implementation that physical `cp -r` is used, not filesystem symlinks (Pages tarballs may not preserve them).
- **Exact version suffix format:** `~ubuntu24.04.podman1` vs `~ubuntu2404.podman1` vs `~podman1~ubuntu24.04` — all are valid tilde forms. Before Phase 1 ships, verify chosen form with `dpkg --compare-versions`: must satisfy `5.8.0~ubuntu24.04.podman1 < 5.8.0` (yield-to-official guarantee) and `5.8.0~ubuntu24.04.podman1 < 5.8.0~ubuntu26.04.podman1` (dist-upgrade order).
- **APT "Suite changed value" prompt on migration:** If the served `Release` file's `Suite:` field changes for an existing client, APT may prompt interactively. Validate with a real 24.04 client running the pre-v3.0 `.sources` after Phase 2 deploys.
- **`ubuntu-26.04` runner GA status:** As of 2026-06-05, not GA. Re-check at implementation time. Container fallback is the safe default.

## Sources

### Primary (HIGH confidence)
- packages.ubuntu.com/noble and /resolute — verified package names for libgpgme45, libsubid5, and all unchanged deps
- actions/runner-images #13964 — ubuntu-26.04 runner request status (open, no timeline)
- Ubuntu 26.04 LTS release notes — glibc 2.43, GCC 15.2, codename Resolute Raccoon, GA 2026-04-23
- reprepro(1) manpage (Debian unstable) — Suite vs Codename, createsymlinks, AlsoAcceptFor, Acquire-By-Hash
- Debian Wiki DebianRepository/SetupWithReprepro — Codename immutability, Suite mutability
- deb-version(5) — tilde sorting semantics
- DEB822 sources.list(5) — Suites: multi-token format
- moby/moby #48306 — Docker containerd.io pool collision (exact precedent for pitfall 1)
- Debian Bug #477708 — reprepro maintainer position on same-name/different-content
- Debian Wiki ReleaseGoals/64bit-time — t64 transition, ~495 renamed packages
- Packagecloud — acquire-by-hash as the CDN Hash Sum mismatch fix
- Existing codebase (direct inspection): `scripts/package_all.sh`, `scripts/ci_publish.sh`, `scripts/repo_manage.sh`, `packaging/repo/conf/distributions`, `packaging/nfpm/*.yaml`, `.github/workflows/build-packages.yml`

### Secondary (MEDIUM confidence)
- launchpad.net/ubuntu/+source/gpgme1.0 — gpgme 1.18 → 2.0.1 source transition
- GnuPG dev T7262 / Arch gpgme 2.0.1 — soname libgpgme.so.11 → libgpgme.so.45
- Docker for-linux #1315 — codename-in-version breaks dist-upgrades
- reprepro AlsoAcceptFor bug thread — AlsoAcceptFor is upload-side only, not a serving alias
- LLVM/llvm-project #49575 — CDN staleness and acquire-by-hash recommendation
- aptly-dev/aptly #1318 — t64 dependency resolution breakage

---
*Research completed: 2026-06-05*
*Ready for roadmap: yes*
