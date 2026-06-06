# Phase 20: Repository Restructure & Migration Aliases - Context

**Gathered:** 2026-06-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Repository-side restructure: the APT repository serves six versioned suites (`stable-2404`, `edge-2404`, `nightly-2404`, `stable-2604`, `edge-2604`, `nightly-2604`) from a single URL under one GPG key, while existing users whose `.sources` still point at bare `stable`/`edge`/`nightly` keep receiving 24.04 packages with no client-side change. Every suite's metadata carries `Acquire-By-Hash: yes`, and the publish tooling routes a `<track>-<distro>` publish without clobbering the other suites.

In scope: `packaging/repo/conf/distributions` restructure (9 suites: 6 versioned + 3 legacy aliases), `scripts/repo_manage.sh` and `scripts/ci_publish.sh` suite routing, by-hash post-processing + re-signing, on-VM validation of the legacy-client path, minimal index.html adjustment.
Out of scope (later phases): CI build matrix for 26.04 (Phase 21), per-distro DEB822 setup docs / index.html instructions / deprecation timeline docs (Phase 22), removing the legacy aliases (future REPO-09), codename-aliased suites (future REPO-10).

</domain>

<decisions>
## Implementation Decisions

User directive: "Apply best practices, no overengineering" — all four gray areas resolved by Claude using best practices, grounded in the existing publish pipeline. Confirmed and locked by the user.

### Legacy alias mechanism
- **D-01:** Bare `stable`/`edge`/`nightly` remain **first-class reprepro distributions** in `conf/distributions`, alongside the six versioned suites. They are fed the *same* 24.04 `.deb` set as their `-2404` counterparts. NOT a post-publish directory copy, NOT a symlink (roadmap lock).
- **D-02:** Rationale lock: this is the only physical approach where the alias's Release file keeps `Suite: stable` / `Codename: stable`, so pre-v3.0 clients never hit apt's "repository changed its 'Suite' value" error (a `cp -r dists/stable-2404 dists/stable` would embed `Suite: stable-2404` and trip exactly that prompt). This closes the STATE.md research-flag question in favor of real suites.
- **D-03:** Codename = Suite name for ALL nine distributions (carries forward Phase 15-01; e.g. `Suite: stable-2404` / `Codename: stable-2404`). No `createsymlinks`.
- **D-04:** Legacy suites' `Description:` field gets a one-line deprecation note (e.g. "DEPRECATED alias for stable-2404 — see migration docs"). The deprecation *timeline* itself is Phase 22 (MIGR-03) — not documented in this phase.
- **D-05:** reprepro's shared `pool/` already dedupes identical `.deb` files across suites — no special handling needed for the duplication between alias and `-2404` suite.

### Acquire-By-Hash strategy
- **D-06:** Keep reprepro. Do NOT migrate to aptly or other tooling — rebuilding the proven publish pipeline for one metadata field is overengineering.
- **D-07:** Implement REPO-08 as a **post-export post-processing step**: after `reprepro export`, for each suite (a) materialize `by-hash/SHA256/<hash>` (and SHA512 if listed) copies of each index file under `dists/<suite>/main/binary-<arch>/`, (b) inject `Acquire-By-Hash: yes` into the suite's Release file, (c) re-sign: regenerate `Release.gpg` and `InRelease` with the same GPG key already imported in the publish environment. Plain bash, consistent with the shell-orchestrated pipeline.
- **D-08:** Re-signing is mandatory after Release mutation — a Release edited after `reprepro export` invalidates the existing signature. The CI key import path in `repo_manage.sh` (GPG_PRIVATE_KEY) already provides the key at the right time.
- **D-09:** One by-hash generation per publish is sufficient (the dists tree is rebuilt from scratch each publish; apt falls back to canonical filenames on by-hash miss). Researcher verifies the exact directory layout, which hash algorithms apt requires, and fallback semantics.

### Publish state & routing
- **D-10:** Keep the proven **rebuild-the-world** publish model in `ci_publish.sh`: fresh `.deb` artifacts for the suite being published, all other suites' packages mirrored down from the live repo URL, full repo assembled in CI, deployed atomically to Pages. No persistent reprepro db, no incremental gh-pages checkout — that statefulness is overengineering here (Phase 21 builds atomicity on top of this model).
- **D-11:** Suite addressing becomes `<track>-<distro>`: publish tooling takes track (stable/edge/nightly) + distro (2404/2604) and routes into the correct versioned suite. The hardcoded `stable|edge|nightly` whitelists in `repo_manage.sh` and `ci_publish.sh` are extended to the new suite set.
- **D-12:** Alias routing rule: publishing a **24.04** track updates BOTH `<track>-2404` and the bare `<track>` alias from the **fresh** debs (one download, two includedeb targets). Publishing a **26.04** track touches ONLY `<track>-2604`; the bare aliases are mirrored from the live repo unchanged, like any other untouched suite.
- **D-13:** Criterion 4 (no clobbering) is satisfied by the mirror-then-include pattern: every publish reassembles all nine suites, with only the published suite (and, for 24.04 tracks, its alias) taking new content.

### Rollout & validation
- **D-14:** All six versioned suites exist from the first Phase 20 deploy. The `-2604` suites publish **empty-but-signed** (reprepro `export` already generates signed empty indexes for every configured distribution), so `apt update` against any suite succeeds with a valid signature chain (success criterion 1) before Phase 21 fills them.
- **D-15:** Legacy-client validation runs on the **ubuntu-24 Lima VM**: configure a pre-v3.0 `.sources`/`.list` pointing at bare `stable`, run `apt update` + `apt policy` against the deployed repo, and assert (a) no "Suite value changed" prompt/error, (b) 24.04 packages still resolve. This closes the STATE.md research flag's "real pre-v3.0 client" requirement.
- **D-16:** No staging GitHub Pages repo/branch. The full multi-suite repo is assembled as a CI artifact (inspectable before deploy) and the structure can be validated locally/in-VM before the production deploy — a parallel staging Pages site is overengineering for this project.
- **D-17:** The live-Pages physical-vs-symlink question from the research flag is resolved by construction: reprepro suites materialize real files (D-01), so nothing depends on symlink survival. The post-deploy `apt update` check in D-15 doubles as the live Pages verification.
- **D-18:** index.html: minimal adjustment only — the suite listing loop must handle the nine suites (and continue skipping empty ones); full per-distro setup instructions are Phase 22 (MIGR-02).

### Claude's Discretion
- Exact mechanism for feeding the alias suites (run `includedeb` twice per .deb vs reprepro `conf/pulls` rules) — planner picks whichever is simpler and closest to the existing loop structure; the semantic (alias content ≡ `-2404` suite content) is what's locked.
- Whether `repo_manage.sh` keeps a single-suite signature or learns track+distro args — planner decides the cleanest CLI surface, as long as `ci_publish.sh` can route per D-11/D-12.
- Where the by-hash post-processing lives (inline in `repo_manage.sh`, separate `scripts/` helper, or function in `functions.sh`).
- How the suite whitelist is expressed (array in config.sh vs regex) — follow existing config patterns.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` — Phase 20 goal + 4 success criteria (six suites/one key/valid signatures; legacy alias physical not symlink; Acquire-By-Hash on every suite; non-clobbering routing)
- `.planning/REQUIREMENTS.md` — REPO-06/07/08 definitions; Out of Scope table (no per-distro repo paths, no hard cutover, no 24.04 binaries in 26.04 suites); future REPO-09/REPO-10 (do not implement)
- `.planning/PROJECT.md` — v3.0 milestone context; "Codename = Suite name" v2.0 decision being revisited; Key Decisions table

### Code this phase modifies
- `packaging/repo/conf/distributions` — current 3-suite reprepro config; becomes 9 distributions (6 versioned + 3 legacy aliases)
- `scripts/repo_manage.sh` — single-suite repo builder; suite whitelist at line 56, GPG import block, includedeb loop, `reprepro export`, pubkey publishing; by-hash post-processing hooks in here or alongside
- `scripts/ci_publish.sh` — multi-suite CI publisher; ALL_SUITES array (line 91), live-repo mirror-down loop, per-suite `reprepro export <suite>`, index.html generation (suite listing loop at line 229-352)
- `.github/workflows/build-packages.yml` — publish job invokes `ci_publish.sh` (line ~305); argument plumbing changes with the new track+distro routing (matrix extension itself is Phase 21)

### Phase 19 outputs this phase builds on
- `.planning/phases/19-per-distro-versioning-dependency-mapping/19-CONTEXT.md` — locked version-suffix decisions (D-07/D-08: `~ubuntu{VERSION_ID}.podman1` composed in config.sh); the per-distro .debs this repo restructure will host

No external specs/ADRs exist — requirements fully captured in the refs above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/repo_manage.sh` GPG import block (GPG_PRIVATE_KEY base64/armored handling + ownertrust) — the same key context is available for the by-hash re-signing step (D-08)
- `scripts/ci_publish.sh` mirror-down loop (Packages index → Filename: parse → curl per .deb) — generalizes from 2 "other suites" to N untouched suites
- `reprepro export` already exports ALL configured distributions, including empty ones — gives D-14's empty-but-signed `-2604` suites for free
- Lima VMs (`ubuntu-24`, `ubuntu-26`) with repo mounted at `/opt/podman-debian` — the pre-v3.0 client validation vehicle (D-15)

### Established Patterns
- `set -euo pipefail` + ERR trap + toolpath bootstrap in every script — by-hash helper follows the same skeleton
- Suite validation as explicit whitelist with clear error message — extend, don't remove
- Repo conf copied from `packaging/repo/conf/` into the output dir, then `db/`+`conf/` cleaned post-build — alias suites just add entries to the same distributions file
- Environment-variable-driven config with `${VAR:-default}` in `config.sh` — any new DISTRO/track plumbing threads through there (Phase 19 already landed DISTRO detection)

### Integration Points
- `ci_publish.sh` is called from the `publish` job in `.github/workflows/build-packages.yml` with `(suite, deb_dir, repo_url, output_dir)` — argument shape changes to carry distro; Phase 21 will fan the matrix into it
- `repo_manage.sh` is invoked by `ci_publish.sh` (line 165) for the fresh suite — alias feeding (D-12) hooks into this sequence
- index.html generation embeds suite names and the `REPO_URL_PLACEHOLDER` sed — suite-listing loop must iterate the new suite set (D-18)
- Phase 19's `~ubuntu{24.04,26.04}.podman1` filename suffixes keep both distros' .debs distinct inside the shared `pool/`

</code_context>

<specifics>
## Specific Ideas

- STATE.md research flag (Phase 20): "physical-copy vs createsymlinks alias strategy needs live GitHub Pages test (Pages tarballs may not preserve symlinks); validate 'Suite changed value' apt prompt with a real pre-v3.0 client" — resolved by D-01/D-02 (real reprepro suites, correct Suite: field by construction) and verified by D-15/D-17
- Known apt failure mode to design against: `E: Repository '... stable InRelease' changed its 'Suite' value from 'stable' to 'stable-2404'` — the alias suites exist precisely to prevent this
- reprepro has NO native Acquire-By-Hash support — confirmed gap motivating D-06/D-07; researcher should verify current reprepro version behavior anyway in case a newer release added it

</specifics>

<deferred>
## Deferred Ideas

- Removing legacy bare-suite aliases after the deprecation window — already tracked as future requirement REPO-09
- Codename-aliased suites (`noble`/`resolute`) for `$VERSION_CODENAME` auto-detect — already tracked as future requirement REPO-10
- Per-distro setup instructions on index.html and DEB822 copy-paste blocks — Phase 22 (MIGR-01/MIGR-02)
- Deprecation timeline documentation — Phase 22 (MIGR-03)

</deferred>

---

*Phase: 20-Repository Restructure & Migration Aliases*
*Context gathered: 2026-06-06*
