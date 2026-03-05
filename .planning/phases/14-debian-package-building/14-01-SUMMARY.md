---
phase: 14-debian-package-building
plan: 01
subsystem: packaging
tags: [nfpm, destdir, deb, debian-packaging, shell-scripting]

# Dependency graph
requires:
  - phase: 13-man-pages-and-uninstall
    provides: "Complete build system with all 12 components and config/man page installers"
provides:
  - "DESTDIR staging support in all 13 build/install scripts"
  - "13 nFPM YAML package configurations in packaging/nfpm/"
  - "Standardized /usr install prefix across all components"
  - "Updated containers.conf with /usr/bin helper paths"
affects: [14-02, 15-apt-repository-and-signing, 16-ci-cd-pipeline]

# Tech tracking
tech-stack:
  added: [nfpm]
  patterns: [destdir-conditional-install, nfpm-yaml-configs, install-d-for-binaries]

key-files:
  created:
    - packaging/nfpm/podman.yaml
    - packaging/nfpm/crun.yaml
    - packaging/nfpm/conmon.yaml
    - packaging/nfpm/netavark.yaml
    - packaging/nfpm/aardvark-dns.yaml
    - packaging/nfpm/pasta.yaml
    - packaging/nfpm/fuse-overlayfs.yaml
    - packaging/nfpm/catatonit.yaml
    - packaging/nfpm/buildah.yaml
    - packaging/nfpm/skopeo.yaml
    - packaging/nfpm/toolbox.yaml
    - packaging/nfpm/container-configs.yaml
    - packaging/nfpm/suite.yaml
  modified:
    - scripts/build_podman.sh
    - scripts/build_buildah.sh
    - scripts/build_skopeo.sh
    - scripts/build_crun.sh
    - scripts/build_conmon.sh
    - scripts/build_fuse-overlayfs.sh
    - scripts/build_catatonit.sh
    - scripts/build_netavark.sh
    - scripts/build_aardvark_dns.sh
    - scripts/build_pasta.sh
    - scripts/build_toolbox.sh
    - scripts/install_container-configs.sh
    - scripts/install_container-manpages.sh
    - config/containers.conf
    - .gitignore

key-decisions:
  - "Switched conmon from make podman to make install PREFIX=/usr for proper DESTDIR support"
  - "Used nFPM type: tree for glob-based directory inclusion (man pages, systemd units, completions)"
  - "Included only passt and pasta in pasta.yaml base config (avx2 variants handled by orchestrator)"

patterns-established:
  - "DESTDIR conditional: if DESTDIR set, no sudo and stage to DESTDIR tree; else direct-install with sudo"
  - "nFPM env var substitution: ${VERSION}, ${ARCH}, ${DESTDIR} injected at package time"
  - "Conflicts/Replaces/Provides triple: all 10 Ubuntu-conflicting packages declare all three"
  - "version_schema: none in all configs for non-semver version support"

requirements-completed: [PKG-01, PKG-02, PKG-03, PKG-04, PKG-05, PKG-06, PKG-07]

# Metrics
duration: 6min
completed: 2026-03-05
---

# Phase 14 Plan 01: DESTDIR Staging and nFPM Package Configs Summary

**DESTDIR staging in all 13 build/install scripts with 13 nFPM YAML configs for Debian packaging of 12 components plus meta-package**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-05T09:36:51Z
- **Completed:** 2026-03-05T09:43:23Z
- **Tasks:** 2/2
- **Files modified:** 28 (15 modified + 13 created)

## Accomplishments
- Added DESTDIR conditional logic to all 13 build/install scripts -- when DESTDIR is set, files stage to a temporary tree without sudo; when unset, existing direct-install behavior is preserved
- Standardized all install paths from /usr/local to /usr (Debian convention) across all components including containers.conf helper_binaries_dir
- Created 13 nFPM YAML package configurations with correct inter-package dependencies, Conflicts/Replaces/Provides against Ubuntu Noble packages, and conffile declarations for /etc/ config files

## Task Commits

Each task was committed atomically:

1. **Task 1: Add DESTDIR support to all build and install scripts** - `f75f79f` (feat)
2. **Task 2: Create all 13 nFPM YAML package configurations** - `4fc5ae5` (feat)

## Files Created/Modified

### Created (13 nFPM configs)
- `packaging/nfpm/podman.yaml` - podman-podman package with 8 runtime dependencies
- `packaging/nfpm/crun.yaml` - podman-crun OCI runtime package
- `packaging/nfpm/conmon.yaml` - podman-conmon runtime monitor package
- `packaging/nfpm/netavark.yaml` - podman-netavark networking with container-configs dependency
- `packaging/nfpm/aardvark-dns.yaml` - podman-aardvark-dns DNS server package
- `packaging/nfpm/pasta.yaml` - podman-pasta user-mode networking (conflicts: passt)
- `packaging/nfpm/fuse-overlayfs.yaml` - podman-fuse-overlayfs rootless overlay package
- `packaging/nfpm/catatonit.yaml` - podman-catatonit minimal init package
- `packaging/nfpm/buildah.yaml` - podman-buildah image builder with container-configs dependency
- `packaging/nfpm/skopeo.yaml` - podman-skopeo image utility with container-configs dependency
- `packaging/nfpm/toolbox.yaml` - podman-toolbox with podman-podman dependency
- `packaging/nfpm/container-configs.yaml` - 5 conffiles + seccomp.json data file + man pages
- `packaging/nfpm/suite.yaml` - meta-package depending on all 12 components (no files)

### Modified (15 files)
- `scripts/build_podman.sh` - DESTDIR conditional in make install
- `scripts/build_buildah.sh` - DESTDIR + PREFIX=/usr in make install
- `scripts/build_skopeo.sh` - DESTDIR conditional in make install
- `scripts/build_crun.sh` - --prefix=/usr in configure + DESTDIR in make install
- `scripts/build_conmon.sh` - Switched from make podman to make install PREFIX=/usr with DESTDIR
- `scripts/build_fuse-overlayfs.sh` - --prefix=/usr (was /usr/local) + DESTDIR in make install
- `scripts/build_catatonit.sh` - --prefix=/usr in configure + DESTDIR in make install
- `scripts/build_netavark.sh` - install -D replacing raw cp, /usr/bin instead of /usr/local/bin
- `scripts/build_aardvark_dns.sh` - install -D replacing raw cp, /usr/bin instead of /usr/local/bin
- `scripts/build_pasta.sh` - install -D replacing raw cp, /usr/bin, process-kill only in non-DESTDIR branch
- `scripts/build_toolbox.sh` - DESTDIR env var for meson install
- `scripts/install_container-configs.sh` - All destinations prefixed with ${DESTDIR:-}
- `scripts/install_container-manpages.sh` - All destinations prefixed with ${DESTDIR:-}
- `config/containers.conf` - helper_binaries_dir updated to /usr/bin (removed /usr/local)
- `.gitignore` - Added output/ for packaging artifacts

## Decisions Made
- **Conmon install target:** Switched from `make podman` to `make install PREFIX=/usr` because the `podman` target installs to /usr/local/libexec which does not support proper DESTDIR semantics. The `install` target with PREFIX is the standard approach.
- **nFPM tree type for globs:** Used `type: tree` in nFPM contents for directories with many files (man pages, systemd units, completions) rather than enumerating each file. This is cleaner and adapts to upstream changes in file listings.
- **Pasta avx2 variants excluded from base config:** Only passt and pasta binaries included in the nFPM YAML. The orchestrator script (plan 14-02) will handle avx2 variants conditionally since nFPM errors if source files do not exist.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All DESTDIR staging and nFPM configs are ready for the packaging orchestrator (plan 14-02)
- Plan 14-02 will create the version extraction logic and nFPM invocation orchestrator
- The exact file lists in tree-type nFPM entries will be validated during the first real DESTDIR build

## Self-Check: PASSED

- All 13 nFPM YAML files verified present on disk
- Commit f75f79f (Task 1) verified in git log
- Commit 4fc5ae5 (Task 2) verified in git log
- All 13 scripts contain DESTDIR references
- All 13 nFPM configs contain version_schema: none
- container-configs.yaml has 5 type: config entries (seccomp.json excluded)
- No /usr/local references in containers.conf

---
*Phase: 14-debian-package-building*
*Completed: 2026-03-05*
