---
phase: 22-migration-docs-installability-smoke-tests
reviewed: 2026-06-07T12:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - tests/test_docs_suites.sh
  - docs/apt-repository.md
  - tests/test_index_html_distro.sh
  - scripts/ci_publish.sh
  - scripts/smoke_repo_install.sh
  - .github/workflows/build-packages.yml
findings:
  critical: 0
  warning: 5
  info: 2
  total: 7
status: issues_found
---

# Phase 22: Code Review Report

**Reviewed:** 2026-06-07T12:00:00Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed six files covering migration documentation (`docs/apt-repository.md`), the CI multi-suite publisher (`scripts/ci_publish.sh`), the installability smoke gate (`scripts/smoke_repo_install.sh`), the CI workflow (`build-packages.yml`), and two test helpers (`tests/test_docs_suites.sh`, `tests/test_index_html_distro.sh`).

`docs/apt-repository.md` is complete and correct: all six distro-qualified suite names are present, the single `Signed-By` keyring path is used consistently throughout, the migration section and verbatim deprecation phrase match the assertions in `test_docs_suites.sh`, and `trusted=yes` does not appear anywhere in user-facing content. The `smoke_repo_install.sh` correctly validates both the distro label and the container runtime against closed whitelists before interpolation; the outer heredoc passes only a `${SUITE}` expansion into a container-side `cat << 'APTEOF'` (quoted delimiter), so there is no shell injection path. The `esc()` HTML-escaping helper in `ci_publish.sh` is applied in the correct `& < > "` order to all dynamic table values. The `sed -i "s|REPO_URL_PLACEHOLDER|${REPO_URL#https://}|g"` substitution is safe: in the CI workflow `REPO_URL` is constructed entirely from `github.repository_owner` and `github.event.repository.name`, which are GitHub-controlled values. `set -euo pipefail` discipline is maintained throughout all three shell scripts.

No Critical findings. Five Warnings and two Info items follow. The most significant findings are: the SHA-tracking cache key in `check-changes` is static, freezing the baseline after the first CI run so the skip optimisation permanently stops working; `available_suites[]` is built but never consumed anywhere (the D-10 guard test confirms only the text is present, not that the array functions); the `TRACK` environment variable is interpolated into the APT `Suites:` field without validation, contradicting the script's own security comment; and neither test is wired into CI so all MIGR-01/02/03 assertions are invisible to automated runs.

## Warnings

### WR-01: SHA-tracking cache frozen at first save — change-detection skip logic broken after first upstream change

**File:** `.github/workflows/build-packages.yml:40-44`
**Issue:** The `check-changes` job caches `/tmp/nightly-sha.json` under the **static** key `nightly-sha-v1` with no `restore-keys` and no `save-always`:

```yaml
- uses: actions/cache@v4
  with:
    path: /tmp/nightly-sha.json
    key: nightly-sha-v1
```

`actions/cache@v4` saves only on a cache **miss** (exact key not found). After the first cron run writes baseline snapshot S0, every subsequent run hits `nightly-sha-v1`, restores S0, and does not re-save the updated JSON the `detect` step writes to `$SHA_FILE`. The baseline is permanently frozen at S0.

Consequence: once any upstream component diverges from S0 (which happens on the first upstream push after the initial cron run), `HEAD_SHA != OLD_SHA` evaluates true every night and `skip=false` permanently. The diagnostic log also misstates the diff ("S0 → current" rather than "yesterday → current"). The intended nightly skip optimisation never fires again after the first upstream change.

Compare with the Go cache at lines 167–170, which correctly uses `key: go-...-${{ github.run_number }}` plus `restore-keys:` — the updatable-cache pattern. The SHA cache has neither.

**Fix:** Use a per-run dynamic key with a stable prefix so each run saves a fresh entry and the next run restores it:

```yaml
- uses: actions/cache@v4
  with:
    path: /tmp/nightly-sha.json
    key: nightly-sha-v1-${{ github.run_number }}
    restore-keys: |
      nightly-sha-v1-
```

Alternatively, split into `actions/cache/restore` + a separate `actions/cache/save` step with `if: always()` to save unconditionally.

---

### WR-02: `available_suites[]` is dead code — built but never consumed; D-10 test guard preserves dead code

**File:** `scripts/ci_publish.sh:465-470`
**Issue:** The `available_suites` array is populated in Step 5's preamble loop:

```bash
available_suites=()
for s in "${ALL_SUITES[@]}"; do
    if [[ -d "${OUTPUT_DIR}/dists/${s}" ]]; then
        available_suites+=("${s}")
    fi
done
```

It is never read again in the file. The Package Versions table (lines 613–653) is driven by `_all_pkgs` derived from bare-suite Packages files — `available_suites` plays no role. The preceding comment ("the empty-skip below hides suites whose Packages index is empty") describes intent that is not implemented; the suite-visibility gating logic was apparently dropped when the table was restructured into the three-column format.

The test assertion at `tests/test_index_html_distro.sh:80` pins the presence of the string `"available_suites"` as a "D-10 guard." This means the test passes, the variable stays in the source, and nobody notices it is never consumed. The guard is protecting dead code.

**Fix:** Either wire `available_suites` into the table so that suites without a populated Packages index are excluded (restoring the D-10 contract), or remove the loop and its comment, and update `test_index_html_distro.sh:80` to drop the now-meaningless assertion.

---

### WR-03: Spurious empty table row when all bare-suite Packages files are absent

**File:** `scripts/ci_publish.sh:628-633`
**Issue:** When none of the three bare-suite Packages files exist, `printf '%s\n'` with empty array expansions still produces one newline (POSIX `printf FORMAT` with zero arguments executes the format once with an implicit empty string). That one newline passes through `sort -u` unchanged, and `readarray -t` captures one empty-string element. The guard `[[ ${#_all_pkgs[@]} -gt 0 ]]` is therefore true, so the `<table>` block is emitted and the row loop writes one `<tr>` with an empty package-name cell and three `<code>—</code>` version cells.

This is confirmed by:
```bash
declare -A a b c   # all empty
printf '%s\n' "${!a[@]}" "${!b[@]}" "${!c[@]}" | wc -l   # outputs: 1
```

In the normal CI pipeline the 2404 publish always runs first and populates the bare-alias Packages files, so this is not reachable in the standard workflow. It is reachable in standalone invocations (e.g., a first-run 2604-only publish against a fresh output directory).

**Fix:** Filter empty strings from the union before `readarray`:

```bash
readarray -t _all_pkgs < <(
    { printf '%s\n' "${!_stable_v[@]}" "${!_edge_v[@]}" "${!_nightly_v[@]}"; } \
    | grep -v '^$' | sort -u
)
```

This makes the `[[ ${#_all_pkgs[@]} -gt 0 ]]` guard reliable regardless of invocation order.

---

### WR-04: `TRACK` interpolated into APT suite name without validation, contradicting the script's own security comment

**File:** `scripts/smoke_repo_install.sh:71`
**Issue:** `SUITE="${TRACK:-nightly}-${LABEL}"` is built from the `TRACK` environment variable. `TRACK` is never validated against the whitelist `{stable, edge, nightly}`. The script's security comment at lines 33–34 states: "Both are exact-match-validated against closed whitelists ({2404,2604} and {docker,podman}) BEFORE any use." This is true for `LABEL` and `SMOKE_RUNTIME` but false for `TRACK`. Line 59 calls it "the (constrained) TRACK" — the constraint comes only from the CI workflow's `choice`-type input, not from the script itself.

When called outside CI with an arbitrary `TRACK`, the value is interpolated literally into the DEB822 `Suites:` field inside the container's APT sources file. A malformed value causes an opaque `apt-get update` failure with a misleading "SMOKE FAIL" message rather than a clear validation error. More critically, the inaccurate security comment gives future maintainers a false assurance that all three user-influenceable inputs are bounded.

**Fix:** Add a `case` block immediately after line 70, mirroring the pattern used for `LABEL`:

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

Also update the security comment to accurately enumerate all three validated inputs.

---

### WR-05: Tests not wired into CI — MIGR-01/02/03/T-22 assertions are invisible to automated runs

**File:** `tests/test_docs_suites.sh:10-12` / `tests/test_index_html_distro.sh:6-9`
**Issue:** Both test files carry an explicit "LOCAL/MANUAL only" disclaimer and are not invoked by any step in `.github/workflows/build-packages.yml`. The tests enforce the `trusted=yes` absence boundary (T-22-DOC-01/T-22-HTML-02), the per-distro DEB822 snippet assertions (MIGR-02), the deprecation callout link (MIGR-03), and the migration section wording (MIGR-01). None of these properties are verified on every push. A commit that removes a distro-qualified suite name, adds `trusted=yes` to the heredoc, or renames the migration anchor will be silently undetected by CI.

These tests have no build prerequisites — they only require `bash` and `grep` and run against source files in the working tree.

**Fix:** Add a step to the `publish` job (or a standalone job with `needs: []`) that runs after checkout:

```yaml
- name: Run doc and HTML unit tests
  run: |
    bash tests/test_docs_suites.sh
    bash tests/test_index_html_distro.sh
```

This adds no compute time beyond a few seconds and gates the existing MIGR assertions automatically.

---

## Info

### IN-01: Package Versions table is distro-blind — always shows 24.04 build versions

**File:** `scripts/ci_publish.sh:615-616`
**Issue:** The version table reads `dists/${_track}/main/binary-amd64/Packages` for tracks `stable`, `edge`, `nightly` — the bare legacy alias suites. Per D-12, bare aliases are fed only from the 24.04 publish run. A visitor on 26.04 who clicks the "Ubuntu 26.04" distro toggle sees version numbers from 24.04 builds. The table column headers say "stable | edge | nightly" with no distro qualifier. When the bare aliases are removed in v3.1, the table will silently go empty with no fallback to the versioned `-2404`/`-2604` Packages files.

In practice, upstream component versions are identical between distros (only the version suffix differs), so the numbers are not wrong today — but the table provides no indication that it reflects 24.04 builds specifically.

**Fix (short-term):** Add a footnote below the `</table>` tag in the heredoc: "Versions shown are from Ubuntu 24.04 builds; 26.04 builds use the same upstream version with a `~ubuntu26.04.podman1` suffix."

**Fix (long-term):** Before v3.1, update the table loop to read from `stable-2404`/`stable-2604` etc. and render per-distro columns or a distro-aware toggle consistent with the setup instructions above the table.

---

### IN-02: `test_index_html_distro.sh` missing assertions for `edge-2404` and `nightly-2404`

**File:** `tests/test_index_html_distro.sh:61-64`
**Issue:** The test asserts four of the six distro-qualified suite names present in the `ci_publish.sh` heredoc: `stable-2404`, `stable-2604`, `edge-2604`, `nightly-2604`. It does not assert `edge-2404` (present at line 567 of `ci_publish.sh`) or `nightly-2404` (present at line 583). A future edit that accidentally drops or misnames either of those two snippets would not be caught by the test.

**Fix:** Add two assertions after the existing four:

```bash
assert_contains "$SRC" "edge-2404"    "suite edge-2404 in heredoc"
assert_contains "$SRC" "nightly-2404" "suite nightly-2404 in heredoc"
```

---

_Reviewed: 2026-06-07T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
