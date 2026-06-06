# Codebase Concerns

**Analysis Date:** 2026-03-02
**Last Updated:** 2026-03-02

## Summary

| Status | Count |
|--------|-------|
| ✅ Fixed | 4 |
| 🔶 Open | 13 |

**Fixed in this session:**
- Git Protocol Hardcoding (quick-3)
- Redundant Dependency Installation (quick-4)
- Double Path Removal in Uninstall (quick-4)
- Build Directory Accumulation (quick-4)

## Tech Debt

**Version Management Inconsistency:**
- Issue: Version configurations are commented out and inconsistent across components in `config.sh`
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/config.sh` lines 47-65, 66-122
- Impact: Difficult to track which versions are actually being used, maintenance overhead when updating
- Fix approach: Create a central version management file or use environment variables consistently

**Git Tag Sorting Algorithm:**
- Issue: Complex git tag sorting logic in `functions.sh` has known edge cases (comment on line 42)
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/functions.sh` lines 37-57
- Impact: May select incorrect latest tags, potentially using older versions
- Fix approach: Use a proper version comparison library or simplify with `git describe --tags`

**Redundant Dependency Installation:** ✅ FIXED (quick-4, commit 0dbf687)
- Issue: `install_dependencies.sh` is called twice in `setup.sh`
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/setup.sh` lines 40 and 46
- Impact: Unnecessary apt operations, slows down installation
- Fix approach: ~~Remove duplicate call or combine dependency installation~~ **Done: Removed duplicate call**

## Known Bugs

**Git Protocol Hardcoding:** ✅ VERIFIED (quick-3, commit b689cce)
- Issue: Hardcoded "git://" protocol in one script may cause HTTPS 504 errors
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/scripts/build_pasta.sh`
- Status: Correctly uses `git://passt.top/passt` to avoid HTTPS 504 errors
- ~~Trigger: When git HTTPS servers return 504 errors~~ **Resolved: git:// protocol in use**

**Double Path Removal in Uninstall:** ✅ FIXED (quick-4, commit ef15792)
- Issue: Multiple `rm -f /usr/local/usr/local/...` commands in uninstall script
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/uninstall.sh` lines 70-84
- Symptoms: Incorrect paths, may fail to remove files
- Fix approach: ~~Use correct single paths~~ **Done: Corrected all double paths**

**Build Directory Accumulation:** ✅ FIXED (quick-4, commit dcf0cc1)
- Issue: Build directory accumulates large downloaded files without cleanup
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/build/`
- Symptoms: ~173MB of Go tarball, protoc zip, rustup-init taking disk space
- Fix approach: ~~Add cleanup function to remove downloaded archives after successful builds~~ **Done: Added `cleanup_build_artifacts()` function**

## Security Considerations

**Overly Broad File Removals:**
- Risk: `remove_if_user_installed()` uses `dpkg --search` which might miss files
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/functions.sh` lines 158-164
- Current mitigation: Limited scope, only removes files known to be user-installed
- Recommendations: Add logging to track which files are being removed, consider safer removal patterns

**Insecure Path Handling:**
- Risk: Multiple scripts use unvalidated user input for paths
- Files: Throughout `scripts/` directory
- Current mitigation: Most paths are hardcoded relative to toolpath
- Recommendations: Add input validation for user-provided paths

**Installation Script Privileges:**
- Risk: Script installs to system-wide directories (`/usr/local/bin`, `/opt/`)
- Files: All installation scripts
- Current mitigation: Run by user who should have sudo access
- Recommendations: Document required permissions, consider user-specific installations

## Performance Bottlenecks

**Sequential Component Building:**
- Problem: Components built one by one in `setup.sh`
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/setup.sh` lines 54-94
- Cause: No parallelization, dependencies prevent concurrent builds
- Improvement path: Identify independent components to build in parallel

**Network Dependencies:**
- Problem: Multiple HTTP calls to GitHub APIs during runtime
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/functions.sh` lines 62-75
- Cause: Version auto-detection requires network
- Improvement path: Cache version information, allow offline mode with cached versions

**Large Download Caching:** ✅ FIXED (quick-4, commit dcf0cc1)
- Problem: Large downloads (Go tarball: 60MB+) are not cleaned up
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/build/`
- Cause: Download cache persists after successful builds
- Improvement path: ~~Implement cleanup of successful downloads~~ **Done: Added `cleanup_build_artifacts()` function**

## Fragile Areas

**Architecture Detection Logic:**
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/functions.sh` lines 15-32
- Why fragile: Limited to x86_64 and aarch64, newer architectures may fail
- Safe modification: Add clear error messages, support more architectures
- Test coverage: No automated testing of architecture detection

**Environment Variable Dependencies:**
- Files: Multiple scripts rely on `toolpath`, `ARCH`, etc.
- Why fragile: Missing or incorrect env vars can cause failures
- Safe modification: Add validation and fallbacks
- Test coverage: No validation checks for required env vars

**Git Operations Without Error Handling:**
- Files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/functions.sh` lines 77-118
- Why fragile: Network issues or invalid repos cause failures
- Safe modification: Add retry logic and better error messages
- Test coverage: No mocking of git operations in tests

## Scaling Limits

**Filesystem Space Requirements:** ✅ IMPROVED (quick-4)
- Current capacity: ~173MB+ of downloads + build directories
- Limit: Limited by available disk space during build
- Scaling path: ~~Implement cleanup of artifacts after successful builds~~ **Done: `cleanup_build_artifacts()` now removes archives after builds**

**Build Time:**
- Current capacity: ~30+ minutes for full Podman build
- Limit: Network speed, CPU performance
- Scaling path: Parallel builds, binary caching, pre-built components

## Dependencies at Risk

**External API Dependencies:**
- Package: GitHub API
- Risk: Rate limits, API changes, downtime
- Impact: Version auto-detection fails
- Migration plan: Implement local caching, allow manual version specification

**System Package Dependencies:**
- Package: apt-get packages
- Risk: Debian package availability changes
- Impact: Build prerequisites may be unavailable
- Migration plan: Package essential dependencies, provide fallback build methods

## Missing Critical Features

**Verification of Installed Components:**
- Problem: No post-installation verification
- Blocks: Users don't know if installation succeeded completely
- Priority: High - Should verify all binaries work and have correct versions

**Rollback Mechanism:**
- Problem: No easy way to rollback to previous state
- Blocks: Difficult to recover from failed installations
- Priority: Medium - Provide backup/restore functionality

## Test Coverage Gaps

**Integration Testing:**
- What's not tested: End-to-end installation process
- Files: All installation scripts
- Risk: Changes may break the full installation flow
- Priority: High - Need automated test of complete install

**Error Handling Testing:**
- What's not tested: Network failures, disk space issues
- Files: Error handling in functions.sh
- Risk: Failure scenarios not properly handled
- Priority: Medium - Test various failure modes

**Build Script Testing:**
- What's not tested: Individual component build scripts
- Files: All scripts/ directory
- Risk: Build failures may go undetected
- Priority: Medium - Test each build script independently

---

*Concerns audit: 2026-03-02*