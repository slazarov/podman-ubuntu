---
phase: 20-repository-restructure-migration-aliases
reviewed: 2026-06-06T22:04:06Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - .github/workflows/build-packages.yml
  - config.sh
  - packaging/repo/conf/distributions
  - scripts/ci_publish.sh
  - scripts/repo_byhash.sh
  - scripts/repo_manage.sh
  - tests/test_alias_routing.sh
  - tests/test_byhash_parse.sh
  - tests/test_distributions_suites.sh
  - tests/test_repo_assemble_byhash.sh
  - tests/test_suite_routing.sh
findings:
  critical: 1
  warning: 4
  info: 3
  total: 8
status: issues_found
---

# Phase 20: Code Review Report

**Reviewed:** 2026-06-06T22:04:06Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

This is a re-review after gap closure. I verified the four claimed fixes and
reviewed the remaining scoped files adversarially.

**Prior-fix verification:**

- **CR-01 (pipefail isolation in `add_byhash_and_resign`)** — VERIFIED SOUND.
  The saved-options + `set +e +o pipefail` + RETURN-trap restore pattern works as
  intended. I reproduced it: a benign non-zero pipe head no longer aborts the
  function between `rm -f InRelease Release.gpg` and the re-sign, and the RETURN
  trap restores the caller's exact option set on every return path (`set +o`
  round-trips correctly). One caveat noted as WR-01.

- **CR-02 (verbatim mirror of untouched suites)** — INTENT SOUND, MECHANISM BROKEN.
  The Step-4/Step-4b exclusion bookkeeping (`IS_VERBATIM`, `VERBATIM_SUITES`,
  `total_other_count` gating) is correct, but the underlying mirror does not work
  for the GitHub project-pages URL the CI actually uses. See **CR-01** below. The
  CDN hash-mismatch regression CR-02 was meant to close is reintroduced at runtime.

- **WR-01 (anchored GPG fingerprint)** — VERIFIED SOUND. `awk -F: '/^fpr:/{print
  $10; exit}'` is anchored and stops at the primary-key fingerprint
  (repo_manage.sh:112, 193).

- **WR-03 (quoted realpath bootstraps)** — VERIFIED SOUND. All bootstraps quote
  `"${scriptpath}/${relativepath}"`.

- **WR-04 (HTML-escaped index.html)** — VERIFIED SOUND. `esc()` escapes
  `&`/`<`/`>`/`"` in the correct order (`&` first) and is applied to both package
  name and version.

The single BLOCKER below reintroduces the exact CDN hash-mismatch regression that
CR-02 was created to close, on the standard project-pages URL CI uses.

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: `mirror_suite_verbatim` saves the wget tree to the wrong path for project-pages URLs — verbatim mirroring silently never happens in CI

**File:** `scripts/ci_publish.sh:181-208`
**Issue:**
The verbatim mirror runs `wget -q -r -np -nH --cut-dirs=0 -P "${lmirror}"
"${REPO_URL}/dists/${lsuite}/"` and then checks for the result at
`"${lmirror}/dists/${lsuite}"` (line 201).

In CI, `REPO_URL` is a GitHub **project-pages** URL with a repo-name path segment:
`.github/workflows/build-packages.yml:316` passes
`https://${{ github.repository_owner }}.github.io/${{ github.event.repository.name }}`.

`wget -nH` strips only the hostname; `--cut-dirs=0` cuts **zero** leading path
directories. So `https://owner.github.io/REPONAME/dists/stable/Release` is saved to
`${lmirror}/REPONAME/dists/stable/Release` — with a leading `REPONAME/`. The GNU
wget man page confirms this: `-nH --cut-dirs=1` on `.../pub/xemacs/` yields
`xemacs/`, so `--cut-dirs=0` retains the full `REPONAME/dists/stable/` path.

Consequences, in order:
1. `[[ -d "${lmirror}/dists/${lsuite}" ]]` at line 201 is **false** (the tree is
   under `${lmirror}/REPONAME/dists/${lsuite}`), so the function takes the `else`
   branch (lines 205-207) and `return 1`.
2. The curl fallback at lines 185-197 does **not** run, because it is gated on
   `wget` *failing* (`if ! wget ...`). Here wget *succeeds* (it fetched the files,
   just under the wrong prefix), so the fallback is skipped.
3. `mirror_suite_verbatim` returns 1 → `IS_VERBATIM["${suite}"]=false` → the suite
   is fed back through the re-includedeb / re-export path (Step 4) and re-signed
   (Step 4b).

Net effect: for every non-target suite on a project-pages deploy (all of CI), the
CR-02 verbatim path is dead. Untouched suites get a fresh `Release` Date + new
signature on byte-identical content, **reopening the Acquire-By-Hash CDN
hash-mismatch window CR-02 exists to prevent**. The fix is effectively a no-op in
production. (It would coincidentally work only for a user/org root-pages site whose
URL has no path segment — not the CI case.)

This is untested: Test group G in `tests/test_repo_assemble_byhash.sh` never calls
`mirror_suite_verbatim` or `ci_publish.sh` — it drives `repo_manage.sh` directly
and *simulates* verbatim by not re-signing the bare alias. The wget path bug
therefore passes all current tests.

**Fix:** Derive cut-dirs from the repo path depth instead of hardcoding `0`, or key
the post-mirror lookup off the actual saved path. Robust lookup approach:

```bash
# after the wget/curl block, locate the tree wherever wget placed it
local lsrc
lsrc="$(find "${lmirror}" -type d -path "*/dists/${lsuite}" -print -quit)"
if [[ -n "${lsrc}" ]]; then
    mkdir -p "${OUTPUT_DIR}/dists"
    rm -rf "${OUTPUT_DIR}/dists/${lsuite}"
    cp -a "${lsrc}" "${OUTPUT_DIR}/dists/${lsuite}"
else
    rm -rf "${lmirror}"; return 1
fi
rm -rf "${lmirror}"; return 0
```

Or compute the count and pass `--cut-dirs="${lcut}"`:

```bash
local lpath="${REPO_URL#*://}"; lpath="${lpath#*/}"   # path segments below host
local lcut=0
[[ "${lpath}" != "${REPO_URL#*://}" && -n "${lpath}" ]] && lcut=$(awk -F/ '{print NF}' <<<"${lpath%/}")
wget -q -r -np -nH --cut-dirs="${lcut}" -P "${lmirror}" "${REPO_URL}/dists/${lsuite}/"
```

Then add a test that drives `mirror_suite_verbatim` against a `file://`/local-HTTP
repo whose URL carries a path segment, asserting the tree lands at
`${OUTPUT_DIR}/dists/<suite>` and that the served `Release` Date is byte-identical
to source.

## Warnings

### WR-01: Final-`gpg` failure in `add_byhash_and_resign` aborts with a misleading line number; a failed `--clearsign` is swallowed

**File:** `scripts/repo_byhash.sh:102-104`; call site `scripts/ci_publish.sh:383`
**Issue:** The helper disables `set -e` internally (correct, per CR-01), so its
return value is the exit code of its last command — the `gpg -abs` at line 103. If
that final `gpg` genuinely fails (key expired, gpg-agent crash), the function
returns non-zero, the RETURN trap restores `set -euo pipefail`, the caller's ERR
trap fires, and `error_handler` exits — the safe direction, but it reports the
call-site line (ci_publish.sh:383), not the failing gpg line. Worse, a failure on
the inline `--clearsign` at line 102 is silently swallowed (errexit off) and only
surfaces if the subsequent `-abs` *also* fails — so a publish could ship a stale or
missing `InRelease` while `Release.gpg` succeeds.
**Fix:** Check each `gpg` explicitly inside the helper and return on failure:
```bash
gpg --batch --yes --clearsign -o "${ldist}/InRelease" "${lrelease}" \
    || { echo "ERROR: clearsign failed for ${lsuite}" >&2; return 1; }
gpg --batch --yes -abs -o "${ldist}/Release.gpg" "${lrelease}" \
    || { echo "ERROR: detached-sign failed for ${lsuite}" >&2; return 1; }
```

### WR-02: Verbatim pool download failures leave a signed `Packages` index referencing missing pool files

**File:** `scripts/ci_publish.sh:251-264`
**Issue:** For a verbatim-mirrored suite, the live `Packages` index is copied
byte-for-byte (so apt trusts it) and the pool `.deb` files it references are
downloaded to `${OUTPUT_DIR}/${filename}`. If a pool download fails (line 257 curl
non-zero), the code logs a WARNING, removes the partial file, and continues — but
the index still lists that `Filename`. The result is a signed, verifiable
`Packages` index pointing at a pool path that 404s, so `apt-get install` of that
package fails on the client even though metadata verified. No abort, no
missing-count surfaced.
**Fix:** Treat a failed pool download for a verbatim suite as fatal for that suite
(fall back to non-verbatim, or abort), since serving a signed index that references
absent pool files is worse than re-signing. At minimum, track failures and abort if
any verbatim pool entry could not be fetched.

### WR-03: `sed` placeholder substitution breaks if `REPO_URL` contains `&` or `|`

**File:** `scripts/ci_publish.sh:559`
**Issue:** `sed -i "s|REPO_URL_PLACEHOLDER|${REPO_URL#https://}|g"` injects the URL
unescaped into the sed replacement. A `|` in the URL terminates the s-command
(syntax error) and a `&` expands to the whole match. I reproduced the `|`-induced
failure. `REPO_URL` is a controlled CI input so real-world risk is low, but the
failure mode is silent `index.html` corruption rather than a clean error.
**Fix:** Escape the replacement or avoid sed:
```bash
url_repl="${REPO_URL#https://}"
url_repl="${url_repl//&/\\&}"; url_repl="${url_repl//|/\\|}"
sed -i "s|REPO_URL_PLACEHOLDER|${url_repl}|g" "${OUTPUT_DIR}/index.html"
```

### WR-04: Curl fallback in `mirror_suite_verbatim` produces an incomplete verbatim tree

**File:** `scripts/ci_publish.sh:185-197`
**Issue:** When wget is unavailable, the curl fallback fetches only
`Release`/`InRelease`/`Release.gpg` plus per-arch `Packages` and `Release`. It omits
`Packages.gz`, the `by-hash/<ALGO>/<hash>` copies, and any `Contents`/`i18n` files
the live `Release` checksums. The copied (trusted) `Release` still lists those
omitted files with checksums, so an apt client requesting `Packages.gz` or a
by-hash path gets a 404 / hash mismatch — the very failure this bolt-on prevents.
Combined with CR-01, this fallback is currently the *only* path that can succeed,
making the gap load-bearing.
**Fix:** Make the fallback mirror every file the `Release` lists (parse the
SHA256/SHA512 sections and fetch each relpath plus its by-hash copy), or require
`wget`/`rsync` and fail closed (return 1 → full re-export) when neither is
available, rather than serving a partial signed tree.

## Info

### IN-01: Wrong-file/line ERR diagnostics across sourced helpers

**File:** `scripts/ci_publish.sh:27`, `scripts/repo_byhash.sh:17`, `scripts/repo_manage.sh:17`
**Issue:** `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR` is re-installed in
each sourced script. Because `ci_publish.sh` sources `repo_byhash.sh`, the trap is
defined twice and `$BASH_SOURCE` at fire time reflects the currently-executing
file, which misleads when a failure crosses the source boundary (see WR-01).
**Fix:** Install one trap in the top-level entrypoint, or include `${FUNCNAME[0]}`
in `error_handler` output.

### IN-02: `mirror_suite_verbatim` comment claims "Never aborts the caller" but runs under inherited `set -e`

**File:** `scripts/ci_publish.sh:166-211`
**Issue:** Unlike `add_byhash_and_resign`, this helper does not disable errexit.
The "never aborts" contract holds today only because every fallible command is
guarded. A future unguarded command (a `cp -a` to a read-only dest, `mktemp -d`
out of space) would abort the entire publish, contradicting the comment.
**Fix:** Apply the same save-options/`set +e`/RETURN-trap isolation, or soften the
comment to "all fallible commands are individually guarded."

### IN-03: Content-addressed `cp -f` rewrite is a no-op rebuild (note for any future live-tree mutation)

**File:** `scripts/repo_byhash.sh:78-80, 95-96`
**Issue:** `cp -f "${src}" "${bhdir}/${hash}"` overwrites an existing by-hash file
whose name *is* its content hash, so the destination, if present, is already
byte-identical. Harmless in this offline-assemble flow. If the helper were ever run
against a live-served tree, the truncate-then-rewrite would be a serving race.
**Fix:** None required now; if mutating a live tree later, skip the copy when the
destination exists or write-temp-then-`mv` atomically.

---

_Reviewed: 2026-06-06T22:04:06Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
