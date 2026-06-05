---
phase: 19-per-distro-versioning-dependency-mapping
reviewed: 2026-06-05T00:00:00Z
depth: standard
files_reviewed: 13
files_reviewed_list:
  - config.sh
  - functions.sh
  - packaging/nfpm/buildah.yaml
  - packaging/nfpm/conmon.yaml
  - packaging/nfpm/crun.yaml
  - packaging/nfpm/pasta.yaml
  - packaging/nfpm/podman.yaml
  - packaging/nfpm/skopeo.yaml
  - scripts/package_all.sh
  - scripts/smoke_install_2604.sh
  - scripts/verify_depends.sh
  - scripts/verify_versions.sh
  - tests/test_detect_distro_depends.sh
findings:
  critical: 1
  warning: 6
  info: 4
  total: 11
status: issues_found
---

# Phase 19: Code Review Report

**Reviewed:** 2026-06-05T00:00:00Z
**Depth:** standard
**Files Reviewed:** 13
**Status:** issues_found

## Summary

Reviewed the per-distro versioning + build-time dependency-detection work: distro
detection (`detect_distro_version_id`), ldd->dpkg-query runtime-dep mapping
(`detect_runtime_depends`), `envsubst` injection of `${DETECTED_DEPENDS}` into the
nFPM YAMLs, and three verification scripts.

The shell-injection surface is well-defended: `detect_distro_version_id` validates
against `^[0-9]+\.[0-9]+$` before the value reaches the version string/`.deb`
filename, the smoke runner allowlists `SMOKE_RUNTIME` to `docker|podman` and pattern-
checks `SMOKE_IMAGE`, and the `envsubst` allowlist (`${VERSION} ${ARCH} ${DESTDIR}
${DETECTED_DEPENDS}`) is correct (suite render correctly omits `${DETECTED_DEPENDS}`).
The dpkg version-ordering oracle in `verify_versions.sh` is semantically sound on all
six assertions.

The findings below concern correctness/robustness of the dep detector's failure path,
the empty-`depends:` render shape for inject-only components, dpkg-query multi-line
parsing, and a portability mismatch with the repo's "debian" name.

## Critical Issues

### CR-01: `detect_runtime_depends` hard-fail diagnostic is preempted by `set -e`/`pipefail`, and an unmapped library can abort with a generic error instead of the intended D-03 message

**File:** `functions.sh:114-122`
**Issue:** The intended D-03 behavior is: an unmapped `.so` produces the explicit
message `ERROR: no owning package for <lib> (linked by <bin>)` via the `[[ -z "${pkg}" ]]`
guard (lines 117-120). But the assignment on line 116 is:

```bash
pkg="$(dpkg-query -S "$(realpath "${lib}")" 2>/dev/null | awk -F: '{print $1}' | head -n1)"
```

The caller (`package_all.sh`) runs under `set -euo pipefail`, and `detect_runtime_depends`
is invoked inside a command substitution. When `dpkg-query -S` exits non-zero (the exact
"unmapped library" case D-03 is meant to catch), `pipefail` makes the pipeline exit
non-zero. Whether the explicit guard on line 117 is reached or `set -e` aborts the
assignment first is context-dependent (it differs between a bare top-level run and a
`func | sed` pipeline). The net effect: the build still hard-fails (so the *safety*
property holds), but the operator can get an opaque generic ERR-trap failure at line 116
instead of the actionable "no owning package for X" message — defeating the documented
diagnostic and making a real unmapped-soname incident hard to triage.

Additionally, `2>/dev/null` swallows `dpkg-query`'s own stderr (e.g. "no path found
matching pattern"), removing the one line that would tell the operator *which* path
failed to map.

**Fix:** Decouple the lookup from the pipeline so the explicit guard always runs, and
capture the failure reason instead of discarding it:

```bash
local resolved dpkg_out
resolved="$(realpath "${lib}")"
# Run dpkg-query outside a pipeline so its exit status is testable and its
# stderr is preserved for the D-03 message.
if ! dpkg_out="$(dpkg-query -S "${resolved}" 2>&1)"; then
    echo "ERROR: no owning package for ${lib} -> ${resolved} (linked by ${bin})" >&2
    echo "  dpkg-query: ${dpkg_out}" >&2
    return 1
fi
# Take the package field of the first line; strip :arch multiarch qualifier.
pkg="$(printf '%s\n' "${dpkg_out}" | head -n1 | awk -F: '{print $1}')"
if [[ -z "${pkg}" ]]; then
    echo "ERROR: could not parse owning package for ${lib} (linked by ${bin}); dpkg-query said: ${dpkg_out}" >&2
    return 1
fi
```

## Warnings

### WR-01: `head -n1` placed AFTER `awk` mis-parses multi-line `dpkg-query -S` output (diversions / multi-owner paths)

**File:** `functions.sh:116`
**Issue:** `dpkg-query -S <path>` can emit multiple lines: diversion records
("diversion by X from: /path", "diversion by X to: /path") and paths owned by more than
one package. Because `awk -F:` runs over *all* lines and `head -n1` is applied last, the
parser can return a bogus "package" name. Verified:

```
$ printf 'diversion by foo from: /path\nlibfoo:amd64: /path\n' | awk -F: '{print $1}' | head -n1
diversion by foo
```

A bogus name like `diversion by foo` would then be emitted as a Depends entry, producing
an uninstallable `.deb`. Diversions on shared libraries are rare but real (multiarch /
manual diversions on a build host).

**Fix:** Take the first line first, then split, and prefer a real package field. See the
CR-01 fix (`head -n1 | awk -F: '{print $1}'`). For extra safety, filter diversion lines:
`grep -v '^diversion '` before `head -n1`.

### WR-02: Inject-only components (`crun`, `conmon`, `pasta`) render a `depends:` key with zero list items when detection yields an empty set

**File:** `packaging/nfpm/crun.yaml:14-16`, `packaging/nfpm/conmon.yaml:14-16`, `packaging/nfpm/pasta.yaml:14-16` (also `package_all.sh:374-381`)
**Issue:** For these three YAMLs the entire `depends:` block is a comment plus
`${DETECTED_DEPENDS}`. If `detect_runtime_depends` ever returns an empty set — which it
*will* for a fully static binary (e.g. a statically-linked `pasta`/`passt` or
`catatonit`; `ldd` prints "not a dynamic executable" and zero libs are collected) — the
rendered YAML is:

```yaml
depends:
  # System libraries detected from the binary and injected at build time.

conflicts:
  ...
```

i.e. a `depends:` key with no list items. This parses as `depends: null`. nfpm tolerance
of `depends: null` is unverified here (no nfpm on the review host), and `verify_depends.sh`
Part B's `grep -q '^depends:'` well-formedness check (lines 260-268) would actively FAIL
this case — so the verification gate flags it as broken even though it may be a legitimate
static-binary outcome. This is a latent correctness/robustness gap: the "no native deps"
case is not cleanly handled for inject-only components.

**Fix:** Make the injected fragment self-contained — emit the `depends:` key itself only
when there is at least one entry, or guarantee a sane shape. Simplest robust option: in
`package_all.sh`, when `DETECTED_DEPENDS` is empty, inject a harmless placeholder or omit
the key. Cleaner: have `detect_runtime_depends`/the render step produce the full
`depends:` line + items as one unit, and drop the literal `depends:` key from
crun/conmon/pasta YAMLs so an empty set yields no key at all.

### WR-03: `partA_fail` accumulator suppresses all subsequent `PASS` lines after the first failure

**File:** `scripts/verify_depends.sh:210-213`
**Issue:** The per-component `PASS` line is gated on the *global* `partA_fail` accumulator
inside the loop. Once any component sets `partA_fail=1`, every later component that
actually passes prints no `PASS` line (and no FAIL line either) — it silently vanishes
from the report. This makes a multi-component failure run misleading: the operator sees
the first failure but loses the pass/fail status of everything after it.

**Fix:** Track per-component status in a local and gate the PASS on that:

```bash
local comp_fail=0
# ... set comp_fail=1 (and partA_fail=1) on each failure instead of only partA_fail ...
if [[ "${comp_fail}" -eq 0 ]]; then
    echo "    PASS: ${component} detected set functionally equals t64-adjusted D-14 baseline"
fi
```

### WR-04: `T64_EXPECTED` is accepted for any component, masking a misattributed dependency

**File:** `scripts/verify_depends.sh:181-184`
**Issue:** The check `if in_list "${name}" "${T64_EXPECTED}"; then continue` accepts
`libgpgme11t64` or `libglib2.0-0t64` as valid for *any* component. So if (say) `conmon`
suddenly reported `libgpgme11t64` — a name it should never link — the equivalence check
would rubber-stamp it instead of flagging the misattribution. This weakens the very
property T-19-10 says the gate must protect (the equivalence check "cannot rubber-stamp a
wrong detected set").

**Fix:** Only accept a t64 name when it is the documented substitution for *that*
component's baseline (i.e. the pre-substitution name is in `${baseline}`). Restrict the
allowlist per component rather than globally.

### WR-05: Ubuntu-only `VERSION_ID` regex hard-fails on Debian despite the repo name `podman-debian`

**File:** `functions.sh:69-72`, `config.sh:51`
**Issue:** `detect_distro_version_id` requires `^[0-9]+\.[0-9]+$` and the suffix is
hard-coded `~ubuntu${DISTRO_VERSION_ID}.podman1`. On Debian, `VERSION_ID` is a single
integer (`"12"`) — rejected by the regex — and Debian testing/sid has *no* `VERSION_ID`
at all, so `${VERSION_ID:?...}` (line 62) aborts config load. Verified: `[[ "12" =~
^[0-9]+\.[0-9]+$ ]]` fails. Given the repository is literally named `podman-debian`, a
reviewer/operator will reasonably expect it to build on Debian; instead `config.sh`
hard-fails at source time on any Debian host. If Ubuntu-only is intended for Phase 19, the
error message ("expected NN.NN, e.g. 26.04") should say so explicitly; if Debian support
is in scope, the regex and the `~ubuntu` literal need to handle the single-integer form.

**Fix:** Either (a) document and assert Ubuntu-only with a clear message ("this pipeline
currently supports Ubuntu only; got VERSION_ID '<x>'"), or (b) broaden to
`^[0-9]+(\.[0-9]+)?$` and derive the distro id portion (`ubuntu`/`debian`) from
`os-release`'s `ID` so the suffix matches the actual distro.

### WR-06: `dpkg --search` exit status read via `$?` after a redirect, and a pre-existing quoting/ordering smell in `remove_if_user_installed`

**File:** `functions.sh:352-358`
**Issue:** (Pre-existing, adjacent to the changed surface.) `dpkg --search "${lfile}"
2>&1 > /dev/null` has the redirections in the wrong order (`2>&1` before `>/dev/null`
sends stderr to the *original* stdout, not to /dev/null), and `if [[ $? -eq 1 ]]` reads
`$?` on a separate line — fragile under future edits and `set -e`. Not introduced by this
phase, but it sits in `functions.sh` next to the new detector and shares the "trust the
exit code" pattern; worth hardening while here.

**Fix:** `if ! dpkg --search "${lfile}" >/dev/null 2>&1; then rm -f "${lfile}"; fi`.

## Info

### IN-01: `local`-scoped helper extraction in the test relies on brittle `sed` range matching

**File:** `tests/test_detect_distro_depends.sh:78-94`
**Issue:** `extract_fn` greps `^${fn}()` .. `^}` to `eval` just the two function bodies.
This silently breaks if either function gains a nested `}` at column 0 or the signature
formatting changes (e.g. `detect_runtime_depends ()` with a space). The test would then
`eval` a truncated body and produce confusing failures rather than a clear "extraction
failed" error.
**Fix:** Add a sanity check that the extracted text contains the closing of the function
(e.g. assert the body is non-trivial / ends with a lone `}`), or source the whole file in
a subshell with a guard that prevents the tail `source config.sh`.

### IN-02: `verify_depends.sh` Part B advertises "DISTRO=24.04 and 26.04" but detection is host-only

**File:** `scripts/verify_depends.sh:274-300`
**Issue:** The loop varies only `DISTRO_VERSION_ID` (the version *string*); the actual
dependency *names* come from the 24.04 build host's package DB in both iterations (the
comment on lines 281-285 admits this). The "26.04" pass therefore validates the render
*shape*, not 26.04 dep resolution — which is fine, but the headline "renders + parses for
DISTRO=24.04 and 26.04" overstates the coverage and could be misread as proof that 26.04
names resolve (that is `smoke_install_2604.sh`'s job).
**Fix:** Tighten the echoed wording to "render shape for both version strings (dep names
are host-derived)".

### IN-03: Duplicated `COMPONENT_BINARIES` map across `package_all.sh` and `verify_depends.sh`

**File:** `scripts/package_all.sh:290-301`, `scripts/verify_depends.sh:84-95`
**Issue:** The map is copy-pasted (the verify script even notes "Keep in sync with that
map"). A drift (e.g. adding a binary to a component) silently desynchronizes the proof
from the build. Code-duplication risk on a load-bearing map.
**Fix:** Factor the map into a small sourced file (e.g. `packaging/component_binaries.sh`)
and source it from both, so there is one source of truth.

### IN-04: Stale-`local_tag`/`COMPONENT_TAGS` mutation inside the loop is order-dependent for the suite version

**File:** `scripts/package_all.sh:330`, `scripts/package_all.sh:406-407`
**Issue:** The loop writes back the auto-detected tag (`COMPONENT_TAGS["${component}"]=...`)
so the suite meta-package (lines 406-407) can reuse podman's resolved tag. This works only
because `podman` is iterated before the suite block runs — an implicit ordering dependency
that is easy to break if the suite block is ever moved or podman is removed from
`COMPONENTS`. Non-nightly suite version silently depends on the loop having populated the
map.
**Fix:** Resolve the suite (podman) tag explicitly via `resolve_tag_from_repo "podman"`
in the suite block rather than relying on the loop's side effect, or add a guard that the
podman tag is non-empty before composing `suite_version`.

---

_Reviewed: 2026-06-05T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
