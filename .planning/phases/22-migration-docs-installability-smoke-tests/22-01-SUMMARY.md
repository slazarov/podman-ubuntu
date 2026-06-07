---
phase: 22-migration-docs-installability-smoke-tests
plan: 01
subsystem: docs
tags: [apt, deb822, documentation, migration, ubuntu-2404, ubuntu-2604, bash-test]

# Dependency graph
requires:
  - phase: 20-repository-restructure-migration-aliases
    provides: distro-qualified suite names (stable-2404/2604) and bare-alias deprecation framing
  - phase: 19
    provides: per-distro version suffix ~ubuntu{24.04,26.04}.podman1
provides:
  - Per-distro DEB822 setup sections (Ubuntu 24.04 Noble Numbat / 26.04 Resolute Raccoon) in docs/apt-repository.md
  - Single GPG key block referenced identically by both distro sections
  - Top-of-doc deprecation callout linking to the migration section
  - "Migrating from Bare Suite Names" section (slug #migrating-from-bare-suite-names) — SHARED CONTRACT consumed by Plan 02's index.html
  - tests/test_docs_suites.sh doc-grep unit test (local/manual, not CI-wired)
affects: [22-02 index.html distro toggle, 22-03 CI smoke gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "doc-grep unit test with grep -qF assertions + assignment-form PASS/FAIL counters (set -e safe)"
    - "negative grep assertion as a security boundary check (trusted=yes must not leak)"

key-files:
  created:
    - tests/test_docs_suites.sh
  modified:
    - docs/apt-repository.md

key-decisions:
  - "Per-distro section headers locked as '## Ubuntu 24.04 (Noble Numbat)' / '## Ubuntu 26.04 (Resolute Raccoon)' (PLAN authoritative over UI-SPEC's illustrative ### form)"
  - "Deprecation wording quoted verbatim from D-04/D-11, not the paraphrased PATTERNS.md skeleton"
  - "Test uses assignment-form counters (PASS=$((PASS+1))) not ((PASS++)) to avoid set -e abort on the first assertion"

patterns-established:
  - "doc-grep test: grep -qF positive assertions + a negative grep for forbidden strings, exiting non-zero on any FAIL"

requirements-completed: [MIGR-01, MIGR-03]

# Metrics
duration: 6min
completed: 2026-06-07
---

# Phase 22 Plan 01: Migration Docs (per-distro DEB822 + deprecation + migration) Summary

**Restructured docs/apt-repository.md into per-distro DEB822 setup sections (stable-2404 / stable-2604) with a single GPG key block, a top-of-doc deprecation callout, and a migration section, fronted by a test-first doc-grep unit test.**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-06-07
- **Completed:** 2026-06-07
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 rewritten)

## Accomplishments
- Test-first doc-grep unit test `tests/test_docs_suites.sh` asserting all six distro-qualified suite names, the single `Signed-By` keyring path, the migration header, and the verbatim deprecation phrase — plus a negative assertion that `trusted=yes` never leaks (T-22-DOC-01).
- `docs/apt-repository.md` reorganized into intro → deprecation callout → Ubuntu 24.04 setup → Ubuntu 26.04 setup → GPG Signing Key → Track Selection → Individual Packages → Supported Architectures → Migrating from Bare Suite Names → Troubleshooting → Important Notes.
- Migration section provides both a sed one-liner (per-distro) and full replacement `.sources` blocks; documents that bare suites keep serving 24.04 during the deprecation window.
- Version suffix note updated from `~podman1` to `~ubuntu24.04.podman1` / `~ubuntu26.04.podman1`; Troubleshooting 404 section now lists distro-qualified suite names.

## Task Commits

1. **Task 1: Add tests/test_docs_suites.sh (test-first — RED)** - `8e81036` (test)
2. **Task 2: Restructure docs/apt-repository.md (GREEN)** - `99ddf34` (docs)

## Files Created/Modified
- `tests/test_docs_suites.sh` - doc-grep unit test: 9 positive assertions + 1 negative (trusted=yes); local/manual, not CI-wired
- `docs/apt-repository.md` - rewritten in place with per-distro DEB822 sections, single GPG block, deprecation callout, migration section

## Decisions Made
- Per-distro headers use the PLAN's exact strings (`## Ubuntu 24.04 (Noble Numbat)` / `## Ubuntu 26.04 (Resolute Raccoon)`); the UI-SPEC's `###`/no-codename variant was illustrative ("e.g.").
- Deprecation wording sourced verbatim from D-04/D-11, not the PATTERNS.md L87-94 paraphrase ("They will be removed...") which would have failed the verbatim-phrase grep.
- Test counters use the assignment form (`PASS=$((PASS+1))`) matching `tests/test_detect_distro_depends.sh`, not the skeleton's `((PASS++))` which aborts under `set -euo pipefail` when the value is 0.

## Deviations from Plan

None - plan executed exactly as written. (The advisor flagged the `((PASS++))` set -e abort latent in the PATTERNS.md skeleton; the PLAN's read_first already pointed to the assignment-form harness, so following the PLAN avoided it — not a deviation.)

## Issues Encountered
None.

## Known Stubs
None - both files are complete and functional. The grep test is intentionally local/manual (not wired into CI) per the RESEARCH Wave 0 gap that `tests/` are not run by `build-packages.yml`; this is documented in the test's header comment and is not a stub.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The migration anchor `#migrating-from-bare-suite-names` is locked and live — Plan 02's index.html deprecation callout and Plan 03's CI smoke gate can link to / build on it.
- Per-distro suite-name strings (`stable-2404`/`stable-2604` etc.) match what Plan 02's index.html snippets and Plan 03's smoke-test suites must emit.
- `scripts/ci_publish.sh` shows as modified in the working tree (Plan 02's file) — out of scope here and intentionally NOT staged or committed by this plan.

## Self-Check: PASSED

- FOUND: tests/test_docs_suites.sh
- FOUND: docs/apt-repository.md
- FOUND: .planning/phases/22-migration-docs-installability-smoke-tests/22-01-SUMMARY.md
- FOUND: commit 8e81036 (Task 1)
- FOUND: commit 99ddf34 (Task 2)

---
*Phase: 22-migration-docs-installability-smoke-tests*
*Completed: 2026-06-07*
