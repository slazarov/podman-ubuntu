# Phase 14: Debian Package Building - Context

**Gathered:** 2026-03-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Build .deb packages for all 12 Podman components plus a meta-package using nFPM, with DESTDIR staging integrated into existing build scripts. Direct-install behavior preserved when DESTDIR is unset. Packages must declare correct inter-package dependencies and handle conflicts with official Ubuntu packages.

Components: podman, crun, netavark, aardvark-dns, conmon, pasta, fuse-overlayfs, catatonit, buildah, skopeo, toolbox, container-configs (+ podman-suite meta-package).

</domain>

<decisions>
## Implementation Decisions

### DESTDIR Integration
- Modify existing build scripts in-place to add DESTDIR support (no separate packaging layer)
- When DESTDIR is set, files stage to $DESTDIR/usr/...; when unset, direct-install behavior is unchanged
- Replace raw `cp` commands with `install -D -m 0755` for consistent DESTDIR support (netavark, pasta, aardvark-dns, etc.)
- Standardize all install prefixes to /usr (Debian convention) — no more /usr/local in any component
- Drop sudo when DESTDIR is set (staging tree doesn't need root); keep sudo for direct-install mode

### Package Versioning
- Strip `v` prefix from tags (v5.5.2 → 5.5.2), pass through date-based versions (pasta), extract from namespaced tags (container-libs common/v0.67.0 → 0.67.0)
- Append `~podman1` suffix to all versions (e.g., 5.5.2~podman1) — the `~` ensures official Ubuntu packages always upgrade over ours
- Read version from GIT_CHECKED_OUT_TAG after each build script runs, pass to nFPM via environment variable
- container-configs package uses container-libs common/ tag version (e.g., 0.67.0~podman1)

### nFPM Configuration
- nFPM YAML configs live in `packaging/nfpm/` directory at project root (one file per component)
- Version and architecture injected via nFPM's native environment variable substitution (${VERSION}, ${ARCH})
- Single orchestrator script (e.g., scripts/package_all.sh) iterates components, sets vars, invokes nFPM
- Built .deb files output to `output/` directory at project root (gitignored)

### Package Contents & Boundaries
- go-md2man is a build-only tool — no .deb package (keeps the 12-package list clean)
- Man pages bundled with their component package (podman-podman includes podman.1, etc.)
- container-configs: all 6 config files in /etc/containers/ declared as conffiles (preserved on upgrade)
- seccomp.json in /usr/share/containers/ is NOT a conffile (data file, overwritten on upgrade — upstream changes are wanted)
- Conflicts/Replaces/Provides declared only against packages that actually exist in Ubuntu repos (research needed to identify which)

### Claude's Discretion
- Exact nFPM YAML structure and field ordering
- How the packaging orchestrator iterates components and handles errors
- DESTDIR variable naming convention (DESTDIR vs INSTALL_ROOT)
- Meta-package (podman-suite) nFPM config structure
- Order of operations: build all → stage all → package all, or build+stage+package per component

</decisions>

<specifics>
## Specific Ideas

- alvistack (http://download.opensuse.org/repositories/home:/alvistack/xUbuntu_24.04/) uses podman-* prefix pattern — established precedent for this naming convention
- The `~` version suffix is Debian best practice for third-party packages (apt considers `~` lower than nothing, so official packages always win)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GIT_CHECKED_OUT_TAG` variable: already set by git_checkout() in functions.sh — version source for packaging
- `log_component()`: logs component name + version — could be extended to export version for packaging
- `detect_architecture()`: returns amd64/arm64 — maps directly to Debian architecture names
- `run_script()` in setup.sh: component orchestration pattern — packaging orchestrator can follow same pattern

### Established Patterns
- Build scripts follow Clone → Checkout → Build → Install pattern — DESTDIR adds a stage step before install
- `install -m 0644` already used in install_container-configs.sh — consistent with proposed `install -D` approach
- Environment variable overrides (NPROC, SCCACHE_ENABLED, etc.) — DESTDIR fits this pattern naturally
- `set -euo pipefail` + error_handler trap in every script — packaging scripts should follow same convention

### Integration Points
- Each build_*.sh script's install step needs DESTDIR prefix
- setup.sh's run_script() orchestration — packaging step runs after all builds complete
- config.sh's architecture variables — feed directly into nFPM arch field
- .gitignore needs output/ and build staging directories added

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 14-debian-package-building*
*Context gathered: 2026-03-05*
