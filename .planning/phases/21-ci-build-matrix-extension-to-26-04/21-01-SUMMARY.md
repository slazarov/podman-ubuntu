---
phase: 21-ci-build-matrix-extension-to-26-04
plan: 01
subsystem: infra
tags: [github-actions, ci, build-matrix, ubuntu-2604, container, go-cache, nfpm]

# Dependency graph
requires:
  - phase: 20-repository-restructure-migration-aliases
    provides: "(track, distro) publish path — config.sh VALID_DISTROS=(2404 2604), resolve_publish_targets, detect_distro_version_id honoring the dotted DISTRO override"
  - phase: 19
    provides: "config.sh VERSION_SUFFIX=~ubuntu{VERSION_ID}.podman1 + detect_distro_version_id fail-closed validation (^[0-9]+\\.[0-9]+$)"
provides:
  - "Single matrixed `build` job in build-packages.yml replacing build-amd64/build-arm64"
  - "Four distro×arch cells (24.04/26.04 × amd64/arm64) in one run with fail-fast: false"
  - "26.04 cells building inside ubuntu:26.04 containers on the native amd64/arm64 runners"
  - "Distro-dimensioned Go cache keys (go-<distro>-<arch>-<track>-<run>) and artifacts (debs-<distro>-<arch>)"
  - "Dotted DISTRO override threaded into setup.sh and package_all.sh per cell"
affects: [21-02-publish-gating-retrofit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "strategy.matrix.include with explicit per-cell distro/arch/runner/container (no cartesian product + exclusions)"
    - "Runner label as a matrix FIELD so a GA-runner swap is a one-line cell edit (CICD-06)"
    - "ubuntu:26.04 container build on native runners via job-level container: ${{ matrix.container }} (empty string => no container for 2404)"
    - "Closed case map matrix.distro (2404/2604) -> dotted DISTRO (24.04/26.04) feeding config.sh"

key-files:
  created:
    - .planning/phases/21-ci-build-matrix-extension-to-26-04/21-01-SUMMARY.md
  modified:
    - .github/workflows/build-packages.yml

key-decisions:
  - "Used strategy.matrix.include (explicit cells) rather than a distro×arch cartesian product, so each cell binds its own runner label and container image directly"
  - "26.04 cells run inside ubuntu:26.04 containers on the existing native ubuntu-24.04 / ubuntu-24.04-arm runners; the runner label stays a matrix field for a future one-line GA-runner swap"
  - "Container bootstrap step (if: matrix.container != '') installs only Ubuntu-archive packages (sudo git curl ca-certificates) — no language package managers, so no package-legitimacy audit needed"
  - "matrix.arch (not runner.arch) is authoritative in the Go cache key — keeps amd64/arm64 isolated regardless of how the runner reports arch"
  - "publish.needs narrowed to [build] only — full atomic 4-cell gating + per-distro download deferred to Plan 02 (kept file valid YAML)"

patterns-established:
  - "Distro dimension lives in matrix include entries; cache key + artifact name both consume matrix.distro + matrix.arch"
  - "Dotted DISTRO override derived via a closed case map at the top of both the build and package steps"

requirements-completed: [CICD-05, CICD-06, CICD-07]

# Metrics
duration: 4min
completed: 2026-06-07
---

# Phase 21 Plan 01: CI Build Matrix Extension to 26.04 Summary

**Collapsed the two duplicated build jobs into one four-cell strategy.matrix (24.04/26.04 × amd64/arm64) with fail-fast: false, ubuntu:26.04 containers on the native runners, and distro-dimensioned Go caches + artifacts.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-06-07T02:55Z
- **Completed:** 2026-06-07T02:58Z
- **Tasks:** 1
- **Files modified:** 1 (workflow) + 1 SUMMARY created

## Accomplishments
- Replaced `build-amd64` and `build-arm64` with a single matrixed `build` job covering all four distro×arch cells in one workflow run (CICD-05).
- `fail-fast: false` so a 26.04 cell failure cannot abort the 24.04 cells.
- 26.04 cells build inside `ubuntu:26.04` containers on the existing native amd64/arm64 runners, with the runner label held as a matrix field for a one-line GA-runner swap (CICD-06).
- Go cache keys (`go-<distro>-<arch>-<track>-<run>`) and upload artifacts (`debs-<distro>-<arch>`) now carry a distro dimension, eliminating any cross-distro cache or artifact contamination (CICD-07).
- The dotted `DISTRO` override (closed case map `2604`→`26.04`) is threaded into both `setup.sh` and `package_all.sh` so `config.sh` composes `~ubuntu26.04.podman1` for the 26.04 cells.
- A bootstrap step installs `sudo git curl ca-certificates` only in the bare 26.04 container (guarded by `if: matrix.container != ''`); 24.04 host runners skip it.

## Task Commits

Each task was committed atomically:

1. **Task 1: Replace build-amd64/build-arm64 with a single four-cell strategy.matrix build job** - `fbdc5c2` (ci)

**Plan metadata:** (final docs commit — see git log)

## Files Created/Modified
- `.github/workflows/build-packages.yml` - Two build jobs merged into one matrixed `build` job; distro-dimensioned cache keys and artifact names; 26.04 container bootstrap; dotted DISTRO override into setup.sh + package_all.sh; `publish.needs` narrowed to `[build]`.

## Decisions Made
- Used `strategy.matrix.include` (explicit cells) instead of a cartesian distro×arch product with exclusions — each cell binds its own runner + container directly, matching the plan's intent and keeping the GA-runner swap a one-line edit.
- `matrix.arch` (not `runner.arch`) is authoritative in the Go cache key for deterministic per-arch isolation.
- Left the publish job's body untouched beyond pointing `needs`/`if` at `[build]`; the atomic 4-cell gating and per-distro download is explicitly Plan 02's job (YAML comment added).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. The workflow parses cleanly under both `python3 -c "import yaml..."` and `ruby -ryaml`. The plan's automated verifier and every acceptance-criteria grep pass. Note: builds run only on Linux/CI; on the macOS dev host this was validated by YAML parsing (PyYAML + Ruby) and structural assertions, not by executing the pipeline — consistent with the project's macOS constraint.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The build half of the pipeline now produces all four distro×arch package sets with isolated caches and distinctly named artifacts.
- Plan 21-02 must retrofit the `publish` job: per-distro artifact download (`debs-2404-*` vs `debs-2604-*`), the `distro` step output (currently still the literal `2404`), and atomic 4-cell gating across both distros.
- Research flag still open (carried from STATE.md): re-check whether GA `ubuntu-26.04` / `ubuntu-26.04-arm` runner labels exist at deploy time; container fallback (implemented here) is the safe default until then.

## Self-Check: PASSED

- FOUND: `.planning/phases/21-ci-build-matrix-extension-to-26-04/21-01-SUMMARY.md`
- FOUND: `.github/workflows/build-packages.yml`
- FOUND: commit `fbdc5c2`

---
*Phase: 21-ci-build-matrix-extension-to-26-04*
*Completed: 2026-06-07*
