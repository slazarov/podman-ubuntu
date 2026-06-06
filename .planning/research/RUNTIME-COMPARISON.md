# OCI Runtime Comparison: crun vs runc vs Alternatives

**Context:** Podman build ecosystem audit - determining optimal default runtime and whether both are needed
**Researched:** 2026-03-03
**Confidence:** HIGH (Official documentation, GitHub repos, benchmark data from README files)

## Quick Recommendation

**Default:** **crun** - Faster, lower memory footprint, Podman's default since 2021
**Keep runc?** **NO** - Not necessary for typical Podman use cases; crun is superior for all metrics that matter
**Alternatives:** youki (Rust, promising but less mature), gvisor/runsc (for security sandboxing only)

---

## Executive Summary

crun is a C-based OCI runtime developed by the containers organization (same as Podman). It was specifically designed to address runc's performance and memory limitations. For Podman deployments, crun is the clear choice - it's the default runtime in Podman since 2021 and offers:

- **~50% faster** container startup times
- **Much lower memory footprint** (can run containers with as little as 512KB memory vs 4MB+ for runc)
- **Better rootless support** (designed with rootless containers in mind)
- **Active development** by the same team as Podman
- **Same OCI compliance** as runc - drop-in replacement

runc remains the "reference implementation" but has no technical advantages over crun for Podman use cases.

---

## Performance Benchmarks

### Container Startup Time (100 sequential /bin/true containers)

| Runtime | Time | vs crun |
|---------|------|---------|
| **crun** | 1.69s | baseline |
| runc | 3.34s | +97% slower |

**Source:** crun official README (containers/crun GitHub)

### Memory Constraints

```bash
# runc fails with 4M memory limit
podman --runtime /usr/bin/runc run --rm --memory 4M fedora echo it works
# Error: container_linux.go:346: starting container process caused...

# crun succeeds with 512KB memory limit
podman --runtime /usr/bin/crun run --rm --memory 512k fedora echo it works
# it works
```

**Source:** crun official README

### youki Benchmark (from youki README)

| Runtime | Time (mean) | vs youki |
|---------|-------------|----------|
| **crun** | 47.3ms | baseline (fastest) |
| youki | 111.5ms | 2.4x slower than crun |
| runc | 224.6ms | 4.7x slower than crun |

**Source:** youki benchmark (youki-dev/youki GitHub, youki v0.3.3 vs runc v1.1.7 vs crun v1.15)

---

## Feature Comparison Matrix

| Feature | crun | runc | youki | gvisor/runsc |
|---------|------|------|-------|--------------|
| **Language** | C | Go | Rust | Go |
| **OCI Runtime Spec** | Full | Full | Full | Full |
| **Memory Footprint** | Minimal | High | Medium | High |
| **Startup Speed** | Fastest | Slowest | Medium | Slowest |
| **Rootless Support** | Excellent | Good | Good | Good |
| **CRIU Checkpoint/Restore** | Yes | Yes | No | No |
| **Systemd Cgroup** | Yes | Yes | Yes | Yes |
| **cgroup v2** | Yes | Yes | Yes | Yes |
| **cgroup v1** | Yes (deprecated) | Yes | Yes | Yes |
| **Seccomp** | Yes | Yes | Yes | N/A |
| **AppArmor** | Yes | Yes | Yes | N/A |
| **SELinux** | Yes | Yes | Yes | N/A |
| **krun (VM isolation)** | Yes | No | No | No |
| **WASM handlers** | Yes (wasmedge, wasmer, wamr) | No | No | No |
| **Security Sandbox** | Standard | Standard | Standard | **Enhanced** |
| **Podman Default** | **Yes** | No | No | No |

---

## Detailed Analysis

### crun (Recommended)

**Repository:** https://github.com/containers/crun
**Latest Release:** v1.26 (2025-12-22)
**Stars:** 3,805 | Forks: 387 | Contributors: Active (containers org)

**Strengths:**
- **Performance:** Fastest OCI runtime available (50%+ faster than runc)
- **Memory Efficiency:** Minimal footprint - works with severely constrained containers (512KB)
- **Native C implementation:** No Go runtime overhead, direct system calls
- **Library mode:** Can be embedded as library, not just CLI
- **krun integration:** Built-in VM isolation via libkrun for enhanced security
- **WASM support:** Native WebAssembly handlers (wasmedge, wasmer, wamr)
- **Active development:** Regular releases, same org as Podman
- **Rootless-first:** Designed with rootless containers as primary use case

**Weaknesses:**
- C codebase (memory safety concerns vs Rust, though well-audited)
- Smaller community than runc

**Best for:**
- Podman deployments (official default)
- Resource-constrained environments
- High-density container workloads
- Rootless container use cases
- Production deployments where startup time matters

### runc

**Repository:** https://github.com/opencontainers/runc
**Latest Release:** v1.4.0 (2025-11-27)
**Stars:** 13,093 | Forks: 2,263 | Contributors: Active (OpenContainers org)

**Strengths:**
- **Reference implementation:** The original OCI runtime
- **Widest adoption:** Docker, containerd, and many others use runc
- **Mature codebase:** Battle-tested over many years
- **Extensive documentation:** Large community knowledge base
- **Security audited:** Third-party audit by Cure53

**Weaknesses:**
- **Go runtime overhead:** Re-execs itself, uses C module for setup anyway
- **Higher memory footprint:** Requires 4MB+ for basic containers
- **Slower startup:** Nearly 2x slower than crun
- **No krun equivalent:** No built-in VM isolation option

**Best for:**
- Docker/containerd environments (historical default)
- Environments requiring OCI reference implementation
- Debugging/compatibility testing

### youki (Rust Alternative)

**Repository:** https://github.com/youki-dev/youki
**Stars:** 7,259 | Forks: 410

**Strengths:**
- **Rust implementation:** Memory-safe, modern language
- **Better than runc:** ~2x faster than runc in benchmarks
- **Clean architecture:** Well-structured codebase
- **Active development:** Growing community
- **Passed containerd e2e tests:** Production-ready claims

**Weaknesses:**
- **Slower than crun:** ~2.4x slower than crun in benchmarks
- **Less mature:** Fewer production deployments than crun/runc
- **Smaller ecosystem:** Fewer integrations, less community knowledge

**Best for:**
- Environments prioritizing memory safety
- Rust-based container toolchains
- Experimental/alternative deployments

### gvisor/runsc (Security-Focused)

**Repository:** https://github.com/google/gvisor
**Stars:** 17,819 | Forks: 1,522

**Strengths:**
- **Application kernel:** Provides strong isolation from host kernel
- **Memory-safe Go:** Written in memory-safe language
- **Sandbox containers:** Designed for untrusted workload isolation
- **Kubernetes integration:** Works with GKE, Anthos

**Weaknesses:**
- **Significant overhead:** Not a drop-in replacement for performance
- **Different threat model:** Designed for isolation, not speed
- **Compatibility:** Some applications don't work in gvisor sandbox

**Best for:**
- Running untrusted containers
- Multi-tenant environments
- High-security requirements
- NOT for general-purpose Podman use

---

## Podman-Specific Considerations

### Current Integration

1. **crun is Podman's default runtime** since 2021
2. Both scripts (`build_crun.sh` and `build_runc.sh`) currently build both runtimes
3. Podman auto-detects available runtimes
4. Runtime can be specified per-container: `podman --runtime crun run ...`

### Configuration

```bash
# In containers.conf (Podman configuration)
[engine]
runtime = "crun"

# Or per-command override
podman --runtime crun run ...
podman --runtime runc run ...
```

### Migration Path

If currently using runc:
```bash
# 1. Install crun (already in build scripts)
sudo make install  # from crun build

# 2. Verify crun works
crun --version

# 3. Update Podman default (containers.conf)
# Or rely on auto-detection (Podman prefers crun if both present)

# 4. Remove runc (optional)
sudo rm /usr/local/bin/runc
```

---

## Recommendation

### Primary Runtime: crun ONLY

**Rationale:**
1. **Performance:** 50%+ faster than runc
2. **Memory:** Can run containers with 512KB vs 4MB+ for runc
3. **Integration:** Podman's default, developed by same team
4. **Features:** krun for VM isolation, WASM support
5. **Maintenance burden:** No need to maintain two runtime builds

### Action Items

1. **Keep crun build script** - It's the optimal choice
2. **Remove runc build script** - No technical justification for keeping it
3. **Update documentation** - Explain crun-only decision
4. **If users need runc** - They can install from distro packages for debugging

### When to Consider Alternatives

| Scenario | Recommended Runtime |
|----------|---------------------|
| Standard Podman deployment | **crun** |
| Memory-constrained environments | **crun** |
| Running untrusted workloads | **gvisor/runsc** (in addition to crun) |
| WASM containers | **crun** (native support) |
| VM-isolated containers | **crun with krun** |
| Docker/containerd compatibility testing | runc (install separately if needed) |
| Rust-only toolchain preference | youki |

---

## Build Script Analysis

### Current State

**build_crun.sh:**
- Clones from https://github.com/containers/crun.git
- Uses autogen/configure/make (C build system)
- Depends on: autoconf, automake, libtool, libseccomp, libcap, yajl, systemd
- Parallel make: `make -j "$NPROC"`
- Installs to /usr/local/bin

**build_runc.sh:**
- Clones from https://github.com/opencontainers/runc.git
- Uses Go build (make with Go toolchain)
- Build tags: `selinux seccomp apparmor`
- Parallel make: `make -j "$NPROC"`
- Installs to /usr/local/bin/runc
- Go optimizations: GOGC, GCFLAGS, LDFLAGS

### Recommendation: Remove build_runc.sh

The runc build adds:
- Go compilation time (~2-5 minutes)
- Maintenance burden for version updates
- Binary that provides no advantage over crun
- ~15MB additional installed binary

**Savings:** Remove runc build = faster installation, less maintenance, no functional loss.

---

## Sources

| Source | Type | Confidence |
|--------|------|------------|
| [crun GitHub README](https://github.com/containers/crun) | Official documentation | HIGH |
| [runc GitHub README](https://github.com/opencontainers/runc) | Official documentation | HIGH |
| [youki GitHub README](https://github.com/youki-dev/youki) | Official documentation | HIGH |
| [gvisor GitHub README](https://github.com/google/gvisor) | Official documentation | HIGH |
| [crun NEWS changelog](https://github.com/containers/crun/blob/main/NEWS) | Release history | HIGH |
| [Podman Installation Docs](https://podman.io/docs/installation) | Official documentation | HIGH |
| GitHub API (repo stats, releases) | Primary source data | HIGH |
| Existing project scripts (build_crun.sh, build_runc.sh) | Code analysis | HIGH |

---

## Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Performance benchmarks | HIGH | Direct from crun/youki official READMEs |
| Feature comparison | HIGH | Official documentation for all runtimes |
| Podman compatibility | HIGH | crun is Podman's documented default |
| Recommendation | HIGH | Clear technical superiority of crun |
| Alternative runtimes | MEDIUM | youki/gvisor are less common in Podman context |

---

*Runtime comparison research for: Podman Debian Compiler v1.1 Ecosystem Audit*
*Researched: 2026-03-03*
