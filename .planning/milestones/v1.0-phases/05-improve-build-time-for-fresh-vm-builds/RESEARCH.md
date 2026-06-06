# Phase 5 Research: Build Time Optimization for Fresh VM Builds

**Researched:** 2026-03-03
**Domain:** Build parallelization, compiler optimization, shallow clones
**Confidence:** HIGH

---

## Summary

This research update covers the latest best practices for build time optimization in 2026, focusing on four key areas: make parallelization, Go 1.26+ compiler optimizations, Cargo/Rust parallelization, and git shallow clone edge cases.

**Primary recommendation:** Use `make -j$(nproc)` for all Make-based builds with automatic job detection. For Go 1.26+, the new Green Tea GC provides automatic 10-40% performance improvement with no configuration needed. For Cargo, use `CARGO_BUILD_JOBS=$(nproc)` environment variable. Apply shallow clones (`--depth 1`) only to fresh clones, never to existing repositories.

---

## Standard Stack

### Core Optimization Tools

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `nproc` | Coreutils | CPU core detection | Universal, accurate, handles cgroups |
| `make -j` | GNU Make 4.x | Parallel builds | 3-8x speedup, universally supported |
| `CARGO_BUILD_JOBS` | Cargo 1.75+ | Rust parallel compilation | Official environment variable, 2-4x speedup |
| `git clone --depth 1` | Git 2.x | Shallow clones | ~95% network reduction |

### Compiler Optimization Flags

| Compiler | Flag | Speed Boost | Trade-off |
|----------|------|-------------|-----------|
| Go | `-gcflags='-c=16'` | ~25% faster | More RAM usage |
| Go | `GOGC=off` | ~30% faster | ~2.5x RAM during compilation |
| Go | `-ldflags='-s -w'` | 30-40% smaller binary | No debug symbols |
| Cargo | `codegen-units=256` (dev) | Faster incremental | Slightly slower code |
| Cargo | `codegen-units=16` (release) | Better optimizations | Default for release |

### Supporting Tools

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `sccache` | Compiler cache | CI/CD with remote cache (S3/WebDAV) |
| `ninja` | Build system | Meson projects (conmon) - auto-parallelizes |
| `ccache` | C/C++ cache | Local development caching |

**Installation:**
```bash
# Standard build dependencies
apt-get install -y build-essential ninja-build ccache

# Optional: sccache for remote caching
cargo install sccache
```

---

## Architecture Patterns

### Pattern 1: Make Parallelization

**What:** Use `make -j$(nproc)` for parallel compilation

**When to use:** All Make-based builds (protoc, passt, slirp4netns, Go toolchain)

**Implementation:**
```bash
# In config.sh
export NPROC="${NPROC:-$(nproc)}"

# In build scripts
make -j"${NPROC}"
```

**Gotcha with `-j` vs `-j$(nproc)`:**
- `make -j` (no number): Unlimited parallelism - can cause memory exhaustion and slow down due to thrashing
- `make -j$(nproc)`: Limits to CPU cores - optimal for most cases
- `make -j$((NPROC * 2))`: For I/O-bound workloads, 2x CPU cores can help

**Recommended approach:**
```bash
# Default to nproc, allow override
export MAKEFLAGS="-j${NPROC:-$(nproc)}"
make  # Uses parallel jobs automatically
```

Source: GNU Make documentation, Stack Overflow best practices

### Pattern 2: Go 1.26+ Build Optimization

**What:** Go 1.26 (released Feb 2026) introduces automatic performance improvements

**Key changes in Go 1.26:**
1. **Green Tea GC** - Now enabled by default, provides 10-40% GC overhead reduction
2. **30% faster cgo calls** - Reduced baseline overhead
3. **Stack allocation for slices** - Compiler places more slice backing stores on stack

**Build flags for Go 1.26+:**
```bash
# No special flags needed for Green Tea GC - it's default!

# Optional: Disable Green Tea GC (for debugging issues)
# GOEXPERIMENT=nogreenteagc go build  # Will be removed in Go 1.27

# Faster compilation (if RAM available)
GOGC=off go build -gcflags='-c=16' ./...

# Smaller binaries for release
go build -ldflags='-s -w' ./...
```

**Recommendation:** For Go 1.26+, no special optimization flags are needed. The compiler and runtime are optimized by default. Only use `GOGC=off` during compilation (not runtime) for 30% faster builds on systems with sufficient RAM.

**Verified pattern from containers/podman Makefile (Zread 2026-03-03):**
```makefile
# From actual Podman Makefile
GO ?= go
GOFLAGS ?= -trimpath
GO_LDFLAGS:= $(shell if $(GO) version|grep -q gccgo; then echo "-gccgoflags"; else echo "-ldflags"; fi)
GOCMD = CGO_ENABLED=$(CGO_ENABLED) GOOS=$(GOOS) GOARCH=$(GOARCH) $(GO)

# Build command pattern
$(GOCMD) build $(BUILDFLAGS) $(GO_LDFLAGS) '$(LDFLAGS_PODMAN)' -tags "$(BUILDTAGS)" -o $@ ./cmd/podman

# For parallel testing they use:
bats -T --filter-tags ci:parallel -j $$(nproc) test/system/
```

**Key insight:** Podman doesn't use `-j` for Go builds (Go parallelizes internally via `GOMAXPROCS`), but DOES use `-j$(nproc)` for parallel test execution with bats.

Sources:
- Go 1.26 Release Notes (go.dev/doc/go1.26)
- Heise Online (Feb 2026)
- InfoWorld coverage (Feb 2026)

### Pattern 3: Cargo/Rust Parallelization

**What:** Use `CARGO_BUILD_JOBS` environment variable for parallel compilation

**Implementation:**
```bash
# In config.sh
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$NPROC}"

# Cargo automatically uses this
cargo build --release
```

**Profile configuration (Cargo.toml):**
```toml
# Defaults - don't override unless necessary
[profile.dev]
codegen-units = 256  # Fast incremental builds
incremental = true

[profile.release]
codegen-units = 16   # Better optimizations
opt-level = 3
lto = false          # LTO is slow, enable only for final binaries
```

**Important note on codegen-units:**
- Higher values (256) = faster compilation, slower runtime
- Lower values (16) = slower compilation, faster runtime
- Release profile uses 16 by default - do not change to 256

**Jobserver implementation (verified from rust-lang/cargo via Zread):**
- Cargo creates a jobserver with N tokens based on `-j` parameter
- Immediately acquires one token for itself, leaving N-1 for parallel rustc invocations
- `CARGO_BUILD_JOBS` sets the jobserver token count
- Experimental `-Zfine-grain-locking` improves parallel builds (fixes blocking behavior)

Source: Cargo Book (doc.rust-lang.org/stable/cargo/reference/profiles)
Source: Zread rust-lang/cargo - Job Queue and Parallelization (verified 2026-03-03)

### Pattern 4: Git Shallow Clone Strategy

**What:** Use `--depth 1` for fresh clones only, never for existing repos

**Implementation:**
```bash
# In config.sh
export SHALLOW_CLONE="${SHALLOW_CLONE:-true}"

# In build scripts
if [[ ! -d "${repo_dir}" ]]; then
    # Fresh clone - use shallow
    if [[ "${SHALLOW_CLONE}" == "true" ]]; then
        git clone --depth 1 "${repo_url}" "${repo_dir}"
    else
        git clone "${repo_url}" "${repo_dir}"
    fi
else
    # Existing repo - just update
    cd "${repo_dir}"
    git fetch origin
    git checkout origin/main
fi
```

**When NOT to use shallow clone:**
1. When you need `git bisect` for debugging
2. When you need `git rebase` or merge operations
3. When building from a specific tag requires history traversal
4. When contributing changes back (need full history)
5. When tooling depends on full history (some monorepo tools)

**Recovery from shallow clone:**
```bash
# Convert shallow clone to full clone
git fetch --unshallow

# Or deepen incrementally
git fetch --deepen 100

# Advanced: deepen by date (Git 2.x)
git fetch --shallow-since="2024-01-01"
```

**Partial clone alternative (Git 2.19+):**
```bash
# Download objects on-demand instead of upfront
git clone --filter=blob:none "${repo_url}"

# Combined with shallow
git clone --depth 1 --filter=blob:none "${repo_url}"
```

Sources:
- OpenReplay Blog (2025)
- Graphite Guide
- Medium Deep Dive (2022, still relevant)
- Zread git/git - Transport Protocols, Remote Repository Interaction (verified 2026-03-03)

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CPU core detection | Custom parsing | `nproc` | Handles cgroups, containers, NUMA |
| Parallel job limits | Manual semaphore | `make -j` | Built-in job server, dependency tracking |
| Cargo parallelization | Scripted builds | `CARGO_BUILD_JOBS` | Official support, handles edge cases |
| Git history depth | Custom clone logic | `--depth` + `--shallow-since` | Git built-in, efficient |
| Compiler caching | Directory copying | `sccache` / `ccache` | Handles invalidation, remote caching |

**Key insight:** Build tools have sophisticated parallelization built-in. Use their native mechanisms rather than wrapping with custom scripts.

---

## Common Pitfalls

### Pitfall 1: Unlimited Make Parallelism

**What goes wrong:** `make -j` without a number spawns unlimited processes, causing:
- Memory exhaustion
- System thrashing
- Actually slower builds due to context switching

**Why it happens:** Users think "more parallelism = faster"

**How to avoid:** Always use `make -j$(nproc)` or set `MAKEFLAGS="-j$(nproc)"`

**Warning signs:** System becomes unresponsive during builds, dmesg shows OOM killer

### Pitfall 2: Shallow Clone on Existing Repository

**What goes wrong:** Running `git fetch --depth 1` on an existing full clone can:
- Truncate history unexpectedly
- Break `git bisect` that was working
- Cause "graft commit" issues with merges

**Why it happens:** Scripts don't distinguish between fresh clone and update

**How to avoid:** Only apply `--depth 1` to fresh clones

```bash
# Correct pattern
if [[ ! -d "${repo}/.git" ]]; then
    git clone --depth 1 "${url}" "${repo}"
else
    git -C "${repo}" pull  # No --depth on existing
fi
```

### Pitfall 3: Disabling Go Optimizations for Production

**What goes wrong:** Using `-gcflags='-N -l'` (disable optimizations) in production builds

**Why it happens:** Developers copy-paste debug flags to production

**How to avoid:**
- Debug flags only for development
- Production uses default optimizations or `-ldflags='-s -w'`

### Pitfall 4: Over-tuning codegen-units

**What goes wrong:** Setting `codegen-units = 256` in release profile, causing slower binaries

**Why it happens:** Confusion between compile-time and runtime optimization

**How to avoid:** Use Cargo defaults for release profile:
- `codegen-units = 16` for release
- `codegen-units = 256` for dev (default)

### Pitfall 5: RAM Exhaustion with GOGC=off

**What goes wrong:** `GOGC=off` during Go compilation causes OOM on memory-constrained systems

**Why it happens:** `GOGC=off` uses 2.5x more RAM during compilation

**How to avoid:**
- Check available RAM before setting GOGC=off
- Default to GOGC=off only if system has 4GB+ RAM
- Allow user override via environment variable

---

## Code Examples

### Complete Make Parallelization Pattern

```bash
#!/bin/bash
set -euo pipefail

source "${toolpath}/config.sh"

# NPROC is already set in config.sh
# Default: $(nproc), overridable via environment

cd "${BUILD_ROOT}/some-package"

# Configure
./configure --prefix=/usr/local

# Build with parallel jobs
make -j"${NPROC}"

# Install
make install
```

### Go 1.26+ Build Pattern

```bash
#!/bin/bash
set -euo pipefail

source "${toolpath}/config.sh"

cd "${BUILD_ROOT}/podman"

# Build with optimization flags from config.sh
# GOGC_BUILD is "off" by default for faster compilation
env GOGC="${GOGC_BUILD}" \
    go build \
    -gcflags="${GO_GCFLAGS}" \
    -ldflags="${GO_LDFLAGS}" \
    -o /usr/local/bin/podman \
    ./cmd/podman
```

### Cargo Build Pattern

```bash
#!/bin/bash
set -euo pipefail

source "${toolpath}/config.sh"

cd "${BUILD_ROOT}/netavark"

# CARGO_BUILD_JOBS is set in config.sh
# Cargo uses it automatically
cargo build --release

# Install binary
cp target/release/netavark /usr/local/libexec/podman/
```

### Conditional Shallow Clone Pattern

```bash
#!/bin/bash
set -euo pipefail

source "${toolpath}/config.sh"

REPO_URL="https://github.com/containers/conmon"
REPO_DIR="${BUILD_ROOT}/conmon"
REPO_TAG="${CONMON_TAG:-}"

if [[ ! -d "${REPO_DIR}" ]]; then
    echo "Cloning conmon..."
    if [[ "${SHALLOW_CLONE}" == "true" ]]; then
        if [[ -n "${REPO_TAG}" ]]; then
            git clone --depth 1 --branch "${REPO_TAG}" "${REPO_URL}" "${REPO_DIR}"
        else
            git clone --depth 1 "${REPO_URL}" "${REPO_DIR}"
        fi
    else
        git clone "${REPO_URL}" "${REPO_DIR}"
    fi
else
    echo "Updating conmon..."
    cd "${REPO_DIR}"
    git fetch origin
    if [[ -n "${REPO_TAG}" ]]; then
        git checkout "${REPO_TAG}"
    else
        git checkout origin/main
    fi
fi
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Go GC tuning with GOGC | Green Tea GC (default in 1.26) | Feb 2026 (Go 1.26) | 10-40% GC overhead reduction, automatic |
| `make -j` unlimited | `make -j$(nproc)` | Established best practice | Prevents memory exhaustion |
| Manual Cargo parallelism | `CARGO_BUILD_JOBS` env var | Cargo 1.50+ | Official, handles edge cases |
| Full git clone always | Shallow clone for CI/fresh builds | Git 1.9+ | 95% network reduction |

**Deprecated/outdated:**
- `GOGC=off` at runtime: Was a hack for specific workloads, Green Tea GC makes this unnecessary
- Manual `-c=16` tuning: Still helps for compilation speed, but less impactful with Green Tea GC
- `hurry` tool: Early 2025 experimental tool, sccache remains the standard for caching

---

## Components to Optimize

Based on project structure:

| Component | Build System | Optimization Strategies |
|-----------|--------------|------------------------|
| Go | Make | `make -j`, gcflags, ldflags (already configured) |
| protoc | Make | `make -j` |
| Rust/crun | Cargo | `CARGO_BUILD_JOBS` (already configured) |
| conmon | Meson/ninja | `ninja -j` (auto-parallelizes) |
| passt | Make | `make -j` |
| Podman | Make | `make -j`, gcflags, ldflags |
| netavark | Cargo | `CARGO_BUILD_JOBS` (already configured) |
| aardvark-dns | Cargo | `CARGO_BUILD_JOBS` (already configured) |
| slirp4netns | Autotools | `make -j` |

---

## Open Questions

1. **Should sccache be enabled by default?**
   - What we know: sccache provides 3-5x speedup with warm remote cache
   - What's unclear: Whether to enable for local-only caching without remote
   - Recommendation: Keep disabled by default, document for CI/CD users

2. **What's the optimal NPROC for memory-constrained VMs?**
   - What we know: `nproc` reports CPU cores, not available RAM
   - What's unclear: Formula for capping based on available RAM
   - Recommendation: Default to `nproc`, document override for small VMs

---

## Sources

### Primary (HIGH confidence)
- Go 1.26 Release Notes - https://go.dev/doc/go1.26 (Go 1.26 features, Green Tea GC)
- Cargo Book - https://doc.rust-lang.org/stable/cargo/reference/profiles (codegen-units defaults)
- Context7 /golang/go - Compiler flags documentation
- **Zread containers/podman** - Makefile verified patterns (GOFLAGS, -trimpath, parallel test execution)
- **Zread rust-lang/cargo** - Jobserver implementation, codegen-units, -Zfine-grain-locking
- **Zread git/git** - Shallow clone implementation, partial clone (Git 2.19+)

### Secondary (MEDIUM confidence)
- Heise Online (Feb 2026) - Go 1.26 coverage
- InfoWorld (Feb 2026) - Go 1.26 Green Tea GC analysis
- OpenReplay Blog - Git shallow clone guide (2025)
- Graphite Guide - Git shallow clone deep dive
- GNU Make Documentation - Parallel builds

### Tertiary (LOW confidence)
- Various Stack Overflow discussions on make -j behavior
- Reddit r/git discussions on shallow clone pitfalls

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Official documentation sources
- Architecture patterns: HIGH - Verified with Context7 and official docs
- Pitfalls: MEDIUM - Community knowledge with official verification

**Research date:** 2026-03-03
**Updated with Zread verification:** 2026-03-03
**Valid until:** 2026-06-01 (Go 1.27 may change defaults)
