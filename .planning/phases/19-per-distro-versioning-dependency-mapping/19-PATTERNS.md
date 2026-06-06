# Phase 19: Per-Distro Versioning & Dependency Mapping - Pattern Map

**Mapped:** 2026-06-05
**Files analyzed:** 5 modified + 1 new (plus 7 nFPM YAMLs sharing one edit pattern)
**Analogs found:** 6 / 6 (all in-repo — this phase is a refactor of existing pipeline code)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `functions.sh` (add `detect_runtime_depends`, `detect_distro_version_id`) | utility | transform | `functions.sh::detect_crun_parser_depend` (in package_all.sh today) / `detect_architecture` | exact |
| `config.sh` (add distro detect + `VERSION_SUFFIX` composition) | config | transform | `config.sh::ARCH` override idiom (line 19) | exact |
| `scripts/package_all.sh` (remove hardcoded suffix, wire detection) | script/orchestrator | batch | itself — existing packaging loop (lines 319-385) | exact (in-place) |
| `packaging/nfpm/{crun,podman,buildah,skopeo,conmon,pasta}.yaml` | config | n/a | existing depends blocks + `${CRUN_PARSER_DEPEND}` injection | exact |
| `scripts/verify_versions.sh` | test | request-response (CLI assert) | NO in-repo analog — see No Analog Found | none |
| `scripts/smoke_install_2604.sh` (or inline) | test | request-response (container) | NO in-repo analog — see No Analog Found | none |

## Pattern Assignments

### `functions.sh` — `detect_runtime_depends()` (utility, transform)

**Analog:** `detect_crun_parser_depend()` — currently at `scripts/package_all.sh:199-219`. This is the working ldd→name prototype to GENERALIZE (D-01) and then DELETE (D-04). Move the generalized version into `functions.sh` (research Recommended Structure, line 156) so `config.sh`/`package_all.sh` both see it; today `package_all.sh` already sources `functions.sh` (line 14).

**Existing precedent to copy — hard-fail + ldd shape** (`scripts/package_all.sh:199-219`):
```bash
detect_crun_parser_depend() {
    local crun_bin="${DESTDIR}/usr/bin/crun"
    if [[ ! -x "${crun_bin}" ]]; then
        echo "ERROR: crun binary not found or not executable: ${crun_bin}" >&2
        return 1
    fi
    if ldd "${crun_bin}" | grep -q 'libjson-c\.so\.5'; then echo "libjson-c5"; return 0; fi
    if ldd "${crun_bin}" | grep -q 'libyajl\.so\.2'; then echo "libyajl2"; return 0; fi
    echo "ERROR: unable to detect crun parser runtime dependency from ldd ${crun_bin}" >&2
    return 1
}
```

Copy these properties from the analog:
- `[[ ! -x ... ]]` guard + `echo "ERROR: ..." >&2; return 1` (the D-03 hard-fail idiom — flows through the ERR trap)
- `ldd "${bin}"` as the enumeration primitive (NOT readelf/objdump)
- `return 1` on any unresolved path (no silent fallback — D-03)

Generalize to: loop over N binaries, `ldd | awk '/=> \//{print $3}'`, `realpath` each, `dpkg-query -S` → owning package, strip `:arch` qualifier (`awk -F: '{print $1}'`), exclude `libc6`/`libgcc-s1` (D-02), dedupe `sort -u`. Full reference body in RESEARCH.md Pattern 1 (lines 172-204). The crun `libjson-c5`/`libyajl2` case falls out naturally (D-04 proof, RESEARCH lines 351-358).

**Function-definition style** (`functions.sh:15-32`, `detect_architecture`): `local`-scoped vars, `case`/`echo` returns, `echo "ERROR: ..." >&2` then exit/return on the unsupported branch. Match this style.

---

### `functions.sh` — `detect_distro_version_id()` (utility, transform)

**Analog:** the `ARCH` override idiom in `config.sh:19`:
```bash
export ARCH="${ARCH:-$(detect_architecture)}"
```
plus `detect_architecture` (`functions.sh:15-32`) for the helper shape.

**Pattern to apply** (D-05/06): honor `${DISTRO:-}` override first (mirrors `${ARCH:-...}`), else source `/etc/os-release` and read `VERSION_ID`, else hard-fail. Reference body in RESEARCH.md Pattern 2 (lines 216-229):
```bash
detect_distro_version_id() {
    if [[ -n "${DISTRO:-}" ]]; then echo "${DISTRO}"; return; fi   # D-06 override
    if [[ -r /etc/os-release ]]; then
        . /etc/os-release
        echo "${VERSION_ID:?VERSION_ID missing from /etc/os-release}"
        return
    fi
    echo "ERROR: cannot determine distro: no DISTRO override and /etc/os-release unreadable" >&2
    return 1
}
```
> NOTE: no existing code in this repo reads `/etc/os-release` — this is new. Validate `VERSION_ID` against `^[0-9]+\.[0-9]+$` before composing (RESEARCH Security V5, line 462). Reconcile `DISTRO` format (`26.04` vs `2604`) per RESEARCH Open Question 1 / A3.

---

### `config.sh` — VERSION_SUFFIX composition (config, transform)

**Analog:** `config.sh` `export`-everything style; the `ARCH` block (lines 18-37) is the template for "detect-or-override then export."

**Where it lands:** `config.sh` sources `functions.sh` first (line 12), so `detect_distro_version_id` is available. Add after the architecture block, following D-07 (single source of truth):
```bash
DISTRO_VERSION_ID="$(detect_distro_version_id)"
export VERSION_SUFFIX="~ubuntu${DISTRO_VERSION_ID}.podman1"   # D-07/D-08
```

---

### `scripts/package_all.sh` — wiring (orchestrator, batch)

**Analog:** itself. Three concrete edit sites in the existing file:

1. **DELETE** hardcoded suffix (`package_all.sh:27`): `VERSION_SUFFIX="~podman1"` → now comes from `config.sh` (sourced at line 11). D-07.

2. **DELETE** `detect_crun_parser_depend()` (`package_all.sh:199-219`) and its call sites (lines 366-371) — absorbed by `detect_runtime_depends` (D-04).

3. **REPLACE** the per-component export + envsubst block (`package_all.sh:360-379`). Current shape to copy/modify:
```bash
export VERSION="${local_version}"
export ARCH="${ARCH}"
export DESTDIR="${DESTDIR}"
export CRUN_PARSER_DEPEND="libyajl2"
if [[ "${component}" == "crun" ]]; then
    CRUN_PARSER_DEPEND="$(detect_crun_parser_depend)"
    export CRUN_PARSER_DEPEND
fi
nfpm_config="/tmp/nfpm-${component}.yaml"
envsubst '${VERSION} ${ARCH} ${DESTDIR} ${CRUN_PARSER_DEPEND}' < "${NFPM_DIR}/${component}.yaml" > "${nfpm_config}"
```
New shape: drop the `CRUN_PARSER_DEPEND` special case; compute `DETECTED_DEPENDS` from the component's binaries via `detect_runtime_depends` piped through `sed 's/^/  - /'` (YAML list fragment, RESEARCH Pattern 3 lines 244-248); add `${DETECTED_DEPENDS}` to the `envsubst` allowlist. The `extract_version ... ${VERSION_SUFFIX}` calls (lines 344, 355, 397, 400) need NO change — they already append the now-per-distro `VERSION_SUFFIX`.

**Binary path source:** the loop has `DESTDIR` populated; pass `${DESTDIR}/usr/bin/<bin>` per component. pasta links two binaries `passt` + `pasta` (RESEARCH anti-pattern, line 258).

---

### `packaging/nfpm/*.yaml` — depends injection (config)

**Analog:** the existing `${CRUN_PARSER_DEPEND}` injection in `crun.yaml:19` — the precedent for an env-substituted depends entry.

**Current state** (concrete, the regression baseline — D-14):
- `crun.yaml:14-19`: `libseccomp2`, `libsystemd0`, `libcap2`, `${CRUN_PARSER_DEPEND}`
- `podman.yaml:14-26`: internal `podman-*` deps (lines 16-23) + `libgpgme11`, `libseccomp2`
- `buildah.yaml:14-18`: `podman-container-configs` + `libgpgme11`, `libseccomp2`
- `skopeo.yaml:14-19`: `podman-container-configs` + `libgpgme11`, `libsubid4`, `libsqlite3-0` *(`libsqlite3-0` was the pre-v3.0 hardcoded datum — NOT a real v1.22.0 link; skopeo built with no sqlite BUILDTAG links no sqlite. Removed from the skopeo baseline as stale in Plan 05, see 19-UAT.md.)*
- `conmon.yaml:14-17`: `libglib2.0-0`, `libsystemd0`
- `pasta.yaml`: NO `depends:` key today (detection may now add some — RESEARCH line 258)

**Edit per file (D-12/D-13):** keep internal `- podman-*` lines literal (package-level, not soname-derived); DELETE the hardcoded system-lib lines; place `${DETECTED_DEPENDS}` at column 0 under `depends:`:
```yaml
depends:
  - podman-container-configs      # internal deps stay literal (D-13)
${DETECTED_DEPENDS}               # system libs injected here (D-12)
```
> YAML caveat (RESEARCH Pitfall 3, lines 304-308): fragment carries its own `  - ` indentation; placeholder at column 0; for zero-dep + zero-internal components omit `depends:` entirely. `nfpm pkg` parses loudly on bad YAML — that is the render-and-parse smoke gate.

---

### `scripts/verify_versions.sh` (test) — NEW, no in-repo analog

**Pattern source:** RESEARCH Code Examples (lines 319-333). Self-contained `assert_lt` wrapping `dpkg --compare-versions A lt B`. Four assertions (D-11 a/b/c + the added old-`~podman1` < new-`~ubuntu24.04.podman1`, RESEARCH Pitfall 2 line 301). Use the project's `set -euo pipefail` header (every script has it, e.g. `package_all.sh:4`).

## Shared Patterns

### Hard-fail on detection failure (D-03)
**Source:** `detect_crun_parser_depend` (`package_all.sh:202-218`) + `error_handler` (`functions.sh:283-298`).
**Apply to:** `detect_runtime_depends`, `detect_distro_version_id`.
Pattern: `echo "ERROR: <specific message including the path/binary> " >&2; return 1`. Every entry script sets `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR` (e.g. `package_all.sh:17`); a `return 1` under `set -euo pipefail` routes through it. No silent fallback to stale names.

### Detect-or-override then export (D-06)
**Source:** `config.sh:19` `export ARCH="${ARCH:-$(detect_architecture)}"`.
**Apply to:** `DISTRO` override, `VERSION_SUFFIX` composition. Honor explicit env var first, sensible auto-detect default second.

### envsubst single-pass YAML render
**Source:** `package_all.sh:374` `envsubst '${VERSION} ${ARCH} ${DESTDIR} ${CRUN_PARSER_DEPEND}' < ... > /tmp/nfpm-<c>.yaml`.
**Apply to:** all 7 component renders — replace `${CRUN_PARSER_DEPEND}` with `${DETECTED_DEPENDS}` in the allowlist. nFPM expands `${VAR}` natively but the existing pipeline pre-renders with envsubst; keep that single mechanism (no yq/new tool — RESEARCH lines 250).

### Centralized config, sourced by all (D-07)
**Source:** `config.sh` sourced by `package_all.sh:11`; `functions.sh` sourced by both.
**Apply to:** `VERSION_SUFFIX` lives only in `config.sh`; helpers live in `functions.sh`.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `scripts/verify_versions.sh` | test | CLI assert | No shell verification/test scripts exist in `scripts/` today (only build/install/package scripts). Use RESEARCH Code Examples (lines 319-333) as the template. |
| 26.04 container apt-install smoke | test | container | No container-smoke harness in repo. Use RESEARCH lines 336-348 (`docker/podman run ubuntu:26.04 ... apt-get install -y /out/*.deb`). |
| `/etc/os-release` distro detection | utility | transform | No code in this repo reads os-release yet. Closest idiom is the `ARCH`/`detect_architecture` override; structure is new, grounded in RESEARCH Pattern 2. |

## Metadata

**Analog search scope:** `config.sh`, `functions.sh`, `scripts/`, `packaging/nfpm/*.yaml`
**Files scanned:** package_all.sh, config.sh, functions.sh, 6 nFPM YAMLs (crun/podman/buildah/skopeo/conmon/pasta)
**Pattern extraction date:** 2026-06-05
