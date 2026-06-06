---
phase: 19-per-distro-versioning-dependency-mapping
reviewed: 2026-06-06T00:00:00Z
depth: standard
files_reviewed: 12
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
  critical: 2
  warning: 5
  info: 3
  total: 10
status: issues_found
---

# Phase 19: Code Review Report

**Reviewed:** 2026-06-06
**Depth:** standard
**Files Reviewed:** 12 (+4 cross-referenced YAMLs: netavark, aardvark-dns, fuse-overlayfs, catatonit)
**Status:** issues_found

## Summary

Reviewed the per-distro versioning and direct-DT_NEEDED dependency detector rewrite (plan 19-05) plus the surrounding packaging, smoke, and verification scripts. The detector logic is well-reasoned and the explicit subshell handling for `ldd` and `dpkg-query` (CR-01 of the prior fix wave) is correct. However, the review surfaced **two BLOCKER-class gaps in the D-03 hard-fail invariant** and a **dependency-injection mismatch** between `COMPONENT_BINARIES` and the nFPM YAMLs that silently drops detected dependencies for four components.

The most serious issue: `detect_runtime_depends` derives its dependency set from `objdump -p` inside a process substitution whose exit status is never checked, and `objdump` (binutils) is neither installed by the pipeline nor listed in `verify_depends.sh`'s prerequisite tool check. A missing or failing `objdump` yields an **empty dependency set that passes silently** — the opposite of the D-03 "any breakage hard-fails" contract.

Note on the pipeline-exit concern from the brief: the command-substitution call sites (`package_all.sh:392`, `verify_depends.sh:167,316`) are protected by `set -o pipefail`, so a `detect_runtime_depends` non-zero exit *does* propagate through the trailing `| sed`/`| tr`. That path is sound. The unguarded path is the internal `objdump` process substitution, below.

## Critical Issues

### CR-01: `objdump` failure inside process substitution silently yields zero deps (D-03 bypass)

**File:** `functions.sh:197`
**Issue:** The DT_NEEDED enumeration loop reads from a process substitution:
```bash
done < <(objdump -p "${bin}" 2>/dev/null | awk '/NEEDED/{print $2}')
```
Process-substitution exit status is not propagated to `set -e` and is not captured anywhere. `objdump`'s stderr is also discarded (`2>/dev/null`). If `objdump` is absent (binutils not installed), fails, or reads a file it cannot parse, `awk` receives empty input, the `while` loop body never executes, and the function returns the dep set accumulated so far — for the first/only binary that means an **empty set with exit 0**. This is indistinguishable from a legitimately static binary and directly violates the D-03 invariant that any unresolvable/unowned/unreadable case must hard-fail.

Compounding this: `objdump`/binutils is never installed by the pipeline (no `binutils` reference in `scripts/` or `setup.sh`), and `verify_depends.sh:72` checks `dpkg-query ldd realpath envsubst nfpm` but **not** `objdump`. So the proof gate itself would pass on a host where detection is silently broken.

**Fix:** Run `objdump` outside the pipeline, capture its output and exit status, and hard-fail on error (mirroring the `ldd`/`dpkg-query` treatment already in this function):
```bash
local needed_out
if ! needed_out="$(objdump -p "${bin}" 2>&1)"; then
    echo "ERROR: objdump failed on ${bin}; cannot enumerate DT_NEEDED (D-03)" >&2
    echo "  objdump: ${needed_out}" >&2
    return 1
fi
while read -r soname; do
    [[ -n "${soname}" ]] || continue
    ...
done < <(printf '%s\n' "${needed_out}" | awk '$1=="NEEDED"{print $2}')
```
Also add `objdump` to the `verify_depends.sh:72` tool-presence loop and make `binutils` an explicit build-host prerequisite.

### CR-02: Detected system-library deps silently dropped for netavark, aardvark-dns, fuse-overlayfs, catatonit

**File:** `scripts/package_all.sh:290-314, 387-408`; `packaging/nfpm/netavark.yaml`, `packaging/nfpm/aardvark-dns.yaml`, `packaging/nfpm/fuse-overlayfs.yaml`, `packaging/nfpm/catatonit.yaml`
**Issue:** `COMPONENT_BINARIES` (package_all.sh:290) includes `netavark`, `aardvark-dns`, `pasta`, `fuse-overlayfs`, and `catatonit`. For each, `package_all.sh` runs `detect_runtime_depends`, builds `DETECTED_DEPENDS`, and exports it. But:
- `netavark.yaml` has a literal `depends:` block (`podman-container-configs`) with **no `${DETECTED_DEPENDS}` placeholder** — and netavark is not in `INJECT_ONLY_DEPENDS`. Any detected system lib is computed and then thrown away.
- `aardvark-dns.yaml`, `fuse-overlayfs.yaml`, `catatonit.yaml` have **no `depends:` key and no `${DETECTED_DEPENDS}` placeholder** at all. Detection runs, the result is exported, and `envsubst` has nothing to substitute it into.

Only `podman`/`buildah`/`skopeo` (literal `depends:` + placeholder) and `crun`/`conmon`/`pasta` (inject-only placeholder) actually consume the injected fragment. So for 4 of the 10 binary-bearing components the detector's output never reaches the package.

In practice netavark/aardvark are Rust binaries linking only libc6/libgcc-s1 (both excluded → empty set), and fuse-overlayfs/catatonit are often built static, so the *current* dropped set is empty. But this is a latent correctness defect: the moment any of these grows a real shared-library dependency (e.g. fuse-overlayfs dynamically linking `libfuse3-3`), the `.deb` will ship **without** the required `Depends` and installs will produce broken binaries. The architecture asserts D-01/D-03 ("declare what you link, hard-fail otherwise"), and this silently violates it for a third of the components.

This is also invisible to `verify_depends.sh` Part B: it renders these YAMLs, but since the fragment has no placeholder to land in, the render-and-parse check still passes (netavark's static `depends:` satisfies the well-formedness assertion), so the gate cannot catch the drop.

**Fix:** Either (a) add a `${DETECTED_DEPENDS}` consumption point to every YAML whose component is in `COMPONENT_BINARIES` — treat `aardvark-dns`/`fuse-overlayfs`/`catatonit` as inject-only (add to `INJECT_ONLY_DEPENDS`) and add the placeholder under netavark's existing `depends:`; or (b) make `package_all.sh` hard-fail when a component is in `COMPONENT_BINARIES`, produces a non-empty `DETECTED_DEPENDS`, but its YAML contains no `${DETECTED_DEPENDS}` token:
```bash
if [[ -n "${DETECTED_DEPENDS}" ]] && ! grep -q '${DETECTED_DEPENDS}' "${NFPM_DIR}/${component}.yaml"; then
    echo "ERROR: ${component} has detected deps but ${component}.yaml has no \${DETECTED_DEPENDS} placeholder — deps would be dropped (D-03)" >&2
    exit 1
fi
```
Option (b) is the minimal D-03-faithful guard; option (a) is the complete fix.

## Warnings

### WR-01: `smoke_install_2604.sh` glob may select wrong-distro / wrong-arch `.deb`

**File:** `scripts/smoke_install_2604.sh:122-123, 157-159`
**Issue:** `skopeo_debs=( "${OUTPUT_DIR}"/podman-skopeo_*_*.deb )` and the in-container `skopeo_deb=( /out/podman-skopeo_*_*.deb )` match every skopeo `.deb` in `output/`. Per AGENTS.md, 24.04- and 26.04-built `.deb`s (and amd64/arm64) coexist in `output/` with distinct suffixes. `skopeo_deb[0]` then picks the lexically-first match, which may be the 24.04 build or the non-native arch — contradicting the script's stated purpose ("a 26.04-built .deb") and potentially failing the install on arch mismatch. The proof would then test the wrong artifact (false pass) or fail for an unrelated reason (false fail).
**Fix:** Constrain the glob to the 26.04 suffix and native arch, e.g. `podman-skopeo_*~ubuntu26.04.podman1_${arch}.deb` (derive `arch` via `dpkg --print-architecture` inside the container), or assert exactly one match and error on ambiguity:
```bash
if [[ "${#skopeo_debs[@]}" -gt 1 ]]; then
    echo "ERROR: multiple skopeo .debs in ${OUTPUT_DIR}; clean output/ or set an explicit deb — ambiguous which to test" >&2; exit 1
fi
```

### WR-02: `verify_depends.sh` baseline mirrors are hand-copied and can drift from `package_all.sh`

**File:** `scripts/verify_depends.sh:84-104`
**Issue:** `COMPONENT_BINARIES` (lines 84-95) and `INJECT_ONLY_DEPENDS` (lines 100-104) are duplicated verbatim from `package_all.sh:290-314`. Both files comment "Keep in sync," but nothing enforces it; the two maps will silently diverge on the next packaging edit, and the verification gate would then validate a different binary/inject set than the build actually uses — defeating the gate's purpose. This same duplication already masks CR-02: both maps list netavark/aardvark-dns, but neither file checks that the corresponding YAML can receive the injection.
**Fix:** Extract `COMPONENT_BINARIES` / `INJECT_ONLY_DEPENDS` into a single sourced file (e.g. `scripts/_component_maps.sh`) consumed by both `package_all.sh` and `verify_depends.sh`, so there is one source of truth.

### WR-03: `objdump` `/NEEDED/` regex matches more than DT_NEEDED entries

**File:** `functions.sh:197`
**Issue:** `awk '/NEEDED/{print $2}'` matches any line *containing* the substring `NEEDED`, not the `NEEDED` tag in field 1. `objdump -p` output is currently benign, but the unanchored pattern means a future objdump format change, a section/note name, or a versioned-dependency line containing "NEEDED" could feed a bogus `$2` token into the resolve step (failing the build, or worse resolving to an unintended path). Combined with CR-01's swallowed stderr, such a line would be hard to diagnose.
**Fix:** Anchor on the tag field: `awk '$1=="NEEDED"{print $2}'`.

### WR-04: `extract_version_nightly` degrades to `0.0.0` instead of failing, and uses unguarded `cat`

**File:** `scripts/package_all.sh:91, 75-137`
**Issue:** Several nightly extractors silently fall back to `0.0.0` (line 135) when a grep/sed yields nothing, producing a package versioned `0.0.0~git...` that sorts below — and would be overwritten by — any real release: a silent data-quality defect rather than a hard error, inconsistent with the D-03 "fail loud" stance used elsewhere in this phase. `conmon` uses `cat "${repo_path}/VERSION" | tr ...` (useless-use-of-cat with no existence guard), so a missing `VERSION` hard-fails while the other extractors degrade to `0.0.0` — inconsistent failure semantics.
**Fix:** In nightly mode, make extraction failure a hard error (the build should not ship a `0.0.0` package), or at minimum emit a WARNING naming the component when the `0.0.0` fallback triggers. Replace `cat "${repo_path}/VERSION" | tr -d ...` with `tr -d '[:space:]' < "${repo_path}/VERSION"`.

### WR-05: `dpkg-query -S` `head -n1` may pick the wrong package on multi-owner files

**File:** `functions.sh:191`
**Issue:** After filtering diversion lines, `head -n1` takes the first owner. For a shared library legitimately co-owned (transition packages, alternatives) the first line is arbitrary — dpkg output order is not contractually stable — and the chosen package becomes a hard `Depends`. This is acceptable for the in-tree binaries today but is an unguarded assumption that could yield a wrong dependency name.
**Fix:** When more than one non-diversion owner is returned, either fail loudly (D-03 spirit — ambiguous ownership is a real signal) or document why first-wins is safe for the specific libraries in scope.

## Info

### IN-01: `detect_runtime_depends` `EXCLUDE` uses an O(n*m) inner loop

**File:** `functions.sh:201-209`
**Issue:** Exclusion is a nested loop over `EXCLUDE` for every package. With two excludes this is irrelevant for performance, but an associative-set lookup is clearer and matches the `pkgs` associative-array style already used.
**Fix:** `local -A EXCLUDE=( [libc6]=1 [libgcc-s1]=1 )` then `[[ -v EXCLUDE[$pkg] ]] && continue`.

### IN-02: Commented-out version pins left in `config.sh`

**File:** `config.sh:141-149, 164-221`
**Issue:** Multiple blocks of commented-out `export GOVERSION=...`, `PODMAN_VERSION`, etc. remain. They document intent but are dead code that can mislead (stale `1.22.6`/`5.5.2` values implying a default that no longer applies).
**Fix:** Remove the stale commented pins or move them into `docs/CONFIGURATION.md` as examples.

### IN-03: `tests/test_detect_distro_depends.sh` references undefined `teardown`

**File:** `tests/test_detect_distro_depends.sh:111`
**Issue:** `teardown 2>/dev/null || true` calls a `teardown` function never defined in the file. It is `|| true`-guarded so harmless, but it is dead/erroneous code suggesting a removed fixture.
**Fix:** Remove the `teardown` call (or define it if a cleanup fixture was intended).

---

## Narrative Findings (AI reviewer)

All findings above are narrative findings from direct adversarial review of the changed files at standard depth. No `<structural_findings>` block was provided, so there is no fallow structural substrate to reconcile.

Cross-file verifications performed (no defect found):
- `set -o pipefail` confirmed in `package_all.sh:4`, `verify_depends.sh:4`, `smoke_install_2604.sh:4` — so the `detect_runtime_depends | sed/tr` call sites correctly propagate the detector's non-zero exit. The CR-01 pipeline concern from the brief is sound on those paths; the unguarded path is the internal `objdump` proc-sub (see CR-01 above).
- `detect_distro_version_id` regex `^[0-9]+\.[0-9]+$` correctly rejects injection-shaped and compact-form overrides (covered by `tests/test_detect_distro_depends.sh:128-133`).
- `SMOKE_RUNTIME` / `SMOKE_IMAGE` validation (`smoke_install_2604.sh:51-91`) is tight: runtime is an exact `docker|podman` allowlist, image is regex-validated before interpolation — no command-injection surface found.
- `verify_versions.sh` uses `dpkg --compare-versions` as the oracle; all six ordering assertions are self-validating, and the `~podman1 < ~ubuntu24.04.podman1` claim holds under dpkg version semantics.
- Static-binary case in `detect_runtime_depends` (ldd "not a dynamic executable" → `continue`) correctly yields an empty set without error.
- nFPM YAML indentation: injected `  - pkg` (2-space) aligns with static `  - podman-*` items in podman/buildah/skopeo; the inject-only fragment `depends:\n  - pkg` is column-0 valid YAML. Confirmed consistent.
- `verify_depends.sh` Part A per-component gating (`comp_fail`/`partA_fail`, WR-03/WR-04 of prior wave) and t64 acceptance (`T64_PRE_SUBST` keyed per-component) are correct and do not rubber-stamp an unexpected name.

---

_Reviewed: 2026-06-06_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
