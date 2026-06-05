---
phase: 19-per-distro-versioning-dependency-mapping
plan: 02
subsystem: packaging
tags: [bash, nfpm, envsubst, dpkg, dependency-detection, versioning]

# Dependency graph
requires:
  - phase: 19-per-distro-versioning-dependency-mapping
    plan: 01
    provides: "detect_runtime_depends(), detect_distro_version_id(), config.sh VERSION_SUFFIX single source of truth"
provides:
  - "package_all.sh: per-component ${DETECTED_DEPENDS} computed via detect_runtime_depends and injected through envsubst"
  - "package_all.sh: COMPONENT_BINARIES map (DESTDIR-relative ELF paths per component)"
  - "6 nFPM YAMLs (crun/podman/buildah/skopeo/conmon/pasta) declare system deps exclusively via ${DETECTED_DEPENDS}"
  - "hardcoded VERSION_SUFFIX and detect_crun_parser_depend/CRUN_PARSER_DEPEND fully removed"
affects: [phase-19-plan-04, cicd-pipeline]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-component ldd→dpkg-query depends injected as a column-0 YAML fragment via envsubst"
    - "Internal podman-* deps stay literal; system libs are ground-truth-derived (D-12/D-13)"

key-files:
  created: []
  modified:
    - scripts/package_all.sh
    - packaging/nfpm/crun.yaml
    - packaging/nfpm/podman.yaml
    - packaging/nfpm/buildah.yaml
    - packaging/nfpm/skopeo.yaml
    - packaging/nfpm/conmon.yaml
    - packaging/nfpm/pasta.yaml

key-decisions:
  - "DETECTED_DEPENDS placeholder sits at column 0 under depends:; the sed 's/^/  - /' fragment carries its own two-space + '- ' indent, so it merges cleanly with literal internal deps"
  - "No '|| true' around detect_runtime_depends — an unmapped soname aborts the build under set -euo pipefail + ERR trap (D-03 hard-fail preserved)"
  - "pasta passes both binaries (passt + pasta) to a single detection call; container-configs/toolbox have no COMPONENT_BINARIES entry so detection is skipped"

patterns-established:
  - "COMPONENT_BINARIES associative array as the single source for per-component ELF paths"

requirements-completed: [PKG-08, PKG-10]

# Metrics
duration: 2min
completed: 2026-06-05
---

# Phase 19 Plan 02: Wire Detection & Per-Distro Suffix into the Packaging Pipeline Summary

**`package_all.sh` now derives each component's system-library depends from its built binaries via `detect_runtime_depends` and injects them as a `${DETECTED_DEPENDS}` YAML fragment, while the per-distro `VERSION_SUFFIX` from config.sh flows through unchanged — making .deb dependency declarations ground-truth-derived per distro.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-06-05T12:36:16Z
- **Completed:** 2026-06-05T12:38:13Z
- **Tasks:** 2
- **Files modified:** 7 (0 created, 7 modified)

## Accomplishments
- Removed the hardcoded `VERSION_SUFFIX="~podman1"` from `package_all.sh`; config.sh (sourced at line 11, Plan 01) is now authoritative. The four `${VERSION_SUFFIX}` append sites are untouched and now append the per-distro `~ubuntu${DISTRO_VERSION_ID}.podman1`.
- Deleted `detect_crun_parser_depend()` and the entire `CRUN_PARSER_DEPEND` special case (export + crun `if` branch + envsubst allowlist entry). The crun JSON-parser dep now falls out of `detect_runtime_depends` against the host package DB (D-04).
- Added the `COMPONENT_BINARIES` associative array mapping each component that ships native ELF binaries to its DESTDIR-relative path(s); pasta carries both `passt` and `pasta`; container-configs and toolbox have no entry.
- Rewired the per-component packaging block to compute `DETECTED_DEPENDS` via `detect_runtime_depends "${component_bins[@]}" | sed 's/^/  - /'`, export it, and pass it through the envsubst allowlist (`${VERSION} ${ARCH} ${DESTDIR} ${DETECTED_DEPENDS}`). Hard-fail is preserved — no `|| true`.
- Converted the 6 target nFPM YAMLs to inject `${DETECTED_DEPENDS}` at column 0 under `depends:`, removing every hardcoded system-lib line (libseccomp2, libsystemd0, libcap2, libgpgme11, libglib2.0-0, libsubid4, libsqlite3-0) while keeping internal `podman-*` deps literal (8 in podman, `podman-container-configs` in buildah/skopeo). pasta gained a `depends:` block it did not have before.

## Task Commits

Each task was committed atomically:

1. **Task 1: rewire package_all.sh (suffix + crun special-case removal + per-component detection)** - `2d0a029` (refactor)
2. **Task 2: convert 6 nFPM YAMLs to ${DETECTED_DEPENDS} injection** - `5c6aa3b` (refactor)

## Files Created/Modified
- `scripts/package_all.sh` - Removed hardcoded suffix line and `detect_crun_parser_depend()`; added `COMPONENT_BINARIES` map; replaced the per-component export+envsubst block with `detect_runtime_depends`-driven `DETECTED_DEPENDS` injection.
- `packaging/nfpm/crun.yaml` - All four system-lib lines (incl. `${CRUN_PARSER_DEPEND}`) replaced by column-0 `${DETECTED_DEPENDS}`.
- `packaging/nfpm/podman.yaml` - Dropped `libgpgme11`, `libseccomp2`; kept all 8 internal `podman-*` deps; appended placeholder.
- `packaging/nfpm/buildah.yaml` - Dropped `libgpgme11`, `libseccomp2`; kept `podman-container-configs`; appended placeholder.
- `packaging/nfpm/skopeo.yaml` - Dropped `libgpgme11`, `libsubid4`, `libsqlite3-0`; kept `podman-container-configs`; appended placeholder.
- `packaging/nfpm/conmon.yaml` - Both system-lib lines replaced by column-0 placeholder.
- `packaging/nfpm/pasta.yaml` - Added a new `depends:` block with `${DETECTED_DEPENDS}` between the header fields and `conflicts:`.

## Decisions Made
- **Column-0 placeholder + self-indented fragment:** `${DETECTED_DEPENDS}` is written at column 0 under `depends:`. Verified via a render simulation (`envsubst` with a two-line stand-in fragment) that the output is well-formed YAML — entries land at the correct two-space indent and merge cleanly below literal internal deps. An empty fragment leaves a blank line, which YAML tolerates (Plan 04's render-and-parse smoke is the loud gate for any garbled/empty case).
- **No fallback around detection:** kept the D-03 hard-fail contract — the detection call has no `|| true`, so an unmapped library aborts the build.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- **macOS dev-host verify limitation (expected, environment-scoped):** `dpkg-query` and `ldd` are Linux-only, so `detect_runtime_depends` cannot run against real ELF binaries here. This plan's automated checks are syntax (`bash -n`) + structural greps + an `envsubst` render simulation with a stand-in fragment — all of which pass on macOS. End-to-end proof (real detection on built binaries, rendered-YAML parse, .deb `Depends` field) is deferred to Plan 04 on an Ubuntu host, per the phase validation strategy.

## Threat Surface
All three mitigations from the plan's threat register are honored: detected names come only from the host package DB via `detect_runtime_depends` (T-19-05); the detection call has no silent fallback (T-19-06 / D-03); all `${DESTDIR}/<path>` expansions and the `component_bins` array use quoted static repo-controlled values (T-19-07). No new security-relevant surface introduced.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The packaging pipeline now produces per-distro version identity and ground-truth depends. **Plan 04** exercises the dpkg/ldd-dependent behavior on an Ubuntu host: real detection on built binaries, render-and-parse smoke of the injected fragment, hard-fail on an unmapped soname, and the 26.04 install smoke (libgpgme45/libsubid5 rename pickup).
- netavark/aardvark-dns keep their single internal dep with no injection point this plan; fuse-overlayfs/catatonit stay unchanged (their real detected set, if any, is surfaced and added only in Plan 04).
- No blockers.

## Self-Check: PASSED

- FOUND: scripts/package_all.sh
- FOUND: packaging/nfpm/crun.yaml
- FOUND: packaging/nfpm/podman.yaml
- FOUND: packaging/nfpm/buildah.yaml
- FOUND: packaging/nfpm/skopeo.yaml
- FOUND: packaging/nfpm/conmon.yaml
- FOUND: packaging/nfpm/pasta.yaml
- FOUND: 2d0a029 (Task 1 refactor)
- FOUND: 5c6aa3b (Task 2 refactor)

---
*Phase: 19-per-distro-versioning-dependency-mapping*
*Completed: 2026-06-05*
