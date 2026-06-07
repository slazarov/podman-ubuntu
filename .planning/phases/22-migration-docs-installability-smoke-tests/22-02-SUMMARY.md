---
phase: 22-migration-docs-installability-smoke-tests
plan: 02
subsystem: infra
tags: [apt, deb822, index-html, ci-publish, migration, ubuntu-2604, bash, vanilla-js]

# Dependency graph
requires:
  - phase: 20-publish-pipeline
    provides: "ci_publish.sh three-column package-versions table + available_suites[] accumulator loop (D-18, preserved here as D-10)"
  - phase: 22-01
    provides: "docs/apt-repository.md #migrating-from-bare-suite-names anchor (shared contract for the deprecation callout link)"
provides:
  - "index.html per-distro setup: distro toggle (Ubuntu 24.04 default / 26.04), two DEB822 snippets per track tab differing only in Suites:"
  - "setDistro() vanilla-JS function swapping per-distro snippets across all tabs via data-distro show/hide"
  - "DEB822 snippets standardized on Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg (consistent with docs, ROADMAP SC-4)"
  - "Deprecation callout on the landing page linking to the docs migration section"
  - "tests/test_index_html_distro.sh string-assertion unit test (local/manual)"
affects: [migration-docs, ci-publish, future-suite-rename-removal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-distro DEB822 snippet toggle: paired <pre class=\"snippet\" data-distro=\"NNNN\"> blocks, JS show/hide by dataset.distro"
    - "Test-greps-source: heredoc-emitting generator tested by grepping the generator source directly (heredoc is the authoritative string)"

key-files:
  created:
    - tests/test_index_html_distro.sh
  modified:
    - scripts/ci_publish.sh

key-decisions:
  - "Active distro-btn reuses .tab-btn.active treatment (white bg, weight 600, #333 edge) — NOT the green #2ea44f accent (reserved for .track.recommended) nor the PATTERNS-skeleton blue; UI-SPEC/PLAN hard constraint over stale PATTERNS"
  - "Keyring path standardized on /etc/apt/keyrings/podman-ubuntu.gpg whole-file (GPG import step + all six snippets); legacy /usr/share/keyrings/ fully removed (RESEARCH OQ1 resolved, ROADMAP SC-4)"
  - "Test counters use assignment form PASS=$((PASS+1)) not ((PASS++)) so they never abort under set -e; negative assertions use grep -qF so 'deb [signed-by=' is matched verbatim not as a bracket expression"

patterns-established:
  - "Per-distro DEB822 toggle: two data-distro snippets per tab, setDistro() shows/hides by dataset.distro (ephemeral, no localStorage)"
  - "Heredoc-generator unit test greps the generator source directly"

requirements-completed: [MIGR-02, MIGR-03]

# Metrics
duration: 6min
completed: 2026-06-07
---

# Phase 22 Plan 02: index.html Per-Distro Setup Summary

**Generated landing page now ships a default-24.04 distro toggle, two DEB822 snippets per track tab (Signed-By /etc/apt/keyrings/, per-distro Suites), a setDistro() swapper, and a deprecation callout linking to the docs migration anchor — legacy /usr/share/keyrings one-liners fully removed.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-06-07
- **Completed:** 2026-06-07
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments
- index.html heredoc in `scripts/ci_publish.sh` now emits a distro toggle (Ubuntu 24.04 active by default / Ubuntu 26.04) above the track tabs
- Each of the three track tabs (stable/edge/nightly) holds two DEB822 snippets differing only in the `Suites:` line (`<track>-2404` vs `<track>-2604`); 2404 visible, 2604 `display:none`
- `setDistro(ver)` JS swaps which per-distro snippet is visible across all tabs and toggles the active button
- Legacy `deb [signed-by=/usr/share/keyrings/...]` one-liners rewritten to DEB822 with `Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg`; GPG-import step moved to `/etc/apt/keyrings/` with `mkdir -p`. Whole-file `/usr/share/keyrings/` count is now 0
- Deprecation callout added linking to `docs/apt-repository.md#migrating-from-bare-suite-names` (shared anchor from Plan 01)
- New `tests/test_index_html_distro.sh` (15 assertions) drives the RED→GREEN cycle and guards the D-10 table/accumulator preservation and the T-22-HTML-02 no-`trusted=yes` security boundary

## Task Commits

1. **Task 1: Add tests/test_index_html_distro.sh string-assertion test (RED)** - `58f0702` (test)
2. **Task 2: Rewrite snippets to DEB822 + distro toggle, setDistro(), deprecation callout (GREEN)** - `e1ce618` (feat)

## Files Created/Modified
- `tests/test_index_html_distro.sh` - 15 grep assertions on the ci_publish.sh heredoc: positive (setDistro, data-distro 2404/2604, distro-btn, per-distro suites, Signed-By path, migration anchor, D-10 table/accumulator guards) + negative (legacy keyring path, deb one-liner, trusted=yes). Local/manual, not wired into CI.
- `scripts/ci_publish.sh` - Step 5 heredoc: `.distro-group`/`.distro-btn` CSS; distro toggle markup; GPG import + six DEB822 snippets on `/etc/apt/keyrings/`; deprecation callout; `setDistro()` JS. Three-column package-versions table + `available_suites[]` loop preserved verbatim.

## Decisions Made
- **Active distro-btn styling:** reused `.tab-btn.active` treatment (white bg, weight 600, `#333` border) per the PLAN action text and UI-SPEC hard constraint, overriding the stale PATTERNS skeleton which proposed a blue (`#0366d6`) active state. Green `#2ea44f` stays reserved exclusively for `.track.recommended` (verified: only the two pre-existing recommended-track rules use it).
- **Keyring path:** standardized on `/etc/apt/keyrings/podman-ubuntu.gpg` across the whole file (RESEARCH OQ1 resolved as Claude's discretion, mandated by ROADMAP SC-4 for docs/index.html consistency).

## Deviations from Plan

None - plan executed exactly as written. (Two test-harness robustness choices — assignment-form counters and `grep -qF` for negative assertions — were applied while authoring the new test per the plan's own guidance, not corrections to existing code.)

## Issues Encountered
None. RED confirmed (3 vacuous-pass + 12 fail against the un-edited heredoc), GREEN confirmed (15/15) after Task 2. `bash -n scripts/ci_publish.sh` exits 0 (heredoc terminators intact); whole-file `grep -c '/usr/share/keyrings/'` returns 0.

## Threat Surface

No new threat surface beyond the plan's `<threat_model>`. T-22-HTML-01 (esc() guards dynamic table interpolation) preserved unchanged; T-22-HTML-02 (every user-facing snippet uses `Signed-By`, no `trusted=yes`) enforced and test-guarded. The added toggle/callout markup is static (not attacker-influenced).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- index.html per-distro setup (MIGR-02) and on-page deprecation timeline (MIGR-03) complete.
- Manual visual verification (toggle defaults to 24.04, switching to 26.04 swaps all three track snippets to `-2604`, package-versions table still renders) is deferred to the first CI/Pages preview — the page is generated only inside `ci_publish.sh` runs.
- Ready for Plan 03 (smoke_repo_install.sh + workflow smoke-gate step).

## Self-Check: PASSED

- Files: tests/test_index_html_distro.sh, scripts/ci_publish.sh, 22-02-SUMMARY.md — all FOUND
- Commits: 58f0702 (test/RED), e1ce618 (feat/GREEN) — all FOUND

---
*Phase: 22-migration-docs-installability-smoke-tests*
*Completed: 2026-06-07*
