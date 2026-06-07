---
phase: 21-ci-build-matrix-extension-to-26-04
reviewed: 2026-06-07T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - .github/workflows/build-packages.yml
  - tests/test_ci_matrix.sh
findings:
  critical: 1
  warning: 5
  info: 4
  total: 10
status: issues_found
---

# Phase 21: Code Review Report

**Reviewed:** 2026-06-07
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed the Phase-21 CI changes that collapse `build-amd64`/`build-arm64` into a
single 4-cell `distro×arch` matrix (24.04/26.04 × amd64/arm64, with 26.04 cells
running inside `ubuntu:26.04` containers on native host runners) and retrofit the
`publish` job for atomic gating, distro-scoped artifact downloads, and per-distro
`ci_publish.sh` invocations. The contract test `tests/test_ci_matrix.sh` was also
added.

The matrix design is sound: `fail-fast: false` correctly keeps 24.04 cells alive
when a 26.04 cell breaks, `needs.build.result == 'success'` correctly aggregates
across all four cells (publish runs only when every cell succeeded), cache keys
and artifact names carry an explicit `distro` dimension preventing cross-distro
contamination, and `merge-multiple: true` is correctly scoped to a single distro's
two arch artifacts. The publish-gating semantics are correct.

The most serious issue is the bare-container bootstrap (BLOCKER): the 26.04 cells
install their prerequisites with a single un-retried `apt-get update` against a
known-stale image index — a failure mode the repo's own AGENTS.md explicitly
documents as "the hard way." Several robustness and test-coverage warnings follow.

## Critical Issues

### CR-01: 26.04 container bootstrap uses un-retried `apt-get update` against a known-stale image index

**File:** `.github/workflows/build-packages.yml:143-147`
**Issue:** The new bootstrap step for the 2604 cells is:
```yaml
- name: Bootstrap ubuntu:26.04 container prerequisites
  if: matrix.container != ''
  run: |
    apt-get update
    apt-get install -y --no-install-recommends sudo git curl ca-certificates
```
This is the single point of failure that decides whether *either* 26.04 cell can
proceed, and it has no resilience. The project's own AGENTS.md states the rule
"learned the hard way":

> Run `sudo apt-get update` before the first build — fresh VMs carry stale apt
> indexes and `install_dependencies.sh` will 404 on superseded versions.

A bare `ubuntu:26.04` image is exactly such a stale-index environment. A transient
mirror hiccup or a superseded package version causes `apt-get install` to 404/fail,
which (because there is no retry) fails the cell, which — by the correct
`needs.build.result == 'success'` gating in CR-adjacent logic — **silently skips the
entire publish job**, including the 24.04 packages that built fine. A flaky network
during bootstrap therefore blocks publication of all four distros' packages. This is
a correctness/reliability defect with a blast radius far larger than the failing cell.

**Fix:** Retry the bootstrap and refresh the index defensively:
```yaml
- name: Bootstrap ubuntu:26.04 container prerequisites
  if: matrix.container != ''
  run: |
    for attempt in 1 2 3; do
      apt-get update && break
      echo "apt-get update failed (attempt ${attempt}); retrying in 15s" >&2
      sleep 15
    done
    apt-get install -y --no-install-recommends \
      sudo git curl ca-certificates \
      || { sleep 15; apt-get update && apt-get install -y --no-install-recommends \
           sudo git curl ca-certificates; }
```

## Warnings

### WR-01: Duplicated `case "${{ matrix.distro }}"` distro-mapping block invites drift

**File:** `.github/workflows/build-packages.yml:180-184` and `245-249`
**Issue:** The compact-label → dotted-VERSION_ID map is hand-copied into both the
"Build all components" and "Package all components" steps:
```bash
case "${{ matrix.distro }}" in
  2404) DISTRO_DOTTED=24.04 ;;
  2604) DISTRO_DOTTED=26.04 ;;
  *) echo "ERROR: unknown matrix.distro '${{ matrix.distro }}'" >&2; exit 1 ;;
esac
```
If a future distro (e.g. `2804`) is added to the matrix and only one of the two
copies is updated, the build step would stage binaries with one suffix while
packaging composes a *different* `VERSION_SUFFIX` — producing mislabeled or
mismatched `.deb` filenames that pass CI silently. Two sources of truth for the
same mapping is a latent correctness hazard.
**Fix:** Compute `DISTRO_DOTTED` once (e.g. a job-level `env:` derived value or a
single early step that writes `distro_dotted` to `$GITHUB_OUTPUT`) and reference
`${{ steps.x.outputs.distro_dotted }}` in both steps. Alternatively encode the
dotted value directly as a matrix field (`distro_dotted: '24.04'`) alongside
`distro`, eliminating the case statement entirely.

### WR-02: `output/*.deb` may accumulate stale artifacts across matrix cells if `output/` is not pristine

**File:** `.github/workflows/build-packages.yml:258-264`
**Issue:** `upload-artifact` uploads `path: output/*.deb`. Each cell is a fresh
runner/container with a fresh `actions/checkout`, so `output/` should be empty at
start — today this is fine. However, the upload silently uploads *whatever* matches
the glob; there is no assertion that the expected number of `.deb` files exists, nor
that they all carry the cell's own `~ubuntu{XX.XX}.podman1` suffix. If a future
change ever shares state (a cache of `output/`, a self-hosted runner, a packaging
bug that emits zero debs), a cell could upload an empty or wrong-distro artifact set
and the publish job's `publish_distro` count-check (line 344) would either skip
publishing that distro or publish the wrong binaries. Defense-in-depth is missing at
the producer side.
**Fix:** Before upload, assert the artifact set is non-empty and distro-correct:
```bash
- name: Verify .deb output before upload
  run: |
    shopt -s nullglob
    debs=(output/*~ubuntu${DISTRO_DOTTED}.podman1*.deb)  # DISTRO_DOTTED from a shared output
    (( ${#debs[@]} > 0 )) || { echo "ERROR: no ${DISTRO_DOTTED} .debs in output/" >&2; exit 1; }
```
(Requires WR-01's shared `DISTRO_DOTTED` to be in scope.)

### WR-03: `publish_distro` masks an empty-artifact bug instead of failing the gated publish

**File:** `.github/workflows/build-packages.yml:340-355`
**Issue:** The publish helper deliberately *skips* (returns 0) when a distro's
download directory contains zero `.deb` files:
```bash
if [[ "${count}" -eq 0 ]]; then
  echo "WARNING: no .deb files in ${deb_dir} — skipping ci_publish.sh for ${label}"
  return 0
fi
```
The comment argues this guards against "an unexpected-but-non-fatal empty cell."
But the publish job only runs when `needs.build.result == 'success'` — i.e. *all four
cells succeeded*, which by contract means both distros produced artifacts. If the
download dir is nevertheless empty, that is a genuine defect (artifact
name/pattern mismatch, download failure, or a packaging bug that produced no debs
despite a "successful" build), and silently soft-publishing only the other distro
turns a detectable failure into a partial repository with no error. This contradicts
the phase's own "no partial publish / atomic" goal: the deploy still proceeds with
one distro missing.
**Fix:** Given the `success`-gated invariant, an empty deb dir should be fatal, not
skipped:
```bash
if [[ "${count}" -eq 0 ]]; then
  echo "ERROR: build reported success but no .deb files in ${deb_dir} for ${label}" >&2
  return 1
fi
```
If a soft-skip is genuinely desired for first-deploy bootstrapping, gate it behind an
explicit, documented input rather than making it the default behavior.

### WR-04: Test does not assert the publish job uses two distinct download *paths* (the actual no-merge guarantee)

**File:** `tests/test_ci_matrix.sh:178-186, 246-258`
**Issue:** The "no cross-distro merge" assertions verify the download *patterns* are
`{debs-2404-*, debs-2604-*}` and that no bare `debs-*` pattern exists. But the real
no-merge invariant is that the two downloads land in *different directories*
(`all-debs-2404/` vs `all-debs-2604/`). A regression that kept the two correct
patterns but pointed both at the *same* `path:` (e.g. both `all-debs/`) would merge
26.04 binaries into the 24.04 set and **pass every current assertion**. The test's
headline guarantee is under-specified.
**Fix:** Add a PyYAML assertion that the two download steps have distinct `path`
values, and a grep-floor assertion counting distinct `path:` lines under
`download-artifact`:
```python
paths = [s['with']['path'] for s in steps
         if isinstance(s.get('with'), dict) and 'pattern' in s['with']]
print('1' if len(paths) == len(set(paths)) == 2 else '0')
```

### WR-05: Grep-floor label counts use `grep -c` (lines, not occurrences) and a fragile literal

**File:** `tests/test_ci_matrix.sh:262-267`
**Issue:** The "ci_publish invoked for both distros" gate counts lines containing
`"2404"` / `"2604"`:
```bash
l2404=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec '"2404"')
```
`grep -c` counts matching *lines*, not matches, and the test only checks `>= 1`. This
gate passes as long as the string `"2404"` appears on any single non-comment line —
it does **not** prove `ci_publish.sh` is actually called with that label, nor that
both `publish_distro "2404" ...` and `publish_distro "2604" ...` invocations exist.
A refactor that dropped one `publish_distro` call but left the label referenced
elsewhere (a comment-stripped `case 2404)` would not match the quoted form, but an
echo or env reference could) would not be caught. The assertion is weaker than its
description claims.
**Fix:** Assert the actual invocation shape, e.g. grep for
`publish_distro[[:space:]]+"2404"` and `publish_distro[[:space:]]+"2604"`, and in the
PyYAML path inspect the `publish` "Build and publish repository" step's `run` block
for both `publish_distro "2404"` and `publish_distro "2604"` substrings.

## Info

### IN-01: `find` operator-precedence ambiguity in the debug step

**File:** `.github/workflows/build-packages.yml:226`
**Issue:**
```bash
find "$DESTDIR" -type f -name '*.so*' -o -type f -perm /111 2>/dev/null | head -50
```
Because `-o` has lower precedence than the implicit `-a`, this evaluates as
`(-type f -a -name '*.so*') -o (-type f -a -perm /111)`, which happens to be
acceptable, but the intent is unclear and the first `-type f` is redundant. The step
is `if: always()` and purely diagnostic, so this is non-fatal. Carried over from the
pre-matrix workflow.
**Fix:** Group explicitly: `find "$DESTDIR" -type f \( -name '*.so*' -o -perm /111 \)`.

### IN-02: `edge` track uses `eval` on grepped file content

**File:** `.github/workflows/build-packages.yml:208`
**Issue:** `eval "$(grep -E '^export (PROTOC_VERSION|PROTOC_TAG)=' versions-stable.env)"`.
The input is a repo-controlled file with double-quoted constants, so the practical
risk is low, but `eval` on file content is a pattern worth avoiding; the
`while IFS= read` parser used a few lines above for the stable track does the same
job without `eval`. Pre-existing, carried into the matrix job unchanged.
**Fix:** Reuse the line-parsing approach already present in the stable branch, or
`source` the two needed vars in a subshell and re-export them explicitly.

### IN-03: `runner.arch` comment is slightly misleading vs. `matrix.arch`

**File:** `.github/workflows/build-packages.yml:164-166`
**Issue:** The cache-key comment says `matrix.arch` is "authoritative regardless of
how the runner reports `runner.arch`." That is true and good, but the prior workflow
keyed on `runner.arch` (values like `X64`/`ARM64`), so any cache saved before this
change is now unreachable under the new `amd64`/`arm64` key namespace. This is the
intended behavior (clean cache cut-over) but is not documented; reviewers may worry
about a cache regression. Purely a documentation nit.
**Fix:** Add a one-line note that the key namespace intentionally changed from
`runner.arch` to `matrix.arch`, so the first post-merge run is a cold cache by design.

### IN-04: Test's bare-`debs-*` negative gate can be evaded by `debs-*-*`

**File:** `tests/test_ci_matrix.sh:250-254`
**Issue:** The "no bare cross-distro merge" negative check matches only
`pattern: debs-*$` (trailing end-of-line). A regression introducing
`pattern: debs-*-*` or `pattern: 'debs-*'` (quoted, or with trailing whitespace
followed by a comment) could slip past. Combined with WR-04, the no-merge guarantee
rests on assertions that are each individually evadable.
**Fix:** Tighten to also reject any download pattern that is not exactly one of the
two allowed forms; in the PyYAML path the existing set-equality check
(`pats == {'debs-2404-*','debs-2604-*'}`) is already strict — make the grep floor
match that strictness rather than only excluding one specific bare form.

---

## Narrative Findings (AI reviewer)

All findings above (CR-01, WR-01..WR-05, IN-01..IN-04) are narrative findings from
direct review of the two files. No structural pre-pass (`<structural_findings>`) was
supplied with this review.

**Correctly implemented (verified, no defect):**
- `fail-fast: false` (line 115) correctly isolates cell failures.
- `needs.build.result == 'success'` (line 278) correctly aggregates across all four
  matrix cells under a single `build` job — publish runs only when every cell passed,
  matching GitHub Actions matrix-job result semantics.
- Go cache `key`/`restore-keys` (167-170) and artifact `name` (262) both carry the
  `matrix.distro` + `matrix.arch` dimensions; no cross-distro cache or artifact
  collision is possible across the four cells.
- `merge-multiple: true` (307, 314) is correctly scoped to a single distro's two arch
  artifacts via the per-distro `pattern` + distinct `path` (subject to WR-04's test gap).
- `container: ${{ matrix.container }}` with `container: ''` for 2404 cells correctly
  yields a host-runner (non-container) execution for those cells.
- Per-distro sequential `ci_publish.sh "${TRACK}" "${label}" ...` invocations (354-355)
  pass compact labels `2404`/`2604` that `config.sh`'s `VALID_DISTROS=(2404 2604)` and
  `resolve_publish_targets` validate; the mirror-then-include model preserves the
  first distro's freshly published suites when the second runs.

---

_Reviewed: 2026-06-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
