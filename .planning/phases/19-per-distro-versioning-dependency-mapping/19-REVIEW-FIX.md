---
phase: 19-per-distro-versioning-dependency-mapping
fixed_at: 2026-06-05T00:00:00Z
review_path: .planning/phases/19-per-distro-versioning-dependency-mapping/19-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 19: Code Review Fix Report

**Fixed at:** 2026-06-05T00:00:00Z
**Source review:** .planning/phases/19-per-distro-versioning-dependency-mapping/19-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope (critical_warning): 7 (CR-01, WR-01..WR-06)
- Fixed: 7
- Skipped: 0
- Out of scope (Info, not attempted): 4 (IN-01..IN-04)

All edits were made and committed inside an isolated git worktree
(`gsd-reviewfix/19-*`) and fast-forwarded onto `main` by the cleanup tail.
After every change: `bash -n` passed on each edited shell file and the existing
`tests/test_detect_distro_depends.sh` suite passed (6 passed, 0 failed); the
WR-02 render shape was additionally verified with a local `envsubst`
simulation for both the non-empty and empty (fully-static binary) cases.

## Fixed Issues

### CR-01 / WR-01: `detect_runtime_depends` failure-path diagnostic + multi-line `dpkg-query -S` parse

**Files modified:** `functions.sh`
**Commit:** d243148
**Applied fix:** Replaced the single pipelined assignment
`pkg="$(dpkg-query -S "$(realpath …)" 2>/dev/null | awk -F: … | head -n1)"`
with a decoupled lookup: `dpkg-query -S` now runs outside any pipeline
(`if ! dpkg_out="$(dpkg-query -S "${resolved}" 2>&1)"; then …`) so its exit
status is testable under the caller's `set -euo pipefail` and the explicit
D-03 "no owning package for X (linked by Y)" guard always runs instead of an
opaque ERR-trap abort. Its stderr is preserved (`2>&1`) and echoed in the
error. For WR-01, the first real line is taken before splitting on `:`
(`grep -v '^diversion ' | head -n1 | awk -F: '{print $1}'`), so diversion
records and multi-owner output can no longer yield a bogus
`diversion by foo` "package" name. Added `resolved dpkg_out` to the function's
`local` declaration. Test extraction (`sed /^fn()/,/^}/`) still works (no
new column-0 `}` introduced); suite green.

_Note: CR-01 and WR-01 share the exact same source lines (the dep-lookup
inside the read loop); the review's CR-01 fix already subsumes WR-01, so they
are addressed in a single atomic commit referencing both._

### WR-05: Ubuntu-only `VERSION_ID` regex error message

**Files modified:** `functions.sh`
**Commit:** 9a38b38
**Applied fix:** Chose review option (a) — document/assert Ubuntu-only — because
the phase is intentionally Ubuntu-only per 19-CONTEXT.md (D-08 hard-codes the
`~ubuntu{VERSION_ID}.podman1` suffix and all D-14 baselines are Ubuntu's;
N-distro support is future requirement PKG-11, explicitly out of scope). The
regex itself is unchanged (still `^[0-9]+\.[0-9]+$`); the rejection message
now reads "this pipeline currently supports Ubuntu only (dotted VERSION_ID like
24.04 or 26.04); got …" plus a second line naming the Debian single-integer
case and pointing at PKG-11, so a Debian operator is not left guessing.

### WR-06: `dpkg --search` exit-status check in `remove_if_user_installed`

**Files modified:** `functions.sh`
**Commit:** 6ba690a
**Applied fix:** Replaced `dpkg --search "${lfile}" 2>&1 > /dev/null` followed
by a separate-line `if [[ $? -eq 1 ]]` with
`if ! dpkg --search "${lfile}" >/dev/null 2>&1; then rm -f "${lfile}"; fi`.
This fixes the wrong redirection order (stderr previously went to the original
stdout, not /dev/null) and removes the fragile `$?`-on-next-line pattern.
Behavior is preserved: the file is deleted only when dpkg does not own it.

### WR-03 / WR-04: Part A PASS gating + per-component t64 acceptance

**Files modified:** `scripts/verify_depends.sh`
**Commit:** 8bfd974
**Applied fix (WR-03):** Introduced a per-component `comp_fail` flag inside the
Part A loop; each component's `PASS` line is now gated on `comp_fail` and the
global `partA_fail` is only set at the end of the iteration. A component that
passes after an earlier component failed is no longer silently dropped from the
report. **(WR-04):** Replaced the global `T64_EXPECTED="libgpgme11t64
libglib2.0-0t64"` allowlist with a `T64_PRE_SUBST` map (t64-name ->
pre-substitution name). A t64 name is accepted only when its pre-substitution
form is in *that* component's baseline, so a misattributed dep (e.g.
`libgpgme11t64` reported by conmon) is flagged rather than rubber-stamped
(T-19-10). WR-03 and WR-04 modify tightly interleaved lines in the same loop;
committing them separately would leave a broken intermediate state, so they are
addressed in one atomic commit referencing both.

### WR-02: self-contained injected `depends:` block for inject-only components

**Files modified:** `scripts/package_all.sh`, `scripts/verify_depends.sh`,
`packaging/nfpm/crun.yaml`, `packaging/nfpm/conmon.yaml`,
`packaging/nfpm/pasta.yaml`
**Commit:** bf157be
**Applied fix:** Adopted the review's "cleaner" option. Removed the literal
`depends:` key + comment from crun/conmon/pasta YAMLs (their only depends
content was the injected fragment). Added an `INJECT_ONLY_DEPENDS` map to both
`package_all.sh` and `verify_depends.sh`; for those components the injected
fragment now carries its own `depends:` header, emitted *only* when the detected
set is non-empty. A fully-static binary (empty set) therefore renders no
`depends:` key at all instead of a bare `depends:` with zero items (which parses
as `depends: null` and would trip Part B's well-formedness gate). YAMLs with
static suite deps (podman/buildah/skopeo) are unchanged and still receive list
items only. Verified with a local `envsubst` render of both the non-empty and
empty cases.

## Skipped Issues

None — all in-scope findings were fixed.

## Out-of-Scope (Info — not attempted, per fix_scope=critical_warning)

- **IN-01:** brittle `sed`-range function extraction in
  `tests/test_detect_distro_depends.sh` (suggest extraction sanity check).
- **IN-02:** `verify_depends.sh` Part B wording overstates 26.04 coverage
  (dep names are host-derived; tighten the echoed wording).
- **IN-03:** `COMPONENT_BINARIES` map duplicated between `package_all.sh` and
  `verify_depends.sh` (suggest a single sourced file). Note: this fix added a
  *second* duplicated map (`INJECT_ONLY_DEPENDS`) to both files for the same
  reason of keeping the proof in lockstep with the build; if IN-03 is taken up
  later, both maps should move to the shared sourced file together.
- **IN-04:** suite-version reuse of podman's resolved tag is order-dependent on
  the loop (suggest resolving the suite tag explicitly).

---

_Fixed: 2026-06-05T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
