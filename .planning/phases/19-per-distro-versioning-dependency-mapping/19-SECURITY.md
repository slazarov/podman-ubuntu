---
phase: 19
slug: per-distro-versioning-dependency-mapping
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-06
---

# Phase 19 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

Each declared mitigation was verified by reading the implementation and locating
the specific code construct that enforces it — documentation/intent alone was
not accepted. Implementation files are authoritative; this file is the audit
record only.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| build env → version string / filenames | `DISTRO` env var and `/etc/os-release` `VERSION_ID` interpolated into package version string and `.deb` filenames | distro version identifier |
| build host package DB → declared deps | `dpkg-query -S` output (owning package names) flows into `.deb` control metadata via `detect_runtime_depends` | package names |
| rendered /tmp/nfpm-*.yaml → nfpm | envsubst-rendered config (containing `${DETECTED_DEPENDS}` fragment) fed to `nfpm pkg` | YAML package definition |
| binary → detector | `detect_runtime_depends` runs `ldd` only on in-tree, freshly-built ELF binaries under DESTDIR | ELF binaries (trusted, in-tree) |
| SMOKE_RUNTIME/SMOKE_IMAGE → run invocation | env-overridable runtime/image strings feed `docker`/`podman run` | runtime name, image reference |
| local .deb + 26.04 archive → container | smoke test apt-installs locally-built `.deb`s, resolving system deps from the signed distro archive inside a throwaway `--rm` container | .deb packages |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-19-01 | Tampering | `detect_distro_version_id` (VERSION_ID interpolation) | mitigate | `=~ ^[0-9]+\.[0-9]+$` fail-closed before VERSION_SUFFIX — functions.sh:75-79, config.sh:47,51; negatives tested (test_detect_distro_depends.sh:128,132-133) | closed |
| T-19-02 | Elevation (theoretical) | `detect_runtime_depends` running `ldd` | accept | Only in-tree freshly-built binaries under DESTDIR via static `COMPONENT_BINARIES` — functions.sh:121-122; package_all.sh:387-392; verify_depends.sh:161-167 | closed |
| T-19-03 | Repudiation / Integrity | unmapped/unresolvable soname | mitigate | Three D-03 hard-fail `return 1` paths, no swallow — functions.sh:169-173, 181-185, 192-195; static-binary `\|\| true` (143-146) is the documented zero-dep case only | closed |
| T-19-04 | Tampering | word-splitting / unquoted expansion in detection loop | mitigate | All `"${bin}"`/`"${lib}"`/`"${resolved}"` expansions quoted (functions.sh:130-197); `realpath` before `dpkg-query` (175); inherits caller `set -euo pipefail` (entry points set it at line 4) | closed |
| T-19-05 | Tampering / Integrity | `${DETECTED_DEPENDS}` injection into nFPM YAML | mitigate | Names only from `dpkg-query -S` (functions.sh:181-196), `sort -u` + `sed 's/^/  - /'` (package_all.sh:392); zero residual hardcoded system libs in 6 YAMLs; render-and-parse gated by verify_depends.sh:262-336 | closed |
| T-19-06 | Repudiation / Integrity | silent fallback masking mislinked binary | mitigate | No `\|\| true` on detection call under `set -euo pipefail` + ERR trap — package_all.sh:4, 17, 392 | closed |
| T-19-07 | Tampering | unquoted DESTDIR/binary-path expansion in call | mitigate | Quoted `"${DESTDIR}/${rel_bin}"` (package_all.sh:390-392); `COMPONENT_BINARIES` static map (package_all.sh:290-301); unquoted split at :389 is the documented static multi-binary idiom | closed |
| T-19-08 | Tampering | version-ordering oracle (`verify_versions.sh`) | accept | Host `dpkg --compare-versions` with only literal in-script fixtures — verify_versions.sh:24, 33-56; no input surface | closed |
| T-19-09 | Tampering / Injection | `SMOKE_RUNTIME`/`SMOKE_IMAGE` env interpolation | mitigate | Exact `docker\|podman` case (smoke_install_2604.sh:52-64); image regex `^[A-Za-z0-9][A-Za-z0-9._/:-]*$` (84-87); quoted expansions; `--rm` container (146) | closed |
| T-19-10 | Integrity | false-pass on 24.04 equivalence (t64 trap) | mitigate | Explicit `BASELINE_24_04` + component-scoped `T64_PRE_SUBST` allowlist (verify_depends.sh:119-139); undocumented delta or missing baseline name FAILs → exit 1 (196-244) | closed |
| T-19-11 | Repudiation | silent skip when no container runtime | mitigate | Hard `exit 1` when no runtime found — smoke_install_2604.sh:69-73; no skip path | closed |
| T-19-SC | Tampering | apt install from 26.04 archive in smoke test | accept | Standard apt over the signed distro archive inside `--rm` container — smoke_install_2604.sh:146-149, 152, 183; the install is the test | closed |
| T-19-12 | Tampering / false-pass | smoke skopeo install | mitigate | HARD skopeo+configs install, no `\|\| true` (smoke_install_2604.sh:183); missing sibling .deb hard-errors (171-175); best-effort confined to optional podman install (191-192) | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Detailed Findings

### T-19-01 — VERSION_ID interpolation — CLOSED
`detect_distro_version_id()` validates with `[[ "${version_id}" =~ ^[0-9]+\.[0-9]+$ ]]`
and returns 1 on mismatch (functions.sh:75-79) BEFORE the value is echoed, so a
malformed `DISTRO`/`VERSION_ID` cannot reach
`VERSION_SUFFIX="~ubuntu${DISTRO_VERSION_ID}.podman1"` (config.sh:51). Failure
aborts config load under the caller's `set -e`. Negative cases (`2604`,
`26.04; rm`, `ubuntu26.04`) covered by test_detect_distro_depends.sh:128,132-133.

### T-19-02 — ldd on built binaries — ACCEPTED
Constraint documented in the function header (functions.sh:121-122). All call
sites build paths from the static repo-controlled `COMPONENT_BINARIES` map
prefixed by `${DESTDIR}` (package_all.sh:387-392, verify_depends.sh:161-167).
No untrusted path reaches the detector.

### T-19-03 — unmapped soname hard-fail — CLOSED
`detect_runtime_depends()` hard-fails (`return 1`) on: unresolved direct NEEDED
soname (functions.sh:169-173), resolved path with no owning package
(181-185), empty/unparseable package field (192-195). The only `|| true` is the
deliberate static-binary path (143) followed by the "not a dynamic executable"
guard (144-146) — the legitimate zero-dependency case (D-05), not a masking.

### T-19-04 — quoting / word-splitting — CLOSED
Every expansion in the detection loop is quoted; `resolved="$(realpath "${lib}")"`
normalizes before `dpkg-query -S "${resolved}"` (functions.sh:175,181).
functions.sh is a sourced library and intentionally carries no top-level `set`
line (must not mutate the caller's shell options); all entry points
(package_all.sh, verify_depends.sh, smoke_install_2604.sh) set
`set -euo pipefail` at line 4.

### T-19-05 — DETECTED_DEPENDS → nFPM YAML — CLOSED
Package names originate solely from `dpkg-query -S` against the host dpkg DB —
no hardcoded soname→package table. Output is `sort -u` (functions.sh:209) then
`sed 's/^/  - /'` (package_all.sh:392). All six target YAMLs (buildah, conmon,
crun, skopeo, podman, pasta) carry the `${DETECTED_DEPENDS}` placeholder with
zero residual hardcoded system-lib lines (grep confirmed). nfpm render-and-parse
of every YAML on both distros is gated by verify_depends.sh Part B (262-336).

### T-19-06 — no silent fallback — CLOSED
package_all.sh: `set -euo pipefail` (line 4), ERR trap (line 17), detection call
at line 392 has no `|| true` anywhere around it — a detector `return 1`
propagates and aborts packaging.

### T-19-07 — quoted DESTDIR expansion — CLOSED
`component_bins+=("${DESTDIR}/${rel_bin}")` (package_all.sh:390), passed as
`"${component_bins[@]}"` (392). The intentional unquoted
`${COMPONENT_BINARIES[$component]}` at :389 is a controlled word-split of a
static space-separated value (pasta's `passt pasta` multi-binary idiom).

### T-19-08 — version-ordering oracle — ACCEPTED
verify_versions.sh:24 calls `dpkg --compare-versions "$1" lt "$2"`; every
argument is a hardcoded literal (33-56). No env/config/build input reaches the
comparison — no injection surface.

### T-19-09 — SMOKE_RUNTIME/SMOKE_IMAGE validation — CLOSED
Exact-match `case` accepts only `docker|podman`, else ERROR + exit 1
(smoke_install_2604.sh:52-64). `SMOKE_IMAGE` validated against
`^[A-Za-z0-9][A-Za-z0-9._/:-]*$` (84-87). All expansions quoted; container runs
`--rm` (146).

### T-19-10 — t64 equivalence not a rubber-stamp — CLOSED
Explicit `BASELINE_24_04` map (verify_depends.sh:119-125) plus constrained
`T64_PRE_SUBST` allowlist (136-139). The check FAILs on any detected name not in
baseline/accepted-alt/component-scoped t64 form AND on any missing baseline name
(196-219); t64 acceptance is component-scoped (WR-04, :205); non-zero
`partA_fail` exits 1 (240-244).

### T-19-11 — no silent skip — CLOSED
No runtime found → `echo "ERROR: no container runtime found ..." >&2; exit 1`
(smoke_install_2604.sh:69-73). No skip/return-0 path; the PKG-08 gate cannot be
bypassed.

### T-19-SC — apt from 26.04 archive — ACCEPTED
`apt-get update` + `apt-get install` of locally-built .debs inside the
throwaway `--rm` container (smoke_install_2604.sh:146-149, 152, 183) against
the distro's signed archive. Intentional test behavior; never a production
target.

### T-19-12 — skopeo install stays HARD — CLOSED
Single HARD `apt-get install -y "${configs_deb[0]}" "${skopeo_deb[0]}"`
(smoke_install_2604.sh:183) with no `|| true` — a wrong renamed system dep
(libgpgme45/libsubid5/libassuan9) fails the gate. Missing sibling
`podman-container-configs` .deb hard-errors (171-175). The best-effort
`|| true` is confined to the OPTIONAL secondary podman install (191-192),
documented as not the PKG-08 signal.

---

## Unregistered Flags

None. No `## Threat Flags` section exists in any Phase 19 SUMMARY. The
19-02-SUMMARY.md `## Threat Surface` narrative maps to existing registered
threats (T-19-05, T-19-06/D-03, T-19-07) and introduces no new attack surface.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-19-01 | T-19-02 | `ldd` only ever runs on freshly-built, in-tree binaries under DESTDIR (static `COMPONENT_BINARIES` paths), never on external/untrusted input | plan-time disposition (19-01, 19-05), verified by gsd-security-auditor | 2026-06-06 |
| AR-19-02 | T-19-08 | verify_versions.sh uses host `dpkg --compare-versions` with only literal in-script fixtures; no env/config/build input reaches the comparison | plan-time disposition (19-03), verified by gsd-security-auditor | 2026-06-06 |
| AR-19-03 | T-19-SC | Standard apt over the distro's signed archive inside a disposable `--rm` container; the install IS the test, never a production target | plan-time disposition (19-04), verified by gsd-security-auditor | 2026-06-06 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-06 | 13 | 13 | 0 | gsd-security-auditor (opus) via /gsd:secure-phase |

> Note (out of audit scope): the executor flagged ShellCheck was not run on the
> macOS dev host (19-05-SUMMARY). `bash -n` is clean on all touched scripts.
> A ShellCheck pass in CI/Linux is recommended but is a code-quality item, not
> an open threat.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-06
