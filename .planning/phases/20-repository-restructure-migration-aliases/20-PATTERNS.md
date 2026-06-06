# Phase 20: Repository Restructure & Migration Aliases - Pattern Map

**Mapped:** 2026-06-06
**Files analyzed:** 7 (5 modified, 1-2 new)
**Analogs found:** 7 / 7 (all in-repo; this is a self-modifying restructure of existing files)

## Orientation

This phase has an unusual pattern profile: nearly every file being changed **already exists** and the "analog" is the file's own current structure. The job is to extend in place, following the exact skeleton already present. Two genuinely new files (`scripts/repo_byhash.sh` and `tests/test_*.sh`) copy patterns from existing scripts/tests. Per CONTEXT, the planner has discretion on whether `repo_byhash.sh` is a standalone script vs a `functions.sh` helper, and whether the suite whitelist lives in `config.sh` vs inline arrays.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `packaging/repo/conf/distributions` | config (reprepro metadata) | transform | itself (3 stanzas → 9) | exact (self) |
| `scripts/repo_manage.sh` | script (single-suite repo builder) | batch/transform | itself + `ci_publish.sh` | exact (self) |
| `scripts/ci_publish.sh` | script (multi-suite publisher) | batch/transform | itself | exact (self) |
| `config.sh` | config | transform | `config.sh` arch/distro blocks | exact (self) |
| `.github/workflows/build-packages.yml` (publish job) | config (CI) | request-response | itself (publish step) | exact (self) |
| `scripts/repo_byhash.sh` (NEW, discretion) | utility (post-export by-hash + re-sign) | file-I/O + transform | `scripts/repo_manage.sh` skeleton + GPG block | role-match |
| `tests/test_suite_routing.sh` etc. (NEW, Wave 0) | test (pure-function unit) | request-response | `tests/test_detect_distro_depends.sh` | exact (role) |

## Shared Patterns

### Script skeleton (every new/touched script)
**Source:** `scripts/repo_manage.sh:1-17`, identical in `ci_publish.sh:1-22`
**Apply to:** `scripts/repo_byhash.sh` (if standalone)
```bash
#!/bin/bash
set -euo pipefail
relativepath="../"
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi
source "${toolpath}/config.sh"
source "${toolpath}/functions.sh"
trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR
```
If `repo_byhash.sh` becomes a `functions.sh` helper instead, guard with the `_SOURCED` pattern (see `config.sh:3-5`) — no shebang/trap needed, just the function.

### Suite whitelist validation (extend, do not remove)
**Source:** `scripts/repo_manage.sh:56-59` (mirrored at `ci_publish.sh:69-72`)
```bash
if [[ "${SUITE}" != "stable" && "${SUITE}" != "edge" && "${SUITE}" != "nightly" ]]; then
    echo "ERROR: Invalid suite '${SUITE}'. Must be 'stable', 'edge', or 'nightly'." >&2
    exit 1
fi
```
**Extension target:** Per D-11, this whitelist must accept the 9-suite set. Per CONTEXT discretion + RESEARCH Code Examples, express as an array (prefer `config.sh`, matching the existing `case "$ARCH"` / exported-var style in `config.sh:18-37`) and validate membership:
```bash
ALL_SUITES=(stable edge nightly stable-2404 edge-2404 nightly-2404 stable-2604 edge-2604 nightly-2604)
VALID_TRACKS=(stable edge nightly)
VALID_DISTROS=(2404 2604)
```
Keep the explicit "clear error message" convention (AGENTS.md "Established Patterns").

### GPG key import + re-sign context
**Source:** `scripts/repo_manage.sh:83-112`
```bash
if [[ -n "${GPG_PRIVATE_KEY:-}" ]]; then
    if echo "${GPG_PRIVATE_KEY}" | base64 -d 2>/dev/null | gpg --batch --import 2>/dev/null; then
        ...
    elif printf '%s' "${GPG_PRIVATE_KEY}" | gpg --batch --import; then
        ...
    fi
    GPG_KEY_ID=$(gpg --list-keys --with-colons | grep fpr | head -1 | cut -d: -f10)
    echo "${GPG_KEY_ID}:6:" | gpg --batch --import-ownertrust
fi
```
**Apply to:** by-hash re-signing (D-08). The key is already imported by `repo_manage.sh` before `ci_publish.sh` reaches the by-hash step, so `repo_byhash.sh` does NOT re-import — it relies on the keyring already holding the key. Re-sign with `gpg --batch --yes --clearsign -o InRelease Release` and `gpg --batch --yes -abs -o Release.gpg Release` (RESEARCH Code Examples lines 327-330).

### config.sh extension style
**Source:** `config.sh:18-53` — `export VAR="${VAR:-default}"`, `case` dispatch, echo of resolved value
**Apply to:** any new suite/track/distro arrays or routing helper. Follow `${VAR:-default}` overridability (AGENTS.md critical constraint: never hardcode distro values into build scripts; thread through config.sh).

## Pattern Assignments

### `packaging/repo/conf/distributions` (config, transform)

**Analog:** itself — current 3 stanzas at lines 1-26.

**Current stanza pattern** (lines 1-8):
```
Origin: podman-ubuntu
Label: Podman Ubuntu
Suite: stable
Codename: stable
Architectures: amd64 arm64
Components: main
Description: Podman compiled from source for Ubuntu 24.04 - stable releases
SignWith: yes
```

**Extension (D-01/D-03/D-04):** Replicate this stanza to 9 total. Keep `Codename == Suite` for all. The 3 bare stanzas (`stable`/`edge`/`nightly`) keep `Suite: stable` exactly (this is the entire REPO-07 mechanism — see Pitfall 1) and get a deprecation `Description`. The 6 versioned stanzas use `Suite: stable-2404` ... `nightly-2604`. All keep `SignWith: yes` (single-key criterion). RESEARCH Pattern 1 (lines 163-189) shows the alias + versioned stanza pair verbatim. No `createsymlinks`.

---

### `scripts/repo_manage.sh` (script, batch/transform)

**Analog:** itself.

**includedeb loop** (lines 136-142) — the core add pattern to reuse for alias feeding (D-12):
```bash
for deb_file in "${DEB_DIR}"/*.deb; do
    if [[ -f "${deb_file}" ]]; then
        reprepro -Vb "${OUTPUT_DIR}" includedeb "${SUITE}" "${deb_file}"
    fi
done
```
**Extension:** Per D-12 + Open Question 2, loop over `publish_targets` (target suite + optional bare alias for 2404) feeding the same `DEB_DIR` — simplest is to wrap the includedeb call in an inner loop over targets, one shared db/export pass.

**Export** (lines 152-154): `reprepro -b "${OUTPUT_DIR}" export`. Per-suite export discipline matters once multiple suites are in play — see `ci_publish.sh:203` and Pitfall 4.

**By-hash call site:** after the export block, before db/conf cleanup (lines 179-182). The cleanup `rm -rf "${OUTPUT_DIR}/db"` must stay AFTER by-hash (by-hash reads `dists/`, not `db/`).

**CLI surface (discretion):** D-11 + CONTEXT allow `repo_manage.sh` to learn `track`+`distro` args or stay single-suite with caller-side routing. The `usage()` at lines 23-33 and arg parse at lines 39-41 are where this changes if the planner picks the multi-arg surface.

---

### `scripts/ci_publish.sh` (script, batch/transform)

**Analog:** itself — this is the orchestration spine.

**ALL_SUITES + OTHER_SUITES derivation** (lines 91-97):
```bash
ALL_SUITES=(stable edge nightly)
OTHER_SUITES=()
for s in "${ALL_SUITES[@]}"; do
    if [[ "$s" != "${SUITE}" ]]; then OTHER_SUITES+=("$s"); fi
done
```
**Extension:** `ALL_SUITES` grows to 9. For 2404 publishes the published targets are BOTH `<track>-2404` and bare `<track>`, so the "other suites" exclusion must remove both (D-12/D-13).

**Mirror-down loop** (lines 113-156) — generalizes from 2 other suites to N. Critical first-deploy tolerance (Assumption A3) lives at lines 123-128:
```bash
packages_content=$(curl -sfL "${packages_url}" 2>/dev/null || true)
if [[ -z "${packages_content}" ]]; then
    echo "  No Packages file ... (first deploy or not published)"
    continue
fi
```
Preserve this `|| true` + empty-check so the new `-2404`/`-2604` URLs 404ing on first deploy is tolerated.

**Filename parse** (line 149): `grep "^Filename:" | sed 's/^Filename: *//'` — reuse unchanged for any suite.

**Per-suite re-include + export** (lines 182-205), especially line 203:
```bash
reprepro -b "${OUTPUT_DIR}" export "${other_suite}"   # per-suite, never bare export (Pitfall 4)
```

**index.html suite loop** (D-18) — lines 229-234 collect available suites, lines 325-352 render only non-empty ones:
```bash
available_suites=()
for s in stable edge nightly; do
    if [[ -d "${OUTPUT_DIR}/dists/${s}" ]]; then available_suites+=("${s}"); fi
done
...
if [[ ${pkg_count} -eq 0 ]]; then continue; fi   # skip empty (keeps -2604 hidden until Phase 21)
```
**Extension:** iterate the 9-suite set; the empty-skip already handles empty-but-signed `-2604`. Minimal change only — no per-distro instructions (those are Phase 22). The static `<h2>Choose a Track>` / tab blocks (lines 272-313) stay as-is for this phase.

---

### `scripts/repo_byhash.sh` (NEW — utility, file-I/O + transform) [discretion: standalone vs functions.sh helper]

**Analog:** `scripts/repo_manage.sh` skeleton (lines 1-17) + GPG block; the function body comes from RESEARCH Code Examples (lines 289-333).

**Core pattern** (RESEARCH lines 293-331): per suite, after `export` — parse Release `SHA256:`/`SHA512:` sections via awk to get `(hash, relpath)`, `cp` each index to `<dir>/by-hash/<ALGO>/<hash>`, inject `Acquire-By-Hash: yes` (idempotent `grep -q || sed -i '/^Suite:/a ...'`), by-hash the Release itself, then re-sign InRelease + Release.gpg.

**Verify before relying on SHA512** (Open Question 1 / A1): on a real export, `grep -E '^(MD5Sum|SHA1|SHA256|SHA512):' dists/<suite>/Release` to confirm which algos reprepro emits; the helper already guards each algo with `[[ -f ]]` / `command -v`. macOS cannot run reprepro — confirm on Lima ubuntu-24 or CI (RESEARCH Environment Availability).

**By-hash layout** (Pitfall 3): `by-hash/` dirs sit ADJACENT to each index (`main/binary-amd64/by-hash/SHA256/<hash>`), plus a Release-level one — never only at dists root.

---

### `tests/test_suite_routing.sh` / `test_alias_routing.sh` / `test_distributions_suites.sh` / `test_byhash_parse.sh` (NEW — test, pure-function unit) [Wave 0]

**Analog:** `tests/test_detect_distro_depends.sh`.

**Test skeleton** (lines 12-37):
```bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
PASS_COUNT=0; FAIL_COUNT=0
assert_equals() { local description="$1" expected="$2" actual="$3"; ... }
assert_succeeds() { ... ( "$@" ) >/dev/null 2>&1 ... }
```
**Platform-skip convention** (lines 6-10): reprepro/gpg/apt assertions are Ubuntu-only — gate them and SKIP on macOS, run pure-function assertions everywhere (mirrors how `detect_runtime_depends` dpkg-assertions are skipped). Routing logic should be extracted into a sourceable function (config.sh/functions.sh) so unit tests call it without a full publish (RESEARCH Wave 0 Gaps). Run directly: `bash tests/test_<name>.sh`.

---

### `.github/workflows/build-packages.yml` (config, CI) — publish job

**Analog:** itself — current publish step (lines ~304-313):
```yaml
- name: Build and publish repository
  env:
    GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
  run: |
    ./scripts/ci_publish.sh \
      "${{ steps.track.outputs.track }}" \
      "all-debs" \
      "https://${{ github.repository_owner }}.github.io/${{ github.event.repository.name }}" \
      "repo-output"
```
**Extension (D-11):** add the `distro` argument to the `ci_publish.sh` invocation to match the new arg shape (`<track> <distro> <deb-dir> <repo-url> <output-dir>` per RESEARCH diagram line 120). The matrix fan-out that supplies distro values is Phase 21 — this phase only plumbs the single argument. Keep `reprepro` install step (lines ~300-303) and the `upload-pages-artifact` / `deploy-pages` steps unchanged (atomic deploy, D-10/D-16).

## No Analog Found

None. Every file maps to an existing in-repo pattern (its own current form or a sibling script/test). The only genuinely new artifacts (`repo_byhash.sh`, Wave-0 tests) copy directly from `repo_manage.sh` and `test_detect_distro_depends.sh` respectively, with the by-hash function body specified concretely in 20-RESEARCH.md Code Examples.

## Metadata

**Analog search scope:** `scripts/`, `packaging/repo/conf/`, `config.sh`, `functions.sh` (skeleton), `tests/`, `.github/workflows/`
**Files scanned:** 7 read in full / targeted
**Pattern extraction date:** 2026-06-06
