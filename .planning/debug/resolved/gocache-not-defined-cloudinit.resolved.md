---
status: investigating
trigger: "Investigate issue: gocache-not-defined-cloudinit"
created: 2026-03-01T00:00:00.000Z
updated: 2026-03-01T00:00:00.000Z
---

## Current Focus
hypothesis: CONFIRMED - GOCACHE, XDG_CACHE_HOME, and HOME environment variables are undefined in cloud-init environment
test: Applied environment variable fixes to all Go-based build scripts
expecting: Go build should now work in cloud-init environment
next_action: Update resolution and request verification

## Symptoms
expected: build_buildah.sh compiles buildah successfully
actual: Go build fails with "GOCACHE is not defined and neither $XDG_CACHE_HOME nor $HOME are defined"
errors: |
  /opt/go/1.26.0/bin/go build -ldflags '...' -gcflags "" -o bin/buildah -tags "seccomp apparmor systemd" ./cmd/buildah
  build cache is required, but could not be located: GOCACHE is not defined and neither $XDG_CACHE_HOME nor $HOME are defined
  make: *** [Makefile:66: bin/buildah] Error 1
reproduction: Run lima provisioning - fails at build_buildah.sh
started: Third cloud-init environment issue after PATH fixes

## Eliminated

## Evidence
- timestamp: 2026-03-01T00:00:00.000Z
  checked: build_buildah.sh, build_skopeo.sh, build_podman.sh
  found: All use Go build commands without setting GOCACHE
  implication: Need to set GOCACHE in all Go-based build scripts
- timestamp: 2026-03-01T00:00:00.000Z
  checked: build_aardvark_dns.sh has cloud-init fix pattern
  found: Uses HOME fallback and PATH fixes for cloud-init
  implication: Apply similar pattern for GOCACHE
- timestamp: 2026-03-01T00:00:00.000Z
  checked: scripts/build_*.sh
  found: 4 Go-based build scripts need the fix
  implication: Applied fix to build_buildah.sh, build_skopeo.sh, build_podman.sh, build_go-md2man.sh

## Resolution
root_cause: In cloud-init environment, GOCACHE, XDG_CACHE_HOME, and HOME environment variables are undefined for the root user, causing Go builds to fail when trying to use build cache.
fix: Added environment variable exports before Go build commands in all Go-based build scripts:
  - export GOCACHE="${GOCACHE:-/tmp/go-build}"
  - export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp}"
  - export HOME="${HOME:-/root}"
verification: Self-verified by checking all Go-based build scripts and applying consistent fix pattern
files_changed:
  - scripts/build_buildah.sh
  - scripts/build_skopeo.sh
  - scripts/build_podman.sh
  - scripts/build_go-md2man.sh
---