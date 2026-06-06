# Phase 1: Architecture Support - Research

**Researched:** 2026-02-28
**Domain:** Cross-architecture shell scripting (amd64/ARM64)
**Confidence:** HIGH

## Summary

This phase requires adding architecture detection and multi-architecture support to a Podman compilation script. The existing codebase hardcodes `x86_64` (amd64) architecture in three installer scripts: Go, Protoc, and Rust. Each toolchain vendor provides ARM64 binaries at predictable URL patterns, making this a straightforward mapping exercise.

**Primary recommendation:** Add a centralized `ARCH` variable in `config.sh` that maps to vendor-specific architecture strings, then update each installer to use architecture-aware download URLs.

## Standard Stack

### Core
| Tool | Current Version | Purpose | Architecture Support |
|------|-----------------|---------|---------------------|
| Go | 1.23.3 | Primary build toolchain | Official binaries for amd64/arm64 |
| Protoc | 33.1 | Protocol buffer compiler | Official binaries for amd64/arm64 |
| Rust | via rustup | Crun dependency | rustup supports all architectures |

### Architecture Mapping
| System Arch | Go Download | Protoc Download | Rust rustup |
|-------------|-------------|-----------------|-------------|
| x86_64/amd64 | `amd64` | `x86_64` | `x86_64-unknown-linux-gnu` |
| aarch64/ARM64 | `arm64` | `aarch_64` | `aarch64-unknown-linux-gnu` |

## Architecture Patterns

### Recommended Detection Pattern
```bash
# Detect system architecture - place in config.sh
detect_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "ERROR: Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
}

# Export for all scripts to use
export ARCH="${ARCH:-$(detect_architecture)}"
```

### Vendor-Specific Architecture Variables
```bash
# Map generic ARCH to vendor-specific strings
# Place in config.sh after ARCH detection

# Go uses: amd64, arm64
export GOARCH="$ARCH"

# Protoc uses: x86_64, aarch_64
case "$ARCH" in
    amd64) PROTOC_ARCH="x86_64" ;;
    arm64) PROTOC_ARCH="aarch_64" ;;
esac
export PROTOC_ARCH

# Rust rustup uses: x86_64-unknown-linux-gnu, aarch64-unknown-linux-gnu
case "$ARCH" in
    amd64) RUSTUP_ARCH="x86_64-unknown-linux-gnu" ;;
    arm64) RUSTUP_ARCH="aarch64-unknown-linux-gnu" ;;
esac
export RUSTUP_ARCH
```

### Recommended Project Structure
```
.
├── config.sh.example      # Add ARCH variable and vendor mappings
├── config.sh              # Generated from example (user's config)
├── functions.sh           # Add detect_architecture() here
├── install.sh             # Main entry point (no changes needed)
└── scripts/
    ├── install_go.sh      # Update to use $GOARCH
    ├── install_protoc.sh  # Update to use $PROTOC_ARCH
    └── install_rust.sh    # Update to use $RUSTUP_ARCH
```

### Pattern 1: Go Installer Update
**What:** Replace hardcoded `amd64` with `$GOARCH` variable
**When to use:** In `scripts/install_go.sh`

**Current code (line 19):**
```bash
wget "https://go.dev/dl/go${GOVERSION}.linux-amd64.tar.gz" -O go.tar.gz
```

**Updated code:**
```bash
wget "https://go.dev/dl/go${GOVERSION}.linux-${GOARCH}.tar.gz" -O go.tar.gz
```

### Pattern 2: Protoc Installer Update
**What:** Replace hardcoded `x86_64` with `$PROTOC_ARCH` variable
**When to use:** In `scripts/install_protoc.sh`

**Current code (line 26):**
```bash
wget "https://github.com/protocolbuffers/protobuf/releases/download/${PROTOC_TAG}/protoc-${PROTOC_VERSION}-linux-x86_64.zip"
```

**Updated code:**
```bash
wget "https://github.com/protocolbuffers/protobuf/releases/download/${PROTOC_TAG}/protoc-${PROTOC_VERSION}-linux-${PROTOC_ARCH}.zip"
```

### Pattern 3: Rust Installer Update
**What:** Replace hardcoded `x86_64-unknown-linux-gnu` with `$RUSTUP_ARCH` variable
**When to use:** In `scripts/install_rust.sh`

**Current code (line 18):**
```bash
wget https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init -O rustup-init
```

**Updated code:**
```bash
wget "https://static.rust-lang.org/rustup/dist/${RUSTUP_ARCH}/rustup-init" -O rustup-init
```

### Anti-Patterns to Avoid
- **Don't detect architecture in each script separately:** This leads to duplication and inconsistency. Detect once in config.sh.
- **Don't use `dpkg --print-architecture`:** The scripts should work without dpkg available (e.g., during early bootstrapping). `uname -m` is more portable.
- **Don't hardcode fallback to amd64:** If architecture is unsupported, fail explicitly rather than silently downloading wrong binaries.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Architecture detection | Custom parsing of `/proc/cpuinfo` | `uname -m` | Standard, portable, reliable |
| Download URL construction | Complex case statements per-script | Centralized mapping in config.sh | Single source of truth |
| Cross-compilation support | Building amd64 on ARM64 | Native ARM64 binaries | Native builds are faster and more reliable |

**Key insight:** All three toolchains (Go, Protoc, Rust) provide official ARM64 binaries. No cross-compilation or source compilation is needed.

## Common Pitfalls

### Pitfall 1: Inconsistent Architecture Naming
**What goes wrong:** Different vendors use different names for the same architecture (amd64 vs x86_64, arm64 vs aarch64).
**Why it happens:** No universal standard; each project chose its own convention.
**How to avoid:** Create a mapping layer in config.sh that translates from a single `ARCH` variable to vendor-specific strings.
**Warning signs:** 404 errors when downloading binaries, "exec format error" when running compiled tools.

### Pitfall 2: Assuming uname -m Returns "arm64"
**What goes wrong:** On Linux ARM64 systems, `uname -m` returns "aarch64", not "arm64".
**Why it happens:** Linux kernel uses ARM's official architecture name (aarch64), while Apple and some projects use "arm64".
**How to avoid:** Handle both `aarch64` and `arm64` in the case statement:
```bash
aarch64|arm64) echo "arm64" ;;
```

### Pitfall 3: Overriding User-Specified ARCH
**What goes wrong:** Always overwriting ARCH prevents users from cross-compiling or testing.
**Why it happens:** Using `ARCH=$(detect_architecture)` unconditionally.
**How to avoid:** Use default assignment: `ARCH="${ARCH:-$(detect_architecture)}"`
**Warning signs:** User's ARCH=arm64 is ignored on amd64 system.

### Pitfall 4: Missing Binary Availability Check
**What goes wrong:** Script fails partway through when a binary doesn't exist for the architecture.
**Why it happens:** Not all versions have ARM64 binaries (older releases).
**How to avoid:** Verify download URLs exist before proceeding, or document minimum versions that support ARM64.
**Warning signs:** 404 errors during wget, partial installations.

## Code Examples

### Complete config.sh Architecture Section
```bash
#!/bin/bash

# Determine toolpath if not set already
relativepath="./"
if [[ ! -v toolpath ]]; then
    scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)
    toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath})
fi

# ============================================
# Architecture Detection
# ============================================

# Detect system architecture
detect_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            echo "ERROR: Unsupported architecture: $arch" >&2
            echo "Supported: x86_64 (amd64), aarch64/arm64 (ARM64)" >&2
            exit 1
            ;;
    esac
}

# Allow override via environment variable, otherwise detect
export ARCH="${ARCH:-$(detect_architecture)}"

# Map to vendor-specific architecture strings
export GOARCH="$ARCH"  # Go uses: amd64, arm64

case "$ARCH" in
    amd64)
        export PROTOC_ARCH="x86_64"
        export RUSTUP_ARCH="x86_64-unknown-linux-gnu"
        ;;
    arm64)
        export PROTOC_ARCH="aarch_64"
        export RUSTUP_ARCH="aarch64-unknown-linux-gnu"
        ;;
esac

echo "Architecture: ${ARCH} (Go: ${GOARCH}, Protoc: ${PROTOC_ARCH}, Rust: ${RUSTUP_ARCH})"

# ============================================
# Version Configuration
# ============================================

# Build Root
export BUILD_ROOT="${toolpath}/build"

# Go Root Folder
export GO_ROOT_FOLDER="/opt/go"

# Go Version and Path
export GOVERSION="1.23.3"
export GOTAG="go${GOVERSION}"
export GOPATH="/opt/go/${GOVERSION}/bin"
export GOROOT="/opt/go/${GOVERSION}"

# ... rest of config.sh
```

### Updated install_go.sh (relevant section)
```bash
#!/bin/bash

set -e

# ... toolpath detection ...

source "${toolpath}/config.sh"
source "${toolpath}/functions.sh"

cd "${BUILD_ROOT}"

# Download Go for detected architecture
wget "https://go.dev/dl/go${GOVERSION}.linux-${GOARCH}.tar.gz" -O go.tar.gz

# Extract
tar -xzf go.tar.gz

# Move to destination
mkdir -p "${GO_ROOT_FOLDER}"
mv go "${GOROOT}"
```

### Updated install_protoc.sh (relevant section)
```bash
#!/bin/bash

set -e

# ... toolpath detection ...

source "${toolpath}/config.sh"
source "${toolpath}/functions.sh"

cd "${BUILD_ROOT}"

# Download Protoc for detected architecture
wget "https://github.com/protocolbuffers/protobuf/releases/download/${PROTOC_TAG}/protoc-${PROTOC_VERSION}-linux-${PROTOC_ARCH}.zip"

# Extract
unzip "protoc-${PROTOC_VERSION}-linux-${PROTOC_ARCH}.zip" -d "protoc-${PROTOC_VERSION}"

# Move to destination
mkdir -p "${PROTOC_ROOT_FOLDER}/${PROTOC_VERSION}"
mv "protoc-${PROTOC_VERSION}"/* "${PROTOC_ROOT_FOLDER}/${PROTOC_VERSION}/"
```

### Updated install_rust.sh (complete file)
```bash
#!/bin/bash

set -e

# Determine toolpath if not set already
relativepath="../"
if [[ ! -v toolpath ]]; then
    scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)
    toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath})
fi

# Load Configuration
source "${toolpath}/config.sh"

# Load Functions
source "${toolpath}/functions.sh"

cd "${BUILD_ROOT}"

# Download Rustup for detected architecture
wget "https://static.rust-lang.org/rustup/dist/${RUSTUP_ARCH}/rustup-init" -O rustup-init
chmod +x rustup-init

./rustup-init
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hardcoded amd64 | Architecture detection | This phase | Enables ARM64 support |
| Per-script architecture | Centralized config | This phase | Single source of truth |

**Deprecated/outdated:**
- Direct use of `x86_64` or `amd64` in download URLs: Should be replaced with variables

## Open Questions

1. **Should ARCH be configurable via command-line argument?**
   - What we know: Current design uses environment variable override
   - What's unclear: Whether install.sh should accept `--arch=arm64` flag
   - Recommendation: Start with environment variable only; add CLI flag in future if needed

2. **Minimum supported Go/Protoc/Rust versions for ARM64?**
   - What we know: Current versions (Go 1.23.3, Protoc 33.1) have ARM64 support
   - What's unclear: When ARM64 support was added to each project
   - Recommendation: Document that current versions are ARM64-compatible; users with older versions may need to upgrade

3. **Should we validate that downloaded binary matches expected architecture?**
   - What we know: `file` command can identify binary architecture
   - What's unclear: Whether this is necessary or overkill
   - Recommendation: Skip for now; rely on official download URLs being correct

## Sources

### Primary (HIGH confidence)
- Go Downloads: https://go.dev/dl/ - Verified amd64/arm64 naming pattern
- Protobuf Releases: https://github.com/protocolbuffers/protobuf/releases - Verified x86_64/aarch_64 naming
- Rust rustup Distribution: https://static.rust-lang.org/rustup/dist/ - Verified target triple naming

### Secondary (MEDIUM confidence)
- Existing codebase analysis - Reviewed all installer scripts and config structure

### Tertiary (LOW confidence)
- None required; all critical information verified from primary sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All three toolchains provide official ARM64 binaries with predictable URL patterns
- Architecture: HIGH - Simple mapping pattern, well-established `uname -m` detection
- Pitfalls: HIGH - Common issues well-documented in cross-platform scripting literature

**Research date:** 2026-02-28
**Valid until:** 2026-08-28 (6 months - architecture patterns are stable)
