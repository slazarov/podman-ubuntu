# Phase 22: Migration Docs & Installability Smoke Tests — Pattern Map

**Mapped:** 2026-06-07
**Files analyzed:** 6
**Analogs found:** 6 / 6

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `docs/apt-repository.md` | documentation | transform (rewrite in-place) | `docs/apt-repository.md` (self) | exact (edit-in-place) |
| `scripts/ci_publish.sh` | generator (HTML + CI logic) | transform + batch | `scripts/ci_publish.sh` L472-623 (self) | exact (extend-in-place) |
| `.github/workflows/build-packages.yml` | CI config | request-response (pipeline gate) | `.github/workflows/build-packages.yml` L276-368 (self) | exact (insert step) |
| `scripts/smoke_repo_install.sh` | smoke test helper | request-response (container exec) | `scripts/smoke_install_2604.sh` | role-match (same idiom) |
| `tests/test_docs_suites.sh` | unit test (doc-grep) | transform | `tests/test_detect_distro_depends.sh` (if present) | role-match |
| `tests/test_index_html_distro.sh` | unit test (string assert) | transform | `.planning/codebase/TESTING.md` skeleton | partial-match |

---

## Pattern Assignments

### `docs/apt-repository.md` (documentation, edit in-place)

**Analog:** `docs/apt-repository.md` (self — edit in-place, not a new file)

**Current structure to reorganise** (`docs/apt-repository.md` L1-147):
- L1-8: Intro paragraph (references bare `stable`/`edge` and Ubuntu 24.04 only — update)
- L10-32: Quick Start DEB822 block (bare `Suites: stable` — replace with per-distro subsections)
- L38-52: "Using the Edge Suite" section (bare suites — replace with per-distro track guidance)
- L54-80: Individual packages table (keep as-is)
- L82-86: Supported Architectures (keep, minor update: mention both Ubuntu LTS versions)
- L88-141: Troubleshooting (keep; update L129 suite list to include distro-qualified names)
- L142-147: Important Notes (move content here to top as a deprecation callout per D-05)

**Target document structure** (D-01):
```
# APT Repository Setup
[intro — both Ubuntu 24.04 and 26.04 LTS, two distro flavours]

> **Note:** [DEPRECATION CALLOUT — v3.0 / bare suite names] (D-05, D-12)

## Ubuntu 24.04 (Noble Numbat) Setup
[DEB822 block with Suites: stable-2404 / edge-2404 / nightly-2404]

## Ubuntu 26.04 (Resolute Raccoon) Setup
[DEB822 block with Suites: stable-2604 / edge-2604 / nightly-2604]

## GPG Signing Key
[Single key section — once only per D-06]

## Track Selection
[stable / edge / nightly descriptions]

## Individual Packages
[existing table, unchanged]

## Supported Architectures
[existing content]

## Migrating from Bare Suite Names (MIGR-03)
[sed one-liner + new .sources block to paste; note that bare suites continue serving 24.04 during deprecation window]

## Troubleshooting
[existing content, update suite list in Repository returns 404 section]

## Important Notes
[update: ~podman1 → ~ubuntu{24.04,26.04}.podman1 per D-05]
```

**DEB822 block pattern** — copy and specialise per distro (`docs/apt-repository.md` L21-27 current):
```
Types: deb
URIs: https://slazarov.github.io/podman-ubuntu
Suites: stable-2404
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
```
Only `Suites:` changes per distro; URI, Components, Signed-By are identical (D-06).

**GPG key download block** (`docs/apt-repository.md` L14-18 current — keep verbatim):
```bash
sudo mkdir -p /etc/apt/keyrings
sudo wget -qO /etc/apt/keyrings/podman-ubuntu.gpg \
  https://slazarov.github.io/podman-ubuntu/podman-ubuntu.gpg
```

**Deprecation callout pattern** (D-12 — Markdown blockquote at document top):
```markdown
> **Note:** The bare suite names `stable`, `edge`, and `nightly` are deprecated as
> of v3.0 (June 2026). They will be removed in a future v3.1 release. Use the
> distro-qualified names (`stable-2404` / `stable-2604` etc.) shown below.
> If you are an existing user, see [Migrating from Bare Suite Names](#migrating-from-bare-suite-names).
> Monitor the [changelog](https://github.com/slazarov/podman-ubuntu) for the removal notice.
```

**Migration sed one-liner pattern** (D-03 — to be placed in the migration section):
```bash
# Replace bare suite name with distro-qualified name (Ubuntu 24.04 users)
sudo sed -i 's/Suites: stable$/Suites: stable-2404/' \
  /etc/apt/sources.list.d/podman-ubuntu.sources
# Replace for edge / nightly similarly (substitute 'stable' with 'edge' or 'nightly')
```

---

### `scripts/ci_publish.sh` (generator, extend Step 5 heredoc)

**Analog:** `scripts/ci_publish.sh` L472-623 (self — the heredoc block to extend)

**Key context: the index.html heredoc is split across three `cat` calls:**
- L472-558: main `cat > ... << 'HTMLEOF'` — the opening HTML, CSS, track tab markup
- L560-603: dynamic Bash section building the package versions table (appended via `cat >> ...`)
- L605-623: closing `cat >> ... << 'HTMLEOF'` — Resources section + `<script>` with `showTab()`

All three must be coordinated. Additions below slot into the first and third segments.

**CSS pattern to extend** (`ci_publish.sh` L490-496 — existing `.tab-btn` CSS block):
```css
.tab-group { margin: 1.5rem 0; }
.tab-buttons { display: flex; gap: 0; }
.tab-btn { padding: 0.5rem 1.5rem; border: 1px solid #ddd; background: #f4f4f4; cursor: pointer; font-size: 0.95em; }
.tab-btn:first-child { border-radius: 6px 0 0 0; }
.tab-btn:last-child { border-radius: 0 6px 0 0; }
.tab-btn.active { background: #fff; border-bottom-color: #fff; font-weight: 600; }
.tab-content { display: none; border: 1px solid #ddd; border-top: none; border-radius: 0 0 6px 6px; padding: 1rem; }
.tab-content.active { display: block; }
```
Add `.distro-btn` directly after `.tab-btn:last-child` in the same `<style>` block (D-08):
```css
.distro-group { margin: 1.5rem 0 0.5rem; }
.distro-btn { padding: 0.4rem 1.2rem; border: 1px solid #ddd; background: #f4f4f4; cursor: pointer; font-size: 0.9em; margin-right: 0.25rem; border-radius: 4px; }
.distro-btn.active { background: #0366d6; color: #fff; border-color: #0366d6; font-weight: 600; }
```

**Existing HTML escaper** (`ci_publish.sh` L460 — reuse unchanged):
```bash
esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }
```

**Distro toggle markup pattern** (D-07/D-08 — insert above the existing `<h2>Setup</h2>` block at approx L524):
```html
<h2>Setup</h2>
<div class="distro-group">
  <strong>Your Ubuntu version:</strong>
  <button class="distro-btn active" onclick="setDistro('2404')">Ubuntu 24.04</button>
  <button class="distro-btn" onclick="setDistro('2604')">Ubuntu 26.04</button>
</div>
```

**Per-distro snippet pattern** (D-08 — replaces each single `<pre><code>` block inside each `<div id="tab-*">`). Each track tab gets two `<pre>` blocks with `data-distro` attributes:
```html
  <div id="tab-stable" class="tab-content active">
    <pre class="snippet" data-distro="2404"><code>sudo tee /etc/apt/sources.list.d/podman-ubuntu.sources &lt;&lt; 'EOF'
Types: deb
URIs: https://REPO_URL_PLACEHOLDER
Suites: stable-2404
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
EOF</code></pre>
    <pre class="snippet" data-distro="2604" style="display:none"><code>sudo tee /etc/apt/sources.list.d/podman-ubuntu.sources &lt;&lt; 'EOF'
Types: deb
URIs: https://REPO_URL_PLACEHOLDER
Suites: stable-2604
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
EOF</code></pre>
  </div>
```
Repeat for `tab-edge` (suite `edge-2404`/`edge-2604`) and `tab-nightly` (suite `nightly-2404`/`nightly-2604`). Note: the `REPO_URL_PLACEHOLDER` replacement at L626 (`sed -i`) handles substitution after generation — keep the same placeholder.

**CRITICAL: keyring path change.** The existing heredoc uses `/usr/share/keyrings/` (L527-548 legacy one-liner). The new DEB822 snippets MUST use `/etc/apt/keyrings/podman-ubuntu.gpg` to match the docs (RESEARCH Pitfall 3 / Open Question 1). The GPG key download step (L527) must also update from `/usr/share/keyrings/` to `/etc/apt/keyrings/`.

**Deprecation callout** (D-09 — insert after the closing `</div>` of the tab-group, before the install step):
```html
<p><em>Note:</em> The bare suite names <code>stable</code>, <code>edge</code>, and <code>nightly</code>
are <strong>deprecated in v3.0</strong> and will be removed in a future v3.1 release.
<a href="https://github.com/slazarov/podman-ubuntu/blob/main/docs/apt-repository.md#migrating-from-bare-suite-names">Migration guide →</a></p>
```

**JS `setDistro()` function** (D-07 — append after `showTab()` in the closing `<script>` block at L613-619):
```javascript
function showTab(track) {
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
  document.querySelector('.tab-btn[onclick*="' + track + '"]').classList.add('active');
  document.getElementById('tab-' + track).classList.add('active');
}
function setDistro(ver) {
  document.querySelectorAll('.distro-btn').forEach(b => b.classList.remove('active'));
  document.querySelector('.distro-btn[onclick*="' + ver + '"]').classList.add('active');
  document.querySelectorAll('.snippet').forEach(s => {
    s.style.display = s.dataset.distro === ver ? '' : 'none';
  });
}
```

---

### `.github/workflows/build-packages.yml` (CI config, insert one step)

**Analog:** `.github/workflows/build-packages.yml` L276-368 (self — the publish job)

**Insertion point:** After `publish_distro "2604" "all-debs-2604"` (L355) and before `- uses: actions/configure-pages@v4` (L357). Insert a single named step.

**Step structure pattern** — copy the inline-shell idiom from the `Build and publish repository` step (L328-355). Use the same `${{ steps.track.outputs.track }}` reference for `TRACK` and `$PWD/repo-output` for the assembled repo path.

**Smoke gate step** (D-13/D-14/D-15/D-16 — full inline step to insert):
```yaml
      - name: Smoke test — install podman-suite from assembled repo per distro
        run: |
          set -euo pipefail
          TRACK="${{ steps.track.outputs.track }}"
          REPO_DIR="$PWD/repo-output"

          smoke_distro() {
            local image="$1" label="$2" suite="${TRACK}-${label}"
            echo ">>> SMOKE: ${image} (suite ${suite})"
            if ! docker run --rm \
                 --privileged \
                 --device /dev/fuse \
                 -v "${REPO_DIR}:/opt/podman-repo:ro" \
                 -e DEBIAN_FRONTEND=noninteractive \
                 "${image}" bash -s << INNEREOF
set -e
cat > /etc/apt/sources.list.d/podman-smoke.list << 'APTEOF'
deb [trusted=yes] file:///opt/podman-repo ${suite} main
APTEOF
apt-get update -qq
apt-get install -y -q podman-suite
podman info --log-level=error
INNEREOF
            then
              echo "SMOKE FAIL: ${image} — install or podman info failed for suite ${suite}" >&2
              exit 1
            fi
            echo ">>> SMOKE PASS: ${image} suite=${suite}"
          }

          smoke_distro "ubuntu:24.04" "2404"
          # Fall back to resolute codename if ubuntu:26.04 tag is not yet GA
          docker pull ubuntu:26.04 >/dev/null 2>&1 && IMG2604="ubuntu:26.04" || IMG2604="ubuntu:resolute"
          smoke_distro "${IMG2604}" "2604"
```
Note: `bash -s << INNEREOF` (passing the script via stdin) avoids the nested single-quote hazard of `bash -c '...'` interpolating `${suite}` inside single quotes. The `INNEREOF` heredoc body runs with `set -e` so any command failure propagates.

**VFS fallback** (RESEARCH Pitfall 1 — add only if `podman info` fails in CI validation; do not pre-add):
```bash
# Inside the container script, before podman info, if storage errors appear:
mkdir -p /etc/containers
printf '[storage]\ndriver = "vfs"\n' > /etc/containers/storage.conf
```

---

### `scripts/smoke_repo_install.sh` (smoke helper, optional — discretion item)

**Analog:** `scripts/smoke_install_2604.sh` L1-209 (exact role + data-flow match)

**Script header pattern** (copy from `scripts/smoke_install_2604.sh` L1-27):
```bash
#!/bin/bash

# smoke_repo_install.sh - MIGR-04 proof: apt-install podman-suite from the
# assembled on-disk APT repo (file:// source) inside a real ubuntu:<distro>
# userland to verify installability + runtime before GitHub Pages publish.
#
# Usage: smoke_repo_install.sh <distro-label> [repo-dir]
#   distro-label   2404 or 2604 (required)
#   repo-dir       path to assembled repo (default: ../repo-output)
#
# Overrides (project env-override idiom):
#   SMOKE_RUNTIME=docker|podman   force the container runtime (validated)

set -euo pipefail
```

**Toolpath bootstrap** (copy verbatim from `scripts/ci_publish.sh` L11-13):
```bash
relativepath="../"
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing "${scriptpath}/${relativepath}"); fi
```

**Runtime selection + validation** (copy from `scripts/smoke_install_2604.sh` L50-73 — validated against exact-match whitelist):
```bash
RUNTIME=""
if [[ -n "${SMOKE_RUNTIME:-}" ]]; then
    case "${SMOKE_RUNTIME}" in
        docker|podman)
            if ! command -v "${SMOKE_RUNTIME}" &>/dev/null; then
                echo "ERROR: SMOKE_RUNTIME='${SMOKE_RUNTIME}' requested but not on PATH." >&2
                exit 1
            fi
            RUNTIME="${SMOKE_RUNTIME}"
            ;;
        *)
            echo "ERROR: SMOKE_RUNTIME must be exactly 'docker' or 'podman' (got '${SMOKE_RUNTIME}')." >&2
            exit 1
            ;;
    esac
elif command -v docker &>/dev/null; then
    RUNTIME="docker"
elif command -v podman &>/dev/null; then
    RUNTIME="podman"
else
    echo "ERROR: no container runtime found — install docker or podman." >&2
    exit 1
fi
```

**Image fallback pattern** (copy from `scripts/smoke_install_2604.sh` L82-107 — for the 2604 leg):
```bash
IMAGE_CANDIDATES=( "ubuntu:26.04" "ubuntu:resolute" )
IMAGE=""
for candidate in "${IMAGE_CANDIDATES[@]}"; do
    echo ">>> Trying to pull image: ${candidate}"
    if "${RUNTIME}" pull "${candidate}"; then
        IMAGE="${candidate}"
        break
    fi
done
if [[ -z "${IMAGE}" ]]; then
    echo "ERROR: could not pull any 26.04 image from: ${IMAGE_CANDIDATES[*]}" >&2
    exit 1
fi
```

**Container invocation pattern** (copy `--rm` + bind-mount idiom from `smoke_install_2604.sh` L146-149, extend with `--privileged --device /dev/fuse`):
```bash
"${RUNTIME}" run --rm \
    --privileged \
    --device /dev/fuse \
    -v "${REPO_DIR}:/opt/podman-repo:ro" \
    -e DEBIAN_FRONTEND=noninteractive \
    "${IMAGE}" \
    bash -c '
        set -e
        cat > /etc/apt/sources.list.d/podman-smoke.list << APTEOF
deb [trusted=yes] file:///opt/podman-repo '"${SUITE}"' main
APTEOF
        apt-get update -qq
        apt-get install -y -q podman-suite
        podman info --log-level=error
        echo ">>> SMOKE PASS: podman-suite installed and podman info succeeded"
    '
```

**Hard-fail + pass message pattern** (copy from `smoke_install_2604.sh` L200-208):
```bash
echo "========================================"
echo ">>> smoke_repo_install.sh: PASS"
echo "========================================"
exit 0
```

---

### `tests/test_docs_suites.sh` (unit test, doc-grep)

**Analog:** Bash test skeleton from `.planning/codebase/TESTING.md`

**Pattern: grep-based assertions on a static file.** Check that the doc contains the six distro-qualified suite names and the deprecation wording.

```bash
#!/bin/bash
set -euo pipefail
PASS=0; FAIL=0
assert_contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -qF "$pattern" "$file"; then
        echo "PASS: $label"; ((PASS++))
    else
        echo "FAIL: $label — '$pattern' not found in $file" >&2; ((FAIL++))
    fi
}
DOC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs/apt-repository.md"
assert_contains "$DOC" "stable-2404" "24.04 stable suite name present"
assert_contains "$DOC" "stable-2604" "26.04 stable suite name present"
assert_contains "$DOC" "edge-2404"   "24.04 edge suite name present"
assert_contains "$DOC" "edge-2604"   "26.04 edge suite name present"
assert_contains "$DOC" "deprecated"  "deprecation notice present"
assert_contains "$DOC" "v3.1"        "v3.1 removal mention present"
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
```

---

### `tests/test_index_html_distro.sh` (unit test, string assertions on heredoc)

**Analog:** Same Bash test skeleton. Greps the `ci_publish.sh` source itself (the heredoc is the authoritative string, not a generated file that must be run first).

```bash
#!/bin/bash
set -euo pipefail
PASS=0; FAIL=0
assert_contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -qF "$pattern" "$file"; then
        echo "PASS: $label"; ((PASS++))
    else
        echo "FAIL: $label — '$pattern' not found in $file" >&2; ((FAIL++))
    fi
}
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/ci_publish.sh"
assert_contains "$SRC" "setDistro"       "setDistro function defined"
assert_contains "$SRC" "data-distro=\"2404\"" "data-distro 2404 snippet present"
assert_contains "$SRC" "data-distro=\"2604\"" "data-distro 2604 snippet present"
assert_contains "$SRC" "distro-btn"      ".distro-btn CSS/markup present"
assert_contains "$SRC" "stable-2404"     "suite stable-2404 in heredoc"
assert_contains "$SRC" "stable-2604"     "suite stable-2604 in heredoc"
assert_contains "$SRC" "deprecated"      "deprecation callout present"
echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
```

---

## Shared Patterns

### Script header + toolpath bootstrap
**Source:** `scripts/ci_publish.sh` L1-27 / `scripts/smoke_install_2604.sh` L1-36
**Apply to:** `scripts/smoke_repo_install.sh`
```bash
#!/bin/bash
set -euo pipefail
relativepath="../"
if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing "${scriptpath}/${relativepath}"); fi
source "${toolpath}/config.sh"
source "${toolpath}/functions.sh"
trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR
```

### HTML escaper (WR-04)
**Source:** `scripts/ci_publish.sh` L460
**Apply to:** Any dynamic value interpolated into the index.html heredoc
```bash
esc() { sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'; }
```

### Container invocation (privileged + fuse + bind-mount + DEBIAN_FRONTEND)
**Source:** `scripts/smoke_install_2604.sh` L146-150 (extended with `--privileged --device /dev/fuse`)
**Apply to:** `scripts/smoke_repo_install.sh`, the smoke gate step in `.github/workflows/build-packages.yml`
```bash
"${RUNTIME}" run --rm \
    --privileged \
    --device /dev/fuse \
    -v "${REPO_DIR}:/opt/podman-repo:ro" \
    -e DEBIAN_FRONTEND=noninteractive \
    "${image}" bash -s << INNEREOF
```

### TRACK variable reference in workflow
**Source:** `.github/workflows/build-packages.yml` L289-290, L333
**Apply to:** smoke gate step
```yaml
TRACK="${{ steps.track.outputs.track }}"
```

### `[trusted=yes]` boundary rule (security)
**Source:** RESEARCH Security Domain
**Apply to:** All files in this phase
- `[trusted=yes]` / `Trusted: yes` is ONLY permitted in CI-internal smoke gate containers.
- It must NEVER appear in `docs/apt-repository.md` or in the index.html DEB822 user snippets.
- User-facing setup always uses `Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg`.

---

## No Analog Found

All files have close analogs. No entries in this section.

---

## Metadata

**Analog search scope:** `scripts/`, `.github/workflows/`, `docs/`, `tests/`
**Files scanned:** 6 source files read in full or in targeted sections
**Pattern extraction date:** 2026-06-07

### Critical implementation note (Open Question 1 from RESEARCH)
The live `ci_publish.sh` L527-548 emits **legacy one-line `deb [signed-by=/usr/share/keyrings/...]`** format — not DEB822. The locked decision D-07/D-08 assumes DEB822 snippets. The planner must include a **snippet rewrite** task (legacy → DEB822, `/usr/share/keyrings/` → `/etc/apt/keyrings/`) as an explicit action in the ci_publish.sh plan, not just a suite-name swap.
