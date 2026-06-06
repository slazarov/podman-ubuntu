# Phase 8: Build Optimization & Configuration - Research

**Researched:** 2026-03-04
**Domain:** Rust build caching (sccache), Podman containers.conf configuration
**Confidence:** HIGH

## Summary

Phase 8 has two distinct work streams: (1) implementing sccache for Rust build caching to achieve 50-90% rebuild speedup on netavark and aardvark-dns, and (2) enhancing and installing `containers.conf` with runtime, network, and security defaults. Both are well-understood domains with clear implementation paths.

The sccache integration is straightforward because the project already has `SCCACHE_ENABLED` as a config variable and commented-out sccache blocks in both Rust build scripts. The key decision is to install sccache via pre-built binary (not `cargo install`) to avoid a 5-10 minute compilation penalty. Pre-built musl binaries exist for both x86_64 and aarch64 on GitHub releases.

The containers.conf enhancement is additive -- the file already exists with `[engine]` helper_binaries_dir. It needs `runtime = "crun"`, `network_backend = "netavark"`, and `seccomp_profile` defaults added, plus an installation step in `setup.sh` to copy it to `/etc/containers/containers.conf`.

**Primary recommendation:** Use pre-built sccache binaries (v0.14.0) downloaded from GitHub releases, matching existing Go/Protoc install patterns. Enhance containers.conf with three sections. Clean up dead SCCACHE code by uncommenting and activating it.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| BLD-01 | Implement sccache for Rust builds (50-90% rebuild speedup) | Pre-built binary install + RUSTC_WRAPPER=sccache in Rust build scripts. Netavark/aardvark-dns Makefiles pass through env vars to cargo. |
| BLD-02 | Add sccache installation to install_rust.sh (via cargo install sccache) | Recommend pre-built binary instead of cargo install (saves 5-10 min compilation). Download from GitHub releases like Go/Protoc pattern. |
| BLD-03 | Configure RUSTC_WRAPPER=sccache when SCCACHE_ENABLED=true | Both build_netavark.sh and build_aardvark_dns.sh already have commented-out blocks. Uncomment and activate them. |
| BLD-04 | Add sccache directory setup and environment configuration | SCCACHE_DIR env var for cache location, auto-create directory. Config in config.sh alongside existing SCCACHE_ENABLED. |
| CONF-01 | Enhance config/containers.conf with runtime default (crun) | Add `runtime = "crun"` under `[engine]` section in existing file. |
| CONF-02 | Add network backend configuration (netavark) to containers.conf | Add `[network]` section with `network_backend = "netavark"`. |
| CONF-03 | Install containers.conf to /etc/containers/containers.conf during setup | Add a step at end of setup.sh to mkdir -p /etc/containers && cp config/containers.conf /etc/containers/. |
| CONF-04 | Add seccomp_profile default configuration | Add `[containers]` section with `seccomp_profile = "/usr/share/containers/seccomp.json"`. |
| CLNP-04 | Clean up unused SCCACHE_ENABLED dead code | The commented-out sccache blocks in build scripts become active code. Remove "optional/uncomment" comments from config.sh. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| sccache | v0.14.0 | Rust compilation cache | Mozilla's official compiler cache, only real option for Rust caching |
| containers.conf | N/A (TOML config) | Podman runtime configuration | Official Podman configuration file format |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| wget | system | Download sccache binary | Matches existing Go/Protoc download pattern |
| tar | system | Extract sccache archive | sccache ships as .tar.gz |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pre-built sccache binary | `cargo install sccache` | cargo install takes 5-10 minutes to compile sccache itself; pre-built binary is instant |
| Local disk cache | S3/GCS/Redis remote cache | Remote cache is overkill for personal use; local disk is zero-config |

**Installation (pre-built binary approach):**
```bash
# For x86_64:
wget "https://github.com/mozilla/sccache/releases/download/v0.14.0/sccache-v0.14.0-x86_64-unknown-linux-musl.tar.gz"
# For aarch64:
wget "https://github.com/mozilla/sccache/releases/download/v0.14.0/sccache-v0.14.0-aarch64-unknown-linux-musl.tar.gz"
```

## Architecture Patterns

### Sccache Architecture Mapping

The project uses `$ARCH` (amd64/arm64) for architecture detection. Sccache uses different naming:

| Project ARCH | sccache binary name |
|-------------|---------------------|
| amd64 | `x86_64-unknown-linux-musl` |
| arm64 | `aarch64-unknown-linux-musl` |

This is the same mapping pattern as `RUSTUP_ARCH` in config.sh, so add a `SCCACHE_ARCH` variable using the same case block.

### Integration Points

```
config.sh
  SCCACHE_ENABLED=false (existing, line 59)
  SCCACHE_DIR="/var/cache/sccache" (NEW)
  SCCACHE_ARCH (NEW, follows RUSTUP_ARCH pattern)

install_rust.sh
  NEW: Download and install sccache pre-built binary (when SCCACHE_ENABLED=true)

build_netavark.sh (lines 48-51)
  CHANGE: Uncomment sccache block, make it active

build_aardvark_dns.sh (lines 57-59)
  CHANGE: Uncomment sccache block, make it active

config/containers.conf
  CHANGE: Add [containers], [network] sections alongside existing [engine]

setup.sh
  NEW: Add containers.conf installation step after all builds complete
```

### Pattern: Conditional Tool Installation
**What:** Only download/install sccache when SCCACHE_ENABLED=true
**When to use:** Always -- sccache adds install time and only benefits rebuilds, not first-time users
**Example:**
```bash
# In install_rust.sh, AFTER rustup install
if [[ "${SCCACHE_ENABLED:-false}" == "true" ]]; then
    step_start "Installing sccache"

    # Map architecture for sccache download
    case "$ARCH" in
        amd64) SCCACHE_ARCH="x86_64-unknown-linux-musl" ;;
        arm64) SCCACHE_ARCH="aarch64-unknown-linux-musl" ;;
    esac

    SCCACHE_VERSION="0.14.0"
    wget "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}.tar.gz" -O sccache.tar.gz
    tar -xzf sccache.tar.gz
    cp "sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}/sccache" /usr/local/bin/sccache
    chmod +x /usr/local/bin/sccache
    rm -rf sccache.tar.gz "sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}"

    # Create cache directory
    mkdir -p "${SCCACHE_DIR:-/var/cache/sccache}"

    step_done
fi
```

### Pattern: RUSTC_WRAPPER Activation in Build Scripts
**What:** Set RUSTC_WRAPPER=sccache when available and enabled
**When to use:** In every Rust build script (netavark, aardvark-dns)
**Example:**
```bash
# Replace commented-out blocks with:
if [[ "${SCCACHE_ENABLED:-false}" == "true" ]] && command -v sccache &>/dev/null; then
    export RUSTC_WRAPPER=sccache
    echo "  sccache enabled for Rust compilation"
fi
```

### Pattern: containers.conf Installation
**What:** Copy enhanced config to system location
**When to use:** After all builds complete, before final summary
**Example:**
```bash
# In setup.sh, after all run_script calls:
echo ">>> Installing containers configuration..."
mkdir -p /etc/containers
cp "${toolpath}/config/containers.conf" /etc/containers/containers.conf
echo ">>> containers.conf installed to /etc/containers/"
```

### Anti-Patterns to Avoid
- **Using `cargo install sccache`:** Compiles sccache from source, taking 5-10 minutes. Use pre-built binary instead.
- **Setting RUSTC_WRAPPER globally in config.sh:** Only set it in scripts that actually do Rust builds. Avoids confusing other cargo operations.
- **Hardcoding sccache version in multiple files:** Define SCCACHE_VERSION once in config.sh.
- **Installing sccache unconditionally:** It only benefits rebuilds. First-time users get zero benefit but pay download cost.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Rust compilation caching | Custom incremental build tracker | sccache | Handles cache invalidation, dependency tracking, and compiler flag changes |
| Architecture binary mapping | Ad-hoc if/else per download | Central case block in config.sh | Project already uses this pattern for Go, Protoc, Rustup |
| Config file generation | echo/printf/heredoc construction | Static TOML file with cp | Avoids quoting hell, easier to validate and maintain |

**Key insight:** The project already has established patterns for tool installation (wget + extract + copy) and architecture mapping (case blocks in config.sh). Follow these exactly.

## Common Pitfalls

### Pitfall 1: sccache Server Not Running
**What goes wrong:** First cargo build with RUSTC_WRAPPER=sccache fails because sccache server isn't started.
**Why it happens:** sccache uses a client-server model; the server auto-starts on first use, but can fail if port 4226 is occupied.
**How to avoid:** sccache auto-starts the server on first invocation. Test with `sccache --show-stats` before builds. The server auto-terminates after 10 minutes of inactivity.
**Warning signs:** Error messages about connection refused or server not running.

### Pitfall 2: Binary Crates Cannot Be Cached
**What goes wrong:** Final linking step (producing the actual binary) is not cached by sccache.
**Why it happens:** sccache caches individual rustc compilation units. Binary crates that invoke the system linker (bin, dylib, cdylib, proc-macro) cannot be cached. Only intermediate compilation artifacts are cached.
**How to avoid:** This is expected behavior. The 50-90% speedup claim comes from caching the compilation of dependencies and library crates, not the final link. Rebuilds still see significant speedup because most time is in compilation, not linking.
**Warning signs:** `sccache --show-stats` shows cache misses for the main binary crate.

### Pitfall 3: containers.conf Overwriting Existing Config
**What goes wrong:** Blindly copying containers.conf to /etc/containers/ overwrites user customizations.
**Why it happens:** User may have already configured Podman or have a package-managed containers.conf.
**How to avoid:** Check if the file exists before copying. If it exists, either skip or merge. Since this is a fresh-build tool, unconditional copy is acceptable but should log a message.
**Warning signs:** Podman behavior changes after reinstall.

### Pitfall 4: sccache Cache Location Permissions
**What goes wrong:** sccache cannot create or write to its cache directory.
**Why it happens:** Default sccache cache goes to `$HOME/.cache/sccache` but install.sh typically runs as root.
**How to avoid:** Explicitly set SCCACHE_DIR to a known-good location like `/var/cache/sccache` and mkdir -p it during setup.
**Warning signs:** sccache shows 0 cache hits, or errors about permissions.

### Pitfall 5: Incremental Compilation Conflicts with sccache
**What goes wrong:** Rust incremental compilation artifacts bypass sccache entirely.
**Why it happens:** Incremental compilation generates unique artifacts per build that are incompatible with cross-build caching.
**How to avoid:** Release builds (which netavark/aardvark-dns use via `make`) already disable incremental compilation by default. No action needed for this project.
**Warning signs:** Very low cache hit rate despite rebuilds.

### Pitfall 6: seccomp.json File Must Exist
**What goes wrong:** Setting seccomp_profile path in containers.conf but the JSON file doesn't exist on the system.
**Why it happens:** `/usr/share/containers/seccomp.json` is typically provided by the `containers-common` package, which may not be installed when building from source.
**How to avoid:** Either install the `containers-common` package as a dependency, or ship a default seccomp.json, or use a conditional comment explaining the requirement.
**Warning signs:** Podman containers fail to start with seccomp-related errors.

## Code Examples

### Enhanced containers.conf (full file)
```toml
# Podman containers configuration
# Installed by podman-debian to /etc/containers/containers.conf
# See: man containers.conf(5)

[containers]

# Default seccomp profile for container runtime security
# Requires: /usr/share/containers/seccomp.json (from containers-common package)
# Comment out if seccomp.json is not available on your system
seccomp_profile = "/usr/share/containers/seccomp.json"

[engine]

# Default OCI runtime - crun is faster and uses less memory than runc
runtime = "crun"

# Search paths for helper binaries (netavark, aardvark-dns, etc.)
# podman-debian installs these to /usr/local/bin
helper_binaries_dir = [
    "/usr/local/bin",
    "/usr/local/libexec/podman",
    "/usr/libexec/podman",
    "/usr/local/lib/podman",
    "/usr/lib/podman"
]

[network]

# Network backend - netavark is the modern replacement for CNI
# CNI was removed in Podman 5.0
network_backend = "netavark"
```

### sccache Installation in install_rust.sh
```bash
# After rustup installation...

# Install sccache for Rust build caching (optional)
if [[ "${SCCACHE_ENABLED:-false}" == "true" ]]; then
    step_start "Installing sccache v${SCCACHE_VERSION}"

    case "$ARCH" in
        amd64) SCCACHE_ARCH="x86_64-unknown-linux-musl" ;;
        arm64) SCCACHE_ARCH="aarch64-unknown-linux-musl" ;;
    esac

    wget "https://github.com/mozilla/sccache/releases/download/v${SCCACHE_VERSION}/sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}.tar.gz" -O sccache.tar.gz
    tar -xzf sccache.tar.gz
    cp "sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}/sccache" /usr/local/bin/sccache
    chmod +x /usr/local/bin/sccache
    rm -rf sccache.tar.gz "sccache-v${SCCACHE_VERSION}-${SCCACHE_ARCH}"

    # Create cache directory
    mkdir -p "${SCCACHE_DIR}"

    # Verify installation
    sccache --show-stats
    echo "  sccache installed: $(sccache --version)"
    step_done
fi
```

### Activated RUSTC_WRAPPER in Build Scripts
```bash
step_start "Configuring Cargo optimization"
# Set parallel jobs for cargo (uses NPROC by default)
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$NPROC}"

# Enable sccache for Rust build caching when configured
if [[ "${SCCACHE_ENABLED:-false}" == "true" ]] && command -v sccache &>/dev/null; then
    export RUSTC_WRAPPER=sccache
    echo "  sccache enabled for Rust compilation"
fi
step_done
```

### Verification Commands
```bash
# Verify sccache is working (Success Criterion 1)
sccache --show-stats

# Verify containers.conf installed (Success Criterion 2)
cat /etc/containers/containers.conf | grep "runtime"
cat /etc/containers/containers.conf | grep "network_backend"

# Verify rebuild speedup (Success Criterion 3)
# First build: all cache misses
# Second build: should see cache hits in sccache --show-stats

# Verify seccomp config (Success Criterion 4)
cat /etc/containers/containers.conf | grep "seccomp_profile"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CNI networking | Netavark networking | Podman 5.0 (2024) | CNI removed, netavark is only option |
| runc default runtime | crun default runtime | Podman default since 2021 | 50% faster, 8x less memory |
| slirp4netns rootless networking | pasta rootless networking | Podman 5.0 | Better performance |
| No Rust build caching | sccache v0.14.0 | Feb 2025 release | 50-90% rebuild speedup |

**Deprecated/outdated:**
- CNI networking: Removed in Podman 5.0, replaced by netavark
- `cargo install sccache`: Still works but pre-built binaries are faster to install (5-10 min savings)

## Open Questions

1. **seccomp.json availability**
   - What we know: `/usr/share/containers/seccomp.json` comes from `containers-common` package. When building Podman from source, this file may not exist.
   - What's unclear: Whether the project's `install_dependencies.sh` already installs `containers-common` or equivalent.
   - Recommendation: Check if `containers-common` is in the dependency list. If not, add it, or use a commented-out seccomp_profile with an explanatory comment.

2. **SCCACHE_VERSION pinning**
   - What we know: The project philosophy is "always latest stable" for build targets (Podman, etc.), but sccache is a build tool, not a build target.
   - What's unclear: Whether sccache version should be pinned (like current v0.14.0) or auto-detected from GitHub API.
   - Recommendation: Pin to v0.14.0 for now. Auto-detection adds complexity and sccache updates are infrequent. User can override via env variable.

3. **Uninstall script updates**
   - What we know: uninstall.sh removes /etc/containers entirely (line 166). Sccache binary and cache directory are not cleaned up.
   - What's unclear: Whether uninstall should also remove sccache and its cache.
   - Recommendation: Add sccache cleanup to uninstall.sh (remove binary + cache directory) for completeness.

## Sources

### Primary (HIGH confidence)
- [mozilla/sccache GitHub](https://github.com/mozilla/sccache) - Installation methods, version (v0.14.0), architecture support, environment variables
- [sccache Rust.md](https://github.com/mozilla/sccache/blob/main/docs/Rust.md) - Rust-specific caching behavior, RUSTC_WRAPPER, limitations
- [sccache GitHub Releases API](https://api.github.com/repos/mozilla/sccache/releases/latest) - Confirmed v0.14.0 (Feb 9, 2025), pre-built binaries for x86_64-unknown-linux-musl and aarch64-unknown-linux-musl
- [containers/common containers.conf](https://github.com/containers/common/blob/main/pkg/config/containers.conf) - Default TOML keys: runtime, network_backend, seccomp_profile
- [Ubuntu containers.conf manpage](https://manpages.ubuntu.com/manpages/jammy/man5/containers.conf.5.html) - File locations, search order, key documentation
- [netavark Makefile](https://github.com/containers/netavark/blob/main/Makefile) - Confirmed RUSTC_WRAPPER passthrough via standard cargo invocation

### Secondary (MEDIUM confidence)
- [Earthly Blog - sccache](https://earthly.dev/blog/rust-sccache/) - Practical sccache setup guidance, cache hit rate expectations
- [Rust Forum - sccache with cargo install](https://users.rust-lang.org/t/does-sccache-work-with-cargo-install/61043) - Confirmed limitations on binary crate caching

### Tertiary (LOW confidence)
- 50-90% rebuild speedup claim: Based on project REQUIREMENTS.md target and general sccache documentation. Actual speedup depends on crate count, dependency depth, and what fraction is the final link step. Netavark and aardvark-dns are medium-sized Rust projects with many dependencies, so 50-90% is plausible for rebuild (not first build).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - sccache is the only real option for Rust compilation caching; containers.conf format is well-documented
- Architecture: HIGH - project already has established patterns for tool downloads, architecture mapping, and build script structure
- Pitfalls: HIGH - sccache limitations are well-documented; containers.conf pitfalls are straightforward
- Code examples: HIGH - based on existing project patterns and verified sccache documentation

**Research date:** 2026-03-04
**Valid until:** 2026-04-04 (stable domain, sccache v0.14.0 is recent)
