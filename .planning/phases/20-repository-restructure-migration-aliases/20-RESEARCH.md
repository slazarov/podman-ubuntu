# Phase 20: Repository Restructure & Migration Aliases - Research

**Researched:** 2026-06-06
**Domain:** APT repository metadata (reprepro), Debian repository format spec, Acquire-By-Hash, GPG re-signing, multi-suite publish routing
**Confidence:** HIGH

## Summary

This phase restructures the reprepro-backed APT repository from 3 suites (`stable`/`edge`/`nightly`) to 9 distributions: 6 versioned (`<track>-2404`, `<track>-2604`) plus 3 legacy aliases (bare `stable`/`edge`/`nightly`) that physically duplicate their `-2404` counterparts. It adds `Acquire-By-Hash: yes` to every suite via a post-export post-processing step (reprepro has no native support), and extends the publish-routing logic in `repo_manage.sh` / `ci_publish.sh` to address suites by `<track>-<distro>` without clobbering untouched suites.

All four architectural ambiguities were locked by the user in CONTEXT.md ("best practices, no overengineering"). Research confirms every locked decision is sound against the live Debian repository specification and apt's documented behavior: (D-01/D-02) keeping the bare aliases as real reprepro distributions is the *only* approach where the served `Release` file carries `Suite: stable`, which is exactly what prevents apt's `changed its 'Suite' value` error [VERIFIED: forum.proxmox.com, claudiokuenzler.com — the error fires when the served Suite field differs from what apt recorded]; (D-06/D-07) reprepro genuinely lacks server-side Acquire-By-Hash as of 2025 [VERIFIED: Debian bug #820660, arnaudr.io 2025], so a post-export bash step is the correct path; (D-08) re-signing after mutating `Release` is mandatory because the existing signature covers the unmutated bytes.

**Primary recommendation:** Extend `conf/distributions` to 9 stanzas (Codename = Suite per D-03), add a `--distro` dimension to `repo_manage.sh`/`ci_publish.sh` routing, and implement a self-contained `scripts/repo_byhash.sh` (or `functions.sh` helper) that — per suite, after `reprepro export` — materializes `by-hash/<ALGO>/<hash>` copies of every index + the `Release` file, injects `Acquire-By-Hash: yes` into `Release`, and regenerates `InRelease` + `Release.gpg` with the already-imported GPG key.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Legacy alias mechanism**
- **D-01:** Bare `stable`/`edge`/`nightly` remain **first-class reprepro distributions** in `conf/distributions`, alongside the six versioned suites. Fed the *same* 24.04 `.deb` set as their `-2404` counterparts. NOT a post-publish directory copy, NOT a symlink.
- **D-02:** Rationale lock: only physical-real-suite approach keeps the alias's Release file at `Suite: stable` / `Codename: stable`, so pre-v3.0 clients never hit apt's "repository changed its 'Suite' value" error (a `cp -r dists/stable-2404 dists/stable` would embed `Suite: stable-2404` and trip it).
- **D-03:** Codename = Suite name for ALL nine distributions (carries forward Phase 15-01; e.g. `Suite: stable-2404` / `Codename: stable-2404`). No `createsymlinks`.
- **D-04:** Legacy suites' `Description:` gets a one-line deprecation note (e.g. "DEPRECATED alias for stable-2404 — see migration docs"). The deprecation *timeline* is Phase 22 (MIGR-03) — not documented here.
- **D-05:** reprepro's shared `pool/` already dedupes identical `.deb` files across suites — no special handling needed.

**Acquire-By-Hash strategy**
- **D-06:** Keep reprepro. Do NOT migrate to aptly or other tooling.
- **D-07:** Implement REPO-08 as a **post-export post-processing step**: after `reprepro export`, for each suite (a) materialize `by-hash/SHA256/<hash>` (and SHA512 if listed) copies of each index under `dists/<suite>/main/binary-<arch>/`, (b) inject `Acquire-By-Hash: yes` into the suite's Release file, (c) re-sign: regenerate `Release.gpg` and `InRelease` with the same GPG key. Plain bash.
- **D-08:** Re-signing is mandatory after Release mutation — a Release edited after `reprepro export` invalidates the existing signature.
- **D-09:** One by-hash generation per publish is sufficient (dists rebuilt from scratch each publish; apt falls back to canonical filenames on by-hash miss). Researcher verifies exact directory layout, hash algorithms apt requires, and fallback semantics.

**Publish state & routing**
- **D-10:** Keep the **rebuild-the-world** publish model in `ci_publish.sh`: fresh `.deb` artifacts for the published suite, all other suites mirrored down from the live repo URL, full repo assembled in CI, deployed atomically. No persistent reprepro db, no incremental gh-pages checkout.
- **D-11:** Suite addressing becomes `<track>-<distro>`: tooling takes track (stable/edge/nightly) + distro (2404/2604) and routes into the correct versioned suite. The hardcoded `stable|edge|nightly` whitelists in `repo_manage.sh` and `ci_publish.sh` are extended to the new suite set.
- **D-12:** Alias routing rule: publishing a **24.04** track updates BOTH `<track>-2404` and the bare `<track>` alias from the **fresh** debs (one download, two includedeb targets). Publishing a **26.04** track touches ONLY `<track>-2604`; the bare aliases are mirrored from the live repo unchanged.
- **D-13:** Criterion 4 (no clobbering) satisfied by mirror-then-include: every publish reassembles all nine suites, only the published suite (and, for 24.04, its alias) takes new content.

**Rollout & validation**
- **D-14:** All six versioned suites exist from the first Phase 20 deploy. The `-2604` suites publish **empty-but-signed** (reprepro `export` generates signed empty indexes for every configured distribution), so `apt update` against any suite succeeds before Phase 21 fills them.
- **D-15:** Legacy-client validation runs on the **ubuntu-24 Lima VM**: configure a pre-v3.0 `.sources`/`.list` pointing at bare `stable`, run `apt update` + `apt policy` against the deployed repo, and assert (a) no "Suite value changed" prompt/error, (b) 24.04 packages still resolve.
- **D-16:** No staging GitHub Pages repo/branch. Full multi-suite repo assembled as a CI artifact (inspectable before deploy) + validated locally/in-VM.
- **D-17:** Live-Pages physical-vs-symlink question resolved by construction: reprepro suites materialize real files (D-01), so nothing depends on symlink survival. The post-deploy `apt update` check in D-15 doubles as live Pages verification.
- **D-18:** index.html: minimal adjustment only — the suite listing loop must handle the nine suites (continue skipping empty ones); full per-distro setup instructions are Phase 22 (MIGR-02).

### Claude's Discretion
- Exact mechanism for feeding the alias suites (run `includedeb` twice per .deb vs reprepro `conf/pulls` rules) — planner picks simpler/closest to existing loop; semantic (alias content ≡ `-2404` content) is locked.
- Whether `repo_manage.sh` keeps a single-suite signature or learns track+distro args — planner decides cleanest CLI surface, as long as `ci_publish.sh` can route per D-11/D-12.
- Where the by-hash post-processing lives (inline in `repo_manage.sh`, separate `scripts/` helper, or `functions.sh` function).
- How the suite whitelist is expressed (array in config.sh vs regex) — follow existing config patterns.

### Deferred Ideas (OUT OF SCOPE)
- Removing legacy bare-suite aliases after the deprecation window — future REPO-09.
- Codename-aliased suites (`noble`/`resolute`) for `$VERSION_CODENAME` auto-detect — future REPO-10.
- Per-distro setup instructions on index.html and DEB822 copy-paste blocks — Phase 22 (MIGR-01/MIGR-02).
- Deprecation timeline documentation — Phase 22 (MIGR-03).
- CI build matrix for 26.04 — Phase 21.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REPO-06 | Repository serves six versioned suites (stable-2404, edge-2404, nightly-2404, stable-2604, edge-2604, nightly-2604) from a single URL with one GPG key | `conf/distributions` becomes 9 stanzas (6 versioned + 3 alias), one `SignWith: yes` per stanza using the single CI key (Architecture Patterns §Pattern 1). `reprepro export` with no args generates signed indexes for all configured distributions including empty `-2604` suites (D-14, verified via reprepro manpage). |
| REPO-07 | Existing users with bare `stable`/`edge`/`nightly` continue to receive 24.04 packages without client-side change | Bare aliases as real reprepro distributions whose Release file carries `Suite: stable` — the ONLY mechanism that avoids apt's `changed its 'Suite' value` error (Pitfall 1, VERIFIED). 24.04 publish feeds both `<track>-2404` and bare `<track>` from fresh debs (D-12). |
| REPO-08 | Repository metadata includes Acquire-By-Hash so apt never hits CDN hash-sum mismatches | reprepro lacks native support (VERIFIED bug #820660); implemented as post-export bash: materialize `by-hash/<ALGO>/<hash>` per index + Release, inject `Acquire-By-Hash: yes`, re-sign (Pattern 2, Code Examples). Layout: `<index-dir>/by-hash/SHA256/<sha256>` adjacent to each index, NOT at dists root (VERIFIED Debian wiki). |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 9-distribution declaration | Repo metadata config (`conf/distributions`) | — | reprepro reads distributions to know which suites to materialize |
| Suite routing by track+distro | Build/publish tooling (`ci_publish.sh`, `repo_manage.sh`) | config.sh (suite whitelist) | Shell orchestration decides which suite gets fresh debs |
| Legacy alias feeding | Publish tooling (`includedeb` into bare suite) | reprepro `pool/` dedup | Alias content is a routing decision, not a metadata-format one |
| Acquire-By-Hash generation | Post-export bash step (new helper) | GPG re-sign | Not a reprepro capability — bolt-on filesystem + signing operation |
| Release re-signing | GPG (already imported in publish env) | — | Cryptographic integrity; key context already present in `repo_manage.sh` |
| Empty-but-signed `-2604` suites | reprepro `export` | — | reprepro generates signed empty indexes for every configured distribution for free |
| Suite listing on index.html | `ci_publish.sh` HTML loop | — | Presentation only; skips empty suites |
| Legacy-client correctness verification | ubuntu-24 Lima VM (`apt update`/`apt policy`) | — | Only a real pre-v3.0 apt client proves the no-prompt criterion |

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| reprepro | distro-packaged (`apt-get install -y reprepro` in CI) | Builds the multi-suite repo, shared `pool/`, signed Release/InRelease/Release.gpg | Already the proven pipeline tool; CONTEXT D-06 locks keeping it [CITED: CLAUDE.md, .github/workflows/build-packages.yml] |
| gpg | system | Sign/re-sign Release after by-hash mutation | Already used in `repo_manage.sh` GPG_PRIVATE_KEY import block [CITED: scripts/repo_manage.sh:83-112] |
| curl | system | Mirror-down other suites' .debs from live repo | Already used in `ci_publish.sh` mirror loop [CITED: scripts/ci_publish.sh:123-142] |
| sha256sum / sha512sum | coreutils | Compute by-hash filenames | Standard coreutils; available on every Ubuntu runner/VM |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| find / cp | Materialize by-hash copies of index files | Inside the by-hash post-processing loop |
| awk / grep / sed | Parse Release `SHA256:`/`SHA512:` sections to know which files + algorithms to mirror into by-hash | When enumerating index files to hash |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| reprepro + bash by-hash | aptly (native by-hash + publish snapshots) | Locked OUT by D-06 — rebuilds proven pipeline for one field; aptly's snapshot/publish model is a different mental model and a larger blast radius |
| Real alias distributions (D-01) | `cp -r dists/stable-2404 dists/stable` | Embeds `Suite: stable-2404` in the copied Release → triggers apt "Suite value changed" prompt (Pitfall 1). Rejected by D-02. |
| Real alias distributions (D-01) | reprepro `createsymlinks` / filesystem symlink | GitHub Pages artifact tarball may not preserve symlinks (STATE.md research flag); also a symlinked Release still carries the target's Suite field. Rejected by D-01/D-17. |

**Installation:** No new packages. reprepro is installed in CI (`sudo apt-get install -y reprepro`, workflow line ~302) and present on Lima VMs. gpg/curl/coreutils are baseline.

## Package Legitimacy Audit

**N/A — this phase installs no external packages.** All tooling (reprepro, gpg, curl, sha256sum, awk/sed/grep) is either a distro-packaged binary already used by the existing pipeline or coreutils. No npm/PyPI/crates dependency is added. slopcheck not applicable.

## Architecture Patterns

### System Architecture Diagram

```
CI publish job (build-packages.yml)
        │  inputs: build_track (stable|edge|nightly)  + [Phase 21 adds] distro (2404|2604)
        ▼
ci_publish.sh  <track> <distro> <deb-dir> <repo-url> <output-dir>
        │
        ├─(1) compute target suite = "<track>-<distro>"  +  alias = "<track>" (only if distro==2404)
        │
        ├─(2) MIRROR DOWN: for each of the 9 suites NOT being published,
        │       curl dists/<suite>/main/binary-<arch>/Packages  → parse Filename: → curl each .deb
        │       (generalizes existing 2-other-suite loop to N untouched suites)
        │
        ├─(3) BUILD TARGET: repo_manage.sh includedeb fresh debs → "<track>-<distro>"
        │       └─ if distro==2404: ALSO includedeb same fresh debs → bare "<track>" alias  (D-12)
        │
        ├─(4) RE-INCLUDE mirrored debs into their respective untouched suites
        │       reprepro export <suite>   (per-suite export, avoids clobbering target — existing pattern)
        │
        ├─(5) BY-HASH POST-PROCESS (new):  for each of 9 dists/<suite>/:
        │       parse Release SHA256/SHA512 sections
        │       cp each index → <index-dir>/by-hash/<ALGO>/<hash>
        │       cp Release    → dists/<suite>/by-hash/<ALGO>/<hash>
        │       inject "Acquire-By-Hash: yes" into Release
        │       re-sign: gpg --clearsign → InRelease ;  gpg -abs → Release.gpg
        │
        ├─(6) index.html: loop over 9 suites, skip empty (D-18)
        │
        └─(7) upload-pages-artifact → deploy-pages   (atomic Pages deploy)
                 │
                 ▼
        GitHub Pages CDN  ──serves──>  apt clients
              ├─ bare stable/edge/nightly  (24.04 packages, Suite: stable → no prompt)
              ├─ stable-2404 / edge-2404 / nightly-2404
              └─ stable-2604 / edge-2604 / nightly-2604  (empty-but-signed until Phase 21)
```

### Recommended Project Structure (files touched)
```
packaging/repo/conf/distributions   # 3 stanzas → 9 stanzas (6 versioned + 3 alias)
config.sh                           # suite whitelist array / valid-distro set (Claude's discretion)
scripts/repo_manage.sh              # suite whitelist (line 56), optional track+distro CLI, by-hash call site
scripts/ci_publish.sh              # ALL_SUITES (line 91), mirror loop → N suites, alias feeding, by-hash, index.html loop
scripts/repo_byhash.sh             # NEW (or functions.sh helper) — by-hash materialize + re-sign  [discretion]
.github/workflows/build-packages.yml# publish job arg plumbing (track+distro); matrix fan-out is Phase 21
tests/test_*.sh                     # NEW — suite-routing / distributions-parse unit tests (Wave 0)
```

### Pattern 1: Nine-stanza `conf/distributions` (Codename = Suite, SignWith: yes)
**What:** Each of the 9 distributions is a full stanza. Aliases carry `Suite: stable` (bare), versioned carry `Suite: stable-2404`. Description on aliases gets the D-04 deprecation note.
**When to use:** REPO-06 + REPO-07 foundation.
**Example:**
```
# ---- legacy alias (DEPRECATED) ----
Origin: podman-ubuntu
Label: Podman Ubuntu
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: DEPRECATED alias for stable-2404 (Ubuntu 24.04) — see migration docs
SignWith: yes

# ---- versioned ----
Origin: podman-ubuntu
Label: Podman Ubuntu
Suite: stable-2404
Codename: stable-2404
Architectures: amd64 arm64
Components: main
Description: Podman compiled from source for Ubuntu 24.04 - stable releases
SignWith: yes
# ... repeat edge/nightly × {bare, -2404, -2604}  (9 total)
```
Note: `SignWith: yes` uses gpg's default key — fine here because exactly one key is imported in the CI env (single-GPG-key criterion). [CITED: reprepro manpage — "yes/default uses the default key of gpg"]

### Pattern 2: Post-export Acquire-By-Hash (bolt-on, per suite)
**What:** reprepro has no by-hash support, so after `export` you mirror each index into a hash-named path and flag the Release.
**When to use:** REPO-08, once per publish (D-09).
**Layout (VERIFIED Debian wiki + arnaudr.io):** by-hash dirs sit **adjacent to each index**, not at dists root:
```
dists/<suite>/main/binary-amd64/Packages
dists/<suite>/main/binary-amd64/Packages.gz
dists/<suite>/main/binary-amd64/by-hash/SHA256/<sha256-of-Packages>
dists/<suite>/main/binary-amd64/by-hash/SHA256/<sha256-of-Packages.gz>
dists/<suite>/by-hash/SHA256/<sha256-of-Release>      # Release itself is also by-hash-able
```
Provide by-hash for **at least the strongest hash** the Release lists (SHA256 today; SHA512 too if reprepro emits it) [VERIFIED: Debian wiki — "must provide by-hash with the strongest hashsum ... should provide for all"].

### Anti-Patterns to Avoid
- **`cp -r dists/stable-2404 dists/stable`:** copied Release says `Suite: stable-2404` → triggers apt "Suite value changed" prompt for every legacy user. Use a real reprepro distribution instead (D-01/D-02).
- **Symlinking the alias dir:** GitHub Pages artifact may drop symlinks; symlink target's Release still has the wrong Suite. (D-17)
- **Injecting `Acquire-By-Hash: yes` and skipping re-sign:** the existing `InRelease`/`Release.gpg` cover the pre-edit bytes; apt rejects the signature. Always re-sign (D-08).
- **`reprepro export` with no args after partial includes:** the existing code already learned to `export <suite>` selectively (line 203) — re-exporting all from a fresh db would wipe the target suite's Packages. Keep per-suite export.
- **Computing by-hash before injecting `Acquire-By-Hash`:** order is includedeb → export → by-hash copy of *current* index → inject field into Release → re-sign. The Release hash list must already match the on-disk indexes (reprepro guarantees this at export); the by-hash copies are byte-identical to the canonical files.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multi-suite repo metadata (Packages, Release, hashes) | Custom Packages/Release generator | reprepro `export` | Correct compression variants, checksum sections, pool dedup — already proven |
| Release signing | Manual openssl/sign script | gpg `--clearsign` (InRelease) + `-abs` (Release.gpg) | Matches apt-secure expectations; existing key-import path |
| Alias suite content sync | Directory copy / rsync of dists | reprepro real distribution + `includedeb` into the alias | Keeps correct `Suite:` field; shared pool dedup (D-05) |
| Suite Release checksum list | Hand-compute and edit | reprepro emits SHA256/SHA512 sections in Release; parse them to drive by-hash | Avoids drift between Release hash list and actual files |

**Key insight:** The ONLY thing reprepro can't do here is Acquire-By-Hash. Everything else (signing, indexes, pool, empty-but-signed suites) is reprepro's job — the bash bolt-on should be the smallest possible wrapper around `cp` + `gpg`, reading reprepro's own Release output to know what to hash.

## Runtime State Inventory

> This phase restructures suite names — apt clients hold cached release metadata keyed by suite/Suite field. Inventory below.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | apt client-side: each client caches the last-seen `Suite`/`Codename`/`Date` per configured source in `/var/lib/apt/lists/`. Existing users on bare `stable` recorded `Suite: stable`. The alias suites keep `Suite: stable` → **no cached-value mismatch** by construction (D-02). Server-side: reprepro `db/` is ephemeral (rebuilt each publish, deleted post-export — `repo_manage.sh:180`), so no stored suite-name state survives a publish. | None — verified the alias mechanism preserves the cached Suite value. The whole point of D-01. |
| Live service config | GitHub Pages serves the static `dists/` tree; no live DB. The repo is reassembled and atomically redeployed each publish (D-10/D-16). No out-of-git service config holds suite names. | None — repo state is fully reconstructed from `conf/distributions` + mirrored debs each run. |
| OS-registered state | None — no scheduled tasks/units embed suite names on the server. Client-side `/etc/apt/sources.list.d/*.list|.sources` files reference suite names, but per REPO-07 those MUST NOT need editing; the alias serves them. | None on the build side. Client `.sources` are intentionally left untouched (the requirement). |
| Secrets/env vars | `GPG_PRIVATE_KEY` (CI secret) — unchanged; same key signs all 9 suites and re-signs after by-hash injection (D-08). `REPO_URL` derived from `github.repository_owner`/repo name — unchanged. No secret renamed. | None — key reused as-is for re-signing. |
| Build artifacts | reprepro `pool/` is shared and deduped (D-05); `.deb` filenames carry Phase 19's `~ubuntu{24.04,26.04}.podman1` suffix so 24.04 and 26.04 debs coexist distinctly in pool. Old single-suite live repo (`stable`/`edge`/`nightly` only) becomes the alias suites on first Phase 20 deploy; mirror-down reads the OLD bare-suite Packages indexes on the first run. | Verify first-deploy mirror-down handles the transition: on the first 9-suite publish, only bare `stable/edge/nightly` exist live; the `-2404`/`-2604` Packages URLs 404. Existing mirror loop already tolerates 404 (`curl -sfL ... || true`, treats empty as "first deploy") — confirm this still holds for the new suite set. |

**The canonical question — after every file is updated, what runtime systems still have the old string cached?** apt clients cache `Suite: stable`. The alias suite serves `Suite: stable` (not `stable-2404`), so the cached value matches and no re-acceptance is needed. This is the entire architectural reason for D-01.

## Common Pitfalls

### Pitfall 1: apt "changed its 'Suite' value" prompt breaks every legacy user
**What goes wrong:** A client that recorded `Suite: stable` gets a Release whose `Suite:` now reads `stable-2404` → `apt update` errors: `E: Repository '... stable InRelease' changed its 'Suite' value from 'stable' to 'stable-2404'; This must be accepted explicitly before updates ... can be applied`. Non-interactive clients (CI, unattended-upgrades) **fail hard**; the only fix is the user running `apt-get --allow-releaseinfo-change update` — i.e., a client-side change, violating REPO-07.
**Why it happens:** apt compares the served Release `Suite`/`Codename`/`Label`/`Origin` against the cached values per source and refuses silent changes (apt-secure release-info-change protection).
**How to avoid:** Serve the bare alias as a real reprepro distribution with `Suite: stable` / `Codename: stable` (D-01/D-03). Never derive the alias via a copy that embeds `stable-2404`.
**Warning signs:** Any approach where the alias Release file's `Suite:` is not exactly the bare track name.
[VERIFIED: forum.proxmox.com thread 94726, claudiokuenzler.com blog 1101, Debian bug #929248]

### Pitfall 2: Forgetting to re-sign after `Acquire-By-Hash` injection
**What goes wrong:** You append `Acquire-By-Hash: yes` to `Release` but leave the reprepro-generated `InRelease`/`Release.gpg` in place. They sign the pre-edit bytes; apt reports `GPG error ... BADSIG` or signature/Release mismatch and refuses the repo.
**Why it happens:** `InRelease` is an inline-signed copy of `Release`; `Release.gpg` is a detached sig over `Release`. Editing `Release` invalidates both.
**How to avoid:** After injection, regenerate both: `gpg --clearsign -o InRelease Release` and `gpg -abs -o Release.gpg Release`. The key is already imported (`GPG_PRIVATE_KEY` block). Do the injection BEFORE computing the by-hash copy of `Release` itself, so the hashed Release also carries the field (or copy Release to by-hash after injection — keep them byte-identical).
**Warning signs:** apt `update` succeeds against a freshly-built local export but fails after the by-hash step.

### Pitfall 3: by-hash placed at the wrong directory level
**What goes wrong:** Putting `by-hash/` only at `dists/<suite>/by-hash/...` (and not next to each `binary-<arch>/Packages`) means apt's fetch of `main/binary-amd64/by-hash/SHA256/<hash>` 404s.
**Why it happens:** The spec places by-hash **adjacent to each index file**, with a separate by-hash dir per index directory; the Release-level by-hash is additional, not a substitute.
**How to avoid:** For every file with a checksum entry in `Release` (all `main/binary-*/Packages*`, `Contents-*` if any), write `<dirname-of-file>/by-hash/<ALGO>/<hash>`. Also write the Release-level one for `Release` itself.
**Warning signs:** apt hash-sum-mismatch persists, or by-hash fetches 404 in apt `-o Debug::Acquire::http=true` output.
[VERIFIED: Debian wiki DebianRepository/Format — "main/binary-i386/Packages must be also available at main/binary-i386/by-hash/..."]

### Pitfall 4: `reprepro export` (no args) clobbering the target suite
**What goes wrong:** Running a bare `reprepro export` after only the *other* suites are in the current db re-emits empty indexes for the target suite, wiping its freshly-included Packages.
**Why it happens:** export regenerates indexes for all distributions known to the current (fresh) db.
**How to avoid:** Per-suite `reprepro export <suite>` as the existing code already does (`ci_publish.sh:203`). Preserve this discipline across all 9 suites + aliases.
**Warning signs:** Target suite Packages is empty in the assembled artifact despite a successful includedeb.

### Pitfall 5: by-hash retention vs rebuild-the-world
**What goes wrong:** The spec recommends keeping ≥2 previous versions of each index in by-hash for the race-free grace period. The rebuild-the-world model (D-10) produces a fresh dists tree each publish with only the current hash.
**Why it's acceptable here:** D-09 locks single-generation as sufficient because (a) the whole tree deploys atomically via Pages, and (b) apt **falls back to the canonical filename on a by-hash miss**. The Acquire-By-Hash benefit on a CDN is avoiding mismatch *within a single consistent snapshot*, which atomic deploy + matching by-hash provides. Do not over-engineer multi-generation retention.
**Warning signs:** None expected; documented so the planner doesn't add retention complexity.

## Code Examples

### Nine-suite whitelist + track/distro → suite routing
```bash
# config.sh (Claude's discretion on location) — explicit array, follows existing patterns
VALID_TRACKS=(stable edge nightly)
VALID_DISTROS=(2404 2604)
# 9 distributions reprepro knows about:
ALL_SUITES=(stable edge nightly \
            stable-2404 edge-2404 nightly-2404 \
            stable-2604 edge-2604 nightly-2604)

# routing: given TRACK + DISTRO → target suite (+ alias for 24.04)
target_suite="${TRACK}-${DISTRO}"
publish_targets=("${target_suite}")
if [[ "${DISTRO}" == "2404" ]]; then
    publish_targets+=("${TRACK}")   # D-12: feed bare alias from same fresh debs
fi
```

### Acquire-By-Hash post-export step (per suite)
```bash
# Source: derived from Debian wiki DebianRepository/Format + arnaudr.io 2025
# Run AFTER reprepro export <suite>, per suite, in the output dir.
add_byhash_and_resign() {
    local lsuite="$1" lrepo="$2"          # repo = OUTPUT_DIR
    local ldist="${lrepo}/dists/${lsuite}"
    local lrelease="${ldist}/Release"

    [[ -f "${lrelease}" ]] || return 0    # empty-but-... still has a Release

    # 1) by-hash for every checksummed index (strongest algo: SHA256, +SHA512 if present)
    for algo in SHA256 SHA512; do
        # reprepro Release lists files under a "<Algo>:" section: "<hash> <size> <relpath>"
        awk -v a="${algo}:" '$0==a{f=1;next} /^[A-Za-z0-9-]+:/{f=0} f{print $1, $3}' "${lrelease}" \
        | while read -r hash relpath; do
            local src="${ldist}/${relpath}"
            [[ -f "${src}" ]] || continue
            local bhdir
            bhdir="$(dirname "${src}")/by-hash/${algo}"
            mkdir -p "${bhdir}"
            cp -f "${src}" "${bhdir}/${hash}"
        done
    done

    # 2) inject Acquire-By-Hash (idempotent)
    grep -q '^Acquire-By-Hash:' "${lrelease}" \
        || sed -i '/^Suite:/a Acquire-By-Hash: yes' "${lrelease}"

    # 3) by-hash for the Release file itself (after injection, so hashes match)
    for algo in SHA256 SHA512; do
        local cmd="${algo,,}sum"
        command -v "${cmd}" >/dev/null || continue
        local rh; rh="$(${cmd} "${lrelease}" | awk '{print $1}')"
        mkdir -p "${ldist}/by-hash/${algo}"
        cp -f "${lrelease}" "${ldist}/by-hash/${algo}/${rh}"
    done

    # 4) re-sign (key already imported via GPG_PRIVATE_KEY block)
    rm -f "${ldist}/InRelease" "${ldist}/Release.gpg"
    gpg --batch --yes --clearsign -o "${ldist}/InRelease" "${lrelease}"
    gpg --batch --yes -abs       -o "${ldist}/Release.gpg" "${lrelease}"
}
```
*Note for planner: verify the exact `Release` section header names reprepro emits (`SHA256:` / `SHA512:` / `MD5Sum:`) on a real export — the awk parser depends on them. Confirm whether reprepro emits SHA512 by default for this repo; if only SHA256 is listed, provide by-hash for SHA256 only (strongest-available rule).*

### Legacy-client validation on ubuntu-24 Lima VM (D-15)
```bash
# Source: CLAUDE.md Lima patterns + apt release-info-change docs
limactl shell ubuntu-24 -- bash -c 'cd /opt/podman-debian && \
  echo "deb [signed-by=/usr/share/keyrings/podman-ubuntu.gpg] <REPO_URL> stable main" \
    | sudo tee /etc/apt/sources.list.d/podman-legacy.list && \
  sudo apt-get update 2>&1 | tee /tmp/legacy-update.log && \
  ! grep -q "changed its .Suite. value" /tmp/legacy-update.log && \
  apt-cache policy podman 2>&1 | grep -q "~ubuntu24.04.podman1"'
# Assert: exit 0, no "Suite value changed", 24.04-suffixed package resolves.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 3 bare suites (`stable`/`edge`/`nightly`) = 24.04-only | 6 versioned + 3 alias suites, one URL, one key | This phase | Enables per-distro suites without breaking existing users |
| No Acquire-By-Hash | `Acquire-By-Hash: yes` + by-hash dirs on every suite | This phase | Eliminates GitHub Pages CDN hash-sum-mismatch races |
| reprepro native by-hash | Still unsupported in reprepro (bug #820660, halted 2019, new upstream merging patches but not this feature as of 2025) | — | Post-export bash bolt-on remains the correct strategy [VERIFIED] |

**Deprecated/outdated:**
- Bare `stable`/`edge`/`nightly` as the *primary* addressing — now legacy aliases pending REPO-09 removal (do NOT remove this phase).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | reprepro emits both `SHA256:` and `SHA512:` sections in Release for this repo's config | Code Examples (by-hash parser) | Low — parser already guards with `[[ -f ... ]]`/`command -v`; if only SHA256 is emitted, just produce SHA256 by-hash (strongest-available rule still satisfied). Planner should confirm on a real export. |
| A2 | `sed '/^Suite:/a Acquire-By-Hash: yes'` placement is accepted by apt anywhere in the Release header before the checksum sections | Pattern 2 / Code Examples | Low — apt parses Release as a deb822 stanza; field order is not significant. Verified behavior expectation, not tested against this exact file. |
| A3 | The first-deploy mirror loop tolerates the new `-2404`/`-2604` Packages URLs 404ing (only bare suites exist live initially) | Runtime State Inventory (Build artifacts) | Medium — existing loop treats empty/`curl` failure as "first deploy" (`ci_publish.sh:123-128`); planner must confirm the generalized N-suite loop preserves this. |

## Open Questions

1. **Does reprepro list SHA512 in Release for this repo?**
   - What we know: reprepro lists MD5Sum/SHA1/SHA256 by default; SHA512 depends on version/config.
   - What's unclear: exact algorithms in *this* repo's generated Release.
   - Recommendation: planner adds a one-time check (`grep -E '^(MD5Sum|SHA1|SHA256|SHA512):' dists/<suite>/Release`) in an early task or Wave-0 test; the by-hash helper already iterates `for algo in SHA256 SHA512` defensively.

2. **Single `repo_manage.sh` invocation per publish-target vs one call feeding both target+alias?**
   - What we know: Claude's discretion (CONTEXT) — includedeb twice vs one call with two suites.
   - Recommendation: simplest is to loop `publish_targets` (target + optional alias) feeding the *same* `DEB_DIR` to includedeb in each, sharing one db/export pass; matches the existing includedeb loop shape.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| reprepro | Repo build/export | ✓ (CI installs; Lima VMs have it after apt) | distro-packaged | — |
| gpg | Signing / re-signing | ✓ | system | — |
| curl | Mirror-down other suites | ✓ | system | — |
| sha256sum / sha512sum | by-hash filenames | ✓ | coreutils | SHA256 only if sha512sum absent (won't happen on Ubuntu) |
| ubuntu-24 Lima VM | D-15 legacy-client validation | ✓ | 24.04 | CI container with apt as secondary |
| GitHub Pages | Atomic deploy + live serve | ✓ | — | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** None blocking — dev host is macOS (no dpkg/apt/reprepro), so by-hash + legacy-client verification MUST run on the Lima VM / CI, not locally (`bash -n` for syntax only on macOS, per CLAUDE.md).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash unit tests, run directly: `bash tests/<test>.sh` (project convention, no harness) [CITED: CLAUDE.md, docs/TESTING.md] |
| Config file | none — plain bash scripts in `tests/` |
| Quick run command | `bash tests/test_<name>.sh` (single file) |
| Full suite command | `for t in tests/*.sh; do bash "$t" || exit 1; done` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REPO-06 | `conf/distributions` declares 9 stanzas; each unique Suite/Codename; each has SignWith | unit (parse) | `bash tests/test_distributions_suites.sh` | ❌ Wave 0 |
| REPO-06 | track+distro → correct `<track>-<distro>` suite; whitelist rejects bad track/distro | unit (pure function) | `bash tests/test_suite_routing.sh` | ❌ Wave 0 |
| REPO-07 | 24.04 publish targets include bare alias; 26.04 publish does not | unit (routing function) | `bash tests/test_alias_routing.sh` | ❌ Wave 0 |
| REPO-07 | Legacy `.sources` on bare `stable` → no "Suite value changed", 24.04 deb resolves | integration (VM) | ubuntu-24 Lima `apt update`+`apt-cache policy` (D-15 snippet) | ❌ Wave 0 (manual/VM) |
| REPO-08 | Every suite Release has `Acquire-By-Hash: yes`; by-hash dir exists adjacent to each index; InRelease/Release.gpg verify after injection | integration (VM/CI on assembled artifact) | `gpg --verify InRelease` + path-exists asserts on a real export | ❌ Wave 0 (VM/CI) |
| REPO-08 | by-hash parser extracts correct (hash, relpath) from a sample reprepro Release | unit (parse fixture) | `bash tests/test_byhash_parse.sh` | ❌ Wave 0 |
| Crit. 4 | Publishing one suite leaves the other 8 suites' Packages intact (mirror-then-include) | integration (CI/VM) | assemble repo with 2 suites, publish 1, diff the other's Packages | ❌ Wave 0 (VM/CI) |

### Sampling Rate
- **Per task commit:** `bash -n <touched script>` (macOS-safe) + relevant `bash tests/test_*.sh` unit test.
- **Per wave merge:** full `tests/*.sh` run + (if reachable) Lima-VM assemble-and-`apt update` smoke.
- **Phase gate:** Full assembled-repo verification on ubuntu-24 Lima VM (D-15 legacy-client + by-hash signature verify) green before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `tests/test_distributions_suites.sh` — parses `conf/distributions`, asserts 9 stanzas, unique Suite==Codename, SignWith present (REPO-06)
- [ ] `tests/test_suite_routing.sh` — pure routing function track+distro→suite + whitelist rejection (REPO-06/07)
- [ ] `tests/test_alias_routing.sh` — 24.04 includes bare alias, 26.04 does not (REPO-07/D-12)
- [ ] `tests/test_byhash_parse.sh` — by-hash Release-section parser against a literal fixture (REPO-08)
- [ ] VM/CI integration harness — assemble repo → inject by-hash → `gpg --verify InRelease` → `apt update` on ubuntu-24 (REPO-07/08, Crit. 4). macOS cannot run this; runs on Lima/CI.
- [ ] Routing logic should be extracted into a sourceable function (in config.sh or functions.sh) so unit tests can call it without a full publish — mirrors Phase 19's `detect_runtime_depends`/`verify_versions.sh` CI-runnable-pure-function pattern.

## Security Domain

> `security_enforcement` not present in config.json (treat as enabled). This phase's security surface is repository signing integrity — the core trust anchor for every apt client.

### Applicable controls

| Concern | Applies | Standard Control |
|---------|---------|------------------|
| Release signature integrity (apt-secure) | yes | Re-sign `Release` after by-hash mutation with the same key (D-08); never serve a Release whose InRelease/Release.gpg cover stale bytes |
| Single trust anchor (one GPG key, all suites) | yes | All 9 stanzas `SignWith: yes` → gpg default key; exactly one key imported in CI env (REPO-06 "one GPG key") |
| Key handling in CI | yes | `GPG_PRIVATE_KEY` secret, imported via existing base64/armored path + ownertrust; never logged [CITED: repo_manage.sh:83-112] |
| By-hash content integrity | yes | by-hash files are byte-identical copies of canonical indexes whose hashes are signed in Release → no new trust surface; apt verifies the fetched-by-hash file against the signed Release hash |
| Tampering of static CDN content | Mitigated by signing | apt verifies InRelease signature + per-index hashes; GitHub Pages compromise still caught by the offline-held private key not being on Pages |

### Threat patterns

| Pattern | STRIDE | Mitigation |
|---------|--------|------------|
| Serve Release with `Acquire-By-Hash` added but stale signature | Tampering / Spoofing | Mandatory re-sign step (Pitfall 2); CI `gpg --verify` gate before deploy |
| Hash-sum mismatch race on CDN mid-deploy | DoS (failed updates) | Acquire-By-Hash + atomic Pages deploy (the requirement itself) |
| Wrong Suite field causing client to disable repo / accept attacker re-acceptance prompt social-engineering | Spoofing | Alias real-suite design keeps `Suite: stable`, no re-acceptance prompt (Pitfall 1) |

## Sources

### Primary (HIGH confidence)
- Debian Wiki — DebianRepository/Format (https://wiki.debian.org/DebianRepository/Format) — Acquire-By-Hash field, by-hash adjacent-to-index layout, strongest-hash rule, Suite/Codename definitions
- reprepro(1) manpage, Debian testing (https://manpages.debian.org/testing/reprepro/reprepro.1.en.html) — `export [codenames]` selective export, `SignWith` semantics, no by-hash option, hash-related options
- Debian bug #820660 (via arnaudr.io) — reprepro lacks server-side Acquire-By-Hash
- forum.proxmox.com thread 94726 + claudiokuenzler.com blog 1101 + Debian bug #929248 — apt "changed its 'Suite' value" trigger and `--allow-releaseinfo-change` remedy
- Project code: `scripts/repo_manage.sh`, `scripts/ci_publish.sh`, `packaging/repo/conf/distributions`, `.github/workflows/build-packages.yml`, `config.sh`, `CLAUDE.md`

### Secondary (MEDIUM confidence)
- arnaudr.io 2025-07-17 "Acquire-By-Hash ... lack of it in Kali Linux" — by-hash path example, reprepro status, by-hash grace-period retention note
- Ubuntu Wiki AptByHash, Colin Watson "No more Hash Sum Mismatch errors" — by-hash purpose/mechanism

### Tertiary (LOW confidence)
- None relied upon for load-bearing claims.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — reprepro/gpg/curl already in the proven pipeline; no new packages.
- Architecture (9-suite + alias + routing): HIGH — directly grounded in existing code + locked CONTEXT decisions + verified apt Suite-change behavior.
- Acquire-By-Hash layout/spec: HIGH — verified against Debian wiki format spec; only the exact reprepro Release hash-algorithm set (A1) needs a one-line confirmation on a real export.
- Pitfalls: HIGH — apt Suite-change and re-sign requirements verified from multiple authoritative sources.

**Research date:** 2026-06-06
**Valid until:** 2026-07-06 (stable spec; reprepro by-hash status worth a re-check if a new reprepro release ships before implementation)
