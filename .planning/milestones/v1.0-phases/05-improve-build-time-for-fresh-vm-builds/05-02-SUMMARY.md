---
phase: 05-improve-build-time-for-fresh-vm-builds
plan: 02
status: completed
completion_date: 2026-03-03
requirements:
  - PERF-03
---

# Summary: Go Compiler Optimization Flags

## What was built

Added Go compiler optimization flags to all remaining Go-based build scripts:
- `scripts/build_buildah.sh`
- `scripts/build_skopeo.sh`
- `scripts/build_runc.sh`
- `scripts/build_go-md2man.sh`
- `scripts/build_conmon.sh`

## Changes made

Each script was updated with:

1. **Go optimization section** before the "Building" step:
   ```bash
   step_start "Configuring Go optimization"
   # Disable GC during compilation for speed (uses more RAM but ~30% faster)
   export GOGC="${GOGC_BUILD:-off}"
   step_done
   ```

2. **Updated make command** with GCFLAGS and LDFLAGS:
   - build_buildah.sh: Added `GCFLAGS="${GO_GCFLAGS}" LDFLAGS="${GO_LDFLAGS}"`
   - build_skopeo.sh: Added `GCFLAGS="${GO_GCFLAGS}" LDFLAGS="${GO_LDFLAGS}"`
   - build_runc.sh: Added `GCFLAGS="${GO_GCFLAGS}" LDFLAGS="${GO_LDFLAGS}"`
   - build_go-md2man.sh: Added `GCFLAGS="${GO_GCFLAGS}" LDFLAGS="${GO_LDFLAGS}"`
   - build_conmon.sh: Added `GCFLAGS="${GO_GCFLAGS}" LDFLAGS="${GO_LDFLAGS}"`

## Technical approach

The optimization flags reference variables defined in `config.sh`:
- `GO_GCFLAGS="-c=16"` - Parallel compilation within Go compiler (~25% faster)
- `GO_LDFLAGS="-s -w"` - Strip debug symbols for smaller binaries
- `GOGC_BUILD="off"` - Disable Go GC during compilation (~30% faster, uses ~2.5x RAM)

## Verification

All 5 scripts verified:
- Bash syntax check: Passed
- GOGC export present: Verified
- GCFLAGS in make command: Verified
- LDFLAGS in make command: Verified

## Requirements satisfied

- **PERF-03**: Go builds use GOGC=off, gcflags='-c=16', and ldflags='-s -w' for faster compilation

## Deviations

None. Implementation matches plan exactly.
