---
phase: 22-migration-docs-installability-smoke-tests
reviewed: 2026-06-07T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - .github/workflows/build-packages.yml
  - docs/apt-repository.md
  - scripts/ci_publish.sh
  - scripts/smoke_repo_install.sh
  - tests/test_docs_suites.sh
  - tests/test_index_html_distro.sh
findings:
  critical: 0
  warning: 5
  info: 2
  total: 7
status: issues_found
---

# Phase 22: Code Review Report

**Reviewed:** 2026-06-07T00:00:00Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed six files covering migration documentation, the CI publish pipeline, the installability smoke gate, and the associated test suite for Phase 22 (migration docs + installability smoke tests).

The `docs/apt-repository.md` is correct and complete: all six distro-qualified suite names are present, the single `Signed-By` keyring path is used consistently, the migration section and deprecation wording match the `test_docs_suites.sh` assertions, and `trusted=yes` does not appear anywhere in user-facing content. In `smoke_repo_install.sh`, the distro label and container runtime are each validated against closed whitelists before use. The outer heredoc in the smoke gate only expands `${SUITE}` host-side; that value lands inside a container-side `cat << 'APTEOF'` heredoc (quoted delimiter), so there is no shell injection path even with a hostile `TRACK`. The `esc()` HTML-escaping helper in `ci_publish.sh` is applied to all dynamic table values. The `sed -i "s|REPO_URL_PLACEHOLDER|${REPO_URL#https://}|g"` substitution is safe: `REPO_URL` is constructed entirely from GitHub-controlled values (`github.repository_owner`, `github.event.repository.name`) in the workflow, giving no attacker influence over the replacement string. The `set -euo pipefail` discipline is maintained throughout all three shell scripts.

Five warnings and two informational findings are reported below. The most impactful are: the SHA-tracking cache in `check-changes` uses a static key with no `save-always`/`restore-keys`, so the baseline is frozen at first save and the skip-optimization stops working correctly after the first upstream change; `available_suites[]` is built but never consumed (the D-10 guard test proves only the code text is present, not that it functions); `TRACK` is not validated before interpolation despite the script's security comment implying otherwise; and neither test file is wired into CI.

## Warnings

### WR-01: SHA-tracking cache frozen at first save — change-detection skip logic broken

**File:** `.github/workflows/build-packages.yml:40-44`
**Issue:** The `check-changes` job caches `/tmp/nightly-sha.json` under the static key `nightly-sha-v1` with no `restore-keys` and no `save-always`:

```yaml
- uses: actions/cache@v4
  with:
    path: /tmp/nightly-sha.json
    key: nightly-sha-v1
```

`actions/cache@v4` saves to the cache only on a **miss** — when the exact key is not present. After the first cron run writes snapshot S0, every subsequent run hits the same key, restores S0, and never re-saves the updated snapshot the `detect` step writes to `$SHA_FILE`. The baseline is permanently frozen at S0.

Consequence: once any upstream component changes from S0 (which happens on the very first upstream push after the initial run), `HEAD_SHA != OLD_SHA` is true every night and `skip=false` permanently. The step's "Changes detected" output also misstates what changed (always `S0 → current` rather than `yesterday → current`), which makes the diagnostic log misleading. The skip optimization never fires again.

The contrast with the Go cache (lines 167–170) makes this a deliberate omission: the author uses `key: go-...-${github.run_number}` with `restore-keys:` for the Go cache — the updatable-cache pattern. The SHA cache uses neither.

**Fix:** Use a dynamic key with a stable `restore-keys` prefix so each run saves a new entry and the next run restores it:

```yaml
- uses: actions/cache@v4
  with:
    path: /tmp/nightly-sha.json
    key: nightly-sha-v1-${{ github.run_number }}
    restore-keys: |
      nightly-sha-v1-
```

Alternatively, replace the `actions/cache` pair with `actions/cache/restore` + a separate `actions/cache/save` step (with `if: always()`) to save unconditionally.

---

### WR-02: `available_suites[]` is dead code — built but never consumed

**File:** `scripts/ci_publish.sh:465-470`
**Issue:** The `available_suites` array is populated in a loop over `ALL_SUITES` (lines 465–470) but is never read anywhere in the file. The Package Versions table (lines 613–653) is driven by `_all_pkgs` derived from bare-suite Packages files, not by `available_suites`. The preceding comment ("the empty-skip below hides suites whose Packages index is empty") describes intent that is not implemented — the suite-gating logic was apparently lost when the table was restructured into the three-column track format in a prior phase.

The test at `tests/test_index_html_distro.sh:80` pins the presence of the string `available_suites` as a "D-10 guard," which means: (a) the test passes, (b) the variable stays in the code, and (c) nobody notices the array is never used. The D-10 phase design constraint (`22-CONTEXT.md:39`, `22-RESEARCH.md:42`) states "The 'Available Suites' table iterates available_suites[] and skips empty suites" — the current code violates that contract silently.

**Fix:** Either consume `available_suites` to filter which suites appear in the package-versions table (restoring the D-10 intent), or remove both the loop and the misleading comment. If removal is chosen, update `test_index_html_distro.sh:80` to drop the `available_suites` D-10 guard assertion — leaving it in would "protect" code that no longer serves any purpose.

---

### WR-03: Spurious empty `<tr>` row emitted in Package Versions table when all bare suites are missing

**File:** `scripts/ci_publish.sh:628-633`
**Issue:** When none of the three bare-suite Packages files exist (e.g., a standalone invocation of `ci_publish.sh` for only the 2604 distro against a fresh output directory, before any 2404 run has populated the bare aliases), `readarray` produces an array of one empty element rather than zero elements:

```bash
declare -A a b c   # all empty associative arrays
readarray -t all_pkgs < <(
    { printf '%s\n' "${!a[@]}" "${!b[@]}" "${!c[@]}"; } | sort -u
)
# ${#all_pkgs[@]} == 1, all_pkgs[0] == ""
```

The guard `[[ ${#_all_pkgs[@]} -gt 0 ]]` (line 633) is therefore true, so the `<table>` block is emitted. The row loop then writes one `<tr>` with an empty package name cell and three `<code>—</code>` cells. Note: in the standard CI workflow, the 2404 publish always runs first and populates the bare-alias Packages files before Step 5 executes, so this is not reachable in the normal pipeline. It is reachable in standalone or defensive invocations.

**Fix:** Filter empty strings from the union before `readarray`:

```bash
readarray -t _all_pkgs < <(
    { printf '%s\n' "${!_stable_v[@]}" "${!_edge_v[@]}" "${!_nightly_v[@]}"; } \
    | grep -v '^$' | sort -u
)
```

This makes the `[[ ${#_all_pkgs[@]} -gt 0 ]]` guard reliable regardless of invocation order.

---

### WR-04: `TRACK` env var interpolated into APT suite name without validation

**File:** `scripts/smoke_repo_install.sh:71`
**Issue:** `SUITE="${TRACK:-nightly}-${LABEL}"` is built from the `TRACK` environment variable, which is never validated against the whitelist `{stable, edge, nightly}`. The script's own security comment (lines 33–34) states: "Both are exact-match-validated against closed whitelists ({2404,2604} and {docker,podman}) BEFORE any use." This is accurate for `LABEL` and `SMOKE_RUNTIME` but **not** for `TRACK`. Line 59 describes it as "the (constrained) TRACK" — the constraint exists only when called from CI (where `inputs.build_track` is a `choice`-type input). When the script is called outside CI, any value reaches the DEB822 `Suites:` line.

Although a malformed `TRACK` cannot cause shell injection (the value expands into a container-side `cat << 'APTEOF'` heredoc, which treats it as literal text), it produces a malformed DEB822 source file, a cryptic `apt-get update` failure, and a misleading smoke-fail message. More importantly, the inaccurate security comment creates a false sense of safety for maintainers adding new interpolations in the future.

**Fix:** Add a `case` block after line 70, mirroring the pattern used for `LABEL`:

```bash
case "${TRACK:-nightly}" in
    stable|edge|nightly) ;;
    *)
        echo "ERROR: TRACK must be exactly 'stable', 'edge', or 'nightly' (got '${TRACK:-}')." >&2
        exit 1
        ;;
esac
SUITE="${TRACK:-nightly}-${LABEL}"
```

Also update the security comment to accurately state that all three user-influenceable inputs are validated.

---

### WR-05: Neither test file is wired into CI — doc and HTML regressions go undetected

**File:** `tests/test_docs_suites.sh:10-12` / `tests/test_index_html_distro.sh:6-9`
**Issue:** Both test files carry an explicit "LOCAL/MANUAL only" disclaimer and are confirmed absent from `.github/workflows/build-packages.yml` (no workflow step invokes them). The tests enforce MIGR-01/MIGR-02/MIGR-03/T-22-DOC-01/T-22-HTML-02 properties — the `trusted=yes` absence check, the migration anchor link, the per-distro DEB822 snippet assertions, and the D-10 table guard — none of which run automatically on every push. A future commit that breaks any of those properties will ship silently.

**Fix:** Add a step to the workflow, either in the `build` job (before packaging) or as a standalone job with no `needs:`. The tests have no build prerequisites; they only require `bash` and `grep`:

```yaml
- name: Run doc and HTML unit tests
  run: |
    bash tests/test_docs_suites.sh
    bash tests/test_index_html_distro.sh
```

Because these tests check only source-file content, they require no build artifacts and can run on any `ubuntu-24.04` runner.

---

## Info

### IN-01: Package Versions table reads only bare-suite (24.04) Packages files

**File:** `scripts/ci_publish.sh:615-616`
**Issue:** The version table loop iterates `for _track in stable edge nightly` and reads `dists/${_track}/main/binary-amd64/Packages` — the bare legacy alias suites. Per D-12, bare aliases are populated only from the 24.04 publish run. Therefore the table always shows 24.04 build versions. A 26.04 visitor sees version numbers from 24.04 builds with no indication that this is the case.

In practice, upstream component versions are identical between distros (only the distro version suffix differs), so the numbers are not wrong — but the table gives no indication they represent 24.04 builds specifically.

**Fix:** Add a footnote below the table noting "versions shown are from Ubuntu 24.04 builds; 26.04 builds use the same upstream version with a `~ubuntu26.04.podman1` suffix." This is a one-line addition to the HTML heredoc in Step 5.

---

### IN-02: Incomplete suite-name coverage in `test_index_html_distro.sh`

**File:** `tests/test_index_html_distro.sh:61-64`
**Issue:** The test asserts `stable-2404`, `stable-2604`, `edge-2604`, and `nightly-2604` in the `ci_publish.sh` heredoc. It does not assert `edge-2404` (present at line 567) or `nightly-2404` (present at line 583). A future edit that accidentally deletes or misnames either of those two snippets would not be caught.

**Fix:** Add two assertions:

```bash
assert_contains "$SRC" "edge-2404"    "suite edge-2404 in heredoc"
assert_contains "$SRC" "nightly-2404" "suite nightly-2404 in heredoc"
```

---

_Reviewed: 2026-06-07T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
