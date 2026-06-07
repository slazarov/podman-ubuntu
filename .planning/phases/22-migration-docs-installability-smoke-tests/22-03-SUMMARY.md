---
phase: 22-migration-docs-installability-smoke-tests
plan: 03
subsystem: testing
tags: [ci, smoke-test, apt, deb822, podman, github-actions, file-source, podman-suite]

# Dependency graph
requires:
  - phase: 20-repository-restructure-migration-aliases
    provides: "9-suite assembled repo-output (ci_publish.sh mirror-then-include), per-suite Release + by-hash"
  - phase: 21-build-matrix-per-distro-publish
    provides: "publish job: sequential ci_publish.sh 2404 then 2604 into one repo-output, steps.track.outputs.track"
provides:
  - "scripts/smoke_repo_install.sh — MIGR-04 helper: file:// DEB822 install of podman-suite by name + podman info, per distro"
  - "CI installability smoke gate wired into the publish job, between repo assembly and the Pages upload"
affects: [migration-docs, ci-pipeline, future-distro-additions]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "CI-internal file:// DEB822 source with Trusted: yes (confined to the smoke gate, never user-facing)"
    - "Pre-publish container install-gate that aborts before Pages upload on a failed install/podman info"

key-files:
  created:
    - scripts/smoke_repo_install.sh
  modified:
    - .github/workflows/build-packages.yml

key-decisions:
  - "Smoke helper installs the podman-suite meta-package BY NAME from a DEB822 file:// source (not a .deb-by-path like the smoke_install_2604.sh analog)"
  - "Gate runs unconditionally on every publish (D-18), after both ci_publish.sh runs and before the Pages upload (D-13); a failure aborts before any Pages deploy (D-16)"
  - "amd64-only smoke containers (D-17); 2604 leg falls back to ubuntu:resolute if ubuntu:26.04 is not pullable"
  - "Trusted: yes is confined to the CI-internal smoke source (D-14) — accepted limitation, does not exercise the Signed-By path; never user-facing"

patterns-established:
  - "Standalone smoke helper (no config.sh/functions.sh source) for minimal-env CI runners, matching smoke_install_2604.sh"
  - "Exact-match whitelist validation of distro label {2404,2604} and SMOKE_RUNTIME {docker,podman} before any command interpolation (T-22-SMOKE-01)"
  - "Container script fed via stdin heredoc (bash -s << INNEREOF) to avoid the nested single-quote hazard of bash -c"

requirements-completed: [MIGR-04]

# Metrics
duration: 4min
completed: 2026-06-07
---

# Phase 22 Plan 03: CI Installability Smoke Gate Summary

**A pre-publish CI gate that apt-installs the `podman-suite` meta-package by name from the assembled `file://` repo inside real ubuntu:24.04 and ubuntu:26.04 containers and runs `podman info`, blocking the GitHub Pages upload if either fails.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-06-07T08:40:00Z (approx)
- **Completed:** 2026-06-07T08:44:00Z (approx)
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 edited)

## Accomplishments

- New `scripts/smoke_repo_install.sh`: per-distro helper that bind-mounts the assembled `repo-output` read-only into a throwaway privileged container, writes a DEB822 `file://` source with `Trusted: yes`, installs `podman-suite` by name, and runs `podman info --log-level=error` as the gate (D-15).
- Wired the gate into the `publish` job between the publish step and the Pages upload — unconditional on every publish, so an uninstallable package never reaches the live repo.
- Hardened the interpolation surface: distro label and `SMOKE_RUNTIME` are exact-match-validated against closed whitelists before use (T-22-SMOKE-01); image strings are hardcoded literals.
- 2604 leg falls back to `ubuntu:resolute` when `ubuntu:26.04` is not pullable; failure messages name the failing distro/suite.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create scripts/smoke_repo_install.sh** - `612e64a` (feat)
2. **Task 2: Wire the smoke gate into the publish job** - `e1c43aa` (feat)

**Plan metadata:** committed with this SUMMARY (docs: complete plan)

## Files Created/Modified

- `scripts/smoke_repo_install.sh` (created) — MIGR-04 smoke helper: validates a `{2404,2604}` distro label, selects+validates the runtime, picks the image (24.04 direct; 26.04→resolute fallback), resolves+validates the assembled repo dir (must contain `dists/`), then runs a privileged `--device /dev/fuse` container that installs `podman-suite` from a DEB822 `file:///opt/podman-repo` source and runs `podman info`. Hard-fails (naming distro/suite) on any failure.
- `.github/workflows/build-packages.yml` (modified) — added the step "Smoke test — install podman-suite from assembled repo per distro" in the `publish` job, after `publish_distro "2604" "all-debs-2604"` and before `actions/configure-pages@v4`. It exports `TRACK` from `steps.track.outputs.track` and invokes the helper for `2404` then `2604` against `$PWD/repo-output`. No `if:` guard; no new `run-tests` job.

## Decisions Made

- Followed the plan body over the PATTERNS.md code samples where they diverged (advisor-confirmed): DEB822 `.sources` (not the legacy `deb` one-liner `.list`), stdin heredoc (`bash -s`) (not `bash -c '...'`), and a standalone helper that is CALLED by the workflow (not inlined). PATTERNS.md had labeled the helper "optional/discretion" and shown an inlined workflow step — the plan's `files_modified` + `must_haves` require the separate helper invoked by name.
- Did not add a `SMOKE_IMAGE` override (not in the plan's usage block — avoids extra surface/validation).
- Included the VFS storage fallback (RESEARCH Pitfall 1) as a commented-out block in the container script, not enabled pre-emptively — to be turned on only if CI proves the `podman info` storage probe fails.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. `shellcheck` is not installed on the macOS dev host, so the AGENTS.md ShellCheck pass could not be run locally; `bash -n` passed. ShellCheck remains advisory and CI-deferrable.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 22 (migration-docs-installability-smoke-tests) is complete with this plan (3/3). Plan 01 (docs rewrite), Plan 02 (per-distro index.html), and Plan 03 (this smoke gate) are all delivered.
- **CI-proven, not macOS-proven (per the plan's dev-host constraint):** `/gsd-verify-work` MUST treat MIGR-04 as CI-proven. End-to-end validation — `apt install podman-suite` + `podman info` exit 0 in both containers — is deferred to the first real CI publish (or a Lima ubuntu-24 / ubuntu-26 run of `bash scripts/smoke_repo_install.sh 2404|2604 <repo-output>`). On macOS only `bash -n` and `yaml.safe_load` were run.
- The gate is unconditional, so the first nightly/dispatch publish exercises it automatically; if `podman info` errors on storage in CI, enable the documented VFS fallback block in the helper.

## Self-Check: PASSED

- FOUND: scripts/smoke_repo_install.sh
- FOUND: .github/workflows/build-packages.yml
- FOUND: .planning/phases/22-migration-docs-installability-smoke-tests/22-03-SUMMARY.md
- FOUND commit: 612e64a (Task 1)
- FOUND commit: e1c43aa (Task 2)

---
*Phase: 22-migration-docs-installability-smoke-tests*
*Completed: 2026-06-07*
