---
phase: 20-repository-restructure-migration-aliases
reviewed: 2026-06-07T00:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - config.sh
  - packaging/repo/conf/distributions
  - .github/workflows/build-packages.yml
  - scripts/ci_publish.sh
  - scripts/repo_byhash.sh
  - scripts/repo_manage.sh
  - tests/test_alias_routing.sh
  - tests/test_byhash_parse.sh
  - tests/test_distributions_suites.sh
  - tests/test_repo_assemble_byhash.sh
  - tests/test_suite_routing.sh
findings:
  critical: 2
  warning: 6
  info: 4
  total: 12
status: issues_found
---

# Phase 20: Code Review Report

**Reviewed:** 2026-06-07
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

Phase 20 restructures the reprepro repository from 3 suites to 9 (6 versioned
`<track>-<distro>` + 3 bare legacy aliases), adds an Acquire-By-Hash post-export
bolt-on with GPG re-signing (`scripts/repo_byhash.sh`), and threads track+distro
routing through `config.sh`, `scripts/repo_manage.sh`, `scripts/ci_publish.sh`,
and the CI publish job.

The routing helper (`resolve_publish_targets`), the subshell-exit-code pattern,
the awk Release-section parser, the by-hash materialization, and the no-clobber
mirror-then-include logic are all carefully reasoned and well-commented. The test
coverage is genuinely good — the integration harness in
`test_repo_assemble_byhash.sh` exercises the real signature chain and the
no-clobber property.

However, two defects will cause real failures in production: (1) a
`set -euo pipefail` interaction in `repo_byhash.sh` that aborts the helper when
SHA512 is absent or a checksummed file is missing, and (2) the bare-alias mirror
logic in `ci_publish.sh` cannot recover a 26.04 publish's bare-alias state and,
more critically, mishandles the alias when a **26.04** track is published (the
bare alias is then treated as an "other suite" and re-included from the live
repo, overwriting it with 24.04 content). Six warnings cover fragile GPG key
extraction, an unanchored grep, unquoted command substitutions, and an HTML
injection vector in the generated landing page.

## Critical Issues

### CR-01: `set -e` + `pipefail` aborts `add_byhash_and_resign` when a checksum command/section is absent

**File:** `scripts/repo_byhash.sh:72-79` (and the `awk | while` at `52-62`)
**Issue:**
The helper runs under the inherited `set -euo pipefail` from the sourcing script
(`ci_publish.sh` line 9). In the Release-self by-hash loop:

```bash
for algo in SHA256 SHA512; do
    local cmd="${algo,,}sum"
    command -v "${cmd}" >/dev/null || continue
    local rh
    rh="$(${cmd} "${lrelease}" | awk '{print $1}')"
    ...
done
```

A command substitution containing a pipe is subject to `pipefail`: if the left
side of the pipe (`sha512sum`) is missing the file or errors, the whole
substitution returns non-zero and `set -e` aborts the function mid-way — after
`InRelease`/`Release.gpg` have already been removed (line 83 runs in a later
block, but the analogous index loop at 52-62 runs first). I confirmed in a shell
that `rh="$(false | awk '{print $1}')"` aborts under `set -euo pipefail` even
with a separate `local rh` declaration.

More concretely: the awk-pipe-`while` at 52-62 reads each `<hash> <relpath>`
pair. The body does `[[ -f "${src}" ]] || continue` and `cp`. If reprepro emits
a relpath whose file genuinely does not exist (the very A1 case the comment at
line 56 says it defends against), the `continue` is fine — but the parser also
emits the **Release-relative entries for `Release` sub-files** that may not be
materialized for an empty suite, and any single `cp -f` failure (e.g. a
race/permission issue) propagates out of the `while`, and because the producer
`awk` is the pipe head, a transient awk failure aborts the whole publish.

The most reproducible trigger: on a host/keyring where only SHA256 is emitted,
the `SHA512` iteration of the **index** loop (52-62) runs `awk ... | while`
producing zero lines (fine), but the Release-self loop guards `sha512sum` with
`command -v`, so that is safe. The unguarded risk is the index `cp` and the awk
producer under pipefail. Because this helper is invoked for every one of up to 9
suites in `ci_publish.sh`, a single failure aborts the entire publish after some
suites are already re-signed — leaving a half-signed repository on Pages.

**Fix:** Defuse pipefail locally inside the helper, or split the pipes so the
exit status is controlled. Minimal, targeted fix:

```bash
add_byhash_and_resign() {
    local lsuite="$1" lrepo="$2"
    # This helper is sourced under `set -euo pipefail`; isolate it so a missing
    # algo/file or a benign non-zero pipe head does not abort the whole publish.
    local _saved_opts; _saved_opts="$(set +o)"
    set +e +o pipefail
    trap 'eval "${_saved_opts}"' RETURN
    ...
    # restore happens automatically on return via the RETURN trap
}
```

Alternatively replace each `rh="$(${cmd} "${lrelease}" | awk '{print $1}')"`
with an `awk`-free form: `rh="$(${cmd} "${lrelease}")"; rh="${rh%% *}"`, and
wrap the index `cp` loop body so a single failure is logged and skipped rather
than aborting. Add a regression case to `test_repo_assemble_byhash.sh` that runs
the helper against a Release where one listed index file has been deleted.

### CR-02: 26.04 publish treats the bare alias as an "other suite" and clobbers it with mirrored 24.04 content

**File:** `scripts/ci_publish.sh:113-125, 205-237`
**Issue:**
`resolve_publish_targets <track> 2604` returns **only** `<track>-2604` (no bare
alias — confirmed in `config.sh:115-117` and `test_suite_routing.sh` Test 2).
The `OTHER_SUITES` computation (lines 113-125) therefore includes the bare
`<track>` alias in `OTHER_SUITES` for every 26.04 publish.

In Step 2 (lines 143-186) the bare alias is mirrored down from the live repo
(its current contents are the 24.04 packages). In Step 4 (lines 214-237) those
mirrored debs are re-`includedeb`'d into the bare alias and the suite is
re-`export`ed. This is correct **as long as the live bare alias already holds the
intended 24.04 content** — i.e. it round-trips. But it has two failure modes:

1. **First-deploy / empty live repo for a 26.04-first publish:** the bare alias
   mirror download returns nothing (`suite_count=0`), Step 4 skips it (line
   216-219), and the bare alias is **not exported at all** — yet the
   `distributions` file declares it `SignWith: yes`. The Step 4b loop
   (lines 259-264) only re-signs suites that already have a `Release`, so the
   bare alias silently never materializes. That is the intended D-18 "hidden
   until populated" behavior, so acceptable — but see point 2.

2. **The no-clobber guarantee is violated for the bare alias whenever a 26.04
   publish runs concurrently or after a 24.04 publish in the same Pages
   generation.** Because the bare alias is rebuilt from a *fresh empty reprepro
   db* using only the mirrored debs, the re-export regenerates
   `dists/<track>/Release` with a **new Date and new signatures**, even though
   its package content is unchanged. The integration test only exercises 24.04
   publishes (`test_repo_assemble_byhash.sh` lines 217-220, 323) and never
   publishes a 26.04 track, so this path is entirely unverified. The comment at
   `ci_publish.sh:108-112` asserts "untouched suites are mirrored unchanged" —
   but mirroring then re-`includedeb` + re-`export` + re-sign is **not**
   unchanged: the Release Date changes and the signature is regenerated, so apt
   clients see a "new" InRelease for a track that did not actually change. With
   `Acquire-By-Hash`, a CDN mid-deploy can then serve the new InRelease against
   an old Packages (the exact hash-sum-mismatch the by-hash bolt-on is meant to
   prevent) for the bare alias.

**Fix:** Make the bare alias a first-class, distro-gated target rather than an
"other suite". When `DISTRO == 2404`, the alias is already a publish target
(good). When `DISTRO == 2604`, the bare alias must be **mirrored verbatim**
(copy the live `dists/<track>/` tree and pool entries as-is, with their existing
signatures) and **excluded from the re-includedeb/re-export loop** — exactly the
no-clobber path used for the other versioned suites only if those, too, are
copied verbatim. If the project's actual no-clobber strategy is "re-import every
other suite from debs and re-export," then the byte-identical claim in the
comments and the integration test must be expanded to publish a 26.04 track and
assert the bare alias `Release` Date/signature are preserved — currently neither
the code nor the tests cover a 26.04 publish at all.

## Warnings

### WR-01: GPG key-ID extraction grabs the first `fpr` with an unanchored grep — can pick a subkey or a false match

**File:** `scripts/repo_manage.sh:112, 193`
**Issue:**
```bash
GPG_KEY_ID=$(gpg --list-keys --with-colons | grep fpr | head -1 | cut -d: -f10)
```
`grep fpr` is unanchored: it matches any colon-record line containing the
substring `fpr` (a uid like `Frodo fpr fan` matches — confirmed). With
`--list-keys` the first `fpr:` record is the primary key fingerprint, which is
usually what you want, but on a keyring holding more than one public key
`head -1` silently selects whichever key sorts first — not necessarily the
secret key used for signing. Line 112 then writes that fingerprint to
`import-ownertrust`, and line 193 exports it as `podman-ubuntu.gpg`. A mismatched
key here means the published public key does not match the signing key and every
client `apt update` fails GPG verification.

**Fix:** Anchor the record type and prefer the secret key's fingerprint:
```bash
GPG_KEY_ID=$(gpg --list-secret-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
```
Use the same expression in both locations.

### WR-02: `total_other_count > 0` gate skips conf rebuild needed for first-deploy other suites

**File:** `scripts/ci_publish.sh:205-247`
**Issue:**
Step 4 only rebuilds `conf/` and re-includes other suites when
`total_other_count > 0` (line 205). On a first deploy where the live repo is
empty, `total_other_count == 0`, so the entire block is skipped — fine for the
empty suites. But the cleanup of `db/` and `conf/` (lines 240-241) only runs
inside the `if`. On the first-deploy path (`else`, lines 243-247) the `conf/`
and `db/` directories created by `repo_manage.sh` are already removed by
`repo_manage.sh` itself (lines 205-207 of that script), so this is benign today
— but it couples the two scripts' cleanup responsibilities implicitly. If
`repo_manage.sh` ever stops cleaning `db/`/`conf/`, `ci_publish.sh` will publish
reprepro internals to Pages on the first-deploy path. 

**Fix:** Move the `rm -rf "${OUTPUT_DIR}/db" "${OUTPUT_DIR}/conf"` cleanup to an
unconditional step that runs after Step 4 regardless of `total_other_count`, so
the publisher owns its own cleanup invariant rather than relying on the callee.

### WR-03: Unquoted `${scriptpath}/${relativepath}` in `realpath` toolpath bootstrap

**File:** `config.sh:9`, `scripts/ci_publish.sh:13`, `scripts/repo_manage.sh:8`, `scripts/repo_byhash.sh:8`
**Issue:**
```bash
toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath})
```
`${scriptpath}/${relativepath}` is unquoted. If the checkout path ever contains
a space (common on dev machines, e.g. the reviewer's
`/Users/slazarov/Documents/Coding/Repos/...` is fine, but CI runners and Lima
mounts vary), word-splitting passes two arguments to `realpath` and the toolpath
resolves wrong or `realpath` errors. The project style guide (AGENTS.md) mandates
"Always quote expansions."

**Fix:** `toolpath=$(realpath --canonicalize-missing "${scriptpath}/${relativepath}")`

### WR-04: HTML injection / breakage from unescaped package versions in generated `index.html`

**File:** `scripts/ci_publish.sh:388-405`
**Issue:**
Package names and versions parsed from the `Packages` index are interpolated
directly into HTML via heredocs:
```bash
<tr><td>${pkg}</td><td><code>${ver}</code></td></tr>
```
No HTML-escaping. While these values originate from the project's own `.deb`
control files (low external-attacker risk), a version string containing `<`,
`>`, or `&` (legal in Debian versions via epochs/`~`, and `&` is not but could
appear through a packaging bug) will produce malformed HTML or, if an upstream
tag is ever attacker-influenced (nightly builds from upstream HEAD), an XSS
vector on the published Pages site.

**Fix:** Escape the four HTML metacharacters before interpolation:
```bash
esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
pkg_e=$(printf '%s' "$pkg" | esc); ver_e=$(printf '%s' "$ver" | esc)
```
and emit `${pkg_e}` / `${ver_e}`.

### WR-05: `sed -i '/^Suite:/a Acquire-By-Hash: yes'` appends after *every* `Suite:` line

**File:** `scripts/repo_byhash.sh:67-68`
**Issue:**
A reprepro `Release` has exactly one top-level `Suite:` line, so this is correct
in practice. But the `sed` append matches any line beginning `Suite:`. If a
future Release format (or a Description field wrapped onto a continuation line
that happens to start with `Suite:`) introduces a second match, two
`Acquire-By-Hash: yes` lines are injected. The idempotency guard (`grep -q
'^Acquire-By-Hash:'`) prevents re-injection on a *second run*, but not double
injection within a single run if two `Suite:` lines exist.

**Fix:** Constrain to the first match: `sed -i '0,/^Suite:/{/^Suite:/a Acquire-By-Hash: yes
}'` (GNU sed range form), or use awk to insert once after the first `Suite:`.

### WR-06: `pkg_count` from `grep -c` is the amd64-only count and is used to gate suite visibility

**File:** `scripts/ci_publish.sh:379-386`
**Issue:**
```bash
packages_file="${OUTPUT_DIR}/dists/${s}/main/binary-amd64/Packages"
pkg_count=$(grep -c "^Package:" "${packages_file}" 2>/dev/null || true)
```
The visibility decision for a suite is made solely from the **amd64** index. An
arm64-only suite (or a suite whose amd64 index failed to materialize while arm64
succeeded) would be hidden from the landing page despite having content. Given
both arches are always built together this is unlikely today, but it is a silent
correctness gap in the landing-page rendering. The `2>/dev/null || true` also
swallows a genuinely missing-directory error that would indicate a broken
export.

**Fix:** Count across both arches, or check for the existence of any
`binary-*/Packages` with a non-zero `^Package:` count before deciding to skip.

## Info

### IN-01: Dead `Release` by-hash copy — apt never fetches Release/InRelease by hash

**File:** `scripts/repo_byhash.sh:71-79`
**Issue:** apt's Acquire-By-Hash applies only to the index files *listed inside*
Release (Packages, Contents, etc.). `Release`/`InRelease` themselves are always
fetched by fixed path (`dists/<suite>/InRelease`). The by-hash copy of `Release`
created at lines 72-79 is never requested by any client — harmless dead weight,
but it adds files and obscures intent.
**Fix:** Drop the Release-self by-hash block, or document why it is intentionally
materialized (e.g. for a future tooling consumer).

### IN-02: `local cmd`/`local rh` declared inside a `for` loop body

**File:** `scripts/repo_byhash.sh:73, 75`
**Issue:** `local` inside a loop re-declares on each iteration; harmless but
slightly wasteful and unusual. Minor style nit.
**Fix:** Declare `local cmd rh` once at function top alongside `algo`.

### IN-03: Magic distro literal `2404` duplicated across config, scripts, workflow

**File:** `config.sh:115`, `.github/workflows/build-packages.yml:295`, comments throughout
**Issue:** The "2404 gets the bare alias" rule is encoded as a bare string
literal in `resolve_publish_targets` and the CI `distro=2404` output. The
workflow comment (line 293-294) flags this as a deliberate one-line Phase-21
change, so it is acknowledged tech debt.
**Fix:** None required for this phase; track for Phase 21 matrix work.

### IN-04: `is_valid_suite` is defined and tested but never called by any reviewed script

**File:** `config.sh:73-81`
**Issue:** `is_valid_suite` is exercised only by `test_suite_routing.sh`; neither
`ci_publish.sh` nor `repo_manage.sh` calls it (they rely on
`resolve_publish_targets` for validation instead). Not a defect — likely intended
as a public helper / guard for future callers — but currently dead in the
production path.
**Fix:** Either wire it into the suite loops as a defensive guard, or note it as
an intentional public API.

---

_Reviewed: 2026-06-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
