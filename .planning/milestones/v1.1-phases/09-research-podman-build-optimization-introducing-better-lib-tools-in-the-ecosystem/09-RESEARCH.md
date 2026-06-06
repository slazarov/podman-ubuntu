# Phase 9: Research Podman Build Optimization + Introducing Better Lib/Tools in the Ecosystem - Research

**Researched:** 2026-03-04
**Domain:** Shell-based build system optimization for Podman and its container ecosystem components
**Confidence:** MEDIUM-HIGH

## Summary

This phase is a research and optimization phase focused on improving the Podman source compilation pipeline. The current project compiles 12 components (podman, buildah, skopeo, conmon, crun, netavark, aardvark-dns, catatonit, fuse-overlayfs, pasta/passt, go-md2man, toolbox) sequentially, using Go, Rust, and C toolchains. Phases 1-8 have already implemented core optimizations (parallel make, shallow clone, GOGC=off, sccache for Rust), but significant further gains are achievable.

The three highest-impact optimization opportunities are: (1) **mold linker** for Rust builds (5-10x faster linking), (2) **ccache** for C builds (crun, fuse-overlayfs, catatonit, pasta -- 30x faster warm-cache rebuilds), and (3) **Go build cache persistence** across components that share dependencies (podman, buildah, skopeo share ~80% of their Go module graph). A fourth area -- **parallel build orchestration** -- could theoretically build independent components simultaneously, but adds shell scripting complexity and is better suited as a v2 feature.

**Primary recommendation:** Implement mold linker for Rust builds and ccache for C builds as opt-in features (matching the existing SCCACHE_ENABLED pattern). Persist GOCACHE and GOMODCACHE across Go component builds. Evaluate conmon-rs as a future replacement for conmon (Podman 6 timeline). Document which components are optional on modern kernels (fuse-overlayfs on kernel >=5.11).

## Standard Stack

### Core Build Tools (Current)

| Tool | Current Version | Purpose | Status |
|------|----------------|---------|--------|
| Go | Auto-detected latest | Go component builds (podman, buildah, skopeo, conmon, go-md2man) | In use |
| Rust/Cargo | Latest stable via rustup | Rust component builds (netavark, aardvark-dns) | In use |
| GCC | System apt package | C component builds (crun, catatonit, fuse-overlayfs, pasta) | In use |
| Make | System apt package | Build orchestration for most components | In use |
| Meson | System apt package | Build system for toolbox | In use |
| sccache | v0.14.0 | Rust compilation caching | Implemented (Phase 8), opt-in |

### Proposed Additions

| Tool | Version | Purpose | Impact | Confidence |
|------|---------|---------|--------|------------|
| mold | v2.40.1+ (apt or binary) | Alternative linker for Rust builds | 5-10x faster linking step | HIGH |
| ccache | v4.12.3 (apt) | C/C++ compilation caching | 30x faster warm-cache C rebuilds | HIGH |
| GOCACHE persistence | N/A (Go built-in) | Persist Go build cache across components | 20x faster Go rebuilds | HIGH |

### Ecosystem Component Assessment

| Component | Language | Still Needed? | Notes |
|-----------|----------|---------------|-------|
| podman | Go | YES | Core tool |
| buildah | Go | YES | Image building |
| skopeo | Go | YES | Image transport |
| conmon | C/Go | YES (for now) | conmon-rs (Rust) planned as default in Podman 6 (~May 2026) |
| crun | C | YES | Default OCI runtime, superior to runc |
| netavark | Rust | YES | Default network stack |
| aardvark-dns | Rust | YES | DNS resolution for containers |
| catatonit | C | YES | Init process for containers and pause containers |
| fuse-overlayfs | C | CONDITIONAL | Not needed on kernel >=5.11 with native overlay support |
| pasta/passt | C | YES | Rootless networking |
| go-md2man | Go | YES | Man page generation (used by podman, buildah build systems) |
| toolbox | Go/Meson | YES | Container development environments |

## Architecture Patterns

### Current Build Pipeline (Sequential)

```
install_dependencies.sh    (apt packages)
    |
install_rust.sh            (Rust toolchain + sccache)
    |
install_protoc.sh          (protobuf compiler)
    |
install_go.sh              (Go toolchain)
    |
build_aardvark_dns.sh      (Rust - needs Rust)
build_buildah.sh           (Go - needs Go)
build_catatonit.sh         (C - needs apt deps)
build_conmon.sh            (C/Go - needs Go + apt)
build_crun.sh              (C - needs apt deps)
build_fuse-overlayfs.sh    (C - needs apt deps)
build_go-md2man.sh         (Go - needs Go)
build_netavark.sh          (Rust - needs Rust)
build_pasta.sh             (C - needs apt deps)
build_podman.sh            (Go - needs Go)
build_skopeo.sh            (Go - needs Go)
build_toolbox.sh           (Go/Meson - needs Go)
```

All 12 component builds currently execute sequentially. No component build depends on another component build's output (they depend only on the toolchain being installed).

### Pattern 1: Build Cache Strategy

**What:** Layer multiple caching tools to cover all three toolchains
**When to use:** Any rebuild scenario (update, retry after failure, upgrade)

```
Toolchain     | Caching Tool | Cache Type    | Expected Speedup
-----------   | ------------ | ------------- | ----------------
Rust (Cargo)  | sccache      | Compilation   | 50-90% (already implemented)
Rust (Cargo)  | mold linker  | Link time     | 5-10x link speed (NEW)
C (GCC)       | ccache       | Compilation   | 30x warm cache (NEW)
Go            | GOCACHE      | Compilation   | 20x warm cache (NEW - persist)
Go            | GOMODCACHE   | Module download| Skip re-download (NEW - persist)
```

**Example - mold for Rust:**
```bash
# In config.sh
export MOLD_ENABLED="${MOLD_ENABLED:-false}"

# In build_netavark.sh / build_aardvark_dns.sh
if [[ "${MOLD_ENABLED:-false}" == "true" ]] && command -v mold &>/dev/null; then
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER="clang"
    export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C link-arg=-fuse-ld=mold"
    # OR for ARM64:
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER="clang"
    export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C link-arg=-fuse-ld=mold"
fi
```

**Example - ccache for C builds:**
```bash
# In config.sh
export CCACHE_ENABLED="${CCACHE_ENABLED:-false}"

# In build_crun.sh, build_catatonit.sh, build_fuse-overlayfs.sh, build_pasta.sh
if [[ "${CCACHE_ENABLED:-false}" == "true" ]] && command -v ccache &>/dev/null; then
    export CC="ccache gcc"
    export CXX="ccache g++"
fi
```

**Example - Go cache persistence:**
```bash
# In config.sh
export GOCACHE="${GOCACHE:-/var/cache/go-build}"
export GOMODCACHE="${GOMODCACHE:-/var/cache/go-mod}"
mkdir -p "${GOCACHE}" "${GOMODCACHE}"
```

### Pattern 2: Conditional Component Builds

**What:** Skip building components that are not needed on the target system
**When to use:** When kernel version or system configuration makes a component unnecessary

```bash
# Example: Skip fuse-overlayfs on kernel >= 5.11
KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
if [[ "$(echo "$KERNEL_VERSION >= 5.11" | bc)" -eq 1 ]]; then
    echo "Kernel $KERNEL_VERSION supports native overlay, skipping fuse-overlayfs"
    SKIP_FUSE_OVERLAYFS=true
fi
```

### Pattern 3: Opt-In Feature Flag Pattern (Established)

The project already uses a clean opt-in pattern via environment variables with sccache. New features should follow this exact pattern:

```bash
# Default: disabled (zero behavior change for existing users)
export FEATURE_ENABLED="${FEATURE_ENABLED:-false}"

# Installation: only when enabled
if [[ "${FEATURE_ENABLED:-false}" == "true" ]]; then
    # install/configure the feature
fi

# Usage: only when enabled AND binary exists
if [[ "${FEATURE_ENABLED:-false}" == "true" ]] && command -v tool &>/dev/null; then
    # use the feature
fi
```

### Anti-Patterns to Avoid

- **Breaking default behavior:** Never enable new optimizations by default. Users must opt in.
- **Hard dependency on optional tools:** Always check `command -v` before using optional tools like mold, ccache.
- **Ignoring architecture differences:** mold and ccache configs differ between amd64 and arm64. Always use arch-aware configuration.
- **Sharing cargo target directories across projects:** Each Rust project (netavark, aardvark-dns) should keep its own target directory to avoid build conflicts.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| C compilation caching | Custom file-hash-based caching | ccache (apt install ccache) | Content-addressable cache with inode optimization, 20+ years of edge case handling |
| Rust compilation caching | Custom cargo target reuse | sccache (already implemented) | Handles compiler version changes, flag changes, platform changes |
| Fast linking | Custom link scripts | mold linker (apt install mold) | Parallelized linking, 5-10x over GNU ld, drop-in replacement |
| Go build caching | Manual GOPATH sharing | GOCACHE/GOMODCACHE env vars | Go toolchain's built-in content-addressed cache, just persist the directory |
| Build parallelization | GNU parallel/xargs wrapper | Keep sequential for now | Shell-level parallelization of builds has tricky error handling, output interleaving, and resource contention. Not worth the complexity for a personal tool |

**Key insight:** Every toolchain (Go, Rust, C) has its own mature caching ecosystem. The project should leverage these existing tools rather than building custom caching logic.

## Common Pitfalls

### Pitfall 1: Shallow Clone + Tag Checkout Incompatibility
**What goes wrong:** `git clone --depth 1` creates a shallow clone with only the default branch tip. The current `git_clone_update` function then tries to `git fetch --tags` and `git checkout $TAG`, which fails because shallow clones don't include tag history.
**Why it happens:** The existing code works around this by doing `git fetch --all` + `git fetch --tags` when the repo already exists, but the initial `--depth 1` clone may not have the desired tag.
**How to avoid:** Use `git clone --depth 1 --branch $TAG $REPO` for the initial clone when a specific tag is known. This clones only the commit at that tag with depth 1.
**Warning signs:** Build failures on first run with "error: pathspec 'vX.Y.Z' did not match any file(s) known to git"

### Pitfall 2: mold + GCC Version Compatibility
**What goes wrong:** Older GCC versions (< 12) don't properly support `-fuse-ld=mold` with full path arguments.
**Why it happens:** GCC's `-fuse-ld` flag handling changed in GCC 12.
**How to avoid:** Use `clang` as the linker driver (it always accepts `-fuse-ld=mold`), or install `clang` alongside mold. On Debian/Ubuntu, `apt install clang` provides this.
**Warning signs:** Link errors mentioning "cannot find -fuse-ld=mold"

### Pitfall 3: ccache Cache Invalidation with Different Compiler Versions
**What goes wrong:** If the system GCC is upgraded between builds, ccache serves stale cache entries compiled with the old version.
**Why it happens:** ccache hashes the compiler binary. If the binary changes (upgrade), all cache entries become misses, but the old entries still take up space.
**How to avoid:** Set `CCACHE_COMPILERCHECK=content` to hash compiler binary content, ensuring cache invalidation on upgrades. Also set a reasonable max cache size.
**Warning signs:** Strange compilation errors after system upgrades

### Pitfall 4: GOCACHE Invalidation Across Go Versions
**What goes wrong:** Go build cache includes the Go compiler version in its hash. When the project auto-detects "latest Go" and a new Go version is released, the entire GOCACHE becomes invalid.
**Why it happens:** This is by design -- Go's cache is content-addressed including the compiler version.
**How to avoid:** Accept this as expected behavior. The cache still provides massive speedups for rebuilds within the same Go version. Document that a Go version upgrade invalidates the cache.
**Warning signs:** First build after Go upgrade is slower than expected (full rebuild)

### Pitfall 5: sccache + mold Interaction
**What goes wrong:** Using sccache (RUSTC_WRAPPER) and mold (via rustflags) together can cause issues if not configured correctly.
**Why it happens:** sccache wraps rustc calls, and the linker flags must be passed through correctly.
**How to avoid:** Set mold via CARGO_TARGET_*_RUSTFLAGS or .cargo/config.toml rather than RUSTFLAGS env var, which can conflict with sccache's wrapping.
**Warning signs:** Link errors when both sccache and mold are enabled

### Pitfall 6: fuse-overlayfs Removal Breaking Existing Installations
**What goes wrong:** If fuse-overlayfs is conditionally skipped on kernel >=5.11, existing containers that were created with fuse-overlayfs storage driver lose access to their storage.
**Why it happens:** Switching storage drivers requires `podman system reset`.
**How to avoid:** Always build fuse-overlayfs by default. Only make it optional with clear documentation. The preflight check already verifies FUSE support.
**Warning signs:** "overlay: mount failed" errors after upgrade

## Code Examples

### Example 1: mold Installation (Following sccache Pattern)

```bash
# In config.sh - add after SCCACHE settings
export MOLD_ENABLED="${MOLD_ENABLED:-false}"

# In install_dependencies.sh - add mold + clang when enabled
if [[ "${MOLD_ENABLED:-false}" == "true" ]]; then
    apt-get install -y mold clang
fi
```

### Example 2: mold Integration in Rust Build Scripts

```bash
# In build_netavark.sh / build_aardvark_dns.sh
# Add after sccache configuration block
if [[ "${MOLD_ENABLED:-false}" == "true" ]] && command -v mold &>/dev/null; then
    # Create project-level cargo config for mold
    mkdir -p .cargo
    cat > .cargo/config.toml << 'TOML'
[target.'cfg(target_os = "linux")']
rustflags = ["-C", "link-arg=-fuse-ld=mold"]
TOML
    echo "  mold linker enabled for Rust compilation"
fi
```

### Example 3: ccache for C Autotools Builds

```bash
# In config.sh
export CCACHE_ENABLED="${CCACHE_ENABLED:-false}"
export CCACHE_DIR="${CCACHE_DIR:-/var/cache/ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-2G}"

# In install_dependencies.sh
if [[ "${CCACHE_ENABLED:-false}" == "true" ]]; then
    apt-get install -y ccache
    mkdir -p "${CCACHE_DIR}"
fi

# In build_crun.sh (before ./configure)
if [[ "${CCACHE_ENABLED:-false}" == "true" ]] && command -v ccache &>/dev/null; then
    export CC="ccache gcc"
    echo "  ccache enabled for C compilation"
fi
```

### Example 4: Go Cache Persistence

```bash
# In config.sh - add to Go Build Optimization section
# Persist Go build cache across component builds (20x faster rebuilds)
export GOCACHE="${GOCACHE:-/var/cache/go-build}"
export GOMODCACHE="${GOMODCACHE:-/var/cache/go-mod}"

# Create cache directories
mkdir -p "${GOCACHE}" "${GOMODCACHE}"
```

### Example 5: Optimized git_clone_update with Tag-Aware Shallow Clone

```bash
git_clone_update() {
    local lrepository="$1"
    local lfolder="$2"
    local ltag="${3:-}"  # Optional: tag for shallow clone

    if [ -d "${lfolder}" ] && [ -d "${lfolder}/.git" ]; then
        cd "${lfolder}"
        git fetch --all
        git fetch --tags
    else
        if [[ "${SHALLOW_CLONE:-true}" == "true" ]] && [[ -n "${ltag}" ]]; then
            # Clone specific tag with depth 1 (most efficient)
            git clone --depth 1 --branch "${ltag}" "${lrepository}" "${lfolder}"
        elif [[ "${SHALLOW_CLONE:-true}" == "true" ]]; then
            git clone --depth 1 "${lrepository}" "${lfolder}"
        else
            git clone "${lrepository}" "${lfolder}"
        fi
    fi
}
```

### Example 6: Uninstall Additions for New Tools

```bash
# In uninstall.sh - add cleanup for new cache directories
safe_rm_dir "/var/cache/ccache" "ccache cache"
safe_rm_dir "/var/cache/go-build" "Go build cache"
safe_rm_dir "/var/cache/go-mod" "Go module cache"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| GNU ld for Rust linking | mold linker (5-10x) | mold v2.0+ (2023) | Link step drops from seconds to milliseconds |
| No C compilation caching | ccache v4.x with inode cache | ccache 4.7+ (2023) | C rebuilds 30x faster warm cache |
| GOCACHE in /tmp (ephemeral) | Persistent GOCACHE in /var/cache | Go 1.10+ (always available) | Go rebuilds 20x faster |
| conmon (C) | conmon-rs (Rust) | Expected Podman 6 default (~May 2026) | Not yet actionable -- monitor |
| fuse-overlayfs (required) | Native overlay (kernel >=5.11) | Linux 5.11 (2021) | Can skip building fuse-overlayfs |
| CNI networking | netavark (already done) | Podman 5.0 (2024) | Already implemented |
| runc | crun (already done) | Project decision (Phase 6) | Already implemented |
| slirp4netns | pasta (already done) | Project decision (Phase 6) | Already implemented |

**Deprecated/outdated:**
- **conmon (C version):** Still actively maintained but conmon-rs is the planned successor. Not yet ready for production use with Podman -- target Podman 6 (May 2026).
- **fuse-overlayfs on kernel >=5.11:** Still useful for some edge cases (UID mapping experiments), but native overlay is preferred. Should remain as optional build target.

## Build Dependency Graph Analysis

### Current Build Order vs Optimal Build Order

**Current:** Strictly sequential (12 components, one after another)

**Optimal (if parallelized):** Three independent groups after toolchain setup:

```
Group 1: C components     Group 2: Rust components    Group 3: Go components
  - crun                    - netavark                  - go-md2man
  - catatonit               - aardvark-dns              - conmon
  - fuse-overlayfs                                      - buildah
  - pasta                                               - skopeo
                                                        - podman
                                                        - toolbox
```

**Theoretical speedup:** If the longest group takes T minutes, parallel builds complete in T instead of 3T. In practice, Go components dominate build time, so the gain would be ~30-40% (C and Rust components finish while Go builds are still running).

**Recommendation:** Document this as a future optimization. The shell scripting complexity for parallel builds with proper error handling, output interleaving, and resource contention is high. Not recommended for a personal tool at this time.

### Component Build Times (Estimated Relative)

| Component | Language | Estimated Build Time | % of Total |
|-----------|----------|---------------------|------------|
| podman | Go | HIGH | ~20% |
| buildah | Go | HIGH | ~15% |
| skopeo | Go | MEDIUM | ~10% |
| netavark | Rust | MEDIUM | ~10% |
| aardvark-dns | Rust | MEDIUM | ~8% |
| crun | C | LOW-MEDIUM | ~7% |
| conmon | C/Go | LOW | ~5% |
| toolbox | Go/Meson | MEDIUM | ~8% |
| pasta | C | LOW | ~5% |
| fuse-overlayfs | C | LOW | ~4% |
| catatonit | C | LOW | ~3% |
| go-md2man | Go | LOW | ~5% |

Go components account for ~63% of total build time, Rust for ~18%, C for ~19%.

## Open Questions

1. **conmon-rs adoption timeline**
   - What we know: conmon-rs is under active development. Podman 6 (estimated May 2026) is planned to make it the default.
   - What's unclear: Whether conmon-rs builds cleanly on Debian/Ubuntu without Red Hat-specific dependencies. Whether it requires additional build dependencies (capnproto, protobuf-compiler).
   - Recommendation: Monitor the conmon-rs repository. Add a research task to test compilation when Podman 6 beta releases. Do not integrate yet.

2. **sccache for C builds (vs ccache)**
   - What we know: sccache supports C/C++ compilation caching and is already installed (when enabled). ccache is 3-4.5x faster for local disk caching of C.
   - What's unclear: Whether using sccache for both Rust and C (unified cache) outweighs ccache's raw local performance advantage for C.
   - Recommendation: Use ccache for C builds (separate from sccache for Rust). The performance difference is significant for local-only caching, and having two specialized tools is cleaner than one tool doing both suboptimally. Note: sccache's local disk mode has a known ~70s overhead vs ccache for comparable workloads.

3. **Parallel build feasibility**
   - What we know: Components are independent after toolchain setup. GNU parallel or background processes could theoretically parallelize builds.
   - What's unclear: Interaction with CPU/memory contention when GOGC=off (uses 2.5x RAM). Log interleaving. Error handling complexity.
   - Recommendation: Defer to v2. The sequential approach works and is debuggable. Parallel builds add complexity disproportionate to the gain for a personal tool.

4. **git_clone_update shallow clone limitation**
   - What we know: Current shallow clone (`--depth 1`) followed by `git fetch --tags` + `git checkout $TAG` may fail if the tag is not on the default branch tip.
   - What's unclear: How often this actually fails in practice (it works for most repos where main tracks latest release).
   - Recommendation: Improve `git_clone_update` to accept an optional tag parameter and use `git clone --depth 1 --branch $TAG` for initial clones. This is the most network-efficient approach and eliminates the tag-not-found issue.

## Optimization Priority Matrix

| Optimization | Effort | Impact | Risk | Priority |
|-------------|--------|--------|------|----------|
| Go cache persistence (GOCACHE/GOMODCACHE) | LOW | HIGH | NONE | 1 - Do First |
| ccache for C builds | LOW | MEDIUM | LOW | 2 |
| mold linker for Rust | MEDIUM | MEDIUM | LOW | 3 |
| git_clone_update tag optimization | LOW | LOW | NONE | 4 |
| Conditional fuse-overlayfs | MEDIUM | LOW | MEDIUM | 5 |
| Parallel build orchestration | HIGH | MEDIUM | HIGH | DEFER to v2 |
| conmon-rs migration | HIGH | LOW | HIGH | DEFER to Podman 6 |

## Sources

### Primary (HIGH confidence)
- [mold GitHub repository](https://github.com/rui314/mold) - Version 2.40.1, installation methods, Cargo configuration
- [ccache official documentation](https://ccache.dev/) - Version 4.12.3, autotools integration, performance benchmarks
- [Go build cache documentation](https://medium.com/@AlexanderObregon/go-build-cache-mechanics-6ada202c0502) - GOCACHE/GOMODCACHE mechanics
- [Cargo profiles documentation](https://doc.rust-lang.org/cargo/reference/profiles.html) - Codegen units, LTO settings
- [mold Debian package tracker](https://tracker.debian.org/pkg/mold) - apt availability, last updated 2026-01-14

### Secondary (MEDIUM confidence)
- [Tips for Faster Rust Compile Times](https://corrode.dev/blog/tips-for-faster-rust-compile-times/) - mold + sccache combined usage patterns
- [Rust compiler performance survey 2025](https://blog.rust-lang.org/2025/09/10/rust-compiler-performance-survey-2025-results/) - mold/LLD adoption rates
- [Podman rootless overlay support](https://www.redhat.com/en/blog/podman-rootless-overlay) - fuse-overlayfs vs native overlay
- [sccache vs ccache performance](https://github.com/mozilla/sccache/issues/160) - Local disk caching 3-4.5x slower than ccache
- [Go 1.24 remote caching](https://depot.dev/blog/go-remote-cache) - GOCACHEPROG for remote caching (future option)
- [conmon-rs GitHub](https://github.com/containers/conmon-rs) - Build requirements, release status

### Tertiary (LOW confidence)
- conmon-rs default in Podman 6 timeline (May 2026) - Based on community discussions, not official announcement
- Parallel build theoretical speedup (30-40%) - Estimated from component build time proportions, not measured

## Metadata

**Confidence breakdown:**
- Build caching tools (ccache, mold, GOCACHE): HIGH - well-documented, widely used, verified via official docs
- Architecture patterns: HIGH - based on analysis of existing codebase patterns
- Component necessity assessment: MEDIUM - based on community discussions and Podman release notes
- Parallel build analysis: MEDIUM - dependency graph is clear, but real-world performance gains are estimated
- conmon-rs timeline: LOW - community discussion, not official release announcement
- Pitfalls: MEDIUM-HIGH - based on documented issues and common patterns

**Research date:** 2026-03-04
**Valid until:** 2026-04-04 (30 days - stable domain, tools change slowly)
