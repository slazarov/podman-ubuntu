---
status: awaiting_human_verify
trigger: "Fresh comprehensive audit of all CI pipeline files before pushing"
created: 2026-03-05T00:00:00Z
updated: 2026-03-05T00:02:00Z
---

## Current Focus

hypothesis: 9 bugs found and 7 fixed; remaining 2 are known limitations
test: All fixes applied, need CI run to verify
expecting: Pipeline passes packaging step
next_action: User verifies via CI push

## Symptoms

expected: CI pipeline builds all components, packages them with nFPM, publishes to APT repo without errors
actual: Pipeline fails at packaging step. Multiple fixes applied but want comprehensive audit before next push.
errors: Various failures during iteration. Need fresh eyes on all files.
reproduction: Push to trigger GitHub Actions workflow
started: Ongoing CI debugging cycle

## Eliminated

## Evidence

- timestamp: 2026-03-05T00:00:30Z
  checked: All 13 nFPM yaml files cross-referenced with DESTDIR layout and build scripts
  found: BUG-1 CRITICAL - Shared tree directories (man1, bash-completion, fish, zsh) cause all packages to contain all files from all components. dpkg will reject overlapping file ownership.
  implication: Every package with type:tree on shared dirs gets ALL files, causing install conflicts

- timestamp: 2026-03-05T00:00:35Z
  checked: versions-stable.env vs config.sh vs install_go.sh flow
  found: BUG-2 CRITICAL - GOTAG set but GOVERSION missing. config.sh auto-detects GOVERSION, install_go.sh overwrites GOTAG. Stable Go version NOT pinned.
  implication: Go version is always auto-detected even in stable mode

- timestamp: 2026-03-05T00:00:40Z
  checked: versions-stable.env vs config.sh vs install_protoc.sh flow
  found: BUG-3 CRITICAL - PROTOC_TAG set but PROTOC_VERSION missing. Download URL combines stable tag with auto-detected version number causing 404.
  implication: Protoc download fails with version mismatch in URL

- timestamp: 2026-03-05T00:00:45Z
  checked: toolbox.yaml package metadata
  found: BUG-4 HIGH - Package podman-toolbox has conflicts:podman-toolbox (conflicts with itself). Should be conflicts:toolbox.
  implication: dpkg metadata error

- timestamp: 2026-03-05T00:00:50Z
  checked: config.sh sourced by package_all.sh (non-root context)
  found: BUG-5 HIGH - mkdir -p /var/cache/go-build fails as non-root user in packaging step
  implication: package_all.sh crashes sourcing config.sh

- timestamp: 2026-03-05T00:00:55Z
  checked: podman.yaml vs podman make install output
  found: BUG-6 MEDIUM - podman installs man7 pages but podman.yaml did not include man7 tree
  implication: man7 pages not packaged

- timestamp: 2026-03-05T00:01:00Z
  checked: pasta.yaml vs build_pasta.sh install targets
  found: BUG-7 MEDIUM - passt.avx2 and pasta.avx2 conditionally installed but not in nFPM config
  implication: AVX2 optimized binaries not packaged (known limitation, cannot fix without conditional nFPM support)

- timestamp: 2026-03-05T00:01:05Z
  checked: toolbox.yaml vs meson install output
  found: BUG-8 MEDIUM - usr/share/toolbox/ not in toolbox.yaml
  implication: Toolbox profile scripts not packaged

- timestamp: 2026-03-05T00:01:10Z
  checked: zsh completion install paths
  found: BUG-10 HIGH - podman and toolbox zsh completions go to site-functions/ not vendor-completions/
  implication: nFPM would fail looking for wrong directory path

## Resolution

root_cause: Multiple bugs across nFPM configs, versions-stable.env, config.sh
fix: Applied fixes for BUG-1,2,3,4,5,6,8,10. BUG-7 (AVX2) and BUG-9 (network calls) are known limitations.
verification: awaiting CI run
files_changed:
  - packaging/nfpm/podman.yaml
  - packaging/nfpm/crun.yaml
  - packaging/nfpm/buildah.yaml
  - packaging/nfpm/skopeo.yaml
  - packaging/nfpm/toolbox.yaml
  - versions-stable.env
  - config.sh
