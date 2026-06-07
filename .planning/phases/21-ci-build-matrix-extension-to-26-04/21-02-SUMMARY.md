---
phase: 21-ci-build-matrix-extension-to-26-04
plan: 02
subsystem: infra
tags: [github-actions, ci, publish, github-pages, atomic-deploy, per-distro, reprepro, test]

# Dependency graph
requires:
  - phase: 21-ci-build-matrix-extension-to-26-04
    plan: 01
    provides: "Single matrixed `build` job (four distro×arch cells, fail-fast: false), distro-named artifacts debs-<distro>-<arch>, publish.needs narrowed to [build]"
  - phase: 20-repository-restructure-migration-aliases
    provides: "ci_publish.sh 5-arg CLI (track, distro, deb-dir, repo-url, output) + mirror-then-include OTHER_SUITES no-clobber; config.sh VALID_DISTROS=(2404 2604) / resolve_publish_targets"
provides:
  - "publish job gated on the matrixed build job's aggregate result (needs.build.result == 'success') — atomic 4-cell publish (CICD-08)"
  - "Per-distro artifact download into separate dirs (debs-2404-* -> all-debs-2404/, debs-2604-* -> all-debs-2604/) with no cross-distro merge (CICD-05/CICD-07)"
  - "Sequential per-distro ci_publish.sh runs (2404 then 2604) into one accumulating repo-output, then a single atomic deploy-pages"
  - "tests/test_ci_matrix.sh — macOS-runnable proof of the matrix + gating + no-merge contract"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Aggregate-result gating on a single matrix job (needs.<job>.result == 'success' is success only when every fail-fast:false cell passed)"
    - "Per-distro download dirs with merge-multiple scoped to one distro's two arches only — never a bare debs-* merge"
    - "Sequential per-distro ci_publish.sh into one repo-output leveraging the Phase-20 mirror-then-include no-clobber model"
    - "Dual-path workflow test: precise PyYAML structural checks + grep/awk floor with comment-stripping (grep-gate hygiene)"

key-files:
  created:
    - tests/test_ci_matrix.sh
    - .planning/phases/21-ci-build-matrix-extension-to-26-04/21-02-SUMMARY.md
  modified:
    - .github/workflows/build-packages.yml

key-decisions:
  - "Replaced the single literal distro=2404 step output + one ci_publish.sh call with an in-shell publish_distro() helper run for 2404 then 2604 — explicit ordering, one accumulating repo-output, single deploy"
  - "Added a defensive skip-on-empty guard per distro (ci_publish.sh hard-fails on an empty deb dir) so an unexpected-but-non-fatal empty cell does not abort publishing the populated distro; gating should make this unreachable"
  - "Test ships BOTH a PyYAML structural path and a grep/awk floor so it is green on the macOS dev host regardless of PyYAML; grep path strips comment lines so workflow comments cannot self-satisfy a gate"

patterns-established:
  - "Atomic publish = aggregate-result gate + single terminal deploy-pages; both distros assembled into repo-output before the one-shot deploy"
  - "No cross-distro merge enforced structurally (two scoped download steps, zero bare debs-* patterns) AND by test assertion 9"

requirements-completed: [CICD-05, CICD-08]

# Metrics
duration: 5min
completed: 2026-06-07
---

# Phase 21 Plan 02: Publish-Gating Retrofit Summary

**Retrofitted the publish job to gate on all four build cells (atomic publish), download each distro into its own directory with no cross-distro merge, run ci_publish.sh per distro into one accumulating repo-output, and deploy to GitHub Pages once — proven on macOS by a new 27-assertion workflow test.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-06-07
- **Completed:** 2026-06-07
- **Tasks:** 2
- **Files modified:** 1 workflow + 1 test created + 1 SUMMARY created

## Accomplishments
- **Atomic 4-cell gating (CICD-08, T-21-06):** `publish` runs only when `needs.build.result == 'success'`. Because `build` is one `fail-fast: false` matrix job, its aggregate result is `success` only when all four cells (24.04/26.04 × amd64/arm64) pass; any single cell failure skips publish entirely, leaving the live repo untouched.
- **No cross-distro merge (CICD-05/CICD-07, T-21-05):** replaced the single `pattern: debs-*` / `path: all-debs/` download with two distro-scoped steps — `debs-2404-*` → `all-debs-2404/` and `debs-2604-*` → `all-debs-2604/`. `merge-multiple` is now scoped to a single distro's two arches only; no step ever merges 24.04 and 26.04 binaries.
- **Per-distro sequential publish (T-21-08):** an in-shell `publish_distro()` helper invokes `ci_publish.sh <track> 2404 all-debs-2404 <url> repo-output` then the 2604 equivalent into the SAME `repo-output`, leveraging the Phase-20 mirror-then-include no-clobber model (the 2604 run mirrors the 2404 run's freshly-published suites as OTHER_SUITES). Compact labels `2404`/`2604` are passed verbatim and re-validated by config.sh `VALID_DISTROS` (T-21-07).
- **Single atomic deploy (CICD-08):** both distros are assembled into `repo-output` before the one terminal `deploy-pages@v4` — the live repository is replaced in one shot or not at all. Removed the obsolete literal `echo "distro=2404"` step output.
- **Defensive skip-on-empty:** each distro's publish is skipped (logged) if its download dir holds no `.deb` files, so an unexpected empty cell does not abort the populated distro's publish (gating should make this unreachable).
- **Contract test (`tests/test_ci_matrix.sh`):** a pure-bash test asserting all 10 contract points — single `build` job, `fail-fast: false`, four cells, all distro×arch pairings, ubuntu:26.04 containers on 2604, distro-dimensioned cache + artifact names, publish gating, no bare `debs-*` merge, and ci_publish.sh for both distros. Dual-path (PyYAML + grep floor); 27/27 PASS on macOS.

## Task Commits

Each task was committed atomically:

1. **Task 1: Gate publish on all four cells + per-distro download/publish** — `3eeacad` (ci)
2. **Task 2: Add tests/test_ci_matrix.sh asserting the matrix + gating + no-merge contract** — `5cc2607` (test)

**Plan metadata:** (final docs commit — see git log)

## Files Created/Modified
- `.github/workflows/build-packages.yml` — publish job rewritten: aggregate-result gate, two distro-scoped download steps, `publish_distro()` sequential 2404→2604 into one repo-output, skip-on-empty guard, removed literal distro step output; single deploy-pages tail retained.
- `tests/test_ci_matrix.sh` (created) — macOS-runnable workflow-contract test, dual PyYAML/grep paths, 27 assertions.

## Decisions Made
- Used an in-shell `publish_distro()` helper (single `run:` block) rather than two separate workflow steps so the 2404→2604 ordering and the shared `repo-output` are explicit and the skip-on-empty logic is reusable per distro.
- Passed the compact labels `2404`/`2604` as string literals (not the dotted build-time form) — `ci_publish.sh`/`config.sh` validate against `VALID_DISTROS=(2404 2604)`; the dotted form is only the build-step DISTRO override.
- Test floor strips comment-only lines (`grep -v '^[[:space:]]*#'`) before every grep count so the explanatory YAML comments added in Task 1 cannot self-satisfy a gate.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None. The workflow parses cleanly under PyYAML; the plan's automated verifier, every acceptance-criteria grep, and the full `<verification>` block pass. Per the project's macOS constraint, correctness was validated by YAML parsing + structural assertions + the new pure-bash test — the publish pipeline itself runs only on Linux/CI (first real publish still pending, carried as a Phase-20 research flag). ShellCheck was unavailable on the dev host (`shellcheck not found`); `bash -n` passed for both touched scripts as the floor check.

## User Setup Required
None - no external service configuration required. (Publish at runtime still needs the existing `secrets.GPG_PRIVATE_KEY`, unchanged from Phase 20.)

## Next Phase Readiness
- The full Phase-21 four-cell matrix → atomic per-distro publish pipeline is now wired end-to-end and proven on macOS.
- Carried research flag (from Phase 20 / 21-01): the production-CDN smoke of the 9-suite tree and the GA `ubuntu-26.04`/`ubuntu-26.04-arm` runner-label re-check both await the first real CI publish; the container fallback remains the safe default.

## Self-Check: PASSED

- FOUND: `.github/workflows/build-packages.yml`
- FOUND: `tests/test_ci_matrix.sh`
- FOUND: `.planning/phases/21-ci-build-matrix-extension-to-26-04/21-02-SUMMARY.md`
- FOUND: commit `3eeacad`
- FOUND: commit `5cc2607`

---
*Phase: 21-ci-build-matrix-extension-to-26-04*
*Completed: 2026-06-07*
