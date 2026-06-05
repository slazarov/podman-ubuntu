# Phase 19: Per-Distro Versioning & Dependency Mapping - Research

**Researched:** 2026-06-05
**Domain:** Debian/Ubuntu package versioning (dpkg version semantics), build-time runtime-dependency resolution (ldd → dpkg-query), nFPM config generation, Bash build tooling
**Confidence:** HIGH

## Summary

This phase is almost entirely a **Bash + nFPM-config refactor inside an existing, working pipeline** — no new external packages, no new runtime. The technical surface is small and well-understood, and the project already contains a working prototype of the hardest part (`detect_crun_parser_depend()` does exactly the ldd→package-name detection that D-01 wants to generalize). The locked decisions in CONTEXT.md are sound and grounded in real Debian/Ubuntu mechanics. The research below verifies those mechanics against authoritative sources and surfaces **one material correction** the planner must account for.

**The material correction (HIGH confidence, affects success criterion 4):** The current nFPM YAMLs hardcode pre-t64 names (`libgpgme11`, `libglib2.0-0`). On Ubuntu 24.04 these names still install — but only because they are **transitional dummy packages** that depend on the real t64-renamed runtime packages (`libgpgme11t64`, `libglib2.0-0t64`). When D-01's `ldd → dpkg-query -S` runs on a real 24.04 host, it will resolve the linked `.so` to the **t64 name**, not the hardcoded name. Therefore the detected dependency set on 24.04 will **not be textually identical** to the current hardcoded set — it will be the *functionally-equivalent, more-correct* t64 set. D-14 ("detected set must exactly equal the current hardcoded set") must be reinterpreted as **functional equivalence** (does `apt install` resolve to the same physical libraries), not string equality, or the no-regression check will produce a false failure. This is the single most important planning input in this document.

**Primary recommendation:** Generalize `detect_crun_parser_depend()` into a single `detect_runtime_depends(binary...)` function that runs `ldd` on each component's binaries, maps each resolved library path to its owning package with `dpkg-query -S`, dedupes, and emits a depends list. Compose the version suffix once in `config.sh` from `/etc/os-release` (`DISTRO` override). Inject the variable-length depends list into nFPM by **generating the `depends:` block as a YAML fragment and substituting it as a single multi-line `${COMPONENT_DEPENDS}` block** (nFPM's native `${VAR}` expansion plus the project's existing envsubst step both work, but a single multi-line list value is the cleanest fit — see Architecture Patterns). Verify version ordering with `dpkg --compare-versions` and verify 24.04 functional equivalence by comparing resolved-library identity, not name strings.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Distro identity detection (`/etc/os-release`) | Build host / config (`config.sh`) | — | Builds run ON the target distro (D-05); os-release is authoritative; single source of truth precedent |
| Version-suffix composition | Build config (`config.sh`) | Packaging script (`package_all.sh` consumes) | Centralized config pattern (D-07); one place that all components read |
| Runtime-dependency resolution (ldd→dpkg) | Packaging script (`package_all.sh`) | Build host (`dpkg-query` queries host package DB) | Per-binary, per-component; runs after staging tree populated; mirrors `dpkg-shlibdeps` |
| Dependency injection into package metadata | nFPM config (`packaging/nfpm/*.yaml`) | Packaging script (templating/substitution) | nFPM owns the .deb control file; depends list is package metadata |
| Version-ordering / no-regression verification | In-phase verification (CI-agnostic scripts) | Container runtime (26.04 install smoke) | dpkg semantics are host-independent; 26.04 install needs a real 26.04 userland |

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Dependency detection mechanism**
- **D-01:** Runtime system library deps are resolved at build time per binary: `ldd` extracts resolved library paths → `dpkg -S` (or `dpkg-query -S`) maps each path to its owning package on the build host. Mirrors `dpkg-shlibdeps`; satisfies PKG-10.
- **D-02:** Base packages guaranteed present on any Debian/Ubuntu system (`libc6`, `libgcc-s1` — priority: required) are excluded from the generated depends list, matching current hardcoded behavior.
- **D-03:** Detection failure (soname whose owning package cannot be resolved) is a HARD build failure with a clear error message. No silent fallback to stale hardcoded names. Consistent with `detect_crun_parser_depend()` precedent and fail-early philosophy.
- **D-04:** The existing crun parser special case (`${CRUN_PARSER_DEPEND}`, libjson-c5 vs libyajl2) is absorbed by the general detection mechanism — no separate special-case code remains.

**Distro identity plumbing**
- **D-05:** Distro auto-detected from `/etc/os-release` (`ID` + `VERSION_ID`) of the build environment.
- **D-06:** Explicit `DISTRO` env var overrides auto-detection.
- **D-07:** Version suffix composed once in `config.sh` (single source of truth), consumed by `scripts/package_all.sh`. Hardcoded `VERSION_SUFFIX="~podman1"` (package_all.sh:29) replaced by the composed per-distro value.

**Version string composition**
- **D-08:** Suffix form: `~ubuntu{VERSION_ID}.podman1` (e.g. `5.5.2~ubuntu24.04.podman1`). Trailing `.podman1` retained as a repackaging revision counter.
- **D-09:** Nightly form: distro suffix replaces the current trailing `~podman1`, yielding `{base}~git{YYYYMMDD}.{sha}~ubuntu{VERSION_ID}.podman1`.
- **D-10:** pasta keeps its date-based base version; same distro suffix appended (e.g. `20250302~ubuntu24.04.podman1`).
- **D-11:** In-phase verification MUST assert with `dpkg --compare-versions`: (a) suffixed < plain upstream, (b) 24.04 form < 26.04 form of same upstream, (c) nightly form < tagged-release form.

**Scope of dependency replacement**
- **D-12:** ALL hardcoded system library deps across the nFPM YAMLs (`libgpgme11`, `libseccomp2`, `libsystemd0`, `libcap2`, `libglib2.0-0`, `libsubid4`, `libsqlite3-0`) replaced by the build-time detected set.
- **D-13:** Internal suite deps (`podman-crun`, `podman-conmon`, etc.) stay static — package-level relationships, not soname-derived.
- **D-14:** No-regression guardrail (success criterion 4): the detected dependency set on ubuntu:24.04 must exactly equal the current hardcoded set per package. **(See Pitfall 1 — must be read as functional equivalence, not string equality, because of the t64 transition.)**

### Claude's Discretion
- Templating mechanism for injecting a multi-entry `depends:` list into nFPM configs — envsubst single-variable substitution is awkward for YAML lists. Researcher/planner decides: generated depends block, nFPM native templating, yq-based injection, or per-package generated YAML. Pick whatever is most robust and closest to existing patterns.
- How to validate 26.04 installability within this phase (before the Phase 21 CI matrix exists).
- Exact exclusion-list contents beyond `libc6`/`libgcc-s1` if detection surfaces other priority-required libs on 26.04.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope. Generalized N-distro templating is tracked as future requirement PKG-11. Out-of-scope for the milestone (from REQUIREMENTS.md): codename-in-version-string, separate repo path per distro, hard suite rename without aliases, publishing 24.04 binaries to the 26.04 suite, non-LTS interim releases.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PKG-08 | Packages built for 26.04 declare correct renamed runtime deps (libgpgme45, libsubid5) so `apt install` succeeds on 26.04 | Verified 26.04 renames: gpgme 2.0 → `libgpgme45`, subid → `libsubid5` (Code Examples; State of the Art). D-01 ldd→dpkg detection produces these automatically when run on a 26.04 host. |
| PKG-09 | Per-distro version suffix so same upstream version → distinct .deb identities, dist-upgrades order correctly | dpkg tilde semantics verified (Pitfall 2, Code Examples): `~ubuntu24.04.podman1` and `~ubuntu26.04.podman1` both sort below plain upstream; 24.04 < 26.04 numerically. D-11 verification commands provided. |
| PKG-10 | Runtime deps resolved at build time via ldd soname→package detection; future renames caught automatically | `detect_crun_parser_depend()` is the working prototype to generalize (Don't Hand-Roll, Code Examples). `dpkg-query -S` is the standard host-DB→package mapping. |
</phase_requirements>

## Standard Stack

This phase introduces **no new packages**. It uses tools already present on every Debian/Ubuntu build host and already required by the pipeline.

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `ldd` | glibc (host) | List the resolved shared-library paths a binary links against | The canonical way to enumerate runtime sonames; already used by `detect_crun_parser_depend()` |
| `dpkg-query -S` / `dpkg -S` | dpkg ≥ 1.21 (host) | Map a file path (a resolved `.so`) to its owning installed package | Standard dpkg file→package reverse lookup; how `dpkg-shlibdeps` itself attributes libraries |
| `dpkg --compare-versions` | dpkg (host) | Assert version ordering (lt/le/eq/ge/gt) per Debian version semantics | The authoritative oracle for D-11; no reimplementation of version math |
| nFPM | v2.45.0 (pinned in repo) | Produce `.deb` from YAML config | Already the packaging engine; supports `${VAR}` expansion in `depends` |
| `envsubst` (gettext) | host | Pre-expand `${VAR}` in nFPM YAML incl. `contents.src` globs | Existing project mechanism (package_all.sh) |
| `/etc/os-release` | systemd/base-files | Source `ID` and `VERSION_ID` for distro identity | Freedesktop standard; present on all target distros |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `dpkg-shlibdeps` | Debian's own automatic shlib-dependency generator | **Reference / fallback only.** D-01 deliberately uses the simpler explicit ldd→dpkg-query approach. Note it for the planner: dpkg-shlibdeps requires a `debian/control` skeleton and is more ceremony than this nFPM pipeline wants. Do NOT adopt it; it is mentioned only because reviewers may ask "why not dpkg-shlibdeps." |
| `yq` | YAML manipulation | Optional injection mechanism (see Architecture Patterns). Not currently a project dependency — adopting it adds a tool; prefer the substitution approach that needs nothing new. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `ldd` | `objdump -p \| grep NEEDED` / `readelf -d` | objdump/readelf give the raw `DT_NEEDED` soname strings (e.g. `libgpgme.so.45`) without resolving the on-disk path. You'd then need `ldconfig -p` or a manual search to find the path before `dpkg -S`. `ldd` resolves the path directly — fewer steps, matches the existing precedent. Keep `ldd`. (Caveat: `ldd` runs the loader; only run it on trusted, just-built binaries — which these are.) |
| `dpkg-query -S <path>` | `dpkg-query -S <soname>` | dpkg-query can match on the basename, but a resolved absolute path is unambiguous and avoids matching same-named files in other packages. Use the resolved path from `ldd`. |
| Explicit ldd→dpkg | `dpkg-shlibdeps` | See Supporting row. More correct in theory, far heavier in practice; rejected by D-01. |

**Installation:** None. All tools are host-provided or already pinned.

**Version verification:** N/A — no registry packages added this phase. nFPM remains pinned at v2.45.0 (existing `go install ...@v2.45.0` line in `package_all.sh`).

## Package Legitimacy Audit

**Not applicable.** This phase installs no external packages from any registry (npm/PyPI/crates). All tooling is host-provided (`ldd`, `dpkg`, `envsubst`, `/etc/os-release`) or already pinned in-repo (nFPM v2.45.0). slopcheck was therefore not run. No `## Package Legitimacy Audit` table is required by the protocol because no install step is introduced.

## Architecture Patterns

### System Architecture Diagram

```
                       ┌────────────────────────┐
   /etc/os-release ───▶│  config.sh             │   DISTRO env override ──┐
   (ID, VERSION_ID)    │  - detect distro        │◀───────────────────────┘
                       │  - compose VERSION_SUFFIX = ~ubuntu{VERSION_ID}.podman1
                       └───────────┬────────────┘
                                   │ exports VERSION_SUFFIX (+ DISTRO_ID, VERSION_ID)
                                   ▼
   DESTDIR staging ───▶┌────────────────────────────────────────────────┐
   (built binaries)    │  package_all.sh  (per component loop)            │
                       │                                                  │
                       │  1. version = extract_version(tag)+VERSION_SUFFIX│
                       │     (or extract_version_nightly + VERSION_SUFFIX)│
                       │                                                  │
   binary paths ──────▶│  2. detect_runtime_depends(bin...)               │
                       │       ldd <bin> ─▶ resolved .so paths            │
                       │       dpkg-query -S <path> ─▶ owning package     │
                       │       drop libc6/libgcc-s1 (D-02 exclusions)     │
                       │       dedupe ─▶ DEPENDS list                     │
                       │       (hard-fail if any path unresolved — D-03)  │
                       │                                                  │
                       │  3. render nFPM yaml:                            │
                       │       ${VERSION} ${ARCH} ${DESTDIR}              │
                       │       + inject detected DEPENDS block            │
                       │       (envsubst + generated depends fragment)    │
                       │                                                  │
                       │  4. nfpm pkg --packager deb ─▶ output/*.deb      │
                       └───────────┬─────────────────────────────────────┘
                                   ▼
                       ┌────────────────────────┐      ┌──────────────────────────┐
                       │  output/*.deb          │─────▶│  in-phase verification    │
                       └────────────────────────┘      │  - dpkg --compare-versions│
                                                        │    (D-11 a/b/c)           │
                                                        │  - 24.04 functional       │
                                                        │    equivalence (D-14)     │
                                                        │  - 26.04 container        │
                                                        │    apt install smoke      │
                                                        └──────────────────────────┘
```

### Recommended Project Structure

No new files strictly required. Logical placement of new code:

```
config.sh                       # ADD: distro detection + VERSION_SUFFIX composition (D-05/06/07/08)
functions.sh                    # ADD: detect_runtime_depends(); distro-detect helper (keeps config.sh thin)
scripts/package_all.sh          # MODIFY: remove hardcoded VERSION_SUFFIX line 29; remove
                                #         detect_crun_parser_depend (D-04); call detect_runtime_depends
                                #         per component; inject depends block before nfpm
packaging/nfpm/*.yaml           # MODIFY: delete hardcoded system-lib depends; keep internal podman-* deps;
                                #         add a single ${..._DEPENDS} injection point (D-12/D-13)
scripts/verify_versions.sh      # NEW (suggested): D-11 dpkg --compare-versions assertions, CI-agnostic
```

### Pattern 1: Generalized ldd → dpkg-query dependency detection (the D-01/D-04 generalization)
**What:** One function that takes one-or-more binary paths, enumerates their resolved shared libraries, maps each to its owning package, excludes the always-present base packages, dedupes, and fails hard on any unmapped library.
**When to use:** Once per packaged component that ships native binaries (podman, buildah, skopeo, crun, conmon, netavark, aardvark-dns, pasta, fuse-overlayfs, catatonit). Pure-data components (container-configs, toolbox if scripts-only) have no native deps.
**Example:**
```bash
# Source: generalization of detect_crun_parser_depend() in scripts/package_all.sh (existing precedent)
# Excludes per D-02; hard-fails per D-03; absorbs crun parser special case per D-04.
detect_runtime_depends() {
    # Args: one or more absolute paths to ELF binaries in DESTDIR
    local -A pkgs=()           # set of owning packages (dedupe)
    local bin lib pkg
    # Base packages present on every Debian/Ubuntu system — never declared (D-02)
    local -a EXCLUDE=( libc6 libgcc-s1 )

    for bin in "$@"; do
        [[ -x "${bin}" ]] || { echo "ERROR: binary not found/executable: ${bin}" >&2; return 1; }
        # ldd resolves each NEEDED soname to an absolute on-disk path.
        # Field 3 ("=> /path/so") is the resolved object; skip ld-linux / vdso lines.
        while read -r lib; do
            [[ -n "${lib}" && -e "${lib}" ]] || continue
            # Map resolved path -> owning package. dpkg-query prints "pkg:arch: path".
            if ! pkg=$(dpkg-query -S "$(realpath "${lib}")" 2>/dev/null | awk -F: '{print $1}' | head -n1); then
                echo "ERROR: no owning package for ${lib} (linked by ${bin})" >&2   # D-03 hard fail
                return 1
            fi
            [[ -z "${pkg}" ]] && { echo "ERROR: unresolved package for ${lib} (${bin})" >&2; return 1; }
            # strip :arch multiarch qualifier if present (dpkg-query already split on ':')
            pkgs["${pkg}"]=1
        done < <(ldd "${bin}" | awk '/=> \// {print $3}')
    done

    # Emit sorted, deduped, minus exclusions
    local out
    for pkg in "${!pkgs[@]}"; do
        local skip=0
        for ex in "${EXCLUDE[@]}"; do [[ "${pkg}" == "${ex}" ]] && skip=1; done
        [[ "${skip}" -eq 0 ]] && out+="${pkg}"$'\n'
    done
    printf '%s' "${out}" | sort -u
}
```
> Note: `awk '/=> \//'` deliberately matches only lines with a resolved `=> /path`. `linux-vdso.so.1` (no path) and the `ld-linux` loader line are excluded naturally. Verify the exact awk field handling on a real 24.04/26.04 host during Wave 0 — `ldd` output spacing is stable but worth a smoke check.

### Pattern 2: Distro detection + suffix composition in config.sh (D-05/06/07/08)
**What:** Read os-release, honor `DISTRO` override, compose the single `VERSION_SUFFIX`.
**When to use:** Once, at config load. Follows the existing `ARCH="${ARCH:-$(detect_architecture)}"` override idiom.
**Example:**
```bash
# Source: new code; mirrors existing ARCH override pattern in config.sh
# DISTRO override form: "ubuntu24.04" / "ubuntu26.04" OR raw VERSION_ID — pick ONE convention
# and document it. Recommended: DISTRO holds the VERSION_ID (e.g. "26.04"); ID is read from os-release.
detect_distro_version_id() {
    if [[ -n "${DISTRO:-}" ]]; then echo "${DISTRO}"; return; fi   # D-06 override
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        echo "${VERSION_ID:?VERSION_ID missing from /etc/os-release}"
        return
    fi
    echo "ERROR: cannot determine distro: no DISTRO override and /etc/os-release unreadable" >&2
    return 1
}

DISTRO_VERSION_ID="$(detect_distro_version_id)"
export VERSION_SUFFIX="~ubuntu${DISTRO_VERSION_ID}.podman1"   # D-07/D-08
```
> Decide and document whether `DISTRO` carries `26.04` (VERSION_ID only) or `ubuntu26.04`. Success-criterion 1 uses `DISTRO=2604`; CONTEXT D-06 says "DISTRO env var overrides." Reconcile this in planning: the cleanest is `DISTRO` = VERSION_ID string (`26.04`), and the `2604` form in the success criterion is a CI-label convention to be normalized. Flag for the planner.

### Pattern 3: Injecting a variable-length depends list into nFPM (Claude's-Discretion resolution)
**What:** nFPM's `depends:` is a YAML string array. A single `${VAR}` can only fill ONE list entry; a variable number of detected packages needs a different shape.
**Recommendation (most robust, zero new tools):** Generate the entire `depends:` block as a text fragment and substitute it as one multi-line value, OR keep static internal deps in the YAML and append a generated block. Concretely:

```yaml
# packaging/nfpm/crun.yaml  (D-13 internal deps stay; system libs come from injection)
depends:
${DETECTED_DEPENDS}
```
```bash
# In package_all.sh, build a YAML list fragment from the detected set:
DETECTED_DEPENDS="$(detect_runtime_depends "${DESTDIR}/usr/bin/crun" \
  | sed 's/^/  - /')"                       # "  - libseccomp2\n  - libsystemd0\n  - libcap2\n  - libjson-c5"
export DETECTED_DEPENDS
# envsubst with a multi-line value preserves newlines:
envsubst '${VERSION} ${ARCH} ${DESTDIR} ${DETECTED_DEPENDS}' < "${NFPM_DIR}/crun.yaml" > "${nfpm_config}"
```
> Why this over alternatives: (a) **yq injection** works but adds a tool not currently in the toolchain — avoid per "closest to existing patterns." (b) **nFPM native `${VAR}` per entry** can't express a variable count. (c) **per-package generated YAML from scratch** duplicates the static content (contents, conflicts, provides) and is brittle. The fragment-substitution approach reuses the existing envsubst step and keeps each YAML the single source of its static metadata.
> **YAML-indentation caveat:** the generated lines must carry the correct two-space indentation (the `sed 's/^/  - /'`), and the `${DETECTED_DEPENDS}` placeholder must sit at column 0 under `depends:`. Verify rendered YAML parses (`nfpm pkg --config ...` will fail loudly on bad YAML). Components that mix static internal deps (podman, buildah, skopeo) with detected system libs: keep the static `- podman-*` lines literal in the YAML and place `${DETECTED_DEPENDS}` after them.

### Anti-Patterns to Avoid
- **String-equality no-regression check (D-14):** Comparing detected names to the old hardcoded strings will FALSE-FAIL on 24.04 because of t64 transitional packages (`libgpgme11` hardcoded vs `libgpgme11t64` detected). Compare *functional* resolution instead (see Pitfall 1).
- **Codename in version string:** `~noble` / `~resolute` sorts alphabetically and breaks dist-upgrades (Docker moby/for-linux #1315). Already banned by REQUIREMENTS Out-of-Scope and avoided by D-08's numeric `~ubuntu24.04` form. Do not reintroduce.
- **Silent fallback to hardcoded names on detection failure:** Violates D-03. A missing soname mapping is a real defect (e.g. a build that didn't link what it should). Fail the build.
- **Running `ldd` on untrusted binaries:** `ldd` may invoke the dynamic loader. Safe here (binaries are freshly built from pinned source) but never point this function at arbitrary input.
- **Forgetting pasta's binary name:** pasta ships `/usr/bin/passt` and `/usr/bin/pasta`; detect deps from both (and note pasta's YAML currently declares NO system deps — detection may now add some).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Soname → package mapping | A hand-maintained lookup table of `libfoo.so.N → libfooN` | `dpkg-query -S <resolved-path>` | The whole point of PKG-10: a static table is exactly the trap that broke 26.04. The host package DB is always correct for the host distro. |
| Version comparison logic | Custom Bash/awk version-sorting | `dpkg --compare-versions A op B` | Debian version semantics (epochs, tildes, `~`-before-empty) are subtle and already implemented authoritatively. D-11 mandates it. |
| Listing a binary's runtime libs | Parsing `readelf -d` DT_NEEDED + manual path search | `ldd` (then dpkg-query on the resolved path) | `ldd` resolves to on-disk paths in one step; matches the existing `detect_crun_parser_depend()` precedent. |
| Detecting the distro | Parsing `lsb_release` output or hardcoding | Source `/etc/os-release` (`ID`/`VERSION_ID`) | Freedesktop standard, present on all targets, no extra package (lsb_release isn't always installed). |
| crun parser dep special-case | Keeping `detect_crun_parser_depend()` alongside the general one | The general `detect_runtime_depends()` | D-04: the general mechanism naturally detects `libjson-c5` vs `libyajl2` from crun's actual link. Two code paths = drift risk. |

**Key insight:** Every "don't hand-roll" item here is a restatement of why this phase exists. The pre-v3.0 pipeline *did* hand-roll the soname→package table, and that table is precisely what silently broke on 26.04. The mechanism replaces human-maintained knowledge with a query against ground truth (the build host's own package database).

## Runtime State Inventory

> This is a build-pipeline refactor (not a rename of a deployed/runtime-registered identity), but it touches version strings and dependency declarations that flow into published artifacts. Reviewed against all five categories:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **None** — no datastore keys, collection names, or user_ids reference the version suffix or dep names. The only "stored" forms are `.deb` control files, regenerated each build. | None |
| Live service config | **The published APT repo (Phase 15/20 territory).** Already-published 24.04 `.deb`s carry the OLD `~podman1` suffix; new builds carry `~ubuntu24.04.podman1`. Per dpkg tilde semantics `5.5.2~podman1` vs `5.5.2~ubuntu24.04.podman1` both sort below `5.5.2`, **but they do not have a guaranteed order relative to each other** (`podman1` vs `ubuntu24...`: `p` > `u`? no — compared char by char, `~podman1` vs `~ubuntu24.04.podman1`: after the shared `~`, `p`(0x70) vs `u`(0x75) → `p` < `u` → the OLD `~podman1` sorts BELOW the new `~ubuntu24.04.podman1`). So existing installs upgrade cleanly to the new suffix. **Verify this with `dpkg --compare-versions` as part of D-11 (add a 4th assertion: old `~podman1` form < new `~ubuntu24.04.podman1` form).** | Add verification assertion; no data migration (apt handles upgrade) |
| OS-registered state | **None** — no systemd units, cron, Task Scheduler, or launchd entries embed the version suffix or dep names. The `.deb`s ship systemd units but those are content, not registrations keyed on the version. | None |
| Secrets/env vars | **`DISTRO` is a new env var** (override, D-06) and `VERSION_SUFFIX` changes meaning. No secret keys involved. CI workflow (`build-packages.yml`) sets no conflicting var today. | Document `DISTRO` override in any setup/CI docs (Phase 22) |
| Build artifacts | **`/tmp/nfpm-*.yaml` rendered configs** are regenerated each run — no stale-artifact risk. Output `.deb` filenames will change (new version string in filename); any tooling that globs `output/*.deb` is unaffected (still globs). | None — but Phase 20/21 repo publishing must expect the new filename pattern |

**Canonical question answered:** After every repo file is updated, the only "old string still live" is **already-published `.deb` packages in the APT repo** carrying `~podman1`. That is handled by apt's normal upgrade path (the suffix change sorts upward), and the safety of that ordering is exactly what the D-11 verification (plus the suggested 4th assertion) must prove. Nothing else in any runtime system caches the version suffix or dependency names.

## Common Pitfalls

### Pitfall 1: t64 transition makes the 24.04 "no-regression" check a false-failure trap
**What goes wrong:** D-14 says "the detected dependency set on ubuntu:24.04 must exactly equal the current hardcoded set." Run literally as string equality, it FAILS — because the hardcoded YAMLs say `libgpgme11` / `libglib2.0-0`, but `ldd → dpkg-query` on a real 24.04 host resolves the linked `.so` to `libgpgme11t64` / `libglib2.0-0t64`.
**Why it happens:** Ubuntu 24.04's 64-bit `time_t` transition renamed every runtime package whose ABI exposes `time_t`. `libgpgme11` and `libglib2.0-0` still *exist on 24.04* but only as **transitional dummy packages** that `Depends: libgpgme11t64` / `libglib2.0-0t64`. The current pipeline installs fine because apt pulls the real lib through the dummy. The detector, querying the real `.so`, correctly returns the t64 name.
**How to avoid:** Interpret D-14 as **functional equivalence**, not string identity. The no-regression proof should assert: for each component, `apt-get install --simulate` (or `apt-cache depends` resolution) of the detected dep set pulls the *same physical libraries* as the old hardcoded set. Equivalently: the detected set is the old set with each t64-transitioned name replaced by its `t64` form, and `dpkg -S $(ldd ...)` confirms the dummy↔real relationship. **Plan a task that documents the expected detected-vs-hardcoded delta on 24.04 (which names gain `t64`) so the check is a known, asserted mapping — not a surprise.** Affected names (verify on host): `libgpgme11→libgpgme11t64`, `libglib2.0-0→libglib2.0-0t64`. NOT affected (no t64): `libseccomp2`, `libsystemd0`, `libcap2`, `libsqlite3-0`, `libsubid4` (subid is not time_t-affected on 24.04), `libyajl2`/`libjson-c5`.
**Warning signs:** A no-regression test that diffs raw dependency strings and reports unexpected `t64` additions on 24.04. That is the mechanism working correctly, not a bug.

### Pitfall 2: Version-suffix ordering must be proven, not assumed
**What goes wrong:** Choosing a suffix that *looks* right but sorts wrong (e.g. a codename, or a form where 24.04 sorts above 26.04, or above the official upstream).
**Why it happens:** dpkg version comparison is non-obvious: `~` sorts *before* the empty string (so `5.5.2~anything` < `5.5.2`), and the rest is a digit/non-digit alternating comparison. The `~ubuntu24.04` vs `~ubuntu26.04` ordering works because after the shared `~ubuntu` prefix, `24` < `26` numerically.
**How to avoid:** D-11 mandates `dpkg --compare-versions`. Make these assertions a hard test (suggested `scripts/verify_versions.sh`):
- `5.5.2~ubuntu24.04.podman1` **lt** `5.5.2` (yields to official)
- `5.5.2~ubuntu24.04.podman1` **lt** `5.5.2~ubuntu26.04.podman1` (dist-upgrade order)
- nightly `5.9.0~git20260306.abc1234~ubuntu24.04.podman1` **lt** tagged `5.9.0~ubuntu24.04.podman1`
- **(add)** old `5.5.2~podman1` **lt** new `5.5.2~ubuntu24.04.podman1` (existing installs upgrade — see Runtime State Inventory)
**Warning signs:** Any of the above returning the wrong boolean. `dpkg --compare-versions` exits 0/1; wire it into a failing test.

### Pitfall 3: `${DETECTED_DEPENDS}` indentation / empty-list edge cases break nFPM YAML
**What goes wrong:** A component with zero detected system deps (e.g. a pure-Go static-ish binary, or pasta if it links nothing beyond libc) renders `depends:` with an empty or malformed block; or wrong indentation makes nFPM reject the YAML.
**Why it happens:** YAML is whitespace-sensitive; an empty `depends:` followed by nothing, or a list item at the wrong column, is invalid.
**How to avoid:** When the detected set (after exclusions) is empty AND there are no static internal deps, omit the `depends:` key entirely for that render. For components with static internal `podman-*` deps, keep those literal and append the detected block. Validate by letting `nfpm pkg` parse it (it fails loudly). Add a render-and-parse smoke test in Wave 0.
**Warning signs:** `nfpm` errors like "yaml: line N: ..." or a `.deb` with an empty/garbled `Depends:` control field (`dpkg-deb -f pkg.deb Depends`).

### Pitfall 4: `dpkg-query -S` and multiarch / symlink resolution
**What goes wrong:** `ldd` may report a symlinked path (`/lib/x86_64-linux-gnu/libfoo.so.5 -> libfoo.so.5.1.2`); `dpkg-query -S` must be given a path the package DB knows about, and may print a `pkg:arch` qualifier.
**Why it happens:** Multiarch installs files under `/usr/lib/<triplet>/`; dpkg records the real file path; symlinks vs targets can differ in which is package-owned.
**How to avoid:** `realpath` the `ldd` result before `dpkg-query -S` (the example does this), and strip the `:arch` qualifier from the package name (`awk -F: '{print $1}'`). Test on both amd64 and arm64 runners (the pipeline builds both — see `build-packages.yml` `ubuntu-24.04-arm`).
**Warning signs:** Package names coming back as `libfoo5:amd64` (qualifier leaked into Depends) or `dpkg-query: no path found matching pattern` on a symlink.

## Code Examples

### D-11 version-ordering assertions (CI-agnostic)
```bash
# Source: dpkg deb-version(5) semantics — https://manpages.ubuntu.com/manpages/noble/man5/deb-version.5.html
# Exit 0 if relation true, 1 if false. Wire each into a hard test.
assert_lt() {
  if dpkg --compare-versions "$1" lt "$2"; then
    echo "OK: $1 < $2"
  else
    echo "FAIL: expected $1 < $2" >&2; exit 1
  fi
}
assert_lt "5.5.2~ubuntu24.04.podman1" "5.5.2"                                   # yields to official
assert_lt "5.5.2~ubuntu24.04.podman1" "5.5.2~ubuntu26.04.podman1"              # 24.04 < 26.04
assert_lt "5.9.0~git20260306.abc1234~ubuntu24.04.podman1" "5.9.0~ubuntu24.04.podman1"  # nightly < tagged
assert_lt "5.5.2~podman1" "5.5.2~ubuntu24.04.podman1"                          # old install upgrades
```

### 26.04 install smoke (Claude's-Discretion verification vehicle)
```bash
# Source: standard docker/podman-in-CI pattern; no external deps beyond a container runtime.
# Runs the built .deb against a real 26.04 userland to prove PKG-08 renamed deps resolve.
docker run --rm -v "$PWD/output:/out" ubuntu:26.04 bash -c '
  set -euo pipefail
  apt-get update
  # apt install of a local .deb pulls declared deps from the 26.04 archive;
  # if a dep name is wrong (e.g. libgpgme11 instead of libgpgme45) this FAILS here.
  apt-get install -y /out/podman-skopeo_*_amd64.deb
  command -v skopeo && skopeo --version
'
```
> Planner: pick docker or podman as the runner depending on what the CI host has (Phase 18/21 context). On a self-hosted or GH runner without a real 26.04 image yet, `ubuntu:26.04` may be `devel`-tagged until GA — note STATE.md's Phase 21 flag about runner GA timing. The container approach works regardless of runner OS.

### crun parser dep falls out of the general detector (D-04 proof)
```bash
# Before (special case, to be DELETED):
#   detect_crun_parser_depend() { ldd crun | grep libjson-c.so.5 && echo libjson-c5; ... }
# After: detect_runtime_depends "${DESTDIR}/usr/bin/crun" naturally returns whichever of
#   libjson-c5 / libyajl2 crun actually linked, because ldd reports the real .so and
#   dpkg-query -S maps it. No grep on hardcoded sonames remains.
detect_runtime_depends "${DESTDIR}/usr/bin/crun"
#   => libseccomp2 libsystemd0 libcap2 libjson-c5   (example, host-dependent)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hardcoded soname→package names in nFPM YAML | Build-time `ldd`→`dpkg-query -S` detection | This phase (v3.0) | Renames (24.04 t64, 26.04 gpgme/subid) caught automatically |
| `libgpgme11`, `libglib2.0-0` (pre-t64 names) | `libgpgme11t64`, `libglib2.0-0t64` on 24.04 | Ubuntu 24.04 (Feb 2024, 64-bit time_t transition) | Old names survive only as transitional dummies; detector returns t64 names |
| gpgme 1.x `libgpgme11`/`libgpgme11t64` | gpgme 2.0 `libgpgme45` | Ubuntu 26.04 | The user-verified 26.04 breakage that motivates PKG-08 |
| subid `libsubid4` | `libsubid5` | Ubuntu 26.04 | Second user-verified 26.04 rename |
| `~podman1` flat suffix | `~ubuntu{VERSION_ID}.podman1` per-distro suffix | This phase (D-08) | Distinct, sortable, non-colliding per-distro .deb identities |

**Deprecated/outdated:**
- Hardcoded dependency names in `packaging/nfpm/*.yaml` — replaced by detection (D-12).
- `detect_crun_parser_depend()` — absorbed by `detect_runtime_depends()` (D-04).
- `VERSION_SUFFIX="~podman1"` literal at `package_all.sh:29` — replaced by composed value (D-07).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | On 26.04, gpgme 2.0 runtime package is exactly `libgpgme45` and subid is `libsubid5` | State of the Art / PKG-08 | If the exact soname-package differs, detection still self-corrects (that is the point), but the success-criterion test strings would need updating. Detection makes this low-risk. |
| A2 | `libseccomp2`, `libsystemd0`, `libcap2`, `libsqlite3-0`, `libsubid4` were NOT t64-renamed on 24.04 | Pitfall 1 | If one WAS renamed, the expected detected-vs-hardcoded delta on 24.04 differs; verify on a real 24.04 host in Wave 0. Detection still produces the correct name regardless. |
| A3 | `DISTRO` override should carry the `VERSION_ID` string (`26.04`); the `2604` in success-criterion 1 is a CI-label form to normalize | Pattern 2 | If the intended override format is literally `2604`, the composition function needs a normalization step. Planner must reconcile with the success criterion. |
| A4 | nFPM v2.45.0 expands a multi-line `${DETECTED_DEPENDS}` value preserving newlines via envsubst, yielding valid YAML | Pattern 3 | If newline handling mangles the list, fall back to per-package generated YAML or yq injection. Verify with one component in Wave 0. |
| A5 | The published-repo upgrade ordering (`~podman1` < `~ubuntu24.04.podman1`) is the desired/acceptable transition | Runtime State Inventory / Pitfall 2 | Verified by char-comparison reasoning AND must be confirmed by the added `dpkg --compare-versions` assertion. Low risk once asserted. |

## Open Questions (RESOLVED)

1. **`DISTRO` override format (`26.04` vs `2604` vs `ubuntu26.04`)**
   - What we know: D-06 says "DISTRO env var overrides"; success criterion 1 originally showed `DISTRO=2604`; D-08 suffix uses `{VERSION_ID}` = `26.04`.
   - What's unclear: whether the override is the raw VERSION_ID or a compact CI label.
   - Recommendation: Have the composer accept the VERSION_ID form (`26.04`) and, if a compact form like `2604` is desired for CI, normalize `2604`→`26.04` explicitly. Planner should lock one convention and document it. (Tracked as A3.)
   - **RESOLVED (Plan 01 Task 1):** DISTRO carries the dotted VERSION_ID form (`26.04`). `detect_distro_version_id()` regex-validates the value against `^[0-9]+\.[0-9]+$`, so the compact `2604` form is intentionally rejected (no normalization is added — the dotted form is the single documented contract). ROADMAP success criterion 1 was updated to `DISTRO=26.04` to match this resolution.

2. **Exact 24.04 detected-vs-hardcoded delta (the D-14 expected mapping)**
   - What we know: `libgpgme11→libgpgme11t64`, `libglib2.0-0→libglib2.0-0t64` are t64-renamed; others appear unaffected.
   - What's unclear: whether any *other* currently-hardcoded name has a t64 form on 24.04 (low likelihood for the listed set, but unverified on-host).
   - Recommendation: Wave 0 task: on a real ubuntu:24.04, run the detector against each built binary and record the exact output as the asserted baseline. This both validates the mechanism and produces the D-14 reference.
   - **RESOLVED (Plan 04 Task 1):** `scripts/verify_depends.sh` encodes the t64-adjusted baseline (libgpgme11t64/libglib2.0-0t64 substituted for the pre-v3.0 hardcoded names; libseccomp2/libsystemd0/libcap2/libsqlite3-0/libsubid4 unchanged per A2) and asserts D-14 as **functional equivalence**, not string identity, on a real ubuntu:24.04 host. Any undocumented t64 delta beyond the two known names is a FAIL, so the on-host run both confirms A2 and records the asserted baseline.

3. **26.04 image availability for the in-phase smoke test**
   - What we know: STATE.md Phase 21 flag warns `ubuntu-26.04` runner labels may not be GA; container `ubuntu:26.04` is the safe default.
   - What's unclear: whether `ubuntu:26.04` is tagged GA or still `devel`/`resolute` at implementation time.
   - Recommendation: Use the container approach (`docker/podman run ubuntu:26.04`); if the tag isn't GA, fall back to the `resolute` codename tag. Keep the smoke test runner-OS-agnostic.
   - **RESOLVED (Plan 04 Task 2):** `scripts/smoke_install_2604.sh` runs `ubuntu:26.04` with a `resolute` codename fallback, selects the container runtime via `command -v docker`/`podman`, and exposes `SMOKE_RUNTIME`/`SMOKE_IMAGE` overrides — keeping the smoke test runner-OS-agnostic regardless of GA timing.

## Environment Availability

> The build/verify tooling runs on Ubuntu build hosts (native or container), not the macOS dev host where this research ran. Availability below is asserted for the *target* environment (Ubuntu 24.04/26.04 build host), which is the relevant context.

| Dependency | Required By | Available (target) | Version | Fallback |
|------------|------------|--------------------|---------|----------|
| `ldd` | D-01 detection | ✓ (glibc) | host glibc | `readelf -d` + `ldconfig -p` (heavier) |
| `dpkg-query` / `dpkg` | D-01 mapping, D-11 compare | ✓ (base) | host dpkg | none needed |
| `dpkg --compare-versions` | D-11 | ✓ (dpkg) | host dpkg | none needed |
| `envsubst` (gettext-base) | nFPM templating | ✓ (already used) | host | none |
| `/etc/os-release` | D-05 detection | ✓ (base-files/systemd) | — | `DISTRO` override (D-06) |
| nFPM | packaging | ✓ (installed by pipeline) | v2.45.0 pinned | none |
| container runtime (docker/podman) | 26.04 install smoke | ✓ on CI; verify on chosen runner | — | run smoke in a 26.04 native runner if available |
| `ubuntu:26.04` image | 26.04 install smoke | ✗ verify at impl time (may be `devel`/`resolute`) | — | `resolute` codename tag; or defer install proof to Phase 21 matrix |

**Missing dependencies with no fallback:** None for the core mechanism — all detection/versioning tools are base Ubuntu.
**Missing dependencies with fallback:** `ubuntu:26.04` GA image (fallback: `resolute` tag or Phase 21 deferral). Note: this research ran on macOS, so `dpkg`/`nfpm`/`ldd` are **absent on the dev host** — all on-host verification (Wave 0 detector smoke, t64 delta) MUST run on an Ubuntu host/container, not locally.

## Validation Architecture

> `.planning/config.json` was not found / `nyquist_validation` not explicitly false → section included. This project's "tests" are shell-based verification scripts, not a unit framework.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash verification scripts + container smoke (no xUnit framework in repo) |
| Config file | none — see Wave 0 |
| Quick run command | `bash scripts/verify_versions.sh` (D-11 dpkg assertions; runs anywhere dpkg exists) |
| Full suite command | `bash scripts/verify_versions.sh && <build for DISTRO=24.04 + DISTRO=26.04> && <26.04 container apt-install smoke>` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PKG-09 | Version suffixes sort correctly (yield to official, 24.04<26.04, nightly<tagged, old<new) | unit (dpkg oracle) | `bash scripts/verify_versions.sh` | ❌ Wave 0 |
| PKG-10 | Detector returns soname-derived packages; fails hard on unmapped lib | integration (on Ubuntu host) | `bash -c 'source functions.sh; detect_runtime_depends "$DESTDIR/usr/bin/crun"'` | ❌ Wave 0 (needs built DESTDIR on Ubuntu) |
| PKG-08 | 26.04-built .deb `apt install`s on real 26.04 (renamed deps resolve) | smoke (container) | `docker run --rm -v $PWD/output:/out ubuntu:26.04 bash -c 'apt-get update && apt-get install -y /out/podman-skopeo_*.deb'` | ❌ Wave 0 |
| D-14 | 24.04 detected set functionally equals pre-v3.0 set | regression (on 24.04) | compare `apt-get install --simulate` resolution of detected vs old set | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `bash scripts/verify_versions.sh` (fast, dpkg-only, runs even on non-build hosts with dpkg)
- **Per wave merge:** full build for `DISTRO=24.04` + `DISTRO=26.04`, render+parse all nFPM YAMLs, run detector on every component
- **Phase gate:** 26.04 container apt-install smoke green AND 24.04 functional-equivalence green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `scripts/verify_versions.sh` — D-11 dpkg --compare-versions assertions (PKG-09) + the added old<new assertion
- [ ] On-Ubuntu detector smoke harness — run `detect_runtime_depends` on every built binary, record output (establishes D-14 baseline + validates PKG-10 hard-fail path)
- [ ] 26.04 container apt-install smoke script (PKG-08) — parameterize the component/arch
- [ ] nFPM render-and-parse check — confirm `${DETECTED_DEPENDS}` injection yields valid YAML for every component, including the empty-deps and mixed-static-deps cases

## Security Domain

> `security_enforcement` not explicitly `false` in config → section included. This phase is build tooling, not a network/auth surface; the relevant security concerns are supply-chain and command-injection in the build scripts.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth surface in this phase |
| V3 Session Management | no | N/A |
| V4 Access Control | no | N/A |
| V5 Input Validation | yes (low) | `DISTRO` override and os-release `VERSION_ID` feed into a version string and filenames — validate they match an expected pattern (`^[0-9]+\.[0-9]+$` for VERSION_ID) before composing the suffix, to avoid path/shell surprises |
| V6 Cryptography | no | Package signing is Phase 15/20, not here |
| V12 / Supply Chain | yes | Dependency names are derived from the build host's own package DB (`dpkg-query`), not from an external network source — this is *more* trustworthy than a hardcoded table and the right call. No new registry packages installed (no new supply-chain surface). |

### Known Threat Patterns for build-script (Bash) phase
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Unvalidated `DISTRO` / `VERSION_ID` interpolated into version string + filenames | Tampering | Regex-validate `VERSION_ID` (`^[0-9]+\.[0-9]+$`) and `DISTRO` before use; fail closed |
| `ldd` invoking loader on a binary | Elevation (theoretical) | Only run on freshly-built, in-tree binaries (already the case); never on external input |
| Silent dependency fallback masking a mislinked binary | Repudiation / integrity | D-03 hard-fail on any unmapped soname — already locked |
| Word-splitting / unquoted expansion in detection loop | Tampering | `set -euo pipefail` (already project-wide) + quote all path expansions; the example quotes `${lib}`/`${bin}` |

## Sources

### Primary (HIGH confidence)
- `scripts/package_all.sh`, `config.sh`, `functions.sh`, `packaging/nfpm/*.yaml` (codebase) — existing detection precedent (`detect_crun_parser_depend`), version extraction, hardcoded dep inventory, envsubst pipeline
- dpkg `deb-version(5)` — https://manpages.ubuntu.com/manpages/noble/man5/deb-version.5.html and https://manpages.debian.org/wheezy/dpkg-dev/deb-version.5.en.html — tilde-sorts-before-empty semantics, version comparison rules
- Ubuntu version-strings doc — https://documentation.ubuntu.com/project/how-ubuntu-is-made/concepts/version-strings/ — `~`-suffix backport ordering convention
- nFPM configuration docs — https://nfpm.goreleaser.com/docs/configuration/ — `${VAR}` expansion in `depends` and most string fields; "templating not supported"; `contents.src` expansion via `expand: true`
- Ubuntu package pages — https://packages.ubuntu.com/noble/libgpgme11t64 , https://launchpad.net/ubuntu/noble/amd64/libgpgme11 (transitional), https://www.ubuntuupdates.org/package/core/noble/main/base/libgpgme11t64 — confirms 24.04 t64 rename + transitional dummy

### Secondary (MEDIUM confidence)
- Debian Wiki ReleaseGoals/64bit-time — https://wiki.debian.org/ReleaseGoals/64bit-time — why/which packages got t64 renamed (libraries exposing time_t in ABI)
- aptly issue #1318 — https://github.com/aptly-dev/aptly/issues/1318 — confirms `libglib2.0-0t64` naming in 24.04
- Ubuntu 26.04 release notes / repology gpgme — https://documentation.ubuntu.com/release-notes/26.04/ , https://repology.org/project/gpgme/packages — gpgme 2.0 presence in resolute (basis for `libgpgme45`)

### Tertiary (LOW confidence — flagged for Wave 0 on-host verification)
- Exact 26.04 binary package names (`libgpgme45`, `libsubid5`) — user-verified in CONTEXT.md; not re-confirmed against packages.ubuntu.com 26.04 listing in this session (pkgs.org returned HTTP 402). Detection mechanism makes the exact string self-correcting, so risk is low — but Wave 0 should record the actual detected names on a 26.04 host.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all tools host-native, existing precedent in repo, behavior verified against dpkg/nfpm docs
- Architecture: HIGH — generalization of an existing working function; injection pattern reuses existing envsubst step
- Pitfalls: HIGH — t64 transition and tilde semantics confirmed against authoritative Ubuntu/Debian sources; the t64 false-failure trap is the key non-obvious finding
- 26.04 exact package names: MEDIUM — user-verified + repology-corroborated, not re-fetched from 26.04 archive this session; mitigated by self-correcting detection

**Research date:** 2026-06-05
**Valid until:** 2026-07-05 (stable domain — dpkg/nFPM semantics and the 24.04 t64 facts are fixed; the only moving target is 26.04 image GA timing, re-check at Phase 21)
