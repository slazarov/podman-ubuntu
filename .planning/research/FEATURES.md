# Feature Research: Multi-Distro APT Repository (Ubuntu 24.04 + 26.04)

**Domain:** Multi-distro APT repository (self-hosted, GitHub Pages + reprepro), adding Ubuntu 26.04 support alongside existing Ubuntu 24.04
**Researched:** 2026-06-05
**Confidence:** HIGH (structural patterns verified against Docker, GitHub CLI, OBS/alvistack; reprepro/Debian/APT behavior from official docs)

> **Scope note:** This file covers ONLY the v3.0 milestone (adding 26.04 / multi-distro). The v2.0 packaging-and-repo feature research is preserved in `FEATURES-v2.0.md` (control files, GPG signing, package inventory, CI). Read that file for anything about the existing single-distro setup.

## How Established Repos Structure Multi-Distro Serving

This is the question driving the whole milestone. Real-world repos use one of three patterns; our chosen approach is a fourth, legitimate variant.

| Pattern | Who Uses It | Layout | Trade-off |
|---------|-------------|--------|-----------|
| **Codename-per-suite** | Docker, most distro-aligned vendors | `dists/noble/main/`, `dists/resolute/main/`; user's `Suites:` = their `$VERSION_CODENAME` | Distro-native, but `Suites:` differs per machine and requires knowing the codename |
| **Single codename-neutral suite** | GitHub CLI (`cli.github.com/packages stable main`) | One `dists/stable/`; one binary built to lowest-common-denominator glibc serves all distros | Dead-simple identical `.sources` everywhere; only works when one binary is genuinely portable — NOT our case |
| **Separate repo path per distro** | OpenSUSE OBS / alvistack (`.../xUbuntu_24.04/`, `.../xUbuntu_24.10/`) | Each distro = own repo root with flat `./` suite | Fully isolated; user's `URIs:` differs per distro; heavier hosting |
| **Version-based suites in one repo** (OUR CHOICE) | Various smaller multi-distro repos | One repo root, suites `stable-2404`/`stable-2604`/...; user's `Suites:` token differs | Single repo root preserved; one `Suites:` token differs per distro; numeric is clearer than codenames |

**Why version-based suites is right for us:**
- Keeps a single repo root (`https://slazarov.github.io/podman-ubuntu`) — no per-distro URI, matches current hosting and the gh-pages publish model.
- Lets the SAME upstream version ship per-distro-native dependency sets — the entire point of this milestone (the verified 26.04 dependency-rename breakage).
- Numeric `2404`/`2604` read more clearly than `noble`/`resolute` for a 2-distro personal repo.
- The only loss vs Docker's codename model is that users can't auto-derive the suite from `$VERSION_CODENAME` — a non-issue with two clearly-labeled doc blocks.

## What Users Expect in `.sources` (Suites patterns)

Established repos set these expectations:

- **DEB822 `.sources` with `Signed-By`** — already implemented; now table stakes (all four reference repos use it on Ubuntu 24.04+).
- **One `Suites:` token naming their distro+track**, e.g. `Suites: stable-2404`. Users do NOT expect to edit `URIs:` per distro (that's the OBS model they find heavier).
- **`Suites:` accepts multiple space-separated tokens** (verified: APT/DEB822 supports `Suites: stable-2404 edge-2404`). Relevant only for the migration alias strategy, not normal single-track use.
- **Switching track = change one word** in the existing file (current docs already do this for stable→edge; the new axis is `-2404`/`-2604`).

Expected per-distro `.sources` body — only `Suites:` changes between distros:

```
Types: deb
URIs: https://slazarov.github.io/podman-ubuntu
Suites: stable-2404        # stable-2604 on Ubuntu 26.04
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
```

## Migration When Suite Names Change (`stable` → `stable-2404`)

The milestone's riskiest feature. Existing 24.04 users have `Suites: stable` (or `edge`/`nightly`) hardcoded; renaming makes their `apt update` 404. Mechanisms ranked by suitability:

| Mechanism | What It Does | Fit | Confidence |
|-----------|--------------|-----|------------|
| **reprepro `Codename`/`Suite` split + `createsymlinks`** | Make `Codename: stable-2404` canonical (never changes); also publish legacy `Suite: stable`; `reprepro createsymlinks` creates `dists/stable -> dists/stable-2404`. Old `Suites: stable` keeps resolving. | BEST. reprepro docs: Codename must not change (add new sections for new names); `createsymlinks` is the intended Suite→Codename link tool. | HIGH |
| **Copied/symlinked `dists/stable` → `dists/stable-2404` in publish step** | On static GitHub Pages, duplicate or symlink the legacy dists tree during publish. Same end effect without relying on reprepro's command. | Viable fallback. GitHub Pages serves committed symlinks / copied dirs. | MEDIUM |
| **`AlsoAcceptFor`** | Controls which suite names `reprepro include` ACCEPTS on upload (avoids `--ignore=wrongdistribution`). NOT a download/serving alias. | WRONG TOOL for user migration — upload-side only, confirmed by docs + bug history. | HIGH |
| **Deprecation notice (docs + changelog)** | Updated docs to new suite names; transitional note. Pairs with one of the above. | Necessary regardless. | HIGH |

**Recommended migration design:** Make `stable-2404` the canonical `Codename`; publish legacy `stable` as an alias (`createsymlinks`, or copied dists tree in the publish step) for a deprecation window; update docs to the versioned names. Every existing 24.04 `.sources` keeps working with zero user action while docs steer everyone to versioned suites. This directly revisits the v2.0 decision "Codename = Suite name to avoid createsymlinks complexity" — `createsymlinks` is exactly the tool this rename needs.

**Caveat (validate during implementation, MEDIUM):** APT may emit an interactive "Repository changed its 'Suite'/'Codename' value" prompt if the served `Release` file's fields shift under an existing client. Keep the legacy alias's own `Release` labeled `stable` to avoid triggering it. Test with a real 24.04 client that has the old `.sources`.

## Version String Conventions (same upstream version, per-distro builds)

Both 24.04 and 26.04 ship the same upstream Podman version as distinct, distro-native packages. The version string must (a) differentiate the two builds and (b) NOT break a 24.04→26.04 release-upgrade.

- **Docker's mistake (verified):** Docker embeds the codename (`...~debian-buster`). Debian version comparison is alphabetical, so `buster` > `bullseye` — dist-upgrades think the OLD package is newer and refuse to upgrade. AVOID codename-in-version.
- **Ubuntu's safe convention (verified):** Tilde `~<version>` suffix. Tilde sorts BEFORE everything, so `X~24.04` and `X~26.04` both sort below plain `X`, and `~26.04` > `~24.04` in the correct order — a 24.04→26.04 upgrade correctly sees the 26.04 package as newer. The `+ubuntuXX.XX` form (no tilde) exists too but is for "almost-native" packaging; tilde is the safe default for ordering.

**Recommendation:** Extend the existing `~podman1` scheme with a per-distro tilde suffix: `<upstream>~podman1~ubuntu24.04` and `<upstream>~podman1~ubuntu26.04`. This:
- Preserves the existing "yield to official Ubuntu packages" behavior (tilde sorts below an official `<upstream>`).
- Makes the two distro builds distinct and correctly ordered for release-upgrade (`~ubuntu26.04` > `~ubuntu24.04`).
- Uses numeric versions after the tilde, dodging the Docker alphabetical-codename trap.

Confidence: HIGH on the tilde-vs-codename rule; MEDIUM on the exact `~podman1~ubuntuXX.XX` concatenation interacting cleanly with `~podman1` priority — verify with `dpkg --compare-versions` during implementation.

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Per-distro suites published (`stable/edge/nightly`-`2404` and `-2604`) | A repo advertising 26.04 support must serve 26.04-native packages | MEDIUM | Add 3 new reprepro stanzas for `-2604`; rename/alias existing 3 to `-2404` |
| Per-distro dependency mapping in nFPM | Verified breakage: 26.04 renamed/replaced dep packages (libseccomp2, libsystemd0, json-c parser via `${CRUN_PARSER_DEPEND}`). Must install cleanly per distro | MEDIUM-HIGH | Distro-conditional `Depends:`; this is the concrete failure this milestone fixes |
| Backward-compatible legacy suites keep resolving | Silent `apt update` 404 for existing users is unacceptable | MEDIUM | reprepro Suite/Codename + `createsymlinks`, or copied dists tree |
| Per-distro version differentiation (tilde suffix) | Same upstream version must yield two distinct, correctly-ordered packages | LOW | `~ubuntu24.04` / `~ubuntu26.04`; avoids Docker dist-upgrade trap |
| Updated docs with copy-paste `.sources` per distro | Setup instructions must match the user's OS | LOW | Extend `docs/apt-repository.md`; show which suite per distro |
| Correct per-suite `Release` metadata (Suite/Codename/Architectures) | APT validates these; mismatches cause warnings/prompts | LOW | reprepro generates; just configure stanzas |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Single repo root for all distros (no per-distro `URIs:`) | Simpler than OBS; user changes only one `Suites:` token | LOW | Already true; preserve it with the version-suite layout |
| Native builds per distro (not forward-compat shims) | 26.04 packages link 26.04 libs, not 24.04-built binaries riding glibc compat | MEDIUM | PROJECT.md: 24.04 binaries are forward-compat but reverse isn't — native-per-distro is the correct higher-quality choice |
| Zero-touch migration for existing users | Existing 24.04 installs keep updating with no intervention during the deprecation window | MEDIUM | The alias strategy; most personal repos simply break users on rename |
| Documented, time-boxed deprecation of legacy suite names | Sets expectations; allows clean eventual removal | LOW | Doc + changelog note; a courtesy few personal repos bother with |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Codename in package version (`~noble`, `+ubuntu-noble`) | Mirrors what Docker visibly does | Verified to break dist-upgrades — codenames sort alphabetically, not by release order | Numeric tilde suffix `~ubuntu24.04` |
| Separate repo path per distro (OBS/alvistack style) | Total isolation, no version collisions | Forces per-distro `URIs:`, more hosting surface, breaks the single-root setup users already have | Version-based suites within the one repo |
| Single codename-neutral `stable` for all distros (GitHub CLI style) | One `.sources` works everywhere | Only valid if ONE binary serves all distros; defeats this milestone's per-distro-native-deps goal | Keep per-distro suites; accept one differing `Suites:` token |
| Auto-detect distro in setup (`$VERSION_CODENAME` interpolation) | Copy-paste works on any machine unchanged | Version-suite names (`2404`) aren't the codename; codename→suite mapping in a shell snippet adds fragility for a 2-distro repo | Two clearly-labeled copy-paste blocks (24.04 / 26.04) |
| Keeping legacy `stable`/`edge`/`nightly` aliases forever | "Never break anyone" | Permanent ambiguity over which distro the unversioned suite means once >2 distros exist | Time-boxed deprecation window, then remove |
| Adding Debian / non-Ubuntu in this milestone | "While we're touching multi-distro..." | Out of scope per PROJECT.md; multiplies dep-mapping and CI matrix | Ubuntu 24.04 + 26.04 only |
| Epoch bump to force the new version scheme | "Guarantee our versions win" | Epochs are irreversible permanent debt (already an anti-feature in v2.0 research); tilde ordering handles this | Tilde suffix gives correct ordering without an epoch |

## Feature Dependencies

```
Per-distro suites published (reprepro stanzas -2404/-2604)
    └──requires──> Reprepro Suite/Codename redesign (canonical Codename = version suite)
                       └──enables──> Backward-compatible legacy alias (createsymlinks / copied dists)

Per-distro dependency mapping (nFPM)
    └──requires──> CI build matrix extended to 26.04 (builds the 26.04 .debs to publish)

Per-distro version suffix (~ubuntuXX.XX)
    └──enables──> Two distinct packages, same upstream version, correct upgrade ordering

Updated docs (per-distro .sources blocks)
    └──requires──> Per-distro suites published   (docs must reference real suites)

Legacy alias ──conflicts──> APT "Suite changed value" prompt
    (mitigate: keep alias's own Release labeled with the old Suite name)
```

### Dependency Notes

- **Suites publishing requires the Codename redesign first:** the alias strategy hinges on making the versioned name the canonical `Codename` and the old name a `Suite` alias. Reprepro config must change before/with publishing.
- **Dependency mapping requires the CI matrix:** cannot publish 26.04-native `.debs` until CI builds on 26.04 (native `ubuntu-26.04`/`-arm` runners, container fallback per PROJECT.md).
- **Version suffix is independent and low-cost:** can land in nFPM configs anytime; gates correct upgrade behavior.
- **Legacy alias vs APT prompt is the one real conflict:** validate the served `Release` fields don't trigger the interactive "repository changed its value" prompt for existing clients.

## MVP Definition

### Launch With (v3.0 — required for "26.04 support" to be true)

- [ ] Reprepro `conf/distributions` redesigned: canonical `Codename` per track+distro (`stable-2404`, `edge-2404`, `nightly-2404`, `stable-2604`, `edge-2604`, `nightly-2604`), amd64+arm64 each
- [ ] Per-distro dependency mapping in nFPM configs — fixes the verified 26.04 install failure
- [ ] CI matrix builds and publishes all three tracks for both distros
- [ ] Per-distro tilde version suffix (`~ubuntu24.04`/`~ubuntu26.04`)
- [ ] Backward-compatible legacy suite alias for existing 24.04 users (createsymlinks or copied dists tree)
- [ ] Docs updated with per-distro copy-paste `.sources` + migration note

### Add After Validation (v3.x)

- [ ] Time-boxed removal of legacy `stable`/`edge`/`nightly` aliases — after a deprecation window once users have migrated
- [ ] An `apt`-surfaced deprecation notice — trigger: legacy suite still seeing meaningful traffic at window end

### Future Consideration (post-v3)

- [ ] Generalized N-distro / templated reprepro stanzas — defer until a 3rd distro is actually needed (avoid premature abstraction)
- [ ] Codename-aliased suites (`noble`/`resolute` → `-2404`/`-2604`) for Docker-style `$VERSION_CODENAME` auto-detect — only if users ask

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Per-distro suites published | HIGH | MEDIUM | P1 |
| Per-distro dependency mapping (nFPM) | HIGH | MEDIUM-HIGH | P1 |
| Backward-compatible legacy alias | HIGH | MEDIUM | P1 |
| Per-distro tilde version suffix | MEDIUM | LOW | P1 |
| CI matrix → 26.04 | HIGH (enabler) | MEDIUM | P1 |
| Updated per-distro docs | HIGH | LOW | P1 |
| Time-boxed legacy-alias removal | LOW | LOW | P2 |
| `apt`-surfaced deprecation notice | LOW | MEDIUM | P3 |
| Codename auto-detect suites | LOW | MEDIUM | P3 |

**Priority key:** P1 = must have for v3.0; P2 = should have in v3.x; P3 = future.

## Competitor Feature Analysis

| Feature | Docker | GitHub CLI | OBS / alvistack | Our Approach |
|---------|--------|------------|-----------------|--------------|
| Multi-distro layout | Codename-per-suite (`dists/noble`) | Single neutral `stable` for all | Separate repo path per distro (`xUbuntu_24.04/`) | Version-based suites in one repo (`stable-2404`/`-2604`) |
| User `.sources` per distro | `Suites: $VERSION_CODENAME` | Identical everywhere | Different `URIs:` per distro | Same `URIs:`, one `Suites:` token differs |
| Version string | Codename embedded (breaks dist-upgrade) | Plain upstream version | OBS-generated per-distro | Numeric tilde `~ubuntuXX.XX` (safe ordering) |
| Per-distro native deps | Yes | No (one portable binary) | Yes (built per distro) | Yes (the milestone's core fix) |
| Migration on rename | n/a (codenames stable) | n/a | n/a (path-isolated) | createsymlinks alias + deprecation window |

## Dependencies on Existing Repo Structure

- **`packaging/repo/conf/distributions`** currently has 3 stanzas with `Suite == Codename` (`stable`, `edge`, `nightly`). v3.0 rewrites this to 6 stanzas with versioned canonical Codenames plus legacy Suite aliases — the single highest-impact file change.
- **nFPM configs** currently declare distro-specific deps (`libseccomp2`, `libsystemd0`, `${CRUN_PARSER_DEPEND}`) assuming 24.04 names — must become distro-conditional.
- **`docs/apt-repository.md`** currently documents single-distro `Suites: stable`/`edge` (no nightly, no 26.04) — must add per-distro blocks and a migration note.
- **CI workflow** (native amd64+arm64 24.04 runners, nightly cron) — extends to a 4-cell matrix (2 distros × 2 arches) with container fallback for 26.04.
- **GPG signing / `~podman1` priority suffix** — unchanged; the new tilde suffix extends rather than replaces it.

## Sources

- [Docker: Debian/Ubuntu package versions contain codename which "break" dist upgrades (docker/for-linux #1315)](https://github.com/docker/for-linux/issues/1315) — codename-in-version dist-upgrade breakage (HIGH)
- [Install Docker Engine on Debian — Docker Docs](https://docs.docker.com/engine/install/debian/) — codename-per-suite layout, `$VERSION_CODENAME` (HIGH)
- [GitHub CLI Linux install docs (cli/cli)](https://github.com/cli/cli/blob/trunk/docs/install_linux.md) — single neutral `stable` suite for all distros (HIGH)
- [openSUSE Build Service Debian builds — openSUSE Wiki](https://en.opensuse.org/openSUSE:Build_Service_Debian_builds) and [Install Apps from OBS — UbuntuHandbook](https://ubuntuhandbook.org/index.php/2025/04/install-apps-opensuse-obs/) — separate path per distro `xUbuntu_XX.XX/` (HIGH)
- [reprepro(1) manpage — Debian unstable](https://manpages.debian.org/unstable/reprepro/reprepro.1.en.html) — Suite vs Codename, `createsymlinks`, `AlsoAcceptFor` is upload-only (HIGH)
- [DebianRepository/SetupWithReprepro — Debian Wiki](https://wiki.debian.org/DebianRepository/SetupWithReprepro) — Codename must not change; add new sections; Suite may change per release (HIGH)
- [Bug#423034: reprepro AlsoAcceptFor](https://www.mail-archive.com/debian-bugs-dist@lists.debian.org/msg344721.html) — AlsoAcceptFor is not a serving alias (MEDIUM)
- [Ubuntu version string conventions — Ubuntu project documentation](https://documentation.ubuntu.com/project/how-ubuntu-is-made/concepts/version-strings/) — tilde sorting, `~XX.XX` vs `+ubuntuXX.XX` (HIGH)
- [deb-version(5) — package version number format](https://manpages.ubuntu.com/manpages/xenial/man5/deb-version.5.html) — tilde sorts before everything (HIGH)
- [DEB822 source format / sources.list(5)](https://manpages.debian.org/unstable/apt/sources.list.5.en.html) and [RepoLib DEB822 docs](https://repolib.readthedocs.io/en/latest/deb822-format.html) — `Suites:` accepts multiple space-separated tokens (HIGH)
- [DebianRepository/Format — Debian Wiki](https://wiki.debian.org/DebianRepository/Format) — `dists/<suite>/<component>` layout (HIGH)

---
*Feature research for: multi-distro APT repository (Ubuntu 24.04 + 26.04), v3.0 milestone*
*Researched: 2026-06-05*
