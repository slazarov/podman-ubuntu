---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: Ubuntu 26.04 Support
status: executing
stopped_at: Completed 19-02-PLAN.md
last_updated: "2026-06-05T12:38:13Z"
last_activity: 2026-06-05 -- Completed Phase 19 Plan 02 (package_all.sh + nFPM YAMLs wired to DETECTED_DEPENDS + per-distro suffix)
progress:
  total_phases: 4
  completed_phases: 0
  total_plans: 4
  completed_plans: 3
  percent: 75
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-05)

**Core value:** Compile and install Podman on any Debian/Ubuntu system without user interaction.
**Current focus:** Phase 19 — per-distro-versioning-dependency-mapping

## Current Position

Phase: 19 (per-distro-versioning-dependency-mapping) — EXECUTING
Plan: Plans 01 + 02 + 03 complete (04 remaining)
Status: Executing Phase 19
Last activity: 2026-06-05 -- Completed Phase 19 Plan 02 (package_all.sh + nFPM YAMLs wired to DETECTED_DEPENDS + per-distro suffix)

Progress: [███████░░░] 75%

## Performance Metrics

**Velocity:**

- Total plans completed: 30 (all milestones, v1.0-v2.0)
- Average duration: 3min
- Total execution time: 24min

**By Phase (v2.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 14. Debian Package Building | 2/2 | 8min | 4min |
| 15. APT Repository and Signing | 2/2 | 5min | 2.5min |
| 18. Edge Track / Nightly Builds | 2/2 | 10min | 5min |

*Updated after each plan completion*

## Previous Milestones

### v2.0 APT Packaging & CI/CD (Shipped 2026-03-08)

**Phases:** Phases 14-18 (17 absorbed into 18) | **Plans:** 8/8

### v1.2 Include Common Libraries (Shipped 2026-03-04)

**Phases:** 3/3 | **Plans:** 3/3

### v1.1 Ecosystem Audit (Shipped 2026-03-04)

**Phases:** 5/5 | **Plans:** 7/7

### v1.0 MVP (Shipped 2026-03-03)

**Phases:** 5/5 | **Plans:** 13/13

## Accumulated Context

### Decisions

All decisions logged in PROJECT.md Key Decisions table. Recent decisions affecting v3.0 work:

- Phase 15-01: Set Codename = Suite name (stable/edge) to avoid createsymlinks complexity — revisited in v3.0 (suite renames need aliases)
- Phase 18-01: Nightly versions use tilde (~git) convention for dpkg sort below tagged releases — v3.0 extends tilde form with per-distro suffix
- Phase 18-02: Go cache key uses track + run_number for cache isolation — v3.0 adds distro dimension to cache keys
- Phase 19-01: DISTRO override carries the dotted VERSION_ID form (26.04), not the compact CI label (2604); the `^[0-9]+\.[0-9]+$` regex rejects 2604 by design (T-19-01 fail-closed)
- Phase 19-01: Soname→package mapping delegated to the host dpkg DB (detect_runtime_depends), never a hand-maintained table — absorbs the crun parser special case (D-04); excludes only libc6/libgcc-s1 (D-02); hard-fails on any unmapped lib (D-03)
- Phase 19-01: config.sh is the single source of truth for VERSION_SUFFIX = `~ubuntu{VERSION_ID}.podman1` (D-07/D-08); package_all.sh's hardcoded `~podman1` removed in Plan 02
- Phase 19-03: scripts/verify_versions.sh uses literal in-script fixtures + `dpkg --compare-versions` as the authoritative oracle (no reimplemented version math), so it runs on any dpkg host independent of the build pipeline (CI-runnable pre-build)
- Phase 19-02: nFPM `${DETECTED_DEPENDS}` placeholder sits at column 0 under `depends:`; the `sed 's/^/  - /'` fragment carries its own indent so it merges cleanly with literal internal `podman-*` deps (D-12/D-13). No `|| true` around `detect_runtime_depends` — unmapped soname hard-fails the build (D-03)

### Tech Debt

- Minor: install_dependencies.sh lacks DEBIAN_FRONTEND (relies on setup.sh)
- Minor: Circular sourcing pattern config.sh <-> functions.sh (guarded but fragile)

### Research Flags (v3.0)

- Phase 20: physical-copy vs createsymlinks alias strategy needs live GitHub Pages test (Pages tarballs may not preserve symlinks); validate "Suite changed value" apt prompt with a real pre-v3.0 client
- ✓ Phase 19 (closed by Plan 03): version suffix form confirmed via `dpkg --compare-versions` in scripts/verify_versions.sh — yields to official, 24.04 < 26.04, nightly < tagged, legacy ~podman1 < new ~ubuntu24.04.podman1
- Phase 21: re-check whether `ubuntu-26.04` / `ubuntu-26.04-arm` runner labels are GA at implementation time; container fallback is the safe default

### Blockers/Concerns

None yet.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 5 | Generate a nice README for the repo | 2026-03-06 | 3ec1a20 | [5-generate-a-nice-readme-for-the-repo](./quick/5-generate-a-nice-readme-for-the-repo/) |
| 6 | Rename podman-debian to podman-ubuntu | 2026-03-08 | 0fa5450 | [6-rename-repo-from-podman-debian-to-podman](./quick/6-rename-repo-from-podman-debian-to-podman/) |

## Session Continuity

Last session: 2026-06-05T12:38:13Z
Stopped at: Completed 19-02-PLAN.md
Resume file: .planning/phases/19-per-distro-versioning-dependency-mapping/19-04-PLAN.md (Plan 04 remaining)
