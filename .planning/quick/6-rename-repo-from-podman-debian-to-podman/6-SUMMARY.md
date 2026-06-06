---
phase: quick-6
plan: 01
subsystem: branding
tags: [rename, branding, documentation]
key-files:
  modified:
    - config/containers.conf
    - scripts/repo_manage.sh
    - scripts/ci_publish.sh
    - scripts/package_all.sh
    - packaging/nfpm/*.yaml (13 files)
    - packaging/repo/conf/distributions
    - README.md
    - docs/apt-repository.md
    - .planning/REQUIREMENTS.md
    - .planning/STATE.md
    - .planning/milestones/v1.2-REQUIREMENTS.md
decisions:
  - Also updated packaging/nfpm/podman.yaml which was not in plan file list but contained podman-debian references
metrics:
  duration: 1min
  completed: "2026-03-08T18:51:50Z"
  tasks_completed: 2
  tasks_total: 2
---

# Quick Task 6: Rename podman-debian to podman-ubuntu Summary

Renamed all branding references from podman-debian/Podman Debian to podman-ubuntu/Podman Ubuntu across the entire codebase.

## Tasks Completed

### Task 1: Rename in source files
- **Commit:** d1a9669
- **Files:** 19 files (config, scripts, packaging configs, repo distributions)
- Replaced `podman-debian` with `podman-ubuntu` (GPG filenames, vendor fields, Origin, URLs)
- Replaced `Podman Debian` with `Podman Ubuntu` (maintainer names, Label, banner text)
- DEBIAN_FRONTEND env var correctly left untouched

### Task 2: Rename in documentation and planning files
- **Commit:** 0fa5450
- **Files:** README.md, docs/apt-repository.md (planning files updated but gitignored)
- Updated project title, git clone URLs, APT repo URLs, GPG key download paths
- All installation instructions now reference podman-ubuntu

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing] Added packaging/nfpm/podman.yaml to replacement set**
- **Found during:** Task 1
- **Issue:** podman.yaml was not listed in the plan's file list but contained `podman-debian` vendor and maintainer references
- **Fix:** Included it in the sed replacement pass
- **Commit:** d1a9669

**2. [Rule 3 - Blocking] Planning files are gitignored**
- **Found during:** Task 2
- **Issue:** .planning/ directory is in .gitignore, so REQUIREMENTS.md, STATE.md, and milestones files cannot be committed
- **Fix:** Updated the files on disk but only committed README.md and docs/apt-repository.md
- **Commit:** 0fa5450

## Verification

- Zero matches for `podman-debian` across all `*.md`, `*.sh`, `*.yaml`, `*.conf` files
- Zero matches for `Podman Debian` across all source and packaging files
- `podman-ubuntu.gpg` filename consistent between repo_manage.sh and ci_publish.sh
- DEBIAN_FRONTEND references preserved in setup.sh, uninstall.sh, and workflow files

## Self-Check: PASSED
