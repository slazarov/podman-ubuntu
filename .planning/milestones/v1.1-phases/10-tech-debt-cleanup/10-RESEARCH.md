# Phase 10: Tech Debt Cleanup - Research

**Researched:** 2026-03-04
**Domain:** Shell script maintenance / integration gap closure
**Confidence:** HIGH

## Summary

Phase 10 closes two specific integration gaps identified by the v1.1 milestone audit (MISSING-01 and BROKEN-01) plus resolves the informational tech debt item (INFO-01). The work is entirely within existing shell scripts -- no new tools, libraries, or external dependencies are involved.

**MISSING-01** is an asymmetric cleanup issue: `install_dependencies.sh` conditionally installs `mold` and `clang` apt packages when `MOLD_ENABLED=true`, but `uninstall.sh` has zero references to removing these packages. By contrast, sccache (binary removal) and ccache (cache directory removal) both have proper cleanup paths.

**BROKEN-01** is a redundant operation: `containers.conf` is copied twice during a full setup -- once at the end of `build_podman.sh` (lines 62-63, a pre-v1.1 copy) and again at the end of `setup.sh` (lines 111-112, added by Phase 08). The second copy is the canonical one added by design. The first copy in `build_podman.sh` is legacy code that predates the v1.1 configuration work and should be removed.

**Primary recommendation:** Remove the `containers.conf` copy from `build_podman.sh` (lines 61-63), and add conditional `apt-get remove` for `mold clang` to `uninstall.sh`, gated on whether those packages are actually installed. Both changes are small, surgical, and low-risk.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CACHE-07 | Add MOLD_ENABLED feature flag for mold linker (opt-in, default false) | Integration gap: mold apt package not removed during uninstall (MISSING-01). The feature flag itself works; the gap is in cleanup symmetry. |
| CACHE-08 | Conditionally install mold+clang via apt when MOLD_ENABLED=true | Integration gap: clang apt package not removed during uninstall (MISSING-01). install_dependencies.sh:83-85 installs; uninstall.sh has no counterpart. |
| CONF-03 | Install containers.conf to /etc/containers/containers.conf during setup | Integration gap: containers.conf installed twice (BROKEN-01). build_podman.sh:62-63 copies it (legacy), setup.sh:111-112 copies it (Phase 08 canonical). Remove the legacy copy. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 5.x | All scripts in this project use bash | Project standard since v1.0 |
| apt-get | System | Package management on Debian/Ubuntu | Only package manager used by this project |
| dpkg | System | Package query (check if installed) | Used by existing `remove_if_user_installed` in functions.sh |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| set -euo pipefail | N/A | Strict mode | Every script in this project uses it |

### Alternatives Considered
None. This is maintenance work within existing scripts using existing patterns.

## Architecture Patterns

### Existing Project Structure (relevant files)
```
podman-debian/
  config.sh              # Feature flags: MOLD_ENABLED, CCACHE_ENABLED, etc.
  setup.sh               # Main entry point -- runs all scripts, installs containers.conf at end
  uninstall.sh           # Cleanup script -- removes binaries, caches, configs
  functions.sh           # Shared functions (remove_if_user_installed, etc.)
  config/
    containers.conf      # Configuration template
  scripts/
    install_dependencies.sh  # apt-get installs (including conditional mold+clang)
    build_podman.sh          # Builds podman (has legacy containers.conf copy)
    build_netavark.sh        # Uses mold when MOLD_ENABLED=true
    build_aardvark_dns.sh    # Uses mold when MOLD_ENABLED=true
```

### Pattern 1: Feature-Flag-Gated apt Cleanup
**What:** When a feature flag controls installation of apt packages, the uninstall script should conditionally remove those packages using `dpkg -s` to check if they are installed before attempting removal.
**When to use:** Any time the project conditionally installs system packages.
**Example (from existing ccache cache cleanup pattern in uninstall.sh):**
```bash
# Remove ccache cache
safe_rm_dir "/var/cache/ccache" "ccache cache"
```
**Equivalent for apt packages:**
```bash
# Remove mold and clang if they were installed by us
# Use dpkg -s to check if package is installed before attempting removal
if dpkg -s mold &>/dev/null; then
    apt-get remove -y mold
    REMOVED+=("apt package: mold")
fi
if dpkg -s clang &>/dev/null; then
    apt-get remove -y clang
    REMOVED+=("apt package: clang")
fi
```

### Pattern 2: Existing Uninstall Tracking Pattern
**What:** `uninstall.sh` uses two arrays (`REMOVED[]` and `SKIPPED[]`) to track what was cleaned up and prints a summary at the end.
**When to use:** Any new cleanup operations must follow this pattern.
**Key functions:**
- `safe_rm_dir()` -- removes directory with tracking
- `safe_rm_file()` -- removes file with tracking
- `safe_make_uninstall()` -- runs make uninstall with tracking
- New apt removal should append to `REMOVED[]` / `SKIPPED[]` for consistency.

### Pattern 3: Canonical Configuration Install Location
**What:** `setup.sh` installs configuration files AFTER all build steps complete. This was established in Phase 08 (CONF-03).
**When to use:** Configuration installation belongs in `setup.sh`, not in individual build scripts.
**Evidence:** `setup.sh` lines 103-113 -- the "Install Configuration" section is the canonical location.

### Anti-Patterns to Avoid
- **apt-get remove without checking if installed:** Running `apt-get remove mold` when mold is not installed will fail (or at minimum produce confusing output). Always check with `dpkg -s` first.
- **apt-get purge in uninstall:** The project uses `remove` semantics (remove binaries, keep config), not `purge` (remove everything). Using `purge` would be inconsistent with the rest of the uninstall script which does targeted file removal.
- **Removing packages that might be user-installed:** The project installs mold/clang only when MOLD_ENABLED=true. If the user had mold/clang installed independently before running setup, removing them would be destructive. Consider checking if the packages were installed by this tool or are used by other things. However, the existing pattern in the project does NOT track this -- it uses simple presence checks. Follow the existing pattern for consistency.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Package presence check | Custom file checks | `dpkg -s <package>` | Standard Debian way to check if package is installed |
| Conditional removal | Complex version tracking | Simple `dpkg -s` + `apt-get remove -y` | Matches project's existing approach to cleanup |

**Key insight:** This is cleanup code. Keep it simple, follow existing patterns, avoid over-engineering.

## Common Pitfalls

### Pitfall 1: apt-get remove Failing on Non-Installed Packages
**What goes wrong:** Calling `apt-get remove mold` when mold is not installed causes apt to return an error or noisy warning.
**Why it happens:** apt-get remove does not silently skip missing packages.
**How to avoid:** Gate removal with `dpkg -s mold &>/dev/null` check first.
**Warning signs:** Error messages from apt during uninstall on systems that never enabled MOLD_ENABLED.

### Pitfall 2: Removing clang When Other Things Depend on It
**What goes wrong:** User has other software that depends on clang; removing it breaks their system.
**Why it happens:** apt-get remove cascades to remove dependent packages by default.
**How to avoid:** Use `apt-get remove -y --no-remove-recommends` or accept this risk since the tool runs as root and is for dedicated build systems. The existing project pattern does not guard against this for any other packages (it removes /etc/containers entirely, for example). Follow existing pattern.
**Warning signs:** apt-get showing unexpected dependent package removal during uninstall.

### Pitfall 3: Forgetting DEBIAN_FRONTEND=noninteractive
**What goes wrong:** apt-get remove prompts for confirmation interactively.
**Why it happens:** Not setting DEBIAN_FRONTEND before apt commands.
**How to avoid:** `uninstall.sh` already sets `export DEBIAN_FRONTEND=noninteractive` at line 4. All apt commands in the script inherit this. No action needed.

### Pitfall 4: Leaving build_podman.sh Post-Install Section Empty
**What goes wrong:** Removing the containers.conf copy from build_podman.sh leaves the "Post-install configuration" step with nothing to do, which is confusing.
**Why it happens:** The step_start/step_done block would be empty.
**How to avoid:** Remove the entire step block (lines 61-63), not just the mkdir/cp lines.

### Pitfall 5: Ordering in uninstall.sh
**What goes wrong:** apt-get remove runs after /etc/containers is already deleted, and apt complains about missing config.
**Why it happens:** Wrong ordering of cleanup operations.
**How to avoid:** Place apt package removal BEFORE directory cleanup. Currently, `/etc/containers` removal is at line 177. Place apt removal well before that.

## Code Examples

### Fix MISSING-01: Add mold/clang Removal to uninstall.sh
```bash
# Source: Audit finding MISSING-01 from v1.1-MILESTONE-AUDIT.md
# Place this BEFORE the "Remove configuration directories" section

# Remove mold and clang apt packages (installed by MOLD_ENABLED=true)
if dpkg -s mold &>/dev/null; then
    apt-get remove -y mold
    REMOVED+=("apt package: mold")
else
    SKIPPED+=("apt package: mold (not installed)")
fi

if dpkg -s clang &>/dev/null; then
    apt-get remove -y clang
    REMOVED+=("apt package: clang")
else
    SKIPPED+=("apt package: clang (not installed)")
fi
```

### Fix BROKEN-01: Remove Redundant containers.conf Copy from build_podman.sh
```bash
# Source: Audit finding BROKEN-01 from v1.1-MILESTONE-AUDIT.md
# REMOVE these 3 lines from build_podman.sh (lines 61-63):

# step_start "Post-install configuration"
# sudo mkdir -p /etc/containers
# sudo cp "${toolpath}/config/containers.conf" /etc/containers/containers.conf
# step_done

# The canonical install is in setup.sh lines 111-112
```

### After Fix: build_podman.sh Should End At
```bash
step_start "Installing"
run_logged sudo make GO="$GOPATH/go" install PREFIX=/usr
step_done
# (end of file -- no post-install configuration section)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| containers.conf copied in build_podman.sh | containers.conf installed in setup.sh after all builds | Phase 08 (2026-03-04) | Redundant copy left behind in build_podman.sh |
| No mold/clang in project | Conditional mold/clang install | Phase 09 (2026-03-04) | Uninstall path was missed |

**Deprecated/outdated:**
- `build_podman.sh` lines 61-63: Legacy containers.conf copy that predates Phase 08's canonical installation in setup.sh. Should be removed.

## Open Questions

1. **Should ccache apt package also be removed during uninstall?**
   - What we know: ccache is installed via `apt-get install -y ccache` in install_dependencies.sh (line 78). The uninstall.sh removes the ccache *cache directory* (`/var/cache/ccache`) but does NOT remove the ccache *apt package* itself.
   - What's unclear: This was NOT flagged by the audit as a gap (probably because ccache is a common development tool and less intrusive than mold+clang). However, it is technically the same asymmetry.
   - Recommendation: Include ccache apt package removal for symmetry, but this is optional and not required by the phase requirements. Flag it for the planner to decide.

2. **INFO-01: CCACHE_MAXSIZE/CCACHE_COMPILERCHECK implicit consumption**
   - What we know: These variables are exported in config.sh and consumed implicitly by the ccache binary from the environment. No explicit reference in build scripts.
   - What's unclear: The audit marked this as "informational only" -- not a bug, just implicit coupling.
   - Recommendation: Add a brief comment in the relevant C build scripts noting that ccache reads CCACHE_MAXSIZE and CCACHE_COMPILERCHECK from the environment (set in config.sh). This is optional documentation-level improvement, not a functional fix.

## Sources

### Primary (HIGH confidence)
- `v1.1-MILESTONE-AUDIT.md` -- Defines MISSING-01, BROKEN-01, INFO-01 gaps
- `uninstall.sh` -- Current state: no mold/clang removal (verified line by line)
- `build_podman.sh` -- Current state: lines 61-63 copy containers.conf (verified)
- `setup.sh` -- Current state: lines 111-112 are the canonical containers.conf install (verified)
- `install_dependencies.sh` -- Current state: lines 77-85 conditionally install ccache and mold+clang (verified)
- `config.sh` -- Feature flags MOLD_ENABLED, CCACHE_ENABLED confirmed (verified)

### Secondary (MEDIUM confidence)
- Phase 09-02 SUMMARY -- Confirms what was implemented and what cleanup paths were added

### Tertiary (LOW confidence)
None. All findings are from direct source code analysis.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No new tools, all existing project patterns
- Architecture: HIGH - Direct code analysis of all affected files
- Pitfalls: HIGH - Based on actual code structure and apt-get behavior (well-known)

**Research date:** 2026-03-04
**Valid until:** Indefinite (tech debt resolution, no external dependency version concerns)
