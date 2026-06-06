# Architecture Research: v3.0 Ubuntu 26.04 Support (Multi-Distro APT Pipeline)

**Domain:** Multi-distro APT package build & publish pipeline (Ubuntu 24.04 + 26.04, amd64 + arm64, 3 tracks)
**Researched:** 2026-06-05
**Confidence:** HIGH (grounded in existing repo code; reprepro Suite/Codename + createsymlinks/AlsoAcceptFor confirmed against Debian manpages)

## Standard Architecture

This milestone adds a **distro dimension** to a pipeline that already has two dimensions (arch × track). The
existing pipeline is a fan-out / fan-in shape: N build jobs each emit a per-arch `.deb` set, one publish job
merges them into a single reprepro repo and deploys to Pages. The new dimension multiplies the build fan-out
(2 arch → 4 cells) and the suite count (3 suites → 6 suites), but the fan-in shape and the atomic
publish-to-Pages contract are unchanged.

### System Overview (target state)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  TRIGGER LAYER  (workflow_dispatch track | cron nightly)                   │
│   inputs: build_track ∈ {stable, edge, nightly}                            │
└───────────────────────────────┬────────────────────────────────────────────┘
                                 │ track (single value per run)
┌───────────────────────────────▼────────────────────────────────────────────┐
│  BUILD LAYER  — matrix: distro × arch  (4 cells)                            │
│  ┌──────────────────┐ ┌──────────────────┐                                  │
│  │ 24.04 / amd64    │ │ 24.04 / arm64    │   runner: ubuntu-24.04[-arm]     │
│  │ setup.sh         │ │ setup.sh         │   DISTRO=2404                    │
│  │ package_all.sh   │ │ package_all.sh   │   deps-2404.env → nFPM           │
│  └────────┬─────────┘ └────────┬─────────┘                                  │
│  ┌────────▼─────────┐ ┌────────▼─────────┐                                  │
│  │ 26.04 / amd64    │ │ 26.04 / arm64    │   runner: ubuntu-26.04[-arm]     │
│  │ setup.sh         │ │ setup.sh         │   DISTRO=2604                    │
│  │ package_all.sh   │ │ package_all.sh   │   deps-2604.env → nFPM           │
│  └────────┬─────────┘ └────────┬─────────┘                                  │
│           │ artifact: debs-<distro>-<arch>  (4 distinct names)              │
└───────────┴───────────────────┬─────────────────────────────────────────────┘
                                 │ fan-in (download all 4)
┌───────────────────────────────▼────────────────────────────────────────────┐
│  PUBLISH LAYER  — single job, runs once per run                            │
│   1. download 4 artifact sets, keep DISTRO-tagged (do NOT merge-multiple)  │
│   2. for each distro: ci_publish.sh <track> <distro> <debs> <url> <out>    │
│      → writes suite "<track>-<distro>"  (e.g. stable-2404, stable-2604)    │
│   3. import OTHER 5 suites from live Pages repo (per-distro Packages URLs)  │
│   4. reprepro export per suite → one repo tree with 6 dists/ entries        │
│   5. upload-pages-artifact → deploy-pages  (ATOMIC single deploy)           │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                 │
┌───────────────────────────────▼────────────────────────────────────────────┐
│  SERVE LAYER  — GitHub Pages (single site, one pool/, six dists/)          │
│   dists/{stable,edge,nightly}-{2404,2604}/main/binary-{amd64,arm64}/        │
│   pool/main/...  (shared pool — version suffix keeps distros distinct)      │
│   podman-ubuntu.gpg  +  index.html (now distro-aware setup tabs)           │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities (new vs modified vs unchanged)

| Component | Responsibility | Change for this milestone |
|-----------|----------------|---------------------------|
| `.github/workflows/build-packages.yml` | Orchestrate build fan-out + publish fan-in | **MODIFY** — collapse 2 hand-written jobs into a `strategy.matrix` of distro×arch; publish loops over distros |
| `setup.sh` + `scripts/build_*.sh` | Compile components into DESTDIR | **UNCHANGED** — build is distro-agnostic; binaries built natively per runner |
| `scripts/package_all.sh` | Resolve versions, run nFPM per component | **MODIFY** — accept/derive `DISTRO`, source `deps-<distro>.env`, distro-tag version suffix, export dep vars |
| `packaging/nfpm/*.yaml` | nFPM package templates | **MODIFY (small)** — replace hardcoded dep names with `${VAR}` for packages that differ across distros |
| `packaging/nfpm/deps-2404.env`, `deps-2604.env` | Per-distro dependency name map | **NEW** — env files of `DEPEND_*` vars consumed by envsubst |
| `scripts/ci_publish.sh` | Build multi-suite repo, import other suites | **MODIFY** — take `distro` arg; target `<track>-<distro>` suite; iterate 5 other suites |
| `scripts/repo_manage.sh` | reprepro includedeb + export for one suite | **MODIFY** — accept full suite name (`stable-2404`) instead of bare track |
| `packaging/repo/conf/distributions` | reprepro suite definitions | **MODIFY** — 3 → 6 stanzas; add `Suite:`/`AlsoAcceptFor` for migration |
| `index.html` generator (in `ci_publish.sh`) | Landing page setup instructions | **MODIFY** — add distro selector to setup snippets |

## Recommended Project Structure

```
podman-debian/
├── versions-stable.env          # UNCHANGED — component tags (distro-independent)
├── versions-nightly.env         # UNCHANGED
├── packaging/
│   ├── nfpm/
│   │   ├── crun.yaml            # MODIFY — ${CRUN_PARSER_DEPEND} already templated; add others
│   │   ├── *.yaml              # MODIFY where dep names differ across distros
│   │   ├── deps-2404.env       # NEW — DEPEND_LIBSECCOMP=libseccomp2, etc.
│   │   └── deps-2604.env       # NEW — DEPEND_LIBSECCOMP=<26.04 name>, etc.
│   └── repo/
│       └── conf/
│           ├── distributions   # MODIFY — 6 stanzas (track × distro)
│           └── options         # UNCHANGED
└── scripts/
    ├── package_all.sh          # MODIFY — DISTRO awareness + deps-<distro>.env sourcing
    ├── repo_manage.sh          # MODIFY — full suite name arg
    └── ci_publish.sh           # MODIFY — distro arg + 5-other-suites import
```

### Structure Rationale

- **`deps-<distro>.env` lives beside the nFPM YAML** it feeds, mirroring the existing `versions-*.env`
  convention at repo root. Keeping the file format identical (`export VAR=value`) lets CI/`package_all.sh`
  source it the same way it already sources `versions-stable.env`.
- **One shared `pool/`, six `dists/`** is the canonical reprepro multi-suite layout. The `.deb` files are
  byte-identical across distros only when deps are identical; where deps differ, the package filename collides
  unless the version carries a distro token — see "Pool collision" anti-pattern below.

## Architectural Patterns

### Pattern 1: Distro as a first-class matrix axis (not a parallel workflow)

**What:** Add `distro: [2404, 2604]` to a single `strategy.matrix` alongside arch, producing 4 build cells from
one job definition. Runner image is selected by the matrix value (`include:` maps `2404+amd64 → ubuntu-24.04`,
`2404+arm64 → ubuntu-24.04-arm`, `2604+amd64 → ubuntu-26.04`, `2604+arm64 → ubuntu-26.04-arm`).

**When to use:** When build steps are identical except for inputs — exactly the case here (same `setup.sh`, same
`package_all.sh`, only `DISTRO` and runner differ).

**Trade-offs:**
- (+) One job spec; eliminates the current copy-paste drift between the near-identical `build-amd64`/`build-arm64`
  blocks (which today duplicate ~60 lines each).
- (+) `fail-fast: false` lets 26.04 fail without killing 24.04 during bring-up.
- (−) Go cache keys must gain a distro component or 24.04/26.04 collide (`go-${{ runner.arch }}-...` →
  `go-${{ matrix.distro }}-${{ runner.arch }}-...`).
- (−) Native `ubuntu-26.04` / `ubuntu-26.04-arm` runner labels may not exist yet → container fallback needed
  (flagged in PITFALLS; do not assume the label resolves).

**Example:**
```yaml
build:
  strategy:
    fail-fast: false
    matrix:
      distro: ["2404", "2604"]
      arch: ["amd64", "arm64"]
      include:
        - { distro: "2404", arch: "amd64", runner: "ubuntu-24.04" }
        - { distro: "2404", arch: "arm64", runner: "ubuntu-24.04-arm" }
        - { distro: "2604", arch: "amd64", runner: "ubuntu-26.04" }
        - { distro: "2604", arch: "arm64", runner: "ubuntu-26.04-arm" }
  runs-on: ${{ matrix.runner }}
  steps:
    ...
    - uses: actions/upload-artifact@v4
      with:
        name: debs-${{ matrix.distro }}-${{ matrix.arch }}   # 4 distinct names
        path: output/*.deb
```

### Pattern 2: Suite name = `<track>-<distro>`; Codename carries the alias

**What:** Each reprepro distribution stanza gets `Codename: <track>-<distro>` (the stable directory name under
`dists/`) and a `Suite:` field that can be re-pointed. APT matches the third token of a `deb` line against
*either* Codename *or* Suite. This is the lever for migration (Pattern 5).

**When to use:** Always, for this repo — v2.0 set `Codename == Suite == track`; v3.0 must distinguish them so the
old track names can alias to a chosen default distro during cutover.

**Trade-offs:**
- (+) Directory layout is explicit and greppable (`dists/stable-2404/`).
- (−) The v2.0 decision "Codename = Suite to avoid createsymlinks complexity" is now reversed; alias handling
  re-enters scope (Pattern 5).

**Example (`packaging/repo/conf/distributions`, one of six stanzas):**
```
Origin: podman-ubuntu
Label: Podman Ubuntu
Codename: stable-2404
Suite: stable-2404
AlsoAcceptFor: stable           # accept legacy `... stable main` includes during migration
Architectures: amd64 arm64
Components: main
Description: Podman from source for Ubuntu 24.04 — stable
SignWith: yes
```

### Pattern 3: Per-distro dependency mapping via env files + envsubst (NOT runtime apt-cache)

**What:** Encode distro-specific dependency package names in `deps-2404.env` / `deps-2604.env` as
`export DEPEND_X=name`. `package_all.sh` sources the right file based on `DISTRO`, exports the vars, and the
existing `envsubst` call expands them into the nFPM YAML — the identical mechanism already used for
`${CRUN_PARSER_DEPEND}`.

**When to use:** This is the recommended approach over runtime `apt-cache` detection because:
- The pipeline **already** has the pattern — `${CRUN_PARSER_DEPEND}` is already an envsubst variable and
  `package_all.sh` already does `export CRUN_PARSER_DEPEND` before expanding. Extending env-file-driven vars is a
  minimal, consistent delta.
- Env files are **declarative, reviewable, diffable** — the "package renamed on 26.04" knowledge lives in version
  control, not inferred at build time.
- `apt-cache`-based detection is fragile: depends on the runner's apt indices, can silently pick a wrong
  provider, and couples packaging correctness to network/mirror state.

**Hybrid nuance:** Keep the existing `ldd`-based `detect_crun_parser_depend()` for the *parser* lib (json-c vs
yajl) — that genuinely depends on what got linked at build time, which an env file can't know a priori. So:
runtime detection answers "which library did we actually link", static env file answers "what is that library's
package *named* on this distro". The detector returns a logical key; the env file maps key → distro package name.

**Trade-offs:**
- (+) Zero new runtime dependency on apt metadata; reproducible.
- (+) Reuses proven envsubst path:
  `envsubst '${VERSION} ${ARCH} ${DESTDIR} ${CRUN_PARSER_DEPEND}' < yaml`.
- (−) Requires a one-time manual audit of every dep name across both distros (the actual hard work; see
  PITFALLS). A missing entry = uninstallable package on that distro.

**Example:**
```bash
# packaging/nfpm/deps-2404.env
export DEPEND_LIBSECCOMP="libseccomp2"
export DEPEND_LIBSYSTEMD="libsystemd0"
export DEPEND_LIBGPGME="libgpgme11"

# packaging/nfpm/deps-2604.env   (names that changed on 26.04 — VERIFY each)
export DEPEND_LIBSECCOMP="libseccomp2"
export DEPEND_LIBSYSTEMD="libsystemd0"     # may shift under a t64 transition — confirm
export DEPEND_LIBGPGME="libgpgme11t64"     # example of a t64-style rename — confirm
```
```bash
# scripts/package_all.sh (new lines)
DISTRO="${DISTRO:?DISTRO must be set (2404|2604)}"
# shellcheck disable=SC1090
source "${NFPM_DIR}/deps-${DISTRO}.env"
# add the new vars to every envsubst allow-list:
envsubst '${VERSION} ${ARCH} ${DESTDIR} ${CRUN_PARSER_DEPEND} ${DEPEND_LIBSECCOMP} ${DEPEND_LIBSYSTEMD} ${DEPEND_LIBGPGME}' \
  < "${NFPM_DIR}/${component}.yaml" > "${nfpm_config}"
```
```yaml
# packaging/nfpm/crun.yaml — depends: section becomes
depends:
  - ${DEPEND_LIBSECCOMP}
  - ${DEPEND_LIBSYSTEMD}
  - libcap2
  - ${CRUN_PARSER_DEPEND}
```

> envsubst gotcha: list **every** variable explicitly in the allow-list. An unlisted `${VAR}` is left literal in
> the YAML and nFPM emits a malformed dependency. This is the single most likely silent failure when adding new
> dep vars.

## Data Flow

### Build → Package flow (per matrix cell)

```
runner (distro,arch)
   ↓ setup.sh  (native compile → DESTDIR staging)   [distro-agnostic]
   ↓ DISTRO=<2404|2604> exported by workflow step
package_all.sh
   ↓ source versions-stable.env  (track inputs — distro-independent)
   ↓ source deps-<DISTRO>.env    (NEW — distro dep names)
   ↓ VERSION_SUFFIX gains distro token (e.g. ~ubuntu2404.podman1)
   ↓ per component: detect_crun_parser_depend() [runtime] + envsubst [static]
   ↓ nfpm pkg --packager deb
output/*.deb
   ↓ upload-artifact name=debs-<distro>-<arch>
```

### Publish fan-in (single job, per run)

```
download-artifact pattern=debs-*  →  KEEP SEPARATE BY DISTRO
   (do NOT use merge-multiple — 24.04 and 26.04 .deb share filenames but differ in deps;
    merging would let one distro's package overwrite the other's in a flat dir)
   ↓
for distro in 2404 2604:
   ci_publish.sh <track> <distro> all-debs/<distro> <repo-url> repo-output
      ├─ repo_manage.sh <track>-<distro> <debs> repo-output   (includedeb + export)
      └─ import OTHER 5 suites from live Pages:
           dists/<other-track>-<other-distro>/main/binary-<arch>/Packages
   ↓ single repo-output/ tree with all 6 dists/
upload-pages-artifact → deploy-pages   (one atomic deploy of the whole repo)
```

### Atomicity contract (unchanged shape, now 6-suite)

The publish job already achieves atomicity by **rebuilding the entire repo every run** and deploying it as one
Pages artifact: it imports the *other* suites' packages from the currently-live site, adds the freshly built
suite, then deploys everything at once. With 6 suites this means: a `stable` run rebuilds `stable-2404` and
`stable-2604` from fresh artifacts and imports the 4 nightly/edge suites from the live site. The
`concurrency: group: "pages"` lock with `cancel-in-progress: false` serializes deploys so two runs can't race.
**This pattern scales to 6 suites with no architectural change** — only the loop bounds grow. Note: the existing
`ci_publish.sh` already loops "other suites" and exports each individually to avoid clobbering — that logic
generalizes from 2-others to 5-others by composing the track loop with a distro loop.

## Scaling Considerations

| Scale | Architecture adjustments |
|-------|--------------------------|
| 2 distros (this milestone) | Matrix + 6-suite loop. Build wall-clock unchanged (cells run in parallel); publish does 2× the reprepro work serially — acceptable (minutes). |
| 3+ distros (e.g. Debian 13) | Same matrix pattern holds; `distro` axis gains values. Publish import time grows linearly with suite count (N_tracks × N_distros − 1 imports). Parallelize per-distro publish only if it exceeds the deploy budget. |
| Many distros | Re-importing all "other" suites from live Pages each run becomes the bottleneck (O(suites) HTTP fetches of full Packages indices). Mitigation: persist reprepro `db/` + `pool/` as a cached/committed artifact instead of reconstructing from the live site. Out of scope now. |

### Scaling priorities

1. **First bottleneck — native 26.04 ARM runner availability.** If `ubuntu-26.04-arm` doesn't exist, that one
   matrix cell blocks. Fix: container-based build on `ubuntu-24.04-arm` running a 26.04 image, isolated to that
   cell via `matrix.include`.
2. **Second bottleneck — publish-time live-repo re-import.** Linear in suite count. Fine at 6; revisit if distro
   count grows.

## Anti-Patterns

### Anti-Pattern 1: Separate workflow files per distro

**What people do:** Copy `build-packages.yml` to `build-packages-2604.yml`.
**Why it's wrong:** Doubles maintenance of an already-duplicated file, and — fatally — gives each workflow its own
Pages deploy, breaking the single-atomic-deploy contract. Two workflows racing on `actions/deploy-pages` clobber
each other's suites.
**Do this instead:** One workflow, one publish job, distro as a matrix axis and a publish loop.

### Anti-Pattern 2: `merge-multiple: true` when downloading 4 artifact sets

**What people do:** Keep the existing `download-artifact ... merge-multiple: true` into one flat `all-debs/`.
**Why it's wrong:** A 24.04 and a 26.04 build of the same component produce `.deb` files with the **same
filename** (`podman-crun_<ver>_amd64.deb`) but **different dependency content**. Merging into one directory means
the second download overwrites the first, and the wrong package lands in both suites.
**Do this instead:** Download into per-distro subdirectories (artifact names already encode distro:
`debs-2404-amd64`), and feed each distro's directory to its own `ci_publish.sh` invocation.

### Anti-Pattern 3: Shared `pool/` collision across distros

**What people do:** Let reprepro put both distros' same-named `.deb` into the shared `pool/` (reprepro pools by
package name+version+arch).
**Why it's wrong:** If 24.04 and 26.04 packages share name+version+arch but differ in `Depends:`, reprepro either
rejects the second as a duplicate or serves one distro the other's dependencies — an install-time failure.
**Do this instead:** Make the package version distro-distinct so the pool path differs. Extend the existing
`VERSION_SUFFIX="~podman1"` to include the distro token, e.g. `"~ubuntu${DISTRO}.podman1"` →
`5.8.0~ubuntu2404.podman1` vs `5.8.0~ubuntu2604.podman1`. The `~` keeps dpkg sort order correct and the distro
token gives each a unique pool path. Small `package_all.sh` change, large correctness payoff.

### Anti-Pattern 4: Runtime `apt-cache` dependency discovery as the primary mechanism

**What people do:** Query `apt-cache` at package time to find the "current" name of each dep.
**Why it's wrong:** Couples packaging correctness to mutable apt index state; non-reproducible; can pick a wrong
provider. (See Pattern 3 for the env-file alternative and the narrow `ldd` exception.)

## Integration Points

### External Services

| Service | Integration pattern | Notes / gotchas |
|---------|---------------------|-----------------|
| GitHub Pages | `upload-pages-artifact` + `deploy-pages`, one deploy per run | Single site hosts all 6 suites; `concurrency: pages` serializes. No change to deploy mechanism. |
| Live Pages repo (read-back) | `curl` of `dists/<suite>/main/binary-<arch>/Packages` in `ci_publish.sh` | URL gains distro token: `dists/<track>-<distro>/...`. Must tolerate 404 (first deploy of a new suite) — existing code already treats empty Packages as "first deploy". |
| GitHub Actions native runners | `ubuntu-26.04`, `ubuntu-26.04-arm` labels | Availability NOT guaranteed — verify; container fallback per cell if absent. |

### Internal Boundaries

| Boundary | Communication | Considerations |
|----------|---------------|----------------|
| workflow → `package_all.sh` | env var `DISTRO` (new), `NIGHTLY_BUILD`, `DESTDIR` | `DISTRO` must be set in CI; provide a local-run default (e.g. derive from `lsb_release -rs` → 2404/2604). |
| `package_all.sh` → nFPM YAML | `envsubst` allow-list of `${...}` vars | Every new dep var MUST be added to the allow-list or it stays literal. |
| workflow publish → `ci_publish.sh` | positional args, now `(track, distro, debdir, url, out)` | Signature change is breaking — update the workflow call in the same commit. |
| `ci_publish.sh` → `repo_manage.sh` | positional arg `suite` now `<track>-<distro>` | Both scripts' suite validation must accept the 6 composite names (regex `^(stable|edge|nightly)-(2404|2604)$`). |

## Migration Handling (existing suite names)

Existing users have `.sources`/`.list` lines like `deb [...] <url> stable main`. After cutover the directory is
`dists/stable-2404/`. Two viable strategies, in order of preference:

1. **`AlsoAcceptFor` + physical alias copy (recommended, transparent).** Give the 24.04 stanzas `AlsoAcceptFor`
   entries for the bare names (`stable`, `edge`, `nightly`) and publish a `dists/stable` that resolves to the
   2404 suite. Legacy users keep working (24.04 was the only prior distro, so aliasing the bare name to the 2404
   suite is correct), while new users use explicit `stable-2404`/`stable-2604`. Deprecate the alias in docs and
   remove after a grace period. This directly revisits and reverses the v2.0 "Codename = Suite" decision noted in
   PROJECT.md.
   *Confirmed:* `Codename` is the immutable on-disk name; `Suite` may change; `createsymlinks` builds
   suite→codename links; `AlsoAcceptFor` widens which distribution headers are accepted on include
   ([Debian reprepro manpage](https://manpages.debian.org/unstable/reprepro/reprepro.1.en.html)).

   > Pages caveat: `dists/stable` must be a real directory/copy on the served site, not a filesystem symlink,
   > since the Pages artifact tarball may not preserve symlinks. Safest implementation: physically duplicate
   > (`cp -r`) the exported `dists/stable-2404` to `dists/stable` during `ci_publish.sh`, rather than relying on
   > `reprepro createsymlinks`. Treat "alias = copy". The `AlsoAcceptFor` half is build-side only and always safe.

2. **Documented hard cutover (simpler, breaks loudly).** Publish only the six new suites; update docs and the
   `index.html` generator to emit `stable-2404`/`stable-2604`. Existing users get "suite no longer exists" /
   stale-index errors on `apt update` until they edit their sources. Lower implementation cost, worse UX. Use
   only if option 1's alias copy proves troublesome.

## Suggested Build Order

The constraint is "every step stays shippable." The dependency graph is:
**version suffix + dep mapping** (correctness of the artifact) → **reprepro 6-suite config + script suite args**
(where artifacts land) → **CI matrix** (producing all four cells) → **migration aliases** (UX polish).

1. **Dependency mapping + version-suffix first (artifact correctness).**
   Add `deps-2404.env` (mirroring *current* behavior exactly — pure refactor, no functional change), template the
   differing dep names in nFPM YAML, and extend `VERSION_SUFFIX` to include the distro token. Ship: existing
   24.04 pipeline still produces equivalent packages. *Why first:* nothing else is correct if package
   contents/names are wrong, and this step is independently verifiable against the existing single-distro pipeline
   (24.04 output unchanged except the version suffix gains `ubuntu2404`).

2. **Repo restructure + script suite-targeting second (where artifacts land).**
   Expand `distributions` to 6 stanzas, change `repo_manage.sh`/`ci_publish.sh` to take composite suite names and
   loop the 5 other suites. Ship: 24.04 now publishes to `stable-2404` etc.; add migration aliases so the bare
   names still resolve (24.04-only world → aliasing is unambiguous). *Why second:* the CI matrix's publish job
   calls these scripts — they must accept the new suite vocabulary before the matrix produces 26.04 artifacts, and
   doing it here keeps the repo shippable as a "24.04 with new layout" milestone.

3. **CI matrix third (produce all four cells).**
   Collapse the two build jobs into the distro×arch matrix, add `deps-2604.env` (now there's a consumer), wire
   per-distro artifact names and the publish loop. Ship: full 2-distro × 2-arch × 3-track pipeline. *Why third:*
   depends on both the dep files (step 1) and the suite-aware scripts (step 2) already existing; introducing the
   26.04 cells earlier would have nowhere correct to publish.

4. **Migration cutover + docs last (UX).**
   Finalize alias strategy (copy `stable-2404 → stable`), update `index.html` setup tabs to be distro-aware,
   document the deprecation timeline. *Why last:* purely additive UX; the system is already fully functional for
   users who adopt the new explicit suite names.

**Alternative considered — CI matrix first:** rejected. Standing up `ubuntu-26.04` cells before the dep map and
suite layout exist means the 26.04 packages either fail to install (wrong dep names) or collide in the pool (no
distro version suffix) and have no valid suite to land in — the intermediate state is not shippable, violating the
constraint.

## Sources

- Existing repo code (HIGH): `.github/workflows/build-packages.yml`, `scripts/package_all.sh`,
  `scripts/ci_publish.sh`, `scripts/repo_manage.sh`, `packaging/repo/conf/distributions`,
  `packaging/nfpm/crun.yaml`, `versions-stable.env`, `.planning/PROJECT.md`
- [reprepro(1) — Debian unstable manpage](https://manpages.debian.org/unstable/reprepro/reprepro.1.en.html) — Suite vs Codename, `createsymlinks`, `AlsoAcceptFor` (HIGH)
- [DebianRepository/SetupWithReprepro — Debian Wiki](https://wiki.debian.org/DebianRepository/SetupWithReprepro) — Codename immutability, Suite mutability (HIGH)
- [How to create a Debian repository with reprepro — Packagecloud](https://blog.packagecloud.io/how-to-create-debian-repository-with-reprepro/) — multi-suite shared pool layout (MEDIUM)

---
*Architecture research for: v3.0 multi-distro APT build/publish pipeline*
*Researched: 2026-06-05*
