---
phase: 14-debian-package-building
plan: 02
subsystem: packaging
tags: [nfpm, deb, shell-scripting, orchestrator, version-extraction]

# Dependency graph
requires:
  - phase: 14-debian-package-building
    plan: 01
    provides: "DESTDIR staging in build scripts and 13 nFPM YAML configs"
provides:
  - "scripts/package_all.sh orchestrator that invokes nFPM for all 12 components + meta-package"
  - "extract_version() function handling v-prefix, date-based, and namespaced tag patterns"
  - "Version suffix ~podman1 appended to all packages"
affects: [15-apt-repository-and-signing, 16-ci-cd-pipeline]

# Tech tracking
tech-stack:
  added: []
  patterns: [nfpm-orchestrator, version-extraction-3-patterns, component-tag-mapping]

key-files:
  created:
    - scripts/package_all.sh
  modified: []

key-decisions:
  - "Used associative array for component-to-tag mapping rather than case statement for cleaner iteration"
  - "Pasta version uses live date calculation matching build_pasta.sh pattern"

patterns-established:
  - "extract_version() dispatches on component name for 3 version patterns: strip v, date passthrough, namespace strip"
  - "nFPM invocation: export VERSION/ARCH/DESTDIR then nfpm pkg --config --target --packager deb"
  - "Suite meta-package uses podman's version as its own version"

requirements-completed: [PKG-01, PKG-04, PKG-05, PKG-06]

# Metrics
duration: 2min
completed: 2026-03-05
---

# Phase 14 Plan 02: Packaging Orchestrator Script Summary

**nFPM packaging orchestrator iterating 12 components plus meta-package with 3-pattern version extraction and ~podman1 suffix**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-05T09:47:38Z
- **Completed:** 2026-03-05T09:49:50Z
- **Tasks:** 1/1
- **Files modified:** 1 (1 created)

## Accomplishments
- Created scripts/package_all.sh that iterates all 12 Podman components and invokes nFPM to produce .deb packages from a populated DESTDIR staging tree
- Implemented extract_version() handling three version patterns: standard v-prefix stripping, pasta date-based passthrough, and container-configs namespaced tag extraction
- Added prerequisite validation for DESTDIR existence, nfpm availability, and nFPM config directory with actionable error messages

## Task Commits

Each task was committed atomically:

1. **Task 1: Create packaging orchestrator script** - `74262a1` (feat)

## Files Created/Modified

### Created
- `scripts/package_all.sh` - Packaging orchestrator: validates prerequisites, maps 12 components to version tags, extracts clean versions, appends ~podman1 suffix, invokes nFPM for each component plus suite meta-package, prints summary with file names and sizes

## Decisions Made
- **Associative array for tag mapping:** Used `declare -A COMPONENT_TAGS` to map component names to their config.sh tag variables. This is cleaner than a case statement and allows the iteration loop to stay simple.
- **Pasta date at orchestrator runtime:** Pasta version uses `$(date +"%Y%m%d")` at packaging time (matching build_pasta.sh), meaning the package version reflects when packaging ran, consistent with the build timestamp.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 14 (Debian Package Building) is now complete with both DESTDIR staging and the packaging orchestrator
- To build packages: run build scripts with DESTDIR set, then run `./scripts/package_all.sh`
- Phase 15 (APT Repository and Signing) can consume the .deb files from `output/`
- Phase 16 (CI/CD Pipeline) can invoke `scripts/package_all.sh` as the packaging step

## Self-Check: PASSED

- scripts/package_all.sh verified present on disk
- Commit 74262a1 (Task 1) verified in git log
- Script passes bash -n syntax check
- All 10 verification checks pass (executable, extract_version, nfpm pkg, ~podman1, strict mode, config.sh, functions.sh, error_handler, suite.yaml, --packager deb)

---
*Phase: 14-debian-package-building*
*Completed: 2026-03-05*
