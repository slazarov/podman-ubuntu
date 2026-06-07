# Phase 22: Migration Docs & Installability Smoke Tests - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-07
**Phase:** 22-migration-docs-installability-smoke-tests
**Areas discussed:** All four gray areas resolved by Claude under user directive

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| DEB822 docs structure | How to restructure docs/apt-repository.md for per-distro DEB822 blocks | ✓ |
| index.html distro UX | How to add distro dimension to the existing track-tab UI | ✓ |
| Deprecation timeline | When bare stable/edge/nightly aliases go away | ✓ |
| Smoke test design | CI placement, artifact source, containers, pass criteria | ✓ |

**User's choice:** "apply best practices, dont overenginee"
**Notes:** Same directive as Phase 20 — Claude makes all calls following established project patterns.

---

## DEB822 Docs Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Update in-place | One doc, per-distro subsections | ✓ |
| Split files | Separate docs per distro | |
| Auto-detect snippet | Single block using `$(lsb_release -rs)` | |

**Claude's call:** Update `docs/apt-repository.md` in-place with Ubuntu 24.04 / Ubuntu 26.04 subsections. No new files — consistent with the project's keep-it-simple convention. Deprecation notice as a visible blockquote at the top. Migration one-liner for existing users.

---

## index.html Distro UX

| Option | Description | Selected |
|--------|-------------|----------|
| Distro toggle + track tabs | Two distro buttons at top, track tabs below; JS swaps suite names | ✓ |
| 6 combined buttons | stable-2404, edge-2404, etc. as individual buttons | |
| Nested tabs | Outer distro tabs, inner track tabs | |

**Claude's call:** Distro toggle (Ubuntu 24.04 default) above existing track tabs. Extends `showTab()` with `setDistro()` — minimal JS delta. Implementation in `ci_publish.sh` heredoc.

---

## Deprecation Timeline

| Option | Description | Selected |
|--------|-------------|----------|
| Specific date | Hard cutoff date (e.g., 2026-12-31) | |
| Tied to v3.1 | Remove when next milestone ships | ✓ |
| No fixed date | "future release, watch changelog" | |

**Claude's call:** "Deprecated in v3.0 (June 2026). Bare suite names will be removed in a future v3.1 release. Monitor the changelog." No hard date — avoids a self-imposed deadline when removal depends on REPO-09 implementation.

---

## Smoke Test Design

| Option | Description | Selected |
|--------|-------------|----------|
| Steps in publish job (after assembly, before upload) | Deterministic, no external deps; tests actual published artifact | ✓ |
| Separate CI job | Cleaner separation, but needs separate artifact download + local repo setup | |
| Staging URL | Tests against real CDN, but requires prior publish | |

**Claude's call:** Steps inside publish job, after by-hash/re-sign, before upload. `docker run ubuntu:24.04` and `docker run ubuntu:26.04` with `file://` APT source (`[trusted=yes]`) mounted from `OUTPUT_DIR`. `apt install podman-suite && podman info --log-level=error` must exit 0 in both. `--privileged` for fuse/seccomp init.

---

## Claude's Discretion

- Exact CSS for distro toggle buttons (follow existing `.tab-btn` style)
- Whether to extract smoke test logic into a helper script or keep it inline
- Exact section header wording in `docs/apt-repository.md`
- localStorage persistence for distro toggle (ephemeral by default)

## Deferred Ideas

- REPO-09: Removing legacy bare-suite aliases — future milestone
- REPO-10: Codename-aliased suites (`noble`/`resolute`) — future milestone
- ARM64 smoke containers — explicitly deferred (amd64 sufficient for installability; arm64 validated by build matrix)
- Ubuntu 25.x/26.10 interim support — out of scope (LTS-only)
