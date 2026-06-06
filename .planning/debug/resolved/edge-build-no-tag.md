---
status: resolved
trigger: "Edge builds fail with 'ERROR: No version tag found for component: podman' when running package_all.sh. Stable builds work fine."
created: 2026-03-06T00:00:00Z
updated: 2026-05-15T17:15:23Z
---

## Current Focus

hypothesis: CONFIRMED and FIXED - build phase discovers tags via git_checkout/get_latest_tag() but never writes them back; packaging phase re-reads config.sh which defaults empty TAG vars
test: Fix applied to package_all.sh; shell syntax, nightly extraction tests, and edge tag resolver smoke test passed locally
expecting: Edge builds should now auto-detect tags from already-cloned build repos
next_action: User verifies by running edge build in GitHub Actions

## Symptoms

expected: Edge builds should auto-detect latest git tags for each component and build packages successfully
actual: Both amd64 and arm64 edge builds fail immediately with "ERROR: No version tag found for component: podman"
errors: "ERROR: No version tag found for component: podman — Ensure the corresponding *_TAG variable is set in config.sh or environment."
reproduction: Run the edge build workflow in GitHub Actions (edge track, no versions-stable.env)
started: Current CI runs. Stable track works fine with pinned TAG values.

## Eliminated

## Evidence

- timestamp: 2026-03-06T00:01:00Z
  checked: config.sh lines 145-196 - all TAG variables
  found: All TAG vars use `${VAR:-}` pattern, defaulting to empty when not set in environment
  implication: For edge builds (no versions-stable.env), all TAG vars are empty strings

- timestamp: 2026-03-06T00:02:00Z
  checked: functions.sh git_checkout() lines 111-132
  found: When called with empty tag, git_checkout fetches all tags and calls get_latest_tag() to checkout latest. Sets GIT_CHECKED_OUT_TAG but does NOT update the *_TAG config variable
  implication: Build phase auto-detects tags correctly, but information is lost after build step

- timestamp: 2026-03-06T00:03:00Z
  checked: build-packages.yml workflow - packaging step (lines 111-115 and 185-189)
  found: Packaging step runs `./scripts/package_all.sh` as a SEPARATE workflow step from building. Only DESTDIR and PATH are passed. No TAG variables.
  implication: Packaging step has no access to tags discovered during build

- timestamp: 2026-03-06T00:04:00Z
  checked: package_all.sh lines 124-137 (COMPONENT_TAGS map)
  found: COMPONENT_TAGS is populated at source-time from config.sh variables. For edge builds, all are empty. Line 161 validation fails immediately on first component (podman).
  implication: Confirmed root cause - tag discovery happens in build phase but is lost before packaging phase

- timestamp: 2026-03-06T00:05:00Z
  checked: All build scripts (git_clone_update calls)
  found: Component-to-directory mapping: most are 1:1. Exceptions: pasta->passt (but pasta uses date-based version, already handled), container-configs->container-libs
  implication: resolve_tag_from_repo needs COMPONENT_BUILD_DIRS override map for container-configs

## Resolution

root_cause: Two-phase disconnect between build and packaging. Build scripts (setup.sh -> build_*.sh) discover latest tags via git_checkout/get_latest_tag() at build time, but this information is never written anywhere persistent. The packaging step (package_all.sh) runs as a separate workflow step, re-sources config.sh which defaults all *_TAG vars to empty, then fails validation because no tags are set. Stable builds work because versions-stable.env provides explicit TAG values via sudo env.
fix: Added resolve_tag_from_repo() function to package_all.sh. When a TAG variable is empty (edge build), the function reads the currently checked-out git tag from the component's build repo in BUILD_ROOT using `git describe --tags --exact-match HEAD`. This bridges the gap between the build phase (which already cloned and checked out the correct tag) and the packaging phase. Also includes COMPONENT_BUILD_DIRS map for the one case where component name differs from directory name (container-configs -> container-libs).
verification: Locally verified on 2026-05-15 with `bash -n scripts/package_all.sh functions.sh config.sh .github/workflows/build-packages.yml`, `bash tests/test_extract_version_nightly.sh` (9 passed, 0 failed; dpkg sort skipped because dpkg is unavailable on macOS), and a temporary git repo smoke test proving `resolve_tag_from_repo podman` returns the checked-out tag when config TAG variables are empty. Full GitHub Actions edge build was not rerun in this session.
files_changed:
  - scripts/package_all.sh
