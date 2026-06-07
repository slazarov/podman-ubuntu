# Phase 22: Migration Docs & Installability Smoke Tests - Context

**Gathered:** 2026-06-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Two deliverables:

1. **Documentation** — `docs/apt-repository.md` updated with per-distro DEB822 `.sources` blocks (Ubuntu 24.04 / Ubuntu 26.04 as distinct sections, picking the correct suite name per distro), a deprecation notice for bare `stable`/`edge`/`nightly` names, and a migration guide for existing users. The `index.html` landing page gains a distro toggle so users pick their Ubuntu version before seeing the correct suite name in the setup snippet.

2. **CI smoke gate** — A new step sequence inside the existing `publish` job, running after full repo assembly but before GitHub Pages upload. Spins up `ubuntu:24.04` and `ubuntu:26.04` Docker containers, points them at the locally assembled repo via a `file://` APT source, runs `apt install podman-suite` + `podman info`. Both containers must exit 0 or the publish is aborted.

In scope: `docs/apt-repository.md`, `scripts/ci_publish.sh` (index.html generation + smoke steps), `.github/workflows/build-packages.yml` (smoke gate in publish job).
Out of scope: removing legacy bare-suite aliases (REPO-09, future milestone), codename-aliased suites (REPO-10), any packaging or CI matrix changes (Phase 21 complete).

</domain>

<decisions>
## Implementation Decisions

User directive: "Apply best practices, don't overengineer" — all four gray areas resolved by Claude using established patterns from prior phases.

### DEB822 docs structure (MIGR-01, MIGR-03)

- **D-01:** Update `docs/apt-repository.md` in-place. Do NOT create separate per-distro doc files — one doc, clear per-distro subsections. Structure: intro → per-distro setup (Ubuntu 24.04 / Ubuntu 26.04 as parallel subsections, each with its own DEB822 block using the correct suite name) → track selection → individual packages table → deprecation notice → troubleshooting. Existing troubleshooting content stays.
- **D-02:** Suite names in docs: Ubuntu 24.04 → `stable-2404` / `edge-2404` / `nightly-2404`; Ubuntu 26.04 → `stable-2604` / `edge-2604` / `nightly-2604`. The bare names (`stable`, `edge`, `nightly`) are mentioned only in the deprecation section — do not use them as the primary setup path.
- **D-03:** Migration section (MIGR-03): existing users who have `Suites: stable` (or edge/nightly) in their `.sources` file need to change to `Suites: stable-2404` (for 24.04 users) or `stable-2604` (for 26.04 users). Provide the exact sed one-liner or the new `.sources` block to paste. Document that bare suites continue to serve 24.04 packages during the deprecation window.
- **D-04:** Deprecation timeline wording: "Deprecated in v3.0 (June 2026). Bare suite names will be removed in a future v3.1 release. Monitor the changelog or watch the GitHub repository for the removal notice." No hard date — REPO-09 is the future milestone that removes them.
- **D-05:** The existing "Important Notes" section at the bottom of `docs/apt-repository.md` gets a prominent deprecation callout at the top instead, so existing users see it first. Update the note about package suffix from `~podman1` to `~ubuntu{24.04,26.04}.podman1` (per Phase 19).
- **D-06:** GPG key setup is unchanged: single key, same URL, same `Signed-By` path — document once, not per-distro (ROADMAP success criterion 4).

### index.html distro UX (MIGR-02)

- **D-07:** Add a distro toggle above the track tabs: two buttons ("Ubuntu 24.04" / "Ubuntu 26.04"). Default selection: Ubuntu 24.04. When a distro button is active, the DEB822 snippet inside each track tab updates to show the distro-qualified suite name (e.g., `Suites: stable-2404` vs `Suites: stable-2604`). JS extends the existing `showTab()` pattern with a `setDistro(ver)` function that swaps visible snippets.
- **D-08:** Implementation lives in `scripts/ci_publish.sh` heredoc. Keep the existing tab-group CSS, adding `.distro-btn` style (similar to `.tab-btn`). Each track tab contains two `<span>` or `<div>` blocks with the 24.04 and 26.04 snippet — JS shows/hides based on active distro.
- **D-09:** Add a brief deprecation callout below the setup section on index.html: one line noting that `stable`/`edge`/`nightly` bare names are deprecated with a link to the docs migration section.
- **D-10:** The "Available Suites" table at the bottom of index.html already iterates `available_suites[]` and skips empty suites (D-18 from Phase 20 carries forward unchanged).

### Deprecation timeline (MIGR-03)

- **D-11:** Wording locked: "deprecated in v3.0, removal in a future v3.1 release — no fixed date, watch the changelog." Document in both `docs/apt-repository.md` and `index.html`. The reprepro `Description:` deprecation note (Phase 20 D-04) already matches this framing.
- **D-12:** The deprecation notice in docs gets a `> **Note:**` blockquote so it is visually distinct from the setup instructions.

### CI smoke gate (MIGR-04)

- **D-13:** Placement: new step sequence inside the `publish` job, after Step 4 (Acquire-By-Hash + re-sign) and before Step 5 (GitHub Pages upload). This tests the actual signed artifact that would be published — no staging environment needed.
- **D-14:** Container mechanism: `docker run` on the GitHub Actions runner (Docker is pre-installed on `ubuntu-latest`). Two sequential containers: `ubuntu:24.04` and `ubuntu:26.04`. Each gets:
  - The assembled `OUTPUT_DIR` bind-mounted at `/opt/podman-repo`
  - A `file:///opt/podman-repo` APT source with `[trusted=yes]` to bypass GPG for the local test (the CI key already signs the repo; this is a CI-internal test, not a production source)
  - Suite targeting: test `<track>-2404` in the 24.04 container and `<track>-2604` in the 26.04 container (track from the CI matrix TRACK variable)
- **D-15:** Commands inside each container:
  ```bash
  apt-get update -qq
  apt-get install -y -q podman-suite
  podman info --log-level=error
  ```
  `podman info` must exit 0. Container runs with `--privileged` to allow fuse-overlayfs and seccomp to initialize cleanly.
- **D-16:** If either container's smoke test fails, the workflow fails at that step. The GitHub Pages upload step does not run. The failure message names which distro failed and at which command.
- **D-17:** No arch-specific smoke containers — amd64 is sufficient for installability verification (arm64 build correctness is validated by the build matrix cells themselves).
- **D-18:** The smoke test runs on every publish (stable, edge, nightly), not just the first. This ensures regressions are caught on every push.

### Claude's Discretion
- Exact CSS for the distro toggle buttons in index.html (style to match existing `.tab-btn` or simpler inline style)
- Whether the distro toggle state persists across page reloads (localStorage or not — either is fine; default is ephemeral)
- Exact wording of the per-distro section headers in `docs/apt-repository.md`
- Whether to extract smoke test logic into a helper function/script or keep it inline in the publish job steps

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` — Phase 22 goal + 4 success criteria (per-distro DEB822 blocks; index.html per-distro; deprecation timeline; CI smoke gate that gates publish)
- `.planning/REQUIREMENTS.md` — MIGR-01/02/03/04 definitions; REPO-09 (remove bare aliases) is future, NOT in scope; Out of Scope table

### Prior phase decisions this phase builds on
- `.planning/phases/20-repository-restructure-migration-aliases/20-CONTEXT.md` — D-04 (Description deprecation note), D-18 (index.html minimal suite loop from Phase 20, full per-distro instructions deferred to Phase 22), D-12 (24.04 publish also feeds bare alias suites)
- `.planning/PROJECT.md` — v3.0 milestone context, Key Decisions table

### Code this phase modifies
- `docs/apt-repository.md` — current single-distro setup instructions (uses DEB822 format already; references bare `stable`/`edge` suites; missing per-distro sections, migration notice, deprecation timeline)
- `scripts/ci_publish.sh` — index.html generation (Step 5, heredoc at line ~472); smoke gate steps to add after by-hash/re-sign (Step 4) and before upload (Step 6)
- `.github/workflows/build-packages.yml` — publish job; TRACK variable already set; Docker available; smoke steps wire in here or in ci_publish.sh called from here

### Code patterns to follow
- `.planning/codebase/CONVENTIONS.md` — updated 2026-06-07; script header, toolpath bootstrap, error handling patterns, comment style
- `.planning/codebase/TESTING.md` — updated 2026-06-07; test patterns including the `assert_*` skeleton (new smoke test script for tests/ should follow this)

No external specs or ADRs — requirements fully captured above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/ci_publish.sh` Step 5 heredoc: existing tab-group CSS (`.tab-btn`, `.tab-content`, `showTab()` JS function) — extend with distro toggle buttons and `setDistro()` without replacing
- `.github/workflows/build-packages.yml` publish job: `TRACK` env var already set from matrix; `OUTPUT_DIR` already holds assembled repo at the point where smoke steps run
- Docker pre-installed on `ubuntu-latest` runners: `docker run` is available, no setup needed

### Established Patterns
- `[trusted=yes]` APT option: standard pattern for testing from locally-assembled repos in CI where GPG round-trip would be overengineering
- `--privileged` docker flag: used by the build matrix cells (`ubuntu:26.04` container with `--privileged`-equivalent for fuse/overlay); appropriate for smoke test containers too
- `set -euo pipefail` + ERR trap: applies to any new scripts; inline shell steps in GA use `set -e` implicitly (each step fails on non-zero)

### Integration Points
- Smoke gate in publish job inserts between the existing by-hash/re-sign step and the `actions/upload-pages-artifact` step — no other job dependencies change
- index.html is generated entirely in `ci_publish.sh` Step 5; all changes live there
- `TRACK` variable (set at top of `ci_publish.sh` from arg $1) drives which distro suite names appear in the smoke test: `${TRACK}-2404` and `${TRACK}-2604`

</code_context>

<specifics>
## Specific Ideas

- `docs/apt-repository.md` already has a Quick Start section using DEB822 format — keep the `sources.list.d/podman-ubuntu.sources` filename convention, just update the `Suites:` line per-distro
- index.html distro toggle default is Ubuntu 24.04 (the majority of existing users)
- Smoke test failure message should name the failing distro explicitly: `echo "SMOKE FAIL: ubuntu:24.04 — podman info returned exit $?" >&2`

</specifics>

<deferred>
## Deferred Ideas

- Removing legacy bare-suite aliases after the deprecation window — tracked as future requirement REPO-09
- Codename-aliased suites (`noble`/`resolute`) for `$VERSION_CODENAME` auto-detect — tracked as future requirement REPO-10
- Ubuntu 25.x/26.10 interim release support — explicitly out of scope (LTS-only project target)
- ARM64 smoke containers — explicitly deferred (D-17); amd64 is sufficient for installability proof; arm64 build correctness verified by build matrix

</deferred>

---

*Phase: 22-Migration Docs & Installability Smoke Tests*
*Context gathered: 2026-06-07*
