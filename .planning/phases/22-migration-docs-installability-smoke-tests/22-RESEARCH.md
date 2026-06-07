# Phase 22: Migration Docs & Installability Smoke Tests - Research

**Researched:** 2026-06-07
**Domain:** Documentation (DEB822 APT sources), static HTML/JS UX, GitHub Actions CI smoke gate (Podman-in-Docker)
**Confidence:** HIGH (codebase-verified) / MEDIUM (podman-in-docker behaviour, web-verified)

## Summary

Phase 22 has two deliverables and **no new external dependencies** — it edits one Markdown doc, one shell-generated HTML page, and adds a container-based smoke step to an existing CI job. The decisions in `22-CONTEXT.md` are almost fully locked; this research's job is to (a) surface two real discrepancies between the locked decisions and the *current* code, and (b) de-risk the one genuinely uncertain piece: running `podman info` inside a Docker container on a GitHub Actions runner.

The single most important finding: **`22-CONTEXT.md` D-07/D-08 describe extending a "DEB822 snippet" in `index.html`, but the live `ci_publish.sh` emits the LEGACY one-line `deb [...]` format with `/usr/share/keyrings/*.gpg` and a `.list` file** — not DEB822, not the `/etc/apt/keyrings/` path the docs use. The decision's premise is false; the planner must budget a *snippet rewrite* (legacy → DEB822) plus a keyring-path standardization, not a span-duplication. This is flagged as Open Question 1.

The second finding: the smoke gate (D-14) uses `[trusted=yes]`, which **bypasses GPG verification** — so it proves "package installs + podman runs" but not the Signed-By path real users hit. This is an accepted limitation (D-14 locked it), documented here so the planner records it and never leaks `[trusted=yes]` into user-facing docs.

**Primary recommendation:** Edit `docs/apt-repository.md` and the `ci_publish.sh` index.html heredoc in place per the locked structure; rewrite the index.html track snippets to DEB822 to match the docs (flag the keyring-path change for user confirmation); add an inline smoke-gate step to the `publish` job that runs each distro's container **as root with `--privileged --device /dev/fuse`** and treats `podman info` exit 0 as the pass. Optionally extract the smoke logic into `scripts/smoke_repo_install.sh` mirroring the existing `scripts/smoke_install_2604.sh` idiom.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Per-distro setup instructions | Docs (`docs/apt-repository.md`) | — | Static reference; no runtime component |
| Per-distro setup UX (distro toggle) | CDN / Static (`index.html` via `ci_publish.sh`) | CI (generates the page) | Page is generated at publish time inside `ci_publish.sh` Step 5 |
| Deprecation timeline notice | Docs + Static HTML | — | Mirrored in both surfaces (D-11) |
| Installability verification | CI (`build-packages.yml` publish job) | Container runtime (Docker on runner) | Gate runs on the runner before Pages upload (D-13) |

## User Constraints (from CONTEXT.md)

### Locked Decisions

**DEB822 docs structure (MIGR-01, MIGR-03)**
- **D-01:** Update `docs/apt-repository.md` in-place. No separate per-distro doc files — one doc, clear per-distro subsections. Structure: intro → per-distro setup (Ubuntu 24.04 / Ubuntu 26.04 parallel subsections, each its own DEB822 block with correct suite name) → track selection → individual packages table → deprecation notice → troubleshooting. Existing troubleshooting content stays.
- **D-02:** Suite names: Ubuntu 24.04 → `stable-2404`/`edge-2404`/`nightly-2404`; Ubuntu 26.04 → `stable-2604`/`edge-2604`/`nightly-2604`. Bare names mentioned only in the deprecation section — not the primary setup path.
- **D-03:** Migration section: existing users with `Suites: stable` (or edge/nightly) change to `stable-2404` (24.04) or `stable-2604` (26.04). Provide exact sed one-liner or new `.sources` block. Document that bare suites keep serving 24.04 packages during the deprecation window.
- **D-04:** Deprecation wording: "Deprecated in v3.0 (June 2026). Bare suite names will be removed in a future v3.1 release. Monitor the changelog or watch the GitHub repository for the removal notice." No hard date.
- **D-05:** The bottom "Important Notes" section gets a prominent deprecation callout at the **top** instead, so existing users see it first. Update the suffix note from `~podman1` to `~ubuntu{24.04,26.04}.podman1`.
- **D-06:** GPG key setup unchanged: single key, same URL, same `Signed-By` path — documented once, not per-distro.

**index.html distro UX (MIGR-02)**
- **D-07:** Add a distro toggle above the track tabs: two buttons ("Ubuntu 24.04" / "Ubuntu 26.04"), default 24.04. Active distro updates the DEB822 snippet in each track tab to the distro-qualified suite name. JS extends `showTab()` with a `setDistro(ver)` function that swaps visible snippets.
- **D-08:** Implementation lives in `scripts/ci_publish.sh` heredoc. Keep existing tab-group CSS, add `.distro-btn` style (like `.tab-btn`). Each track tab contains two blocks (24.04 + 26.04 snippet); JS shows/hides by active distro.
- **D-09:** Add a brief deprecation callout below the setup section on index.html: one line noting bare names are deprecated, linking to the docs migration section.
- **D-10:** The "Available Suites" table already iterates `available_suites[]` and skips empty suites (Phase 20 D-18 carries forward unchanged).

**Deprecation timeline (MIGR-03)**
- **D-11:** Wording locked: "deprecated in v3.0, removal in a future v3.1 release — no fixed date, watch the changelog." Document in both `docs/apt-repository.md` and `index.html`.
- **D-12:** The docs deprecation notice gets a `> **Note:**` blockquote.

**CI smoke gate (MIGR-04)**
- **D-13:** Placement: new step sequence inside the `publish` job, after Step 4 (by-hash + re-sign) and before Step 5/6 (Pages upload).
- **D-14:** `docker run` on the runner (Docker pre-installed). Two sequential containers `ubuntu:24.04` and `ubuntu:26.04`. Each: `OUTPUT_DIR` bind-mounted, a `file:///opt/podman-repo` APT source with `[trusted=yes]`, suite targeting `<track>-2404` (24.04 container) / `<track>-2604` (26.04 container) from the CI `TRACK` variable.
- **D-15:** Commands inside each container: `apt-get update -qq` → `apt-get install -y -q podman-suite` → `podman info --log-level=error`. `podman info` must exit 0. Container runs `--privileged`.
- **D-16:** Either container's smoke failure fails the workflow; Pages upload does not run; failure message names which distro and which command.
- **D-17:** No arch-specific smoke containers — amd64 only.
- **D-18:** Smoke test runs on every publish (stable, edge, nightly).

### Claude's Discretion
- Exact CSS for the distro toggle buttons (match `.tab-btn` or simpler inline).
- Whether the distro toggle state persists across reloads (localStorage or ephemeral — default ephemeral).
- Exact wording of per-distro section headers in `docs/apt-repository.md`.
- Whether to extract smoke test logic into a helper script or keep it inline in the publish job.

### Deferred Ideas (OUT OF SCOPE)
- Removing legacy bare-suite aliases (REPO-09, future milestone).
- Codename-aliased suites (`noble`/`resolute`) for `$VERSION_CODENAME` auto-detect (REPO-10).
- Ubuntu 25.x/26.10 interim release support (LTS-only target).
- ARM64 smoke containers (D-17 — amd64 sufficient; arm64 build correctness via build matrix).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MIGR-01 | User on either distro sets up the repo from copy-paste DEB822 `.sources` blocks specific to their version | `docs/apt-repository.md` already uses DEB822 + `/etc/apt/keyrings/podman-ubuntu.gpg` + `Signed-By` (verified L14-32); only the `Suites:` line and per-distro split are new. Suite names verified against `config.sh` `ALL_SUITES` (L67-69). |
| MIGR-02 | index.html presents per-distro setup instructions | index.html generated entirely in `ci_publish.sh` Step 5 heredoc (verified L472-611); existing `showTab()` JS pattern (L601-608) is the extension point. **Caveat:** current snippets are legacy `deb` one-liners, not DEB822 — see Open Question 1. |
| MIGR-03 | Deprecation timeline for bare suite names documented | Bare aliases (`stable`/`edge`/`nightly`) are real published suites (`config.sh` `ALL_SUITES` L67) fed only on 24.04 publishes (`resolve_publish_targets` L114-117). Phase 20 D-04 reprepro `Description:` deprecation note already matches the v3.0→v3.1 framing. |
| MIGR-04 | CI installs `podman-suite` + runs `podman info` in real ubuntu:24.04 and ubuntu:26.04 containers before publish | Prior art: `scripts/smoke_install_2604.sh` (verified — runtime selection, `--rm`, bind-mount, hard-fail idiom). Publish job has `OUTPUT_DIR`=`repo-output`, `TRACK`, Docker pre-installed (workflow L276-355). New gate differs: installs from assembled APT repo via `file://`, not a bare local `.deb`. |

## Standard Stack

**No new packages installed by this phase.** All tooling is already present:

| Tool | Version | Purpose | Source |
|------|---------|---------|--------|
| Docker | pre-installed on `ubuntu-latest`/`ubuntu-24.04` runners | Run smoke containers | [CITED: GitHub-hosted runner images include Docker] |
| `reprepro` | apt (installed in publish job, L316-319) | Repo already assembled before smoke step | verified workflow L316 |
| `ubuntu:24.04` / `ubuntu:26.04` Docker images | Docker Hub official | Smoke test base userlands | [ASSUMED] `ubuntu:26.04` tag pullable (see Open Question 3) |
| `podman-suite` + sibling `podman-*` .debs | built by this project's pipeline | Installation target | project-internal, not external |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `docker run ubuntu:NN` smoke | A reusable helper `scripts/smoke_repo_install.sh` | Helper matches the existing `smoke_install_2604.sh` idiom and is locally runnable in Lima VMs; inline steps are simpler to read in the YAML. Discretion item — recommend the helper for parity and local testability. |
| `[trusted=yes]` `file://` source | Full GPG round-trip in the smoke container | GPG round-trip would also prove the Signed-By path real users hit, but D-14 locked `[trusted=yes]` as a CI-internal shortcut. See Security Domain. |

## Package Legitimacy Audit

**N/A — this phase installs no new external packages.**

- `podman-suite` and its `podman-*` siblings are this project's own build artifacts (not registry packages).
- `docker`, `reprepro` are pre-installed / already installed by the existing publish job.
- `ubuntu:24.04` / `ubuntu:26.04` are official Docker Hub base images, not language-ecosystem packages.

The slopcheck / npm-view / PyPI verification dance does not apply. No `Package Legitimacy Gate` run is required.

## Architecture Patterns

### System Architecture Diagram

```
DOCS PATH (MIGR-01/03):
  docs/apt-repository.md  ──edit in place──►  rendered on GitHub
    intro → [Ubuntu 24.04 §: DEB822 stable-2404] → [Ubuntu 26.04 §: DEB822 stable-2604]
          → track table → packages table → DEPRECATION callout(top) → troubleshooting

UX PATH (MIGR-02/03):
  ci_publish.sh Step 5 heredoc ──generates──►  repo-output/index.html ──Pages──► users
    [distro toggle: 24.04 | 26.04]  (NEW, default 24.04)
            │ setDistro(ver) swaps visible snippet
            ▼
    [track tabs: stable | edge | nightly]  (existing showTab)
            │ each tab holds TWO snippets (2404 + 2604), DEB822 format
            ▼
    [deprecation callout] (NEW, links to docs migration §)

SMOKE GATE PATH (MIGR-04):
  build job (4 cells: 2404/2604 × amd64/arm64) ──all success──► publish job
    Step 3  ci_publish.sh ×2 (2404 then 2604) → repo-output/ (9 suites, signed)
    Step 4  by-hash + re-sign  [done by ci_publish.sh internally]
    Step 4.5 SMOKE GATE  (NEW) ───────────────────────────┐
       docker run ubuntu:24.04  (file://repo-output, [trusted=yes])
         apt-get update → apt-get install podman-suite → podman info  (suite=<track>-2404)
       docker run ubuntu:26.04  (file://repo-output, [trusted=yes])
         apt-get update → apt-get install podman-suite → podman info  (suite=<track>-2604)
       any non-zero → fail workflow, name distro+command  ◄──────────┘
    Step 5  configure-pages
    Step 6  upload-pages-artifact + deploy-pages   (only if smoke passed)
```

### Recommended Project Structure
No new directories. Touched files:
```
docs/apt-repository.md                  # edit in place (D-01..D-06)
scripts/ci_publish.sh                   # index.html heredoc (Step 5, L472-611)
scripts/smoke_repo_install.sh           # OPTIONAL new helper (discretion D-? / advisor parity)
.github/workflows/build-packages.yml    # smoke step in publish job, after L355, before L357
tests/test_*.sh                         # OPTIONAL unit test for suite-name strings (see Validation)
```

### Pattern 1: DEB822 `.sources` block (the canonical user-facing setup)
**What:** Modern multi-line APT source format, already in use in the docs.
**When to use:** Every per-distro setup block in `docs/apt-repository.md` and `index.html`.
**Example (Ubuntu 26.04 stable):**
```
# Source: docs/apt-repository.md L21-27 (existing format, Suites line changed)
Types: deb
URIs: https://slazarov.github.io/podman-ubuntu
Suites: stable-2604
Components: main
Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg
```
The only per-distro difference is `Suites:`. URI, Components, Signed-By, and the GPG key are identical across distros (D-06). [VERIFIED: read docs/apt-repository.md L14-32]

### Pattern 2: Smoke install from a locally-assembled repo via `file://` + `[trusted=yes]`
**What:** Point APT at the on-disk assembled repo and install without GPG round-trip.
**When to use:** The CI smoke gate only (never in docs).
**Example (inside the 24.04 container, `<track>` from the matrix/CI var):**
```bash
# Source: synthesised from D-14/D-15 + reprepro file:// convention
set -e
cat > /etc/apt/sources.list.d/podman-smoke.sources <<EOF
Types: deb
URIs: file:///opt/podman-repo
Suites: ${TRACK}-2404
Components: main
Trusted: yes
EOF
apt-get update -qq
apt-get install -y -q podman-suite
podman info --log-level=error
```
Note: in DEB822, `[trusted=yes]` is the field `Trusted: yes`. If the smoke step instead writes a legacy one-line source, use `deb [trusted=yes] file:///opt/podman-repo <track>-2404 main`. Either is acceptable for the CI-internal test; pick one consistently. [CITED: Debian sources.list(5) — `Trusted` / `trusted=yes` option]

### Pattern 3: Container invocation for `podman info` (the de-risked form)
**What:** Run the smoke container as **root** (the image default) with device + privilege flags sufficient for `podman info` to initialize cleanly.
**Recommended invocation:**
```bash
# Source: synthesised from D-15 + podman-in-docker web research (see Pitfall 1)
docker run --rm \
  --privileged \
  --device /dev/fuse \
  -v "$PWD/repo-output:/opt/podman-repo:ro" \
  -e DEBIAN_FRONTEND=noninteractive \
  -e TRACK="${TRACK}" \
  ubuntu:24.04 \
  bash -c '<install + podman info script>'
```
Running as root (no `-u`) sidesteps rootless subuid/subgid setup entirely. `--privileged` plus `--device /dev/fuse` covers storage-driver and FUSE initialization. `podman info` queries config/store/runtime metadata — it does **not** start a container — so it is far less demanding than `podman run`; the main residual risk is the storage graph-driver probe (mitigation in Pitfall 1). [VERIFIED: web research — see Sources]

### Anti-Patterns to Avoid
- **Duplicating the legacy `deb` one-liner per distro in index.html.** D-08's "swap the snippet" is correct, but the snippet must be **rewritten to DEB822 first** (Open Question 1) — don't clone the existing legacy line.
- **Leaking `[trusted=yes]` / `Trusted: yes` into `docs/apt-repository.md` or index.html.** It is a CI-internal shortcut only; user-facing docs must use `Signed-By`.
- **Running the smoke container rootless or with a non-root `-u`.** Forces subuid/subgid plumbing that `podman info` does not need; run as root.
- **Treating `apt install` success as the whole signal.** D-15 requires `podman info` exit 0 as the real gate — a package that installs but whose binary can't introspect its runtime would still be a regression.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Container runtime selection in the smoke helper | Custom which-runtime logic | Copy the validated `SMOKE_RUNTIME` block from `scripts/smoke_install_2604.sh` L50-74 | Already handles docker/podman, validates the value before interpolation (injection-safe), hard-fails with a clear message |
| HTML escaping of dynamic package names/versions in index.html | New escaper | The existing `esc()` function (`ci_publish.sh` L460) | Already orders `&` first to avoid double-escaping (WR-04); reuse it |
| Suite-name construction (`<track>-2404`) | Ad-hoc string building scattered across files | Derive from `${TRACK}` + the distro label, mirroring `resolve_publish_targets` (config.sh L90-118) | Single source of truth for the 9-suite universe is `config.sh ALL_SUITES` |

**Key insight:** Every primitive this phase needs (runtime selection, bind-mount + `--rm` install proof, HTML escaping, suite routing) already exists in the codebase. The phase is wiring + docs, not new machinery.

## Common Pitfalls

### Pitfall 1: `podman info` fails to initialize the storage graph driver inside Docker
**What goes wrong:** Inside a container, Podman cannot use `overlay` on top of an overlay filesystem; if it can't fall back cleanly it errors during store init, and `podman info` returns non-zero.
**Why it happens:** The runner's container filesystem is itself overlay; nested overlay is rejected. fuse-overlayfs needs `/dev/fuse`. As root with `--privileged` Podman normally selects native overlay or fuse-overlayfs, but environments vary.
**How to avoid:**
1. Run as **root** with `--privileged --device /dev/fuse` (recommended invocation above).
2. If `podman info` still errors on storage, force VFS as a deterministic fallback — write `/etc/containers/storage.conf` with `[storage]\ndriver = "vfs"` (or set `STORAGE_DRIVER=vfs`) inside the container before `podman info`. VFS needs no special filesystem support and always initializes; it is slower but the smoke test never runs a container, only `podman info`, so speed is irrelevant.
**Warning signs:** `podman info` stderr mentions "overlay", "native overlay diff", "fuse-overlayfs", or "kernel does not support" — switch that container to VFS.
[VERIFIED: web research — containers/podman #18968, #26590; Red Hat fuse-overlayfs guide]

### Pitfall 2: cgroup / runtime probe noise (lower risk for `podman info`)
**What goes wrong:** Rootless Podman commonly hits "systemd cgroup support not available" / cgroup v2 delegation errors.
**Why it matters here:** Largely avoided because (a) the container runs as **root** (rootful), not rootless, and (b) `podman info` queries metadata rather than launching a container, so cgroup *delegation for a running container* is not exercised. `--log-level=error` (D-15) suppresses warnings.
**How to avoid:** Root + `--privileged` is sufficient. If a cgroup error still surfaces, add `--cgroupns=host` to the `docker run`. Do not add `--cgroup-manager=cgroupfs` unless an error specifically demands it.
[VERIFIED: web research — containers/podman #5443, #27369; access.redhat.com/solutions/5913671]

### Pitfall 3: index.html snippet format mismatch (the silent doc/UX divergence)
**What goes wrong:** Docs use DEB822 `.sources` + `/etc/apt/keyrings/`; the live index.html uses legacy `deb [...]` one-liners + `/usr/share/keyrings/` + `.list`. If MIGR-02 only swaps the suite name in the existing legacy snippet, the page and the docs disagree on format and key path.
**Why it happens:** D-07 was written assuming index.html was already DEB822; it isn't (verified L527-548).
**How to avoid:** Rewrite the index.html track snippets to DEB822 to match the docs, standardizing on `/etc/apt/keyrings/podman-ubuntu.gpg`. See Open Question 1 — the keyring-path change is a slight scope expansion worth one line of user confirmation.
[VERIFIED: read ci_publish.sh L527-548 vs docs/apt-repository.md L14-32]

### Pitfall 4: `ubuntu:26.04` tag not yet GA on Docker Hub
**What goes wrong:** `docker pull ubuntu:26.04` could 404 if the tag isn't published when CI runs.
**Why it happens:** 26.04 release timing vs Docker Hub tag availability.
**How to avoid:** Mirror the existing `smoke_install_2604.sh` fallback (L82-107): try `ubuntu:26.04`, fall back to `ubuntu:resolute` (the 26.04 codename). Build matrix already builds 26.04 inside `ubuntu:26.04` containers (workflow L132), so if the build cells pull it, the smoke step will too — but keep the fallback for safety.
[VERIFIED: read scripts/smoke_install_2604.sh L76-107; workflow L129-136]

## Code Examples

### MIGR-04 smoke gate as an inline `publish`-job step (insert after workflow L355, before L357)
```yaml
# Source: synthesised from D-13/D-14/D-15/D-16 + smoke_install_2604.sh idiom
      - name: Smoke test — install podman-suite + podman info per distro
        run: |
          set -euo pipefail
          TRACK="${{ steps.track.outputs.track }}"
          REPO_DIR="$PWD/repo-output"

          smoke() {            # smoke <image> <distro-label>
            local image="$1" label="$2" suite="${TRACK}-$2"
            echo ">>> SMOKE: ${image} (suite ${suite})"
            if ! docker run --rm --privileged --device /dev/fuse \
                 -v "${REPO_DIR}:/opt/podman-repo:ro" \
                 -e DEBIAN_FRONTEND=noninteractive \
                 "${image}" bash -c '
                   set -e
                   cat > /etc/apt/sources.list.d/podman-smoke.list <<EOF
deb [trusted=yes] file:///opt/podman-repo '"${suite}"' main
EOF
                   apt-get update -qq
                   apt-get install -y -q podman-suite
                   podman info --log-level=error
                 '; then
              echo "SMOKE FAIL: ${image} — install or podman info failed for suite ${suite}" >&2
              return 1
            fi
            echo ">>> SMOKE PASS: ${image}"
          }

          smoke "ubuntu:24.04" "2404"
          # 26.04 fallback to resolute codename if the numeric tag 404s
          docker pull ubuntu:26.04 >/dev/null 2>&1 && IMG2604=ubuntu:26.04 || IMG2604=ubuntu:resolute
          smoke "${IMG2604}" "2604"
```
Note: the heredoc nests a shell variable (`${suite}`) into a single-quoted `bash -c` body via concatenation — verify quoting carefully at plan time, or prefer the extracted-helper approach which avoids the nested-quote hazard.

### MIGR-02 distro toggle JS (extends existing showTab pattern, ci_publish.sh L601-608)
```javascript
// Source: synthesised from D-07; extends existing showTab() at ci_publish.sh L602
function setDistro(ver) {
  document.querySelectorAll('.distro-btn').forEach(b => b.classList.remove('active'));
  document.querySelector('.distro-btn[onclick*="' + ver + '"]').classList.add('active');
  document.querySelectorAll('.snippet').forEach(s => {
    s.style.display = s.dataset.distro === ver ? '' : 'none';
  });
}
```
Each track tab holds two `<pre class="snippet" data-distro="2404">` / `data-distro="2604"` blocks; `setDistro` shows the matching one. Default 24.04 by emitting the 2404 snippets visible and 2604 hidden, plus the `.distro-btn[onclick*="2404"]` carrying `active` in the generated HTML.

## Runtime State Inventory

**OMITTED** — this is not a rename/refactor/migration-of-stored-data phase. It edits docs, generated HTML, and CI config. No databases, live-service configs, OS registrations, secrets, or build artifacts embed a string being renamed. (The "migration" in the phase title is *user documentation* about a suite-name deprecation, not a data migration.)

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Legacy one-line `deb [...]` source + global trusted key | DEB822 `.sources` + `Signed-By` per-repo key | Ubuntu 22.04+ / apt 2.4+ | Docs already use DEB822 (L14-32); index.html still uses legacy — Open Question 1 |
| Trust-everything `apt-key add` | `Signed-By` keyring binding | apt deprecated apt-key | Already adopted in docs; keep it in index.html rewrite |

**Deprecated/outdated:**
- The bare `stable`/`edge`/`nightly` suite names: deprecated in v3.0, removal in a future v3.1 (this phase documents the timeline; REPO-09 removes them later).
- index.html legacy `deb` one-liner + `/usr/share/keyrings/`: should be modernized to DEB822 + `/etc/apt/keyrings/` to match the docs (Open Question 1).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ubuntu:26.04` (or `ubuntu:resolute`) is pullable from Docker Hub at CI time | Standard Stack / Pitfall 4 | Smoke gate's 26.04 leg fails on pull; mitigated by the resolute fallback and the fact the build matrix already pulls `ubuntu:26.04` |
| A2 | `--privileged --device /dev/fuse` as root is sufficient for `podman info` exit 0 on a GHA runner | Pattern 3 / Pitfall 1 | If storage probe still fails, fall back to `STORAGE_DRIVER=vfs` (documented mitigation) — not a blocker |
| A3 | Both `<track>-2404` and `<track>-2604` carry fresh debs on every publish of the current track | Open Question 4 | If a distro suite is empty for the current track, its smoke leg has nothing to install — see OQ4; verified likely-true from the workflow |
| A4 | Standardizing index.html on `/etc/apt/keyrings/` (vs current `/usr/share/keyrings/`) is acceptable to the user | Open Question 1 | If the user wants to keep `/usr/share/keyrings/`, the docs and page would diverge on key path — needs one-line confirmation |

## Open Questions (RESOLVED)

1. **index.html snippet format: rewrite legacy → DEB822, and standardize keyring path?**
   - What we know: Live `ci_publish.sh` emits legacy `deb [signed-by=/usr/share/keyrings/podman-ubuntu.gpg] ... stable main` into a `.list` file (L527-548). Docs use DEB822 `.sources` + `/etc/apt/keyrings/podman-ubuntu.gpg` (L14-32). D-07/D-08 assume the page is already DEB822.
   - What's unclear: Whether to (a) rewrite index.html snippets to DEB822 (matches docs + D-07's own "DEB822 snippet" wording) and move the keyring to `/etc/apt/keyrings/`, or (b) keep legacy and only swap the suite name.
   - Recommendation: **Rewrite to DEB822 and standardize on `/etc/apt/keyrings/`** so the page and docs agree and D-07's wording is honored. The keyring-path change is a small scope expansion — confirm with the user in one line, then proceed.
   - **RESOLVED:** Rewrite the index.html snippets to DEB822 and standardize on `/etc/apt/keyrings/podman-ubuntu.gpg`. This is **authorized as Claude's discretion** — the user's standing directive for this phase is "apply best practices, don't overengineer," and a consistent keyring path between `index.html` and `docs/apt-repository.md` (which already uses `/etc/apt/keyrings/`) is a best-practice consistency fix, not a scope expansion. It directly satisfies ROADMAP **SC-4** (key path consistent across both user-facing surfaces) and honors **D-07**'s "DEB822 snippet" wording. **Plan 02 implements this** (Task 2 rewrites the legacy one-liner + `/usr/share/keyrings/` to DEB822 + `/etc/apt/keyrings/`, with a Task-1 negative assertion that the legacy path is fully removed). No separate user confirmation gate is required — the keyring-path change is explicitly sanctioned here.

2. **Extract smoke logic into `scripts/smoke_repo_install.sh` or keep inline?** (Discretion item.)
   - Recommendation: **Extract a helper** mirroring `scripts/smoke_install_2604.sh`. Benefits: locally runnable in Lima VMs (parity with existing smoke proof), avoids the nested-quote hazard of an inline `bash -c` heredoc, testable. The publish job calls it twice (`smoke_repo_install.sh 2404` / `2604`).
   - **RESOLVED:** Extract the helper `scripts/smoke_repo_install.sh` (mirrors `smoke_install_2604.sh`; locally runnable in Lima, avoids the nested-quote hazard). **Plan 03 implements this** (Task 1 creates the helper; Task 2 wires it into the publish job, invoked twice for 2404/2604).

3. **`ubuntu:26.04` Docker Hub tag availability.**
   - What we know: The build matrix already runs inside `ubuntu:26.04` containers (workflow L132), so the tag is expected to be pullable. `smoke_install_2604.sh` carries a `ubuntu:resolute` fallback.
   - Recommendation: Reuse the same `26.04 → resolute` fallback in the smoke step.
   - **RESOLVED:** Reuse the existing `ubuntu:26.04` → `ubuntu:resolute` pull-fallback. **Plan 03 Task 1 implements this** (the 2604 leg tries `ubuntu:26.04` and falls back to `ubuntu:resolute`, copied from `smoke_install_2604.sh` L82-107).

4. **Are both `<track>-2404` and `<track>-2604` populated on every publish?**
   - What we know: The build job builds all four cells (2404/2604 × amd64/arm64) for the current track; the publish job runs only if all four succeed (`needs.build.result == 'success'`, workflow L278). `ci_publish.sh` is invoked for both `2404` and `2604` (workflow L354-355). So both versioned suites for the current track receive fresh debs every publish.
   - Recommendation: Treat both legs as expected-populated. If a leg's suite is unexpectedly empty, `apt-get install podman-suite` will fail loudly — which is the correct gate behavior, not a false negative.
   - **RESOLVED:** Treat both `<track>-2404` and `<track>-2604` as expected-populated on every publish (the publish job only runs when all four build cells succeed, and `ci_publish.sh` runs for both distro labels). An empty suite is NOT specially handled: `apt-get install podman-suite` against an empty suite fails loudly, which is the **correct gate behavior** (a genuine regression should fail the publish), not a false negative. No special-casing needed in Plan 03 — the loud failure is the intended signal.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker | MIGR-04 smoke containers | ✓ (on GHA runner) | runner-provided | — |
| `ubuntu:24.04` image | 24.04 smoke leg | ✓ | latest | — |
| `ubuntu:26.04` image | 26.04 smoke leg | ✓ (assumed) | latest | `ubuntu:resolute` |
| `/dev/fuse` device | storage init in `podman info` | ✓ via `--device /dev/fuse` | — | `STORAGE_DRIVER=vfs` |
| reprepro | repo already assembled pre-smoke | ✓ (installed L316-319) | apt | — |

**Note (dev host):** This is a macOS dev host — the smoke gate and `podman info` cannot be exercised locally without Linux + Docker. Author the smoke logic on macOS (`bash -n` syntax check), and **defer real execution to CI or a Lima VM** (`ubuntu-24` / `ubuntu-26`, where the repo is mounted at `/opt/podman-debian`). This matches the Phase 19 pattern (authored on macOS, proven in Lima).

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** `ubuntu:26.04` → `ubuntu:resolute`; native overlay storage → VFS.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Plain Bash, standalone scripts (no external framework) |
| Config file | none |
| Quick run command | `bash tests/<test>.sh` |
| Full suite command | `for t in tests/test_*.sh; do bash "$t"; done` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MIGR-01 | Docs contain a DEB822 block per distro with the correct suite name | doc-grep unit | `bash tests/test_docs_suites.sh` | ❌ Wave 0 (optional) |
| MIGR-02 | index.html (generated) contains distro toggle + per-distro snippets | string unit | `bash tests/test_index_html_distro.sh` (assert `setDistro`, `data-distro="2404"`, `data-distro="2604"` present in generated output or heredoc) | ❌ Wave 0 (optional) |
| MIGR-03 | Deprecation wording present in both docs and index.html | doc/string unit | grep for the locked deprecation phrasing | ❌ Wave 0 (optional) |
| MIGR-04 | `podman-suite` installs + `podman info` exits 0 in ubuntu:24.04 and ubuntu:26.04 | integration (container) | The CI smoke gate itself; or `bash scripts/smoke_repo_install.sh 2404` in a Lima VM | ❌ Wave 0 (the gate IS the test) |

### Sampling Rate
- **Per task commit:** `bash -n` on touched scripts + `bash tests/test_<touched>.sh` for any added unit test.
- **Per wave merge:** full `tests/test_*.sh` sweep (macOS-runnable subset).
- **Phase gate:** MIGR-04 is validated end-to-end only by a real CI publish run (or a Lima VM smoke run) — `/gsd-verify-work` must account for this being CI-proven, not macOS-proven.

### Wave 0 Gaps
- [ ] **CRITICAL — the existing unit tests are NOT run in CI.** `grep` of `build-packages.yml` for `tests/` returned nothing: `tests/test_*.sh` are local/manual only, despite `TESTING.md` L284-288 claiming they run in CI. Any unit test added in this phase will **not** auto-run on push. Either (a) accept local-only validation, or (b) add a `run-tests` job to the workflow (small scope expansion — flag to user). Do not assume a new test gates anything automatically.
- [ ] `scripts/smoke_repo_install.sh` — the MIGR-04 helper (if extracted per OQ2); `bash -n`-checkable on macOS, executable only on Linux+Docker.
- [ ] Optional unit tests (`test_docs_suites.sh`, `test_index_html_distro.sh`) — pure-string assertions, macOS-runnable.

*If unit tests are added but the run-tests job is not, mark them "local/manual only" explicitly.*

## Security Domain

`security_enforcement` not explicitly disabled — section included.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth surface in this phase |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes (minor) | index.html already HTML-escapes dynamic package names/versions via `esc()` (WR-04, ci_publish.sh L460) — reuse, do not regress. New static toggle markup is not attacker-influenced. |
| V6 Cryptography | yes (context) | GPG signing of the repo is unchanged; this phase must not weaken the user-facing `Signed-By` requirement. |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| `[trusted=yes]` smoke source disables signature verification | Tampering / Spoofing | Confined to the CI-internal `file://` smoke test (D-14). **Must never appear in `docs/apt-repository.md` or index.html.** Real users always use `Signed-By` with the published key. Document this boundary so a future edit doesn't copy the smoke snippet into the docs. |
| HTML injection via package name/version in generated index.html | Tampering (XSS) | Existing `esc()` escaper (L460); reuse for any new dynamic interpolation. The new toggle markup is static. |
| Command injection via interpolated image/suite names in the smoke `docker run` | Tampering | `TRACK` comes from a constrained CI choice/input; suite/distro labels are hardcoded `2404`/`2604`. If extracting a helper, copy the `smoke_install_2604.sh` validation pattern (exact-match `docker|podman`, image-name regex L84) before interpolating any override. |

**Known limitation (accepted, D-14):** The smoke gate proves *installability and runnability* but, because of `[trusted=yes]`, does **not** exercise the GPG `Signed-By` verification path a real user hits. Record this so it's a known gap, not an assumed coverage. A future hardening could add a GPG-verified smoke leg (out of scope here).

## Sources

### Primary (HIGH confidence)
- `docs/apt-repository.md` (read L1-147) — current DEB822 setup, single-distro, bare-suite references, troubleshooting, "Important Notes"
- `scripts/ci_publish.sh` (read L1-657) — index.html heredoc (L472-611), legacy `deb` snippets (L527-548), `showTab()` JS (L601-608), `esc()` (L460), suite universe handling
- `scripts/smoke_install_2604.sh` (read L1-210) — prior-art smoke idiom: runtime selection/validation, image fallback, `--rm` bind-mount install proof, hard-fail
- `config.sh` (read L1-300) — `ALL_SUITES` 9-suite universe (L67-69), `resolve_publish_targets` (L90-118), `VERSION_SUFFIX`
- `.github/workflows/build-packages.yml` (read L1-368) — publish job structure (L276-368), `TRACK`/`OUTPUT_DIR`, sequential 2404/2604 publish (L354-355), atomic gating (L278); confirmed tests not run in CI
- `.planning/codebase/TESTING.md` — bash test skeleton, assert helpers, platform-conditional skip, Lima execution pattern

### Secondary (MEDIUM confidence — web-verified)
- containers/podman #18968, #26590 — VFS for nested/rootless storage; `/dev/fuse` for fuse-overlayfs
- Red Hat / Eclipse Che fuse-overlayfs guides — `--device /dev/fuse` preferred over bare `--privileged`
- containers/podman #5443, #27369; access.redhat.com/solutions/5913671 — rootless cgroup pitfalls (mitigated by running rootful)
- Debian `sources.list(5)` — `Trusted: yes` / `[trusted=yes]` semantics

### Tertiary (LOW confidence)
- `ubuntu:26.04` Docker Hub tag GA timing — assumed pullable (A1); resolute fallback in place

## Metadata

**Confidence breakdown:**
- Docs structure (MIGR-01/03): HIGH — existing file read; only suite-name + sectioning changes
- index.html UX (MIGR-02): MEDIUM — pattern clear, but the legacy→DEB822 format discrepancy needs a one-line user decision (OQ1)
- Smoke gate (MIGR-04): MEDIUM — strong prior art + web-verified podman-in-docker mitigations; `podman info` exit 0 needs real-CI/Lima proof (deferred per dev-host constraint)
- Pitfalls: HIGH (doc/format) / MEDIUM (container runtime) — cross-referenced codebase + multiple web sources

**Research date:** 2026-06-07
**Valid until:** 2026-07-07 (stable — Bash/APT/Podman patterns move slowly; recheck `ubuntu:26.04` tag availability nearer CI run)
