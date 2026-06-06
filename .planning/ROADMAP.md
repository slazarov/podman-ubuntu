# Roadmap: Podman Ubuntu Compiler

## Milestones

- ✅ **v1.0 MVP** — Phases 1-5 (shipped 2026-03-03)
- ✅ **v1.1 Ecosystem Audit** — Phases 6-10 (shipped 2026-03-04)
- ✅ **v1.2 Include Common Libraries** — Phases 11-13 (shipped 2026-03-04)
- ✅ **v2.0 APT Packaging & CI/CD** — Phases 14-18 (shipped 2026-03-08)
- 🚧 **v3.0 Ubuntu 26.04 Support** — Phases 19-22 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-5) — SHIPPED 2026-03-03</summary>

- [x] Phase 1: Architecture Support (4/4 plans) — completed 2026-03-03
- [x] Phase 2: Non-Interactive Mode (1/1 plan) — completed 2026-03-03
- [x] Phase 3: Error Handling (3/3 plans) — completed 2026-03-03
- [x] Phase 4: User Experience (3/3 plans) — completed 2026-03-03
- [x] Phase 5: Build Time Optimization (2/2 plans) — completed 2026-03-03

</details>

<details>
<summary>✅ v1.1 Ecosystem Audit (Phases 6-10) — SHIPPED 2026-03-04</summary>

- [x] Phase 6: Component Cleanup (1/1 plan) — completed 2026-03-03
- [x] Phase 7: Pre-flight Validation (1/1 plan) — completed 2026-03-03
- [x] Phase 8: Build Optimization & Configuration (2/2 plans) — completed 2026-03-04
- [x] Phase 9: Build Optimization - Go Cache, ccache, mold (2/2 plans) — completed 2026-03-04
- [x] Phase 10: Tech Debt Cleanup (1/1 plan) — completed 2026-03-04

</details>

<details>
<summary>✅ v1.2 Include Common Libraries (Phases 11-13) — SHIPPED 2026-03-04</summary>

- [x] Phase 11: Build container-libs (1/1 plan) — completed 2026-03-04
- [x] Phase 12: Install Configuration Files (1/1 plan) — completed 2026-03-04
- [x] Phase 13: Man Pages and Uninstall (1/1 plan) — completed 2026-03-04

</details>

<details>
<summary>✅ v2.0 APT Packaging & CI/CD (Phases 14-18) — SHIPPED 2026-03-08</summary>

- [x] Phase 14: Debian Package Building (2/2 plans) — completed 2026-03-05
- [x] Phase 15: APT Repository and Signing (2/2 plans) — completed 2026-03-05
- [x] Phase 16: CI/CD Pipeline (delivered via Phase 18) — completed 2026-03-08
- [x] Phase 17: Upstream Automation (absorbed into Phase 18) — completed 2026-03-08
- [x] Phase 18: Edge Track / Nightly Builds (2/2 plans) — completed 2026-03-08

Full v2.0 phase details archived at `.planning/milestones/v2.0-ROADMAP.md`.

</details>

### 🚧 v3.0 Ubuntu 26.04 Support (In Progress)

**Milestone Goal:** Users on both Ubuntu 24.04 and 26.04 can add the APT repo, enable their distro's suite, and install Podman packages that install and run cleanly on their OS version.

- [x] **Phase 19: Per-Distro Versioning & Dependency Mapping** - Distro-tagged version suffixes and per-distro runtime dependency resolution so each distro's .deb is uniquely identified and correctly installable (completed 2026-06-06)
- [ ] **Phase 20: Repository Restructure & Migration Aliases** - Six versioned suites from one URL with legacy aliases that keep existing users working (gap closure in progress — CR-01/CR-02 blockers from verification)
- [ ] **Phase 21: CI Build Matrix Extension to 26.04** - A single distro×arch build matrix that produces native 26.04 packages with atomic, distro-isolated publishing
- [ ] **Phase 22: Migration Docs & Installability Smoke Tests** - Per-distro setup docs, deprecation timeline, and CI-verified install + `podman info` in real containers

## Phase Details

### Phase 19: Per-Distro Versioning & Dependency Mapping

**Goal**: Each distro's packages carry a distinct version identity and declare the runtime dependencies that actually exist on that distro, so building the same upstream version for two distros produces installable, non-colliding .deb files
**Depends on**: Phase 18 (v2.0 packaging pipeline)
**Requirements**: PKG-08, PKG-09, PKG-10
**Success Criteria** (what must be TRUE):

  1. A package built with `DISTRO=26.04` declares the renamed 26.04 dependencies (libgpgme45, libsubid5) instead of the 24.04 names, and `apt install` resolves them on a real ubuntu:26.04 system
  2. The same upstream version built for each distro produces distinct version strings (`~ubuntu24.04.podman1` vs `~ubuntu26.04.podman1`) that satisfy `dpkg --compare-versions`: each sorts below the official upstream version, and the 24.04 form sorts below the 26.04 form so dist-upgrades order correctly
  3. Runtime library dependencies are derived at build time from the binaries' linked sonames (ldd soname→package mapping) rather than hardcoded, so a future distro rename is picked up without editing nFPM config by hand
  4. Building for 24.04 with the new code path produces packages byte-functionally equivalent to the pre-v3.0 24.04 packages (no regression to the shipping pipeline)

**Plans**: 5 plans (1 gap-closure)
Plans:
**Wave 1**

- [x] 19-01-PLAN.md — Distro detection helpers + per-distro VERSION_SUFFIX composition (functions.sh, config.sh)
- [x] 19-03-PLAN.md — verify_versions.sh: dpkg --compare-versions ordering proof (D-11)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 19-02-PLAN.md — ldd→dpkg detected depends wired into package_all.sh + nFPM YAMLs (${DETECTED_DEPENDS})

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 19-04-PLAN.md — On-Ubuntu detector + 24.04 equivalence + 26.04 container install smoke (scripts authored; on-host proofs deferred to UAT)

**Gap closure** *(from UAT diagnoses — Test 1 blocker + Test 3 major)*

- [x] 19-05-PLAN.md — Direct DT_NEEDED detector (drop ldd transitive closure) + stale skopeo libsqlite3-0 baseline fix + smoke sibling-dep (podman-container-configs) install

### Phase 20: Repository Restructure & Migration Aliases

**Goal**: The APT repository serves all six versioned suites from a single URL under one GPG key, while existing users on bare suite names keep receiving 24.04 packages with no client-side change
**Depends on**: Phase 19
**Requirements**: REPO-06, REPO-07, REPO-08
**Success Criteria** (what must be TRUE):

  1. The repository serves six suites (stable-2404, edge-2404, nightly-2404, stable-2604, edge-2604, nightly-2604) from one URL with one GPG key, and `apt update` against any suite succeeds with a valid signature chain
  2. An existing user whose `.sources` still points at bare `stable`/`edge`/`nightly` continues to receive 24.04 packages after the restructure deploys, with no edit to their `.sources` (legacy alias served physically, not via symlink)
  3. Repository metadata includes `Acquire-By-Hash: yes` on every suite, so apt clients fetching from the GitHub Pages CDN never hit a hash-sum mismatch
  4. The publish tooling routes a given track's packages into the correct `<track>-<distro>` suite without clobbering the other five suites' contents

**Plans**: 6 plans (4 original + 2 gap closure)

Plans:
**Wave 1**

- [x] 20-01-PLAN.md — 9-stanza conf/distributions + resolve_publish_targets routing helper + suite whitelist arrays in config.sh + 3 Wave-0 unit tests (REPO-06/07)
- [x] 20-02-PLAN.md — scripts/repo_byhash.sh add_byhash_and_resign (post-export by-hash + re-sign) + test_byhash_parse.sh (REPO-08)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 20-03-PLAN.md — Wire track+distro routing + alias feeding into repo_manage.sh/ci_publish.sh, call by-hash per suite, 9-suite index.html loop, CI distro arg plumbing (REPO-06/07/08)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 20-04-PLAN.md — Ubuntu-only assemble+by-hash+no-clobber integration harness + on-VM/deployed-Pages legacy-client validation checkpoint (D-15) (REPO-06/07/08)

**Gap closure** *(from 20-VERIFICATION.md — closes CR-01/CR-02 blockers; REPO-08 / SC-3 + SC-4)*

- [x] 20-05-PLAN.md — Pipefail isolation in add_byhash_and_resign so a benign non-zero never leaves a half-signed repo (CR-01) + anchored secret-key fpr (WR-01) + quoted realpath bootstrap (WR-03) + Test group F pipefail-abort regression (REPO-08)
- [ ] 20-06-PLAN.md — Verbatim-mirror non-target bare aliases on 26.04 publishes so they are not re-signed (CR-02) + HTML-escape index.html (WR-04) + Test group G 26.04-publish signature-stability (REPO-08/REPO-06)

### Phase 21: CI Build Matrix Extension to 26.04

**Goal**: One CI workflow builds all four distro×arch cells, producing native 26.04 packages, with distro-isolated caches/artifacts and a publish step that only runs when every cell succeeds
**Depends on**: Phase 20
**Requirements**: CICD-05, CICD-06, CICD-07, CICD-08
**Success Criteria** (what must be TRUE):

  1. A single workflow run builds all four distro×arch combinations (24.04/26.04 × amd64/arm64) via one `strategy.matrix`, and a 26.04 cell failure does not abort the 24.04 cells (`fail-fast: false`)
  2. The 26.04 cells build inside `ubuntu:26.04` containers on the existing native runners, written runner-agnostic so switching to GA `ubuntu-26.04` runners is a one-line change
  3. Build caches and artifacts carry a distro dimension (`debs-<distro>-<arch>` artifact names, distro in cache keys) and the publish download never merges across distros, so no 26.04 binary can leak into a 24.04 package or vice versa
  4. The publish job runs only when all four build cells succeed; if any cell fails, the live repository is left untouched

**Plans**: TBD

Plans:

- [ ] 21-01: TBD

### Phase 22: Migration Docs & Installability Smoke Tests

**Goal**: A user on either distro can set up the repo from copy-paste instructions specific to their version, understands the deprecation timeline for bare suite names, and every publish is gated on a real install + smoke test
**Depends on**: Phase 21
**Requirements**: MIGR-01, MIGR-02, MIGR-03, MIGR-04
**Success Criteria** (what must be TRUE):

  1. A user on either 24.04 or 26.04 can copy a DEB822 `.sources` block specific to their Ubuntu version from the docs, paste it, and reach a working `apt install podman-suite`
  2. The repository index page (`index.html`) presents per-distro setup instructions, and the deprecation timeline for the bare `stable`/`edge`/`nightly` suite names is documented
  3. CI installs `podman-suite` and runs `podman info` successfully inside both real `ubuntu:24.04` and `ubuntu:26.04` containers before any publish proceeds, so an uninstallable package never reaches the live repo
  4. The GPG key path and import instructions remain unchanged across both distros (single key, single setup flow)

**Plans**: TBD

Plans:

- [ ] 22-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 19 → 20 → 21 → 22

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Architecture Support | v1.0 | 4/4 | Complete | 2026-03-03 |
| 2. Non-Interactive Mode | v1.0 | 1/1 | Complete | 2026-03-03 |
| 3. Error Handling | v1.0 | 3/3 | Complete | 2026-03-03 |
| 4. User Experience | v1.0 | 3/3 | Complete | 2026-03-03 |
| 5. Build Time Optimization | v1.0 | 2/2 | Complete | 2026-03-03 |
| 6. Component Cleanup | v1.1 | 1/1 | Complete | 2026-03-03 |
| 7. Pre-flight Validation | v1.1 | 1/1 | Complete | 2026-03-03 |
| 8. Build Optimization & Configuration | v1.1 | 2/2 | Complete | 2026-03-04 |
| 9. Build Optimization - Go Cache, ccache, mold | v1.1 | 2/2 | Complete | 2026-03-04 |
| 10. Tech Debt Cleanup | v1.1 | 1/1 | Complete | 2026-03-04 |
| 11. Build container-libs | v1.2 | 1/1 | Complete | 2026-03-04 |
| 12. Install Configuration Files | v1.2 | 1/1 | Complete | 2026-03-04 |
| 13. Man Pages and Uninstall | v1.2 | 1/1 | Complete | 2026-03-04 |
| 14. Debian Package Building | v2.0 | 2/2 | Complete | 2026-03-05 |
| 15. APT Repository and Signing | v2.0 | 2/2 | Complete | 2026-03-05 |
| 16. CI/CD Pipeline | v2.0 | — | Complete (via Phase 18) | 2026-03-08 |
| 17. Upstream Automation | v2.0 | — | Complete (absorbed into Phase 18) | 2026-03-08 |
| 18. Edge Track / Nightly Builds | v2.0 | 2/2 | Complete | 2026-03-08 |
| 19. Per-Distro Versioning & Dependency Mapping | v3.0 | 5/5 | Complete    | 2026-06-06 |
| 20. Repository Restructure & Migration Aliases | v3.0 | 5/6 | In Progress|  |
| 21. CI Build Matrix Extension to 26.04 | v3.0 | 0/? | Not started | - |
| 22. Migration Docs & Installability Smoke Tests | v3.0 | 0/? | Not started | - |

---

*See `.planning/milestones/v1.0-ROADMAP.md` for archived v1.0 phase details.*
*See `.planning/milestones/v1.1-ROADMAP.md` for archived v1.1 phase details.*
*See `.planning/milestones/v1.2-ROADMAP.md` for archived v1.2 phase details.*
*See `.planning/milestones/v2.0-ROADMAP.md` for archived v2.0 phase details.*
