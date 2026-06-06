# Phase 19: Per-Distro Versioning & Dependency Mapping - Context

**Gathered:** 2026-06-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Build-side per-distro package identity: each distro's `.deb` carries a distinct version suffix (`~ubuntu24.04.podman1` vs `~ubuntu26.04.podman1`) and declares runtime dependencies that actually exist on that distro, derived at build time from the binaries' linked sonames instead of hardcoded names — with zero regression to the shipping 24.04 pipeline.

In scope: version suffix composition, distro detection, ldd-based dependency resolution, nFPM config changes, in-phase verification of version ordering and 24.04 dep equivalence.
Out of scope (later phases): repository suites/aliases (Phase 20), CI build matrix (Phase 21), docs/smoke tests (Phase 22).

</domain>

<decisions>
## Implementation Decisions

User directive: "Apply best practices" — all four gray areas resolved by Claude using best practices, grounded in existing codebase precedents. Decisions below are locked.

### Dependency detection mechanism
- **D-01:** Runtime system library deps are resolved at build time per binary: `ldd` extracts resolved library paths → `dpkg -S` (or `dpkg-query -S`) maps each path to its owning package on the build host. This mirrors Debian's own `dpkg-shlibdeps` approach and satisfies PKG-10 (future renames caught automatically, no manual config edits).
- **D-02:** Base packages guaranteed present on any Debian/Ubuntu system (`libc6`, `libgcc-s1` — priority: required) are excluded from the generated depends list, matching current hardcoded behavior.
- **D-03:** Detection failure (soname whose owning package cannot be resolved) is a HARD build failure with a clear error message. No silent fallback to stale hardcoded names. Consistent with the existing `detect_crun_parser_depend()` precedent and the project's fail-early philosophy.
- **D-04:** The existing crun parser special case (`${CRUN_PARSER_DEPEND}`, libjson-c5 vs libyajl2) is absorbed by the general detection mechanism — no separate special-case code remains.

### Distro identity plumbing
- **D-05:** Distro is auto-detected from `/etc/os-release` (`ID` + `VERSION_ID`) of the build environment. Builds always run ON the target distro (native runner or `ubuntu:26.04` container per CICD-06), so os-release is authoritative.
- **D-06:** An explicit `DISTRO` environment variable overrides auto-detection (for testing/forcing). Follows the project's established "environment variable overrides" pattern.
- **D-07:** The version suffix is composed once in `config.sh` (single source of truth — matches the centralized Go cache precedent) and consumed by `scripts/package_all.sh`. The hardcoded `VERSION_SUFFIX="~podman1"` in `package_all.sh:29` is replaced by the composed per-distro value.

### Version string composition
- **D-08:** Suffix form: `~ubuntu{VERSION_ID}.podman1` (e.g. `5.5.2~ubuntu24.04.podman1`). The trailing `.podman1` is retained as a repackaging revision counter.
- **D-09:** Nightly form: distro suffix replaces the current trailing `~podman1`, yielding `{base}~git{YYYYMMDD}.{sha}~ubuntu{VERSION_ID}.podman1` (extends the Phase 18-01 tilde convention).
- **D-10:** pasta keeps its date-based base version; the same distro suffix is appended (e.g. `20250302~ubuntu24.04.podman1`) — identical treatment to today's `~podman1` handling.
- **D-11:** In-phase verification MUST assert with `dpkg --compare-versions`: (a) suffixed version < plain upstream version, (b) 24.04 form < 26.04 form of the same upstream version, (c) nightly form < tagged-release form. This closes the STATE.md v3.0 research flag for Phase 19.

### Scope of dependency replacement
- **D-12:** ALL hardcoded system library deps across the nFPM YAMLs (`libgpgme11`, `libseccomp2`, `libsystemd0`, `libcap2`, `libglib2.0-0`, `libsubid4`, `libsqlite3-0`) are replaced by the build-time detected set. No half-measure of mapping only the renamed packages — that would leave the same trap armed for the next rename. *(Historical hardcoded inventory. NOTE: `libsqlite3-0` was a stale skopeo datum — skopeo v1.22.0 links no sqlite; removed from the skopeo baseline in Plan 05, see 19-UAT.md.)*
- **D-13:** Internal suite deps (`podman-crun`, `podman-conmon`, etc.) stay static in the nFPM YAMLs — they are package-level relationships, not soname-derived.
- **D-14:** No-regression guardrail (success criterion 4): the detected dependency set on ubuntu:24.04 must exactly equal the current hardcoded set per package. This equivalence check is the proof the mechanism works before it ships.

### Claude's Discretion
- Templating mechanism for injecting a multi-entry `depends:` list into nFPM configs — envsubst single-variable substitution is awkward for YAML lists. Researcher/planner decides: generated depends block, nFPM native templating, yq-based injection, or per-package generated YAML. Pick whatever is most robust and closest to existing patterns.
- How to validate 26.04 installability within this phase (before the Phase 21 CI matrix exists) — e.g. local container run of `ubuntu:26.04` with `apt install` of the built .deb. Planner picks the verification vehicle.
- Exact exclusion-list contents beyond `libc6`/`libgcc-s1` if detection surfaces other priority-required libs on 26.04.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` — Phase 19 goal and 4 success criteria (renamed deps resolve on real 26.04; distinct sortable version strings; ldd-derived deps; 24.04 no-regression)
- `.planning/REQUIREMENTS.md` — PKG-08, PKG-09, PKG-10 definitions; Out of Scope table (codename version strings banned — Docker's moby/for-linux #1315 mistake; no 24.04 binaries in 26.04 suite)
- `.planning/PROJECT.md` — v3.0 milestone context: 26.04 verified broken (libgpgme45, libsubid5 renames), forward-compat note, Key Decisions table

### Code this phase modifies
- `scripts/package_all.sh` — version suffix (`VERSION_SUFFIX` line 29), `extract_version()`, `extract_version_nightly()`, `detect_crun_parser_depend()` (the ldd precedent to generalize), envsubst→nfpm pipeline
- `packaging/nfpm/*.yaml` — 13 package configs; hardcoded system lib deps to replace (podman, buildah, skopeo, crun, conmon carry them)
- `config.sh` — where distro detection and suffix composition land (single source of truth)
- `.github/workflows/build-packages.yml` — current TRACK plumbing; Phase 19 must not break it (matrix extension itself is Phase 21)

No external specs/ADRs exist — requirements fully captured in the refs above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `detect_crun_parser_depend()` in `scripts/package_all.sh` — working ldd→package-name detection with hard-fail semantics; the pattern to generalize for D-01
- envsubst preprocessing of nFPM YAML (`envsubst '${VERSION} ${ARCH} ...' < config.yaml`) — established templating mechanism, though awkward for multi-entry lists (see Claude's Discretion)
- `extract_version()` / `extract_version_nightly()` — version derivation per component; suffix is appended at one place in the packaging loop

### Established Patterns
- `set -euo pipefail` + ERR trap everywhere — detection failures should flow through the same error handler
- Environment variable overrides with sensible defaults — DISTRO override follows this
- Centralized config in `config.sh`, sourced by all scripts — suffix composition belongs there
- Tilde version convention from Phase 18 (`~git{date}.{sha}` sorts below tagged releases)

### Integration Points
- `package_all.sh` packaging loop — exports VERSION/ARCH/DESTDIR per component before nfpm invocation; detected depends plug in here
- CI workflow calls the same scripts — changes must be runner-agnostic (Phase 21 adds the 26.04 matrix cell on top)
- Current hardcoded dep inventory (the regression baseline): podman+buildah: libgpgme11, libseccomp2; skopeo: libgpgme11, libsubid4, libsqlite3-0; crun: libseccomp2, libsystemd0, libcap2 + parser; conmon: libglib2.0-0, libsystemd0. *(Historical pre-v3.0 hardcoded set. NOTE: skopeo's `libsqlite3-0` was found stale on-host — skopeo v1.22.0 links no sqlite; corrected skopeo baseline is `libgpgme11t64 libsubid4`, see Plan 05 / 19-UAT.md.)*

</code_context>

<specifics>
## Specific Ideas

- Known 26.04 renames to verify the mechanism against: `libgpgme11` → `libgpgme45`, `libsubid4` → `libsubid5` (user-verified breakage that motivated this milestone)
- STATE.md research flag (Phase 19): "confirm exact version suffix form with `dpkg --compare-versions` before shipping (must yield to official and sort 24.04 < 26.04)" — covered by D-11

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Generalized N-distro templating is already tracked as future requirement PKG-11.)

</deferred>

---

*Phase: 19-Per-Distro Versioning & Dependency Mapping*
*Context gathered: 2026-06-05*
