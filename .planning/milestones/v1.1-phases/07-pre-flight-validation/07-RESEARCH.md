# Phase 7: Pre-flight Validation - Research

**Researched:** 2026-03-03
**Domain:** System requirements validation for rootless Podman installation
**Confidence:** HIGH

## Summary

Pre-flight validation ensures that Podman installation fails early with clear error messages when system requirements are not met. This research covers five critical checks needed for rootless Podman operation: cgroups v2 availability, subuid/subgid configuration, kernel FUSE support, minimum kernel version, and noexec mount detection on critical directories.

The implementation should create a standalone pre-flight check script that runs before any build operations in setup.sh. Each check must complete quickly (target: under 5 seconds total) and provide actionable error messages when failures occur.

**Primary recommendation:** Create a single `scripts/preflight_check.sh` script with individual check functions, called early in setup.sh before any compilation begins. Use exit codes and colored output to distinguish between errors (must fix) and warnings (may work but unsupported).

---

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| VAL-01 | Add pre-flight check for cgroups v2 availability (required for rootless) | See: Cgroups v2 Detection |
| VAL-02 | Add pre-flight check for subuid/subgid configuration (rootless requirement) | See: Subuid/Subgid Verification |
| VAL-03 | Add pre-flight check for kernel FUSE support (fuse-overlayfs requirement) | See: FUSE Kernel Support |
| VAL-04 | Add pre-flight check for minimum kernel version (5.11+ recommended) | See: Kernel Version Check |
| VAL-05 | Add pre-flight check for noexec mount on /tmp and /home (builds fail) | See: Noexec Mount Detection |

</phase_requirements>

---

## Standard Stack

### Core
| Component | Purpose | Why Standard |
|-----------|---------|--------------|
| bash built-ins | File testing, string matching | No dependencies, portable |
| /proc filesystem | Kernel/system info | Standard Linux interface |
| findmnt | Mount option inspection | Part of util-linux, always available |
| uname | Kernel version detection | Standard POSIX utility |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| grep | Pattern matching in files | /proc and /etc parsing |
| awk | Field extraction | Version comparison, mount parsing |

### Error Message Format
```
[ERROR] VAL-01: cgroups v2 is not available
  Current: cgroups v1 detected
  Required: cgroups v2 for rootless Podman
  Fix: Add systemd.unified_cgroup_hierarchy=1 to kernel cmdline

[WARN] VAL-02: subuid/subgid not configured for user 'username'
  Impact: Rootless mode will not work
  Fix: sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER
```

---

## Architecture Patterns

### Recommended Project Structure
```
scripts/
  preflight_check.sh     # Main validation script (standalone, can run independently)

functions.sh             # Add: preflight_* functions
setup.sh                 # Add: run_script "preflight_check.sh" as FIRST step
```

### Pattern 1: Individual Check Functions
**What:** Each validation is a separate function returning 0 (pass) or 1 (fail)
**When to use:** All pre-flight checks - enables granular error reporting

```bash
#!/bin/bash
# Source: Based on Podman official documentation and containers/podman repo

# Check if cgroups v2 is available
# Returns: 0 if v2 available, 1 if v1 or unavailable
check_cgroups_v2() {
    # Method 1: Check for cgroup.controllers file (v2 only)
    if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
        return 0
    fi

    # Method 2: Check mount type
    if findmnt -t cgroup2 /sys/fs/cgroup >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Check subuid configuration for current user
# Returns: 0 if configured, 1 if missing
check_subuid_configured() {
    local user="${1:-$(whoami)}"

    # Check /etc/subuid exists and has entry for user
    if [[ ! -f /etc/subuid ]]; then
        return 1
    fi

    if grep -q "^${user}:" /etc/subuid 2>/dev/null; then
        return 0
    fi

    return 1
}

# Check subgid configuration for current user
# Returns: 0 if configured, 1 if missing
check_subgid_configured() {
    local user="${1:-$(whoami)}"

    if [[ ! -f /etc/subgid ]]; then
        return 1
    fi

    if grep -q "^${user}:" /etc/subgid 2>/dev/null; then
        return 0
    fi

    return 1
}

# Check FUSE kernel support
# Returns: 0 if FUSE available, 1 if not
check_fuse_support() {
    # Method 1: Check /dev/fuse exists
    if [[ -c /dev/fuse ]]; then
        return 0
    fi

    # Method 2: Check kernel config (if available)
    if [[ -f /proc/filesystems ]]; then
        if grep -q "fuse" /proc/filesystems 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Check minimum kernel version
# Returns: 0 if version >= required, 1 if below
# Usage: check_kernel_version "5.11"
check_kernel_version() {
    local required="$1"
    local current

    current=$(uname -r | cut -d'-' -f1)

    # Version comparison using sort -V
    if [[ "$(echo -e "${current}\n${required}" | sort -V | head -n1)" == "${required}" ]]; then
        return 0  # current >= required
    fi

    return 1  # current < required
}

# Check for noexec mount on specified path
# Returns: 0 if safe (no noexec), 1 if noexec detected
# Usage: check_noexec_mount "/tmp"
check_noexec_mount() {
    local path="$1"

    # Use findmnt to check mount options
    # -T: use target path (follows symlinks)
    # -o OPTIONS: output only options field
    local options
    options=$(findmnt -T "$path" -o OPTIONS -n 2>/dev/null)

    if [[ "$options" =~ noexec ]]; then
        return 1  # noexec detected
    fi

    return 0  # noexec not present
}

# Get detailed mount info for error messages
get_mount_info() {
    local path="$1"
    findmnt -T "$path" 2>/dev/null || echo "unknown"
}
```

### Pattern 2: Main Validation Runner
**What:** Single entry point that runs all checks and reports results
**When to use:** setup.sh integration and standalone execution

```bash
#!/bin/bash
# Main preflight check entry point

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

preflight_error() {
    local code="$1"
    local message="$2"
    local current="$3"
    local required="$4"
    local fix="$5"

    echo -e "${RED}[ERROR] ${code}: ${message}${NC}"
    [[ -n "$current" ]] && echo "  Current: ${current}"
    [[ -n "$required" ]] && echo "  Required: ${required}"
    echo "  Fix: ${fix}"
    echo ""

    ((ERRORS++))
}

preflight_warn() {
    local code="$1"
    local message="$2"
    local impact="$3"
    local fix="$4"

    echo -e "${YELLOW}[WARN] ${code}: ${message}${NC}"
    echo "  Impact: ${impact}"
    echo "  Fix: ${fix}"
    echo ""

    ((WARNINGS++))
}

preflight_ok() {
    local code="$1"
    local message="$2"

    echo -e "${GREEN}[OK] ${code}: ${message}${NC}"
}

run_preflight_checks() {
    local start_time end_time duration

    echo "========================================"
    echo "Pre-flight Validation"
    echo "========================================"
    echo ""

    start_time=$(date +%s)

    # VAL-01: cgroups v2
    if check_cgroups_v2; then
        preflight_ok "VAL-01" "cgroups v2 available"
    else
        preflight_error "VAL-01" \
            "cgroups v2 is not available" \
            "cgroups v1 or legacy hierarchy" \
            "cgroups v2 for rootless Podman" \
            "Add systemd.unified_cgroup_hierarchy=1 to kernel cmdline and reboot"
    fi

    # VAL-02: subuid/subgid
    local user=$(whoami)
    if check_subuid_configured "$user" && check_subgid_configured "$user"; then
        preflight_ok "VAL-02" "subuid/subgid configured for ${user}"
    else
        preflight_warn "VAL-02" \
            "subuid/subgid not configured for user '${user}'" \
            "Rootless mode will not function" \
            "sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 ${user}"
    fi

    # VAL-03: FUSE support
    if check_fuse_support; then
        preflight_ok "VAL-03" "FUSE kernel support available"
    else
        preflight_error "VAL-03" \
            "FUSE kernel support not available" \
            "/dev/fuse not found" \
            "FUSE for fuse-overlayfs (rootless storage)" \
            "Install fuse3 package or enable FUSE in kernel config"
    fi

    # VAL-04: Minimum kernel version
    local kernel_version=$(uname -r | cut -d'-' -f1)
    if check_kernel_version "5.11"; then
        preflight_ok "VAL-04" "Kernel version ${kernel_version} (>= 5.11)"
    else
        preflight_warn "VAL-04" \
            "Kernel version ${kernel_version} is below recommended 5.11" \
            "Native overlay may not work; fuse-overlayfs required" \
            "Upgrade kernel to 5.11+ for native rootless overlay support"
    fi

    # VAL-05: noexec mounts
    local noexec_paths=()
    for path in /tmp "${HOME:-/home}"; do
        if ! check_noexec_mount "$path"; then
            noexec_paths+=("$path")
        fi
    done

    if [[ ${#noexec_paths[@]} -eq 0 ]]; then
        preflight_ok "VAL-05" "No noexec mounts on /tmp and /home"
    else
        preflight_error "VAL-05" \
            "noexec mount detected on: ${noexec_paths[*]}" \
            "$(get_mount_info "${noexec_paths[0]}")" \
            "Executable permission for build processes" \
            "Remove noexec from mount options in /etc/fstab, or use different build directory"
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    echo "========================================"
    echo "Validation Complete (${duration}s)"
    echo "  Errors:   ${ERRORS}"
    echo "  Warnings: ${WARNINGS}"
    echo "========================================"

    # Exit with error if any errors occurred
    if [[ $ERRORS -gt 0 ]]; then
        echo ""
        echo "Please fix the errors above before continuing installation."
        exit 1
    fi

    if [[ $WARNINGS -gt 0 ]]; then
        echo ""
        echo "Warnings detected. Installation may continue but some features may not work."
    fi

    exit 0
}

# Allow standalone execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_preflight_checks
fi
```

### Anti-Patterns to Avoid
- **Don't fail on warnings:** subuid/subgid may be intentionally skipped for rootful installs
- **Don't run slow checks:** Network requests or heavy computation violate the 5-second target
- **Don't use obscure tools:** Stick to standard utilities available on minimal Debian
- **Don't hide details:** Always show current vs required state for debugging

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Version comparison | Custom string parsing | `sort -V` | Handles edge cases like 5.10 vs 5.9 |
| Mount option parsing | Regex on /proc/mounts | `findmnt -T` | Handles bind mounts, symlinks correctly |
| User detection | $USER variable | `whoami` or `id -un` | More reliable across sudo/su contexts |

**Key insight:** The Linux ecosystem has standard tools for system introspection. Use them rather than parsing raw kernel interfaces.

---

## Common Pitfalls

### Pitfall 1: False Positive on noexec Check
**What goes wrong:** /tmp is checked directly but build actually uses /var/tmp or a subdirectory
**Why it happens:** Build scripts may use TMPDIR or hardcoded paths
**How to avoid:** Check both the literal path and TMPDIR if set
**Warning signs:** Build fails with "Permission denied" despite /tmp showing no noexec

### Pitfall 2: Kernel Version String Parsing
**What goes wrong:** uname -r returns "5.10.0-23-amd64" and naive comparison fails
**Why it happens:** Distribution-specific version suffixes
**How to avoid:** Use `cut -d'-' -f1` or `awk -F'-' '{print $1}'` before comparison
**Warning signs:** Version check incorrectly reports 5.10 < 5.11

### Pitfall 3: Subuid/Subgid Range Overlap
**What goes wrong:** Multiple users have overlapping subuid ranges
**Why it happens:** Manual editing without coordination
**How to avoid:** For preflight, just check existence; range validation is out of scope
**Warning signs:** Rootless containers can access another user's containers

### Pitfall 4: Cgroups Check on Containers
**What goes wrong:** Running preflight inside a container may see wrong cgroup view
**Why it happens:** Container namespace isolation
**How to avoid:** Check for container environment and adjust expectations
**Warning signs:** /sys/fs/cgroup appears empty or shows container-limited view

### Pitfall 5: FUSE Device Permissions
**What goes wrong:** /dev/fuse exists but user lacks read/write permissions
**Why it happens:** Device permission misconfiguration
**How to avoid:** Test actual read access, not just existence
**Warning signs:** fuse-overlayfs fails despite /dev/fuse existing

---

## Code Examples

### Detect cgroups v1 vs v2
```bash
# Source: containers/podman documentation, verified 2026-03-03

# Most reliable: check for cgroup.controllers file
# This file only exists in cgroup v2 hierarchy
if [[ -f /sys/fs/cgroup/cgroup.controllers ]]; then
    echo "cgroups v2 (unified hierarchy)"
else
    # Check for v1 by looking for named subsystems
    if ls /sys/fs/cgroup/*/ 2>/dev/null | head -1 | grep -q .; then
        echo "cgroups v1 (legacy hierarchy)"
    else
        echo "cgroups unavailable"
    fi
fi

# Alternative: use findmnt
# v2 shows: TYPE=cgroup2
# v1 shows: TYPE=cgroup or multiple mounts
findmnt -t cgroup2 /sys/fs/cgroup >/dev/null 2>&1 && echo "v2" || echo "v1 or unavailable"
```

### Verify subuid/subgid Configuration
```bash
# Source: Podman rootless setup guide, verified 2026-03-03

# Check if user has subordinate ID ranges configured
check_user_namespace_ready() {
    local user="${1:-$(whoami)}"

    # Verify /etc/subuid entry exists
    if ! grep -q "^${user}:" /etc/subuid 2>/dev/null; then
        echo "ERROR: No entry in /etc/subuid for ${user}"
        return 1
    fi

    # Verify /etc/subgid entry exists
    if ! grep -q "^${user}:" /etc/subgid 2>/dev/null; then
        echo "ERROR: No entry in /etc/subgid for ${user}"
        return 1
    fi

    # Extract and validate range
    local subuid_start subuid_count
    subuid_start=$(grep "^${user}:" /etc/subuid | cut -d: -f2)
    subuid_count=$(grep "^${user}:" /etc/subuid | cut -d: -f3)

    if [[ -z "$subuid_start" ]] || [[ -z "$subuid_count" ]]; then
        echo "ERROR: Invalid subuid format"
        return 1
    fi

    echo "OK: User ${user} has ${subuid_count} subordinate UIDs starting at ${subuid_start}"
    return 0
}
```

### Check FUSE Support
```bash
# Source: fuse-overlayfs requirements, containers/fuse-overlayfs repo

check_fuse_available() {
    # Primary check: /dev/fuse character device
    if [[ ! -c /dev/fuse ]]; then
        echo "ERROR: /dev/fuse does not exist or is not a character device"
        return 1
    fi

    # Secondary check: filesystem support
    if ! grep -q fuse /proc/filesystems 2>/dev/null; then
        echo "WARN: FUSE not in /proc/filesystems (may work if module auto-loads)"
    fi

    # Permission check: can we read/write?
    if [[ ! -r /dev/fuse ]] || [[ ! -w /dev/fuse ]]; then
        echo "ERROR: /dev/fuse exists but user lacks read/write permissions"
        return 1
    fi

    echo "OK: FUSE available at /dev/fuse"
    return 0
}
```

### Kernel Version Check with Comparison
```bash
# Source: Standard bash version comparison pattern

check_kernel_min_version() {
    local required="$1"
    local current

    # Extract version (strip everything after first '-')
    current=$(uname -r | cut -d'-' -f1)

    # Use sort -V for semver comparison
    # If required version comes first in sorted output, current >= required
    if [[ "$(printf '%s\n%s' "$required" "$current" | sort -V | head -n1)" == "$required" ]]; then
        echo "OK: Kernel ${current} >= ${required}"
        return 0
    else
        echo "WARN: Kernel ${current} < ${required}"
        return 1
    fi
}

# Usage examples:
check_kernel_min_version "5.11"  # Rootless overlay native support
check_kernel_min_version "4.18"  # Minimum for fuse-overlayfs in userns
```

### Detect noexec Mount Flags
```bash
# Source: Datadog security docs, CIS benchmarks, verified 2026-03-03

check_path_noexec() {
    local path="$1"
    local mount_info

    # findmnt -T follows symlinks and finds the mount point for any path
    # -n: no header
    # -o OPTIONS: output only options column
    mount_info=$(findmnt -T "$path" -n -o OPTIONS 2>/dev/null)

    if [[ -z "$mount_info" ]]; then
        echo "WARN: Could not determine mount options for ${path}"
        return 2  # Unknown
    fi

    # Check for noexec in comma-separated options
    if echo "$mount_info" | grep -qE '(^|,)noexec(,|$)'; then
        echo "ERROR: ${path} is mounted with noexec"
        echo "  Mount options: ${mount_info}"
        return 1
    fi

    echo "OK: ${path} allows execution"
    return 0
}

# Check critical paths
for path in /tmp "${HOME:-/home}" "${BUILD_ROOT:-/build}"; do
    check_path_noexec "$path"
done
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Parse /proc/mounts with regex | Use findmnt utility | Standard for years | Handles edge cases correctly |
| Assume root user | Support rootless first-class | Podman ~2019 | Security by default |
| Check single cgroup path | Check cgroup.controllers | cgroups v2 adoption | More reliable detection |
| Minimum kernel 4.18 | Recommend 5.11+ | Kernel 5.11 (2021) | Native overlay support |

**Deprecated/outdated:**
- `mount | grep` for checking mount options: Use `findmnt` instead - handles bind mounts correctly
- Checking only `/etc/subuid` existence: Must verify user entry exists
- Assuming FUSE requires root: fuse-overlayfs works in user namespaces since kernel 4.18

---

## Integration with Existing Codebase

### setup.sh Changes
```bash
# Add after sourcing config.sh and functions.sh, before any run_script calls:

# Pre-flight Validation (before any build operations)
echo ""
echo ">>> Running pre-flight validation..."
source "${toolpath}/scripts/preflight_check.sh"
```

### functions.sh Additions
```bash
# Add preflight check functions to functions.sh for reusability
# (See code examples above for function definitions)
```

### Standalone Execution
```bash
# Users can run preflight checks independently:
./scripts/preflight_check.sh

# Or source and call individual checks:
source scripts/preflight_check.sh
check_cgroups_v2 && echo "OK" || echo "FAIL"
```

---

## Open Questions

1. **Should preflight checks be mandatory or optional?**
   - What we know: Current design has errors (hard stop) and warnings (continue with caution)
   - What's unclear: Should there be a --skip-preflight option for advanced users?
   - Recommendation: No skip option - if users know enough to skip, they can edit the script

2. **Should kernel version < 5.11 be an error or warning?**
   - What we know: Kernel 5.11+ enables native overlay for rootless; 4.18+ works with fuse-overlayfs
   - What's unclear: Project currently builds fuse-overlayfs, so 4.18 may be sufficient
   - Recommendation: Make 5.11 a warning, 4.18 an error. Most users should have 5.11+ by now

3. **Should subuid/subgid check be skipped for root execution?**
   - What we know: Root doesn't need subuid/subgid for podman
   - What's unclear: Should we detect root and skip, or always warn?
   - Recommendation: Detect EUID=0 and skip the check entirely with an info message

---

## Sources

### Primary (HIGH confidence)
- **containers/podman** - Rootless mode requirements, cgroups v2 detection patterns
- **containers/fuse-overlayfs** (GitHub) - Kernel requirements (4.18+ for userns, 5.11+ for native overlay)
- **Podman official documentation** - subuid/subgid configuration, rootless setup guide

### Secondary (MEDIUM confidence)
- **OneUptime blog (2026)** - Podman rootless setup guide, mount option security
- **Medium (2020)** - Rootless Podman setup walkthrough with cgroups v2 enablement
- **Red Hat Blog (2021)** - Podman rootless overlay support, kernel version requirements
- **Datadog Security Docs** - noexec mount detection using findmnt

### Tertiary (LOW confidence)
- N/A - All core patterns verified with primary sources

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Standard Linux utilities, well-documented interfaces
- Architecture: HIGH - Pattern based on existing project structure and Podman conventions
- Pitfalls: HIGH - Common issues documented across multiple sources

**Research date:** 2026-03-03
**Valid until:** 2027-03-03 (kernel requirements stable, cgroups v2 is now standard)
