# Pitfalls Research

**Domain:** Multi-distro from-source APT packaging (nFPM + reprepro + GitHub Pages + GitHub Actions) — adding Ubuntu 26.04 alongside existing Ubuntu 24.04 support
**Researched:** 2026-06-05
**Confidence:** HIGH (reprepro shared-pool behavior, the t64 transition, and runner-image deprecation are all verified against official/upstream sources; the two highest-risk traps are confirmed by real-world precedents — Docker's containerd.io jammy-vs-noble checksum collision is this project's exact situation)

> Scope: pitfalls specific to adding a *second* Ubuntu version to *this* stack (v3.0 milestone). The v2.0 code makes single-distro assumptions that become bugs the instant a second distro is introduced. Line references are to the files as they exist today (pre-26.04).

## Critical Pitfalls

### Pitfall 1: reprepro shared-pool checksum collision (same name+version, different contents)

**What goes wrong:**
reprepro stores all binaries from all suites in **one shared `pool/`**, keyed by `name_version_arch.deb`. The 24.04-built `podman-crun_1.21.0~podman1_amd64.deb` and the 26.04-built `podman-crun_1.21.0~podman1_amd64.deb` have the **same filename and version but different binary contents** (different glibc, different linked sonames). reprepro refuses the second with `File 'pool/.../podman-crun_..._amd64.deb' is already registered with different checksums!` and the publish dies — or silently keeps the first so one distro ends up serving the other distro's binary.

Not hypothetical: Docker hit exactly this with `containerd.io_1.7.19-1_amd64.deb` differing between `jammy` and `noble` ([moby#48306](https://github.com/moby/moby/issues/48306)). The reprepro maintainer states two binaries with the same name+version sharing one pool is fundamentally unsupported and refuses a bypass flag ([Debian #477708](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=477708)).

**Why it happens:**
`scripts/package_all.sh:27` hardcodes `VERSION_SUFFIX="~podman1"` with **no per-distro component**. The upstream version is identical on both distros, so the version strings are byte-identical. The single-distro design never had two differing artifacts competing for one pool slot.

**How to avoid:**
Add a per-distro version suffix so the two builds never share a pool slot, e.g. `~podman1~ubuntu24.04` / `~podman1~ubuntu26.04`. Use the `~` form so APT ordering stays sane and an official package still upgrades over ours. Verify with `dpkg --compare-versions`. (Do not use a bare `+distro` that could outrank a future real upstream revision — prefer `~ubuntuXX.YY`.)

**Warning signs:**
`reprepro ... includedeb` exits non-zero with "already registered with different checksums"; `apt-get update` on 24.04 pulls a package whose `ldd` references a soname absent on 24.04; two suites' `Packages` list the same `Filename:` pointing at one pool path.

**Phase to address:**
Per-distro versioning/packaging phase — the keystone. Suites, pool layout, and publish all depend on distinct version strings existing first.

---

### Pitfall 2: `ci_publish.sh` re-import-by-basename clobbers cross-distro artifacts

**What goes wrong:**
`scripts/ci_publish.sh` builds the current suite from fresh `.deb`s, then **downloads the other suites' `.deb`s from the live GitHub Pages repo** (lines 113-156) by parsing `Filename:` and re-adding with `reprepro includedeb` (line 194). With two distros, "the live repo" now contains both distros' packages. The download dedups on `deb_basename` (line 137) — so if 24.04 and 26.04 ever produce the same basename (the Pitfall 1 condition), one silently overwrites the other in the temp dir before reprepro sees it. Even with distinct basenames, the re-import has no per-distro routing: a 26.04 publish pulls down and re-registers 24.04 packages and vice-versa, and `ALL_SUITES=(stable edge nightly)` (line 91) plus a single `conf/distributions` no longer model the 6-suite reality.

**Why it happens:**
The "import other suites from the live repo so we don't clobber them" pattern was correct for 3 suites of *one* distro sharing one pool. Doubling distros quadruples suites (stable/edge/nightly × 2404/2604).

**How to avoid:**
Decide the topology explicitly:
- **One repo, 6 suites** (`stable-2404`…`nightly-2604`) with per-distro version suffixes (P1) so the shared pool is collision-free; rewrite `ALL_SUITES`/`OTHER_SUITES` to enumerate all 6 and route each downloaded `.deb` to its correct suite by which suite's `Packages` it came from.
- **Two separate repos** (separate `conf/distributions`, separate pools, served under `/2404` and `/2604`) — simplest isolation, no shared-pool risk, but two apt lines for users and double the Pages artifact.
Either way, the re-import must key on `(suite, filename, arch)` and never dedup across distros by basename alone.

**Warning signs:**
A publish "succeeds" but a suite's package count drops; `dumpunreferenced` shows orphans; a 2604 suite's `Packages` lists a `Filename:` under a pool path whose `.deb` was built on 24.04.

**Phase to address:**
Repository-topology / publish phase. Must follow the versioning decision (P1).

---

### Pitfall 3: Hardcoded library dependency names broken by t64 transition and soname bumps

**What goes wrong:**
nFPM configs hardcode runtime library package names: `podman.yaml` declares `libgpgme11`, `libseccomp2`; `crun.yaml` declares `libseccomp2`, `libsystemd0`, `libcap2`. Ubuntu's **64-bit `time_t` transition** renamed ~495 library packages with a `t64` suffix starting in 24.04 noble (e.g. `libglib2.0-0` → `libglib2.0-0t64`, and **`libgpgme11` → `libgpgme11t64`** — verified on packages.ubuntu.com/noble). A declared dependency whose name no longer exists fails install with "Depends: X but it is not installable." Separately, soname bumps move the correct package name between releases (the project already handles one: crun's parser, `libjson-c.so.5`→`libjson-c5` vs `libyajl.so.2`→`libyajl2`). The user already confirmed 26.04 install failures from exactly this class.

**Why it happens:**
Single-distro builds let you pin one correct name per library. These names are version-specific Ubuntu packaging artifacts, not stable identities. `libgpgme11` in `podman.yaml` likely already resolves on 24.04 only via a transitional/virtual `Provides:` and will break outright on 26.04.

**How to avoid:**
Stop hardcoding library *package* names. The project already has the right pattern in `package_all.sh::detect_crun_parser_depend()` (lines 199-219): run `ldd` on the built binary and map the *soname* to its package. Generalize it: for every linked library, resolve the providing package **on the native build host** via `dpkg -S "$(ldd binary | ...)"` (builds run natively on each distro's runner). This makes deps self-correcting per distro — the 26.04 build emits whatever 26.04 ships, the 24.04 build emits the 24.04 name. A manual per-distro override map is a fragile fallback only. Add a CI lint that fails the build if any declared `depends` package is absent from the build host's `apt-cache`.

**Warning signs:**
`apt-get install podman-suite` reports "Depends: libgpgme11 but it is not installable"; `apt-cache policy libgpgme11` returns nothing on 26.04; a built `.deb`'s `Depends:` references a package not in `apt-cache pkgnames`.

**Phase to address:**
Per-distro versioning/packaging phase (same phase as P1). Add native-host dependency resolution to `package_all.sh`.

---

### Pitfall 4: Suite rename breaks every existing user's `.sources` / `.list`

**What goes wrong:**
Existing users have `deb [signed-by=...] https://slazarov.github.io/podman-ubuntu stable main` (current `index.html` instructs exactly this). v3.0 renames suites to `stable-2404`/`stable-2604`. The moment the old `stable`/`edge`/`nightly` codenames stop being exported, every existing install gets `E: The repository '... stable Release' does not have a Release file` or a 404 on `apt update`, silently freezing them on their last-installed version. Worst kind of breakage: invisible until the user runs `apt update`, and confusing because nothing in their config changed.

**Why it happens:**
v2.0's "Codename = Suite name to avoid createsymlinks complexity" (PROJECT.md notes this needs revisiting) hardcoded bare names into the repo, `index.html`, and docs. No alias layer.

**How to avoid:**
Migration path, not hard cutover, best-first:
1. Keep exporting old `stable`/`edge`/`nightly` codenames as **aliases** for the 24.04 suites for a deprecation window (reprepro `Suite:` differing from `Codename:`, or `AlsoAcceptFor:`), so existing 24.04 users keep working untouched.
2. Ship a one-line migration command in the new `index.html` + release note (`apt modernize-sources` on recent releases, then an explicit suite swap).
3. Announce the window on the landing page; retire old names only after it elapses.
Also: `index.html`/setup snippet emit bare `stable` today — regenerate them to emit the distro-specific suite.

**Warning signs:**
Post-deploy 404s for `dists/stable/InRelease` in Pages access logs; user reports of "does not have a Release file"; the old `.sources` `Suites:` no longer matches any exported `dists/` dir.

**Phase to address:**
Migration/compatibility phase (suite aliases) + docs phase (regenerate `index.html`/snippet). Alias decision goes with the topology decision (P2).

---

### Pitfall 5: 26.04-built binaries leaking into the 24.04 suite (forward-compat trap)

**What goes wrong:**
PROJECT.md confirms 24.04-built binaries run on 26.04 (older glibc, forward-compatible) but **26.04-built binaries do NOT run on 24.04** (newer glibc symbols → `version 'GLIBC_2.XX' not found`). In a 4-leg matrix (2 distros × 2 arches) feeding one `publish` job, it is trivial to drop a 26.04 `.deb` into a 24.04 suite — especially because the current `publish` does `download-artifact ... pattern: debs-* ... merge-multiple: true` (workflow lines 294-298), flattening **all** artifacts into one `all-debs/` with no distro tag. Add a 26.04 leg and that merge silently mixes distros. The package may install fine but crashes at runtime on the older distro.

**Why it happens:**
Artifact names are `debs-amd64`/`debs-arm64` — arch-tagged but **not distro-tagged**. `merge-multiple: true` is correct for 2 arches of one distro; it becomes a footgun the instant a second distro produces artifacts that get flattened together.

**How to avoid:**
Tag artifacts by distro AND arch: `debs-2404-amd64`, `debs-2604-arm64`, etc. In `publish`, download into **per-distro directories** and feed each distro's `.deb`s only into that distro's suites — never a single flat `all-debs/`. Per-distro version suffixes (P1) are a second safety net: a misrouted `~ubuntu26.04` package in a 2404 suite is caught by a CI assertion that every `.deb` in `*-2404` carries `~ubuntu24.04`. Add a smoke test: install the 24.04 suite's packages in a real 24.04 container and run `podman info`.

**Warning signs:**
`podman: /lib/.../libc.so.6: version 'GLIBC_2.XX' not found` on 24.04; a `.deb` in a `*-2404` suite whose suffix says `ubuntu26.04`; matrix legs uploading artifacts with colliding names.

**Phase to address:**
CI matrix phase (artifact naming + per-distro download routing) + verification/smoke-test phase (install-and-run on each target distro in a container).

---

### Pitfall 6: GitHub runner image deprecation timing (oldest GA label removed)

**What goes wrong:**
GitHub keeps **at most 2 GA images + 1 beta** per OS family and begins deprecating the *oldest* GA label once a newer one goes GA ([runners reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)). `ubuntu-26.04`/`ubuntu-26.04-arm` were added around the April 2026 release ([runner-images#13964](https://github.com/actions/runner-images/issues/13964)); when a future Ubuntu (e.g. 28.04) goes GA, the **`ubuntu-24.04` label will start deprecating** and eventually be removed, breaking the 24.04 build legs and the publish job (also pinned to `ubuntu-24.04`). A beta `ubuntu-26.04` image (if used before GA) carries **no Actions SLA** and refreshes weekly.

**Why it happens:**
The workflow pins `ubuntu-24.04`/`ubuntu-24.04-arm` literally in 4+ places. Hardcoded OS labels are time bombs on a rolling-runner platform.

**How to avoid:**
Drive the OS label from the matrix definition, not scattered literals, so adding/removing a distro is a one-line edit. Confirm `ubuntu-26.04` is GA (not beta) before relying on it for published artifacts; if only beta, build 26.04 inside a `container: ubuntu:26.04` on a GA runner (PROJECT.md already anticipates "container fallback if unavailable"). Pin `publish` to the most stable available label, decoupled from the build OS. Track the runner-images deprecation issues.

**Warning signs:**
"The runner label 'ubuntu-24.04' is not available"; a deprecation annotation on runs; 26.04 builds intermittently break after a weekly beta refresh.

**Phase to address:**
CI matrix phase. Matrix as data; gate 26.04 on GA-vs-beta with container fallback.

---

### Pitfall 7: InRelease / Packages caching on GitHub Pages CDN → Hash Sum mismatch

**What goes wrong:**
Adding suites/packages rewrites `InRelease`, `Release`, `Packages` with new checksums. GitHub Pages sits behind a CDN that can serve a **stale `Packages` while the new `InRelease` is already live** (or vice-versa). APT validates `Packages` against `InRelease`; a mismatch yields `E: Failed to fetch ... Hash Sum mismatch` for users mid-update — exactly when you publish a new distro's suites ([Packagecloud](https://blog.packagecloud.io/fixing-apt-hash-sum-mismatch-consistent-apt-repositories/)). Doubling suites doubles metadata churn and the inconsistency window.

**Why it happens:**
Non-atomic delivery: metadata files update one HTTP object at a time on a caching CDN, and reprepro by default does not enable `acquire-by-hash`, so APT fetches `Packages` by plain name (whatever the CDN currently caches) and validates against a possibly-newer `InRelease`.

**How to avoid:**
Enable **`acquire-by-hash`** in reprepro: set `Acquire-By-Hash: yes` per distribution in `conf/distributions`. APT then fetches metadata by content hash, so a stale-cached object is just a different URL and the client always gets a path matching `InRelease` — the recommended long-term fix per Packagecloud and the LLVM/NVIDIA CDN incidents. Current `conf/distributions` does **not** set it. Keep publish atomic: build the full tree and deploy as one Pages artifact (the workflow already uses `upload-pages-artifact` + `deploy-pages`, atomic at artifact level — preserve that).

**Warning signs:**
Users report `Hash Sum mismatch` shortly after a publish; it self-heals after `apt-get clean` + `rm -rf /var/lib/apt/lists/*`; `conf/distributions` lacks `Acquire-By-Hash`.

**Phase to address:**
Repository-topology / publish phase — add `Acquire-By-Hash: yes` when rewriting `conf/distributions` for multi-suite.

---

### Pitfall 8: CI cache key collisions between distro build legs

**What goes wrong:**
The Go-cache key is `go-${{ runner.arch }}-${track}-${run_number}` with restore-keys `go-${runner.arch}-${track}-` / `go-${runner.arch}-` (workflow lines 118-121, 219-222). `runner.arch` is `X64`/`ARM64` — it does **not** distinguish 24.04 from 26.04. Adding a 26.04 leg makes both distros share a cache namespace; a 26.04 leg can restore a 24.04-populated cache. Go's build cache is mostly toolchain-keyed and resilient, but cgo objects and any future C/Rust caches (sccache/ccache) can pick up the wrong distro's compiled fragments → subtly mislinked binaries or maddening cache poisoning.

**Why it happens:**
The key was designed for one distro; `runner.arch` was a sufficient discriminator then, not once a second OS shares the runner pool.

**How to avoid:**
Add a distro dimension to every cache key: `go-${distro}-${runner.arch}-${track}-${run_number}` and matching restore-keys, with `${distro}` from the matrix. Same for any future ccache/sccache CI cache. Treat the key as `(distro, arch, track, toolchain)`.

**Warning signs:**
A 26.04 build links a 24.04-cached object; non-reproducible failures that vanish on cache clear; restore logs showing the other distro's key.

**Phase to address:**
CI matrix phase — bake `distro` into cache keys when the matrix is introduced.

---

### Pitfall 9: GPG key path / keyring divergence between distros

**What goes wrong:**
If the migration introduces a new keyring filename or per-distro key path, existing `.sources`/`.list` with `signed-by=/usr/share/keyrings/podman-ubuntu.gpg` break with `NO_PUBKEY` / "not signed". The repo serves one `podman-ubuntu.gpg` and instructs that exact path. A well-meaning "reorganize keys for two distros" change silently invalidates every existing client.

**Why it happens:**
Restructuring for multi-distro tempts a key/path reorg. APT pins the exact `signed-by` path the user wrote; changing the served key name or recommended path is a breaking change just like a suite rename.

**How to avoid:**
Keep **one signing key and one keyring path** across both distros (no security reason to split — one publisher). Do not rename `podman-ubuntu.gpg` or change `signed-by`. If a key reorg is ever required, apply the same deprecation-window discipline as P4 and keep the old path working. All suites sign with the same key (`SignWith: yes` already does this).

**Warning signs:**
`apt update` reports `NO_PUBKEY` / "signatures couldn't be verified"; the served key filename changed; `index.html` instructs a different `signed-by` path than before.

**Phase to address:**
Migration/compatibility phase — explicit "do not change key path/name" constraint, verified by the docs/migration test.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcode `~podman1` suffix with no distro component | Fewer moving parts | Pool checksum collision the moment a 2nd distro exists (P1) | Never, once multi-distro |
| Two separate repos instead of 6 suites in one | Zero shared-pool risk, simplest publish | Users need 2 apt lines; double Pages artifact; duplicate GPG/index plumbing | Acceptable if 6-suite routing proves too fragile |
| Hardcode library dep names per-distro in YAML (manual map) | Quick fix for the verified 26.04 failure | Breaks on every future release's renames/soname bumps; hand-edit forever | Only as documented fallback when ldd→pkg can't map a lib |
| Keep `merge-multiple: true` flatten in publish | No publish rewrite | Silent cross-distro binary mixing (P5) | Never, once a 2nd distro leg exists |
| Skip `acquire-by-hash`, rely on CDN luck | No conf change | Recurring Hash Sum mismatch on every publish | Never — one-line config |
| Hard-cutover suite rename (drop old names) | Cleaner repo | Every existing user's apt silently breaks (P4) | Never without a deprecation window |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| reprepro shared pool | Same name+version, different contents across suites | Per-distro version suffix → distinct pool entries |
| GitHub Pages CDN | Assuming new metadata is served atomically | `Acquire-By-Hash: yes` + single atomic Pages artifact |
| GitHub-hosted runners | Pinning `ubuntu-24.04` literally everywhere | Matrix-driven OS label; track deprecation; container fallback |
| `actions/download-artifact` | `merge-multiple: true` across distro-tagged artifacts | Per-distro artifact names + per-distro download dirs |
| `actions/cache` | Cache key omits distro dimension | Key on `(distro, arch, track, toolchain)` |
| APT client (`signed-by`) | Renaming served GPG key / keyring path | One key, one path, stable across distros |
| `ci_publish.sh` live re-import | Dedup downloaded debs by basename across distros | Key on `(suite, filename, arch)`; never cross-distro basename dedup |

## Performance / Scale Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `ci_publish.sh` re-downloads ALL other suites' debs every run | Publish slows linearly with package×suite count | Re-import only changed suites; or two-repo isolation | Noticeable at 6 suites × ~14 packages × 2 arches |
| Pages artifact carries every suite's full pool every deploy | Upload/deploy time grows; nears Pages size limits | Acquire-by-hash + prune old nightly snapshots; consider per-distro repos | When nightly history accumulates across 2 distros |
| 4-leg matrix all `timeout-minutes: 180` | Long wall-clock; runner queue contention | Keep legs parallel; cache per (distro,arch) | When adding distros/arches beyond 4 legs |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Splitting into per-distro GPG keys without need | Larger key surface, user confusion, broken `signed-by` | Single signing key across all suites/distros |
| Trusting CDN-cached `Packages` without hash binding | Stale/mismatched metadata, substitution window | `Acquire-By-Hash: yes`; signed `InRelease` already binds checksums |
| Re-importing live-repo debs without re-verifying provenance | A poisoned live object re-enters the new build | Re-verify checksums against the suite's signed `Packages` before re-adding |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Forcing users to know their distro suite name | Wrong suite → no packages or wrong-glibc binaries | Setup snippet detects `. /etc/os-release` and emits the right `*-2404`/`*-2604` |
| Silent suite rename | apt freezes with no error until next `update` | Keep old codenames as aliases + announce deprecation |
| Two apt lines (if two-repo topology) | Confusion, copy-paste errors | If two-repo, provide a single setup script that picks the path by `VERSION_ID` |

## "Looks Done But Isn't" Checklist

- [ ] **Per-distro builds:** Often missing the distro suffix in the *version string* (not just the suite) — verify `dpkg-deb -f pkg.deb Version` differs between the 24.04 and 26.04 build of the same upstream version.
- [ ] **Dependency resolution:** Often still hardcoded names that happen to resolve on 24.04 — verify on a real 26.04 host that `apt-get install --simulate podman-suite` passes and `libgpgme11` vs `libgpgme11t64` is correct per distro.
- [ ] **Suite migration:** Often new suites work but old `stable`/`edge`/`nightly` 404 — verify a pre-v3.0 `.sources` file still `apt update`s during the deprecation window.
- [ ] **Artifact routing:** Often the matrix builds 4 legs but publish still flattens them — verify every `.deb` in a `*-2404` suite carries the 24.04 suffix and runs on a 24.04 container.
- [ ] **CDN consistency:** Often publish "works" in CI but users get Hash Sum mismatch — verify `conf/distributions` has `Acquire-By-Hash: yes` and `dists/*/by-hash/` paths exist.
- [ ] **Runner availability:** Often assumed `ubuntu-26.04` is GA — verify the label is GA (not beta/no-SLA) or the container fallback is wired.
- [ ] **index.html / docs:** Often regenerated for new suites but still hardcode bare `stable` in the copy-paste snippet — verify the rendered snippet emits the distro-specific suite.
- [ ] **GPG path:** Often a key reorg sneaks in — verify served key filename and `signed-by` path unchanged from v2.0.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Pool checksum collision (P1) | MEDIUM | Stop publish; re-version both artifacts with distinct distro suffixes; `reprepro deleteunreferenced`; rebuild repo from scratch and redeploy |
| Cross-distro binary leak (P5) | MEDIUM | Identify mislabeled `.deb` (suffix vs suite mismatch); `reprepro remove <suite> <pkg>`; rebuild the leg; redeploy; advise users to `apt install --reinstall` |
| Suite rename broke users (P4) | LOW if caught / HIGH if window already closed | Re-export old codenames as aliases for the deprecation window; publish migration note; retire only after window |
| Hash Sum mismatch from CDN (P7) | LOW | Enable `Acquire-By-Hash`; redeploy; tell users `apt-get clean && rm -rf /var/lib/apt/lists/* && apt-get update` |
| Wrong dependency name shipped (P3) | LOW | Switch to ldd→pkg resolution on build host; rebuild affected packages; republish suite |
| Runner label removed (P6) | LOW | Move build to `container:` on a GA runner; update matrix label |
| Cache poisoning across distros (P8) | LOW | Add distro to cache key; bump key version to invalidate; rerun |

## Pitfall-to-Phase Mapping

(Phase names are suggested groupings; the roadmap may rename them.)

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| P1 Pool checksum collision | Per-distro versioning/packaging | `dpkg --compare-versions` ordering OK; both distro builds of same upstream version produce distinct `.deb` names; reprepro adds both without error |
| P2 ci_publish cross-distro clobber | Repository topology / publish | Publish preserves all 6 suites' package counts; `dumpunreferenced` empty; re-import keyed on (suite,filename,arch) |
| P3 Hardcoded dep names (t64/soname) | Per-distro versioning/packaging | `apt-get install --simulate podman-suite` passes on real 24.04 and 26.04; CI lint rejects undeclarable deps |
| P4 Suite rename breaks users | Migration/compatibility + docs | Pre-v3.0 `.sources` still updates during deprecation window; old codenames resolve |
| P5 Newer-glibc binary leak | CI matrix + smoke-test | Every `*-2404` `.deb` has 24.04 suffix; `podman info` runs in a 24.04 container |
| P6 Runner deprecation timing | CI matrix | `ubuntu-26.04` is GA or container fallback active; matrix is data-driven |
| P7 CDN Hash Sum mismatch | Repository topology / publish | `Acquire-By-Hash: yes` present; hashed metadata paths exist under `dists/*/by-hash/` |
| P8 Cache key collision | CI matrix | Cache keys include `${distro}`; restore logs never cross distros |
| P9 GPG path divergence | Migration/compatibility | Served key name + `signed-by` path unchanged from v2.0 |

## Sources

- [moby/moby #48306 — containerd.io different checksum jammy vs noble (exact precedent for P1)](https://github.com/moby/moby/issues/48306) — HIGH
- [Debian Bug #477708 — reprepro won't add same name+version with different contents](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=477708) — HIGH
- [ionos-cloud/reprepro #13 — "File is already registered with different checksums!"](https://github.com/profitbricks/reprepro/issues/13) — HIGH
- [reprepro(1) manpage (Debian unstable) — Acquire-By-Hash, distributions conf](https://manpages.debian.org/unstable/reprepro/reprepro.1.en.html) — HIGH
- [Debian Wiki — ReleaseGoals/64bit-time (t64 transition, ~495 libs renamed)](https://wiki.debian.org/ReleaseGoals/64bit-time) — HIGH
- [packages.ubuntu.com/noble/libgpgme11t64 — libgpgme11 → libgpgme11t64 on 24.04](https://packages.ubuntu.com/noble/libgpgme11t64) — HIGH
- [aptly-dev/aptly #1318 — t64 dependency resolution breakage (illustrates P3 fallout)](https://github.com/aptly-dev/aptly/issues/1318) — MEDIUM
- [GitHub-hosted runners reference — 2 GA + 1 beta, oldest deprecates](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) — HIGH
- [actions/runner-images #13964 — Add Ubuntu 26.04 LTS](https://github.com/actions/runner-images/issues/13964) — HIGH
- [actions/runner-images #13855 — Support Ubuntu 26.04](https://github.com/actions/runner-images/issues/13855) — MEDIUM
- [Packagecloud — Fixing APT Hash Sum Mismatch (acquire-by-hash is the fix)](https://blog.packagecloud.io/fixing-apt-hash-sum-mismatch-consistent-apt-repositories/) — HIGH
- [llvm/llvm-project #49575 — apt repo metadata should use acquire-by-hash (CDN staleness)](https://github.com/llvm/llvm-project/issues/49575) — MEDIUM
- [blobfolio — deb822 sources, suite naming, apt-key migration](https://blobfolio.com/2022/deb822-and-apt-key/) — MEDIUM
- Codebase (direct inspection — HIGH): `scripts/package_all.sh` (VERSION_SUFFIX:27, detect_crun_parser_depend:199), `scripts/ci_publish.sh` (live re-import:91,113-156,194), `packaging/repo/conf/distributions`, `packaging/nfpm/{podman,crun,suite}.yaml`, `.github/workflows/build-packages.yml` (artifact merge:294-298, cache keys:118-121)

---
*Pitfalls research for: multi-distro APT packaging (Ubuntu 24.04 + 26.04) on nFPM + reprepro + GitHub Pages + Actions*
*Researched: 2026-06-05*
