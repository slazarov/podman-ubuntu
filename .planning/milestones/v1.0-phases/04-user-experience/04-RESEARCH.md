# Phase 4: User Experience - Research

**Researched:** 2026-03-02
**Domain:** Bash scripting UX patterns (progress reporting, logging, uninstall scripts)
**Confidence:** HIGH

## Summary

This phase focuses on improving user-facing aspects of the installation scripts without changing what gets installed. The three requirements (UX-01, UX-02, UX-03) map to three distinct implementation areas: step-level progress messages within build scripts, capturing verbose build output to log files, and hardening the uninstall script with skip-on-missing logic and summary output.

The codebase already has foundational patterns in place: `run_script()` wrapper in setup.sh, `log_component()` in functions.sh, `error_handler()` with proper trap usage, and `remove_if_user_installed()` for safe package removal. These should be extended rather than replaced.

**Primary recommendation:** Extend existing functions in functions.sh with timing and logging capabilities, add step-level echo statements to each build script, and rewrite uninstall.sh with graceful skip logic and summary reporting.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Progress Granularity**
- Step-level progress within each script (not just script-level "Starting/Completed")
- Show all significant operations: Clone, Checkout, Log version, Pre-build fixes, Build, Install, Post-install config
- Hierarchical format with indented sub-steps under script headers for visual hierarchy
- Show per-step elapsed time AND total script time when each script completes

**Build Output Logging**
- Capture full build output (stdout/stderr) to log files
- Per-component log files: `logs/build_podman.log`, `logs/build_crun.log`, etc.
- Suppress verbose build output on console — show only progress messages
- Store logs in existing `logs/` directory (alongside version logs)

**Uninstall Robustness**
- Skip gracefully when components weren't installed or directories don't exist (no errors)
- Show detailed summary at end: what was removed, what was skipped, any manual cleanup needed
- No confirmation prompt before uninstalling (runs immediately)
- Use strict mode (`set -euo pipefail`) with error handler like other scripts

**Progress Presentation Style**
- Simple text markers (e.g., `>>> Cloning repository...`, `>>> Done: Cloning repository (45s)`)
- No progress bars or spinner animations

### Claude's Discretion
- Exact wording of progress messages
- Timestamp format for elapsed time
- Summary output format for uninstall

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| UX-01 | Progress messages show current operation | Step-level progress pattern using echo with timing; see Architecture Patterns below |
| UX-02 | Build output logged to files | Output redirection with tee; per-component log files in logs/ directory |
| UX-03 | Uninstall script exists and works | Graceful skip logic with test -d/-f; summary arrays for reporting |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 4.0+ | Script runtime | Project already requires bash; uses bash-specific features (${var:-default}, [[ ]]) |
| GNU date | system | Timing calculations | Supports %s for epoch seconds; available on all Debian/Ubuntu |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| tee | coreutils | Dual output (console + file) | Build output logging |
| grep -q | system | Silent existence checks | Skip-on-missing logic in uninstall |

### No External Dependencies
This phase requires no new external dependencies. All functionality is achievable with standard bash and coreutils available on Debian/Ubuntu.

## Architecture Patterns

### Recommended Pattern: Progress Functions in functions.sh

Add new functions to functions.sh that build scripts will call:

```bash
# Source: Established bash pattern for progress tracking
# Format elapsed seconds to human-readable (MM:SS or HH:MM:SS)
format_duration() {
    local seconds=$1
    local minutes=$((seconds / 60))
    local secs=$((seconds % 60))
    if [[ $minutes -ge 60 ]]; then
        local hours=$((minutes / 60))
        minutes=$((minutes % 60))
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [[ $minutes -gt 0 ]]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

# Start a progress step (records start time)
step_start() {
    local step_name="$1"
    export _STEP_NAME="$step_name"
    export _STEP_START=$(date +%s)
    echo "  ${step_name}..."
}

# Complete a progress step (shows elapsed time)
step_done() {
    local step_end=$(date +%s)
    local elapsed=$((step_end - _STEP_START))
    echo "  Done: ${_STEP_NAME} ($(format_duration $elapsed))"
}
```

### Pattern: Step-Level Progress in Build Scripts

Each build script wraps its operations in step_start/step_done calls:

```bash
# Source: Context.md specified format
# Example for build_podman.sh
cd "${BUILD_ROOT}"
step_start "Cloning repository"
git_clone_update https://github.com/containers/podman.git podman
cd "${BUILD_ROOT}/podman"
step_done

step_start "Checking out tag"
git_checkout "${PODMAN_TAG}"
step_done

step_start "Logging version"
log_component "podman"
step_done

step_start "Applying pre-build fixes"
sed -Ei "s|^go 1.22.6$|go 1.23|" go.mod
step_done

step_start "Building"
make GO="$GOPATH/go" BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr
step_done

step_start "Installing"
sudo make GO="$GOPATH/go" install PREFIX=/usr
step_done

step_start "Post-install configuration"
sudo mkdir -p /etc/containers
sudo cp "${toolpath}/config/containers.conf" /etc/containers/containers.conf
step_done
```

### Pattern: Build Output Logging

Redirect verbose output to log files while showing progress on console:

```bash
# Source: Standard bash output redirection pattern
# In functions.sh
log_build_start() {
    local component="$1"
    export BUILD_LOG="${toolpath}/log/build_${component}.log"
    mkdir -p "$(dirname "$BUILD_LOG")"
    echo "Build log: ${component}" > "$BUILD_LOG"
    echo "Started: $(date)" >> "$BUILD_LOG"
}

# Usage in build scripts for verbose commands
make GO="$GOPATH/go" BUILDTAGS="..." 2>&1 | tee -a "$BUILD_LOG" > /dev/null
```

### Pattern: Graceful Uninstall with Skip Logic

```bash
# Source: Established bash pattern for safe removal
# Arrays to track results
declare -a REMOVED=()
declare -a SKIPPED=()
declare -a MANUAL=()

# Safe directory removal with tracking
safe_rm_dir() {
    local dir="$1"
    local description="$2"
    if [[ -d "$dir" ]]; then
        rm -rf "$dir"
        REMOVED+=("$description: $dir")
    else
        SKIPPED+=("$description: $dir (not found)")
    fi
}

# Safe file removal with tracking
safe_rm_file() {
    local file="$1"
    local description="$2"
    if [[ -f "$file" ]]; then
        rm -f "$file"
        REMOVED+=("$description: $file")
    else
        SKIPPED+=("$description: $file (not found)")
    fi
}

# Summary output at end
echo ""
echo "========================================"
echo "Uninstall Summary"
echo "========================================"
echo "Removed:"
for item in "${REMOVED[@]}"; do echo "  - $item"; done
echo ""
echo "Skipped (not found):"
for item in "${SKIPPED[@]}"; do echo "  - $item"; done
```

### Pattern: Extended run_script() with Timing

Enhance the existing run_script() in setup.sh:

```bash
# Source: Extends existing run_script() pattern
run_script() {
    local script="$1"
    local script_start=$(date +%s)

    echo ""
    echo "========================================"
    echo ">>> Starting: ${script}"
    echo "========================================"

    source "${toolpath}/scripts/${script}"

    local script_end=$(date +%s)
    local elapsed=$((script_end - script_start))

    echo ">>> Completed: ${script} in $(format_duration $elapsed)"
    COMPONENTS_OK+=("${script}")
}
```

### Anti-Patterns to Avoid
- **Silent failures:** Do not use `|| true` on critical operations; only on existence checks
- **Inconsistent formatting:** All build scripts must use identical step message format
- **Missing timing:** Every step must have both start and done with elapsed time
- **Hardcoded paths:** Use ${toolpath} and ${BUILD_ROOT} variables, not literal paths

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Elapsed time display | Custom arithmetic in each script | `format_duration()` function | Consistent format, one place to update |
| Progress tracking | Ad-hoc echo statements | `step_start()`/`step_done()` pair | Ensures timing accuracy, consistent indentation |
| Existence checks before removal | Nested if statements | `safe_rm_*()` functions | Cleaner code, consistent tracking |
| Log file management | Scattered redirection | Centralized logging functions | Easier debugging, consistent log format |

**Key insight:** The existing codebase already has good patterns (error_handler, remove_if_user_installed). Extend these rather than creating competing approaches.

## Common Pitfalls

### Pitfall 1: Blocking Pipe with tee
**What goes wrong:** Using `tee` without redirection can cause script to wait for output that never comes
**Why it happens:** tee writes to both file and stdout; if stdout isn't consumed, buffer fills
**How to avoid:** Always redirect tee's stdout: `command 2>&1 | tee file.log > /dev/null`
**Warning signs:** Script hangs during build steps with logging

### Pitfall 2: Timing Precision Loss
**What goes wrong:** Using `date` without +%s gives human-readable time that's hard to calculate with
**Why it happens:** Date formatting varies by locale; string parsing is fragile
**How to avoid:** Always use `date +%s` for epoch seconds, format only for display
**Warning signs:** Negative elapsed times, incorrect durations

### Pitfall 3: Uninstall Continue on Error
**What goes wrong:** `set -e` causes uninstall to stop on first missing file
**Why it happens:** Strict mode exits on any error, including "file not found" on rm
**How to avoid:** Check existence BEFORE rm: `[[ -f "$file" ]] && rm "$file"` or use rm -f
**Warning signs:** Partial uninstall, orphaned files remaining

### Pitfall 4: Variable Scope in Sourced Scripts
**What goes wrong:** Variables set in build scripts don't persist to run_script() for timing
**Why it happens:** Each source call runs in same shell but export is needed for some contexts
**How to avoid:** Use export for timing variables; or calculate timing in run_script() itself
**Warning signs:** Timing shows 0s or empty variable errors

### Pitfall 5: Inconsistent Indentation in Hierarchical Output
**What goes wrong:** Progress messages don't align properly under script headers
**Why it happens:** Mixing tabs and spaces, or different indentation depths
**How to avoid:** Standardize on 2-space indentation for sub-steps; use echo "  message"
**Warning signs:** Jagged output, hard to read hierarchy

## Code Examples

### Complete Progress Step Pattern
```bash
# Source: Consolidated pattern from CONTEXT.md specification
# In functions.sh:

# Track script timing (called by run_script)
declare -g _SCRIPT_START=0

script_start() {
    export _SCRIPT_START=$(date +%s)
}

script_done() {
    local script_name="$1"
    local end=$(date +%s)
    local elapsed=$((end - _SCRIPT_START))
    echo ">>> Completed: ${script_name} in $(format_duration $elapsed)"
}

# Format duration helper
format_duration() {
    local seconds=$1
    if [[ $seconds -ge 3600 ]]; then
        printf "%dh %dm %ds" $((seconds/3600)) $(((seconds%3600)/60)) $((seconds%60))
    elif [[ $seconds -ge 60 ]]; then
        printf "%dm %ds" $((seconds/60)) $((seconds%60))
    else
        printf "%ds" $seconds
    fi
}
```

### Complete Uninstall Function Pattern
```bash
# Source: Robust uninstall pattern with tracking
# In functions.sh or uninstall.sh:

uninstall_component() {
    local component="$1"
    local build_dir="${BUILD_ROOT}/${component}"

    if [[ -d "$build_dir" ]]; then
        cd "$build_dir"
        if make uninstall 2>/dev/null; then
            REMOVED+=("make uninstall: $component")
        else
            # make uninstall failed or doesn't exist
            SKIPPED+=("make uninstall: $component (failed or no target)")
        fi
    else
        SKIPPED+=("build directory: $build_dir (not found)")
    fi
}
```

### Build Output Logging Pattern
```bash
# Source: Standard bash redirection with logging
# In build scripts, replace:
# make GO="$GOPATH/go" BUILDTAGS="..."

# With:
BUILD_LOG="${toolpath}/log/build_podman.log"
step_start "Building"
{
    echo "=== Build started: $(date) ==="
    make GO="$GOPATH/go" BUILDTAGS="seccomp apparmor systemd" PREFIX=/usr 2>&1
    echo "=== Build completed: $(date) ==="
} >> "$BUILD_LOG"
step_done
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Silent script execution | Script-level "Starting/Completed" | Phase 3 | Users know which script is running |
| Script-level only | Step-level progress with timing | Phase 4 | Users see granular progress and can estimate remaining time |
| Build output to console | Build output to log files | Phase 4 | Console stays readable; full logs available for debugging |
| Uninstall with errors | Graceful skip with summary | Phase 4 | Uninstall always completes; users know what was removed |

**Deprecated/outdated:**
- `set -e` comment in uninstall.sh: Should use `set -euo pipefail` with trap
- Direct `rm -rf` without checks: Use safe_rm_* functions with tracking
- Bare `echo` for progress: Use step_start/step_done for consistent format

## Open Questions

1. **Build log rotation**
   - What we know: Logs will accumulate over multiple runs
   - What's unclear: Should old logs be retained or rotated?
   - Recommendation: For v1, append to logs (simple). Add rotation in v2 if needed.

2. **Parallel build logging**
   - What we know: Current setup.sh runs scripts sequentially
   - What's unclear: If parallel builds added later, how to handle interleaved logs?
   - Recommendation: Design log filenames with PID or timestamp if parallel builds are added. Not needed for sequential v1.

## Validation Architecture

> Skipped — workflow.nyquist_validation is not set in .planning/config.json

The config shows `"verifier": true` but no `nyquist_validation` field, indicating the validation architecture section is not required.

## Sources

### Primary (HIGH confidence)
- Project codebase analysis (setup.sh, functions.sh, uninstall.sh, build scripts) - Direct examination of existing patterns
- CONTEXT.md - User decisions and specifications for this phase

### Secondary (MEDIUM confidence)
- Bash manual (man bash) - Timing, redirection, and array patterns
- GNU coreutils documentation - tee, date, rm behavior

### Tertiary (LOW confidence)
- None required - this phase uses well-established bash patterns that don't require external verification

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No new dependencies; extends existing bash patterns
- Architecture: HIGH - Patterns derived from existing codebase structure
- Pitfalls: HIGH - Well-known bash gotchas with established solutions

**Research date:** 2026-03-02
**Valid until:** N/A - Stable bash patterns with no version dependencies
