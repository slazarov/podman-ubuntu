# Phase 6: Component Cleanup - Research

**Researched:** 2026-03-03
**Domain:** Bash shell script cleanup, deprecated component removal, Podman ecosystem verification
**Confidence:** HIGH

## Summary

Phase 6 involves removing deprecated build scripts and their references from the Podman Debian Compiler project. The deprecated components are **runc** (replaced by crun) and **slirp4netns** (replaced by pasta). Both replacements are already in place and functional in the project.

This research validates the technology decisions through multiple external sources. The Podman ecosystem has decisively moved away from both runc and slirp4netns: **Podman 6.0 (expected mid-2026) will formally remove slirp4netns support entirely**, cgroups v1 support, and BoltDB. crun has been the default OCI runtime on cgroups v2 systems since Podman 4.x, and pasta became the default rootless networking tool in Podman 5.0. Both replacements are actively maintained (crun v1.26 released December 2025; passt/pasta under active weekly development).

The cleanup work is purely deletion-based: removing files, removing configuration variables, and removing function calls. No new code is needed -- only removals.

**Primary recommendation:** Systematically delete all references to runc and slirp4netns. No new code needed -- only removals. The Podman ecosystem has fully validated this direction.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLNP-01 | Remove build_runc.sh -- crun is 50% faster, 8x less memory, Podman's default since 2021 | Verified: crun v1.26 (Dec 2025) is actively maintained; Podman defaults to crun on cgroups v2 systems; runc is not deprecated per se but crun has priority selection in Podman. File exists at `scripts/build_runc.sh` -- DELETE |
| CLNP-02 | Remove build_slirp4netns.sh -- pasta is the documented replacement with better performance | Verified: pasta is default since Podman 5.0; slirp4netns formally removed in Podman 6.0; pasta offers 4-50x IPv4 TCP throughput improvement. File exists at `scripts/build_slirp4netns.sh` -- DELETE |
| CLNP-03 | Remove runc and slirp4netns references from install.sh and config.sh | See detailed reference tables below for all locations requiring cleanup |
</phase_requirements>

## Technology Validation

### crun vs runc -- Ecosystem Status

| Property | crun | runc |
|----------|------|------|
| Latest version | v1.26 (Dec 22, 2025) | Actively maintained but lower priority in Podman |
| Language | C | Go |
| Memory footprint | ~8x less than runc | Baseline |
| Startup speed | ~50% faster | Baseline |
| Podman default | Yes (on cgroups v2 systems) | Fallback when crun unavailable |
| OCI spec compliance | Full | Full |
| Maintainer | containers/ (Red Hat backed) | opencontainers/ |
| Podman 6.0 status | Continues as default | Still supported but not default |

**Key finding:** crun has priority over runc in Podman's runtime selection. When both are installed, Podman selects crun. On cgroups v2 systems (which are standard on modern kernels), crun is the explicit default. The project already builds crun via `build_crun.sh` -- no changes needed there.

**Confidence:** HIGH -- verified via GitHub releases page (crun v1.26, Dec 2025), Red Hat documentation, Podman official docs, and multiple community sources.

### pasta vs slirp4netns -- Ecosystem Status

| Property | pasta (passt) | slirp4netns |
|----------|---------------|-------------|
| Podman default since | v5.0 (mid-2024) | Was default pre-5.0 |
| Performance | 4-50x IPv4 TCP throughput | Baseline |
| IPv6 support | Full | Limited |
| Architecture | Separate process, modern Linux isolation | User-mode NAT-based |
| Podman 6.0 status | Only supported option | **Formally removed** |
| Configuration | `default_rootless_network_cmd = "pasta"` | Deprecated option |
| Container-to-host | Fixed in Podman 5.3 (169.254.1.2 default) | Worked via NAT |

**Key finding:** Podman 6.0 (expected mid-2026) **removes slirp4netns support entirely**, including the `--slirp4netns` option and `--network-cmd-path`. This is not just a deprecation -- the code is being deleted from Podman itself. The project already builds pasta via `build_pasta.sh` -- no changes needed there.

**Confidence:** HIGH -- verified via Fedora Podman6 wiki changes page, Podman rootless tutorial, Oracle documentation, and multiple community sources.

### Podman Version Timeline (Context)

| Version | Date | Relevant Changes |
|---------|------|------------------|
| 4.1 | 2022 | pasta integration added |
| 5.0 | 2024 | pasta becomes default; CNI removed |
| 5.3 | Late 2024 | pasta container-to-host fix (169.254.1.2) |
| 5.8 | Feb 12, 2026 | Current latest stable |
| 6.0 | Mid-2026 (expected) | slirp4netns removed; cgroups v1 removed; BoltDB removed |

## Standard Stack

### Core (Active -- DO NOT MODIFY)
| Component | Status | Purpose | Why Standard |
|-----------|--------|---------|--------------|
| crun | Active (keep) | OCI runtime | 50% faster, 8x less memory, Podman default on cgroups v2, v1.26 Dec 2025 |
| pasta | Active (keep) | Rootless networking | Podman default since 5.0, only option in 6.0, 4-50x throughput |

### Deprecated (REMOVE)
| Component | Status | Replacement | Why Remove |
|-----------|--------|-------------|------------|
| runc | Deprecated in project | crun | crun superior in all metrics; Podman selects crun over runc when both present |
| slirp4netns | Deprecated in Podman | pasta | Formally removed in Podman 6.0; pasta is 4-50x faster |

## Architecture Patterns

### File Reference Pattern
The project uses a consistent pattern where each component has:
1. Build script: `scripts/build_<component>.sh`
2. Version variable: `<COMPONENT>_TAG` in `config.sh`
3. Execution call: `run_script "build_<component>.sh"` in `setup.sh`
4. Uninstall handling: Multiple cleanup references in `uninstall.sh`
5. Git ignore entry: `<component>/` in `.gitignore`

### Cleanup Pattern
When removing a component, follow this sequence:
1. Delete the build script from `scripts/`
2. Remove version variables from `config.sh`
3. Remove the `run_script` call from `setup.sh`
4. Remove uninstall references from `uninstall.sh`
5. Remove from `.gitignore` if present
6. Remove dependency declarations from `install_dependencies.sh`

## Detailed Reference Analysis

### runc References (6 locations)

| File | Line(s) | Content | Action |
|------|---------|---------|--------|
| `scripts/build_runc.sh` | 1-53 | Entire file | DELETE FILE |
| `config.sh` | 118-121 | `RUNC_TAG` variable (4 lines) | DELETE |
| `setup.sh` | 85 | `run_script "build_runc.sh"` | DELETE |
| `uninstall.sh` | 97 | `safe_make_uninstall "${BUILD_ROOT}/runc" "runc"` | DELETE |
| `uninstall.sh` | 139 | `safe_rm_file "/usr/local/bin/runc" "binary"` | DELETE |
| `uninstall.sh` | 172 | `safe_rm_file "/usr/local/bin/runc" "binary"` | DELETE |
| `.gitignore` | 13 | `runc/` entry | DELETE |

### slirp4netns References (5 locations)

| File | Line(s) | Content | Action |
|------|---------|---------|--------|
| `scripts/build_slirp4netns.sh` | 1-56 | Entire file | DELETE FILE |
| `config.sh` | 133-136 | `SLIRP4NETNS_TAG` variable (4 lines) | DELETE |
| `setup.sh` | 91 | `run_script "build_slirp4netns.sh"` | DELETE |
| `uninstall.sh` | 93-94 | `safe_make_uninstall "${BUILD_ROOT}/slirp4netns" "slirp4netns"` | DELETE |
| `uninstall.sh` | 135 | `for f in /usr/local/share/man/man1/slirp4netns*; do` loop | DELETE |
| `scripts/install_dependencies.sh` | 66-67 | `# Dependencies for building slirp4netns` + apt-get | DELETE |

### Active Replacements (DO NOT MODIFY)

| Component | Build Script | Config Variable | Setup Call | Status |
|-----------|--------------|-----------------|------------|--------|
| crun | `scripts/build_crun.sh` | `CRUN_TAG` | Line 67 | Active |
| pasta | `scripts/build_pasta.sh` | (no tag - uses date) | Line 79 | Active |

## Code Examples

### config.sh - Section to Remove (runc)
```bash
# Lines 118-121 - DELETE
# Runc Version
#export RUNC_VERSION="1.3.0"
#export RUNC_TAG="v${RUNC_VERSION}"
export RUNC_TAG="${RUNC_TAG:-}"
```

### config.sh - Section to Remove (slirp4netns)
```bash
# Lines 133-136 - DELETE
# Slirp4netns Version
#export SLIRP4NETNS_VERSION="1.3.3"
#export SLIRP4NETNS_TAG="v${SLIRP4NETNS_VERSION}"
export SLIRP4NETNS_TAG="${SLIRP4NETNS_TAG:-}"
```

### setup.sh - Lines to Remove
```bash
# Line 85 - DELETE
run_script "build_runc.sh"

# Line 91 - DELETE
run_script "build_slirp4netns.sh"
```

### uninstall.sh - Lines to Remove (runc)
```bash
# Line 97 - DELETE
safe_make_uninstall "${BUILD_ROOT}/runc" "runc"

# Line 139 - DELETE
safe_rm_file "/usr/local/bin/runc" "binary"

# Line 172 - DELETE (duplicate entry)
safe_rm_file "/usr/local/bin/runc" "binary"
```

### uninstall.sh - Lines to Remove (slirp4netns)
```bash
# Lines 93-94 - DELETE
# Uninstall slirp4netns
safe_make_uninstall "${BUILD_ROOT}/slirp4netns" "slirp4netns"

# Lines 135-137 - DELETE
for f in /usr/local/share/man/man1/slirp4netns*; do
    safe_rm_file "$f" "man page"
done 2>/dev/null || true
```

### install_dependencies.sh - Lines to Remove
```bash
# Lines 66-67 - DELETE
# Dependencies for building slirp4netns
apt-get install -y libglib2.0-dev libslirp-dev libcap-dev libseccomp-dev
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| OCI runtime | runc | crun | 50% faster, 8x less memory, Podman default since 2021, v1.26 actively maintained |
| Rootless networking | slirp4netns | pasta | Podman default since 5.0, formally removed in 6.0, 4-50x throughput improvement |

**Key insight:** Both deprecated components are not just inferior -- they are being actively removed from the Podman ecosystem. Podman 6.0 will not support slirp4netns at all. Keeping these build scripts would confuse users and waste build time compiling components that modern Podman does not need.

## Common Pitfalls

### Pitfall 1: Orphaned References
**What goes wrong:** Removing files but leaving references causes script failures.
**Why it happens:** Incomplete search for all usages.
**How to avoid:** Use systematic grep search for both `runc` and `slirp4netns` before and after changes.
**Warning signs:** Script exits with "file not found" or "command not found" errors.

### Pitfall 2: Uninstall Script Duplication
**What goes wrong:** Missing one of the duplicate uninstall entries leaves cleanup code.
**Why it happens:** runc binary removal appears twice in uninstall.sh (lines 139 and 172).
**How to avoid:** Verify both occurrences are removed.
**Warning signs:** Uninstall script still references removed components.

### Pitfall 3: Breaking Dependency Order
**What goes wrong:** Removing items from setup.sh without verifying build order.
**Why it happens:** Not understanding the component dependency chain.
**How to avoid:** runc and slirp4netns are at the end of the build order; removing them does not affect other components.
**Warning signs:** Build failures for components that should be independent.

### Pitfall 4: Shared Dependencies
**What goes wrong:** Removing dependencies that are also needed by other components.
**Why it happens:** Some dependencies are shared (e.g., libseccomp-dev is used by both slirp4netns and crun).
**How to avoid:** Verify that `libglib2.0-dev`, `libslirp-dev`, `libcap-dev`, and `libseccomp-dev` are not needed by remaining components. Note: `libseccomp-dev` IS used by crun (line 59 of install_dependencies.sh), so only the slirp4netns-specific comment block should be removed.
**Warning signs:** Build failures for crun or other components.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| runc as OCI runtime | crun as default | Podman 4.x (cgroups v2 default) | 50% faster startup, 8x less memory |
| slirp4netns for rootless | pasta as default | Podman 5.0 (mid-2024) | 4-50x throughput, full IPv6, better security |
| CNI networking | Netavark | Podman 5.0 (CNI removed) | Modern network stack |
| BoltDB database | SQLite | Podman 4.8 (default), 6.0 (BoltDB removed) | Better reliability |
| iptables | nftables | Podman 6.0 (iptables removed from Netavark) | Modern firewall |

**Deprecated/outdated:**
- **slirp4netns**: Formally removed in Podman 6.0. The `--slirp4netns` option and `--network-cmd-path` are deleted.
- **runc**: Still supported but crun has priority selection. Not removed from Podman 6.0 but clearly secondary.
- **cgroups v1**: Removed in Podman 6.0.
- **BoltDB**: Removed in Podman 6.0.

## Verification Checklist

After cleanup, verify:
1. `ls scripts/build_runc.sh` returns "No such file or directory"
2. `ls scripts/build_slirp4netns.sh` returns "No such file or directory"
3. `grep -n "runc" config.sh` returns no matches
4. `grep -n "slirp4netns" config.sh` returns no matches
5. `grep -n "runc" setup.sh` returns no matches
6. `grep -n "slirp4netns" setup.sh` returns no matches
7. `grep -rn "RUNC_TAG\|SLIRP4NETNS_TAG" --include="*.sh" .` returns no matches
8. `grep -rn "build_runc\|build_slirp4netns" --include="*.sh" .` returns no matches
9. Active replacements remain intact: `build_crun.sh` and `build_pasta.sh` exist

## Open Questions

None. This is a straightforward cleanup phase with no ambiguity. The ecosystem has clearly validated the direction.

## Sources

### Primary (HIGH confidence)
- [crun GitHub Releases](https://github.com/containers/crun/releases) -- v1.26 released Dec 22, 2025, confirms active maintenance
- [Podman rootless tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md) -- Confirms pasta default since 5.0
- [Fedora Podman6 Changes](https://fedoraproject.org/wiki/Changes/Podman6) -- Confirms slirp4netns removal in Podman 6.0
- [Podman endoflife.date](https://endoflife.date/podman) -- Podman 5.8 (Feb 2026) is current stable
- Direct codebase analysis -- All files read and analyzed for reference locations

### Secondary (MEDIUM confidence)
- [Oracle: Use Pasta Networking with Podman](https://docs.oracle.com/en/learn/ol-podman-pasta-networking/) -- Confirms pasta as modern replacement
- [Red Hat: Introduction to crun](https://www.redhat.com/en/blog/introduction-crun) -- Performance comparison data
- [Red Hat: Selecting a container runtime](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/building_running_and_managing_containers/selecting-a-container-runtime_building-running-and-managing-containers) -- crun vs runc selection behavior
- [passt.top](https://passt.top/passt/about/) -- Official passt/pasta project page, confirms 4-50x throughput
- [Podman 5.3 rootless networking enhancements](https://linuxiac.com/podman-5-3-promises-an-enhanced-rootless-networking/) -- pasta improvements in 5.3

### Tertiary (LOW confidence)
- None -- all findings verified through multiple sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- Verified via GitHub releases, official docs, multiple sources
- Architecture: HIGH -- Direct codebase analysis, well-documented project patterns
- Pitfalls: HIGH -- Simple deletion task with clear scope, shared dependency concern verified
- Technology validation: HIGH -- crun and pasta confirmed as correct replacements via Podman official docs, Red Hat docs, and community sources

**Research date:** 2026-03-03
**Valid until:** 2026-06-03 (stable -- deprecation decisions are permanent; Podman 6.0 release may further validate)
