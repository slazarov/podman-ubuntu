# Technology Stack

**Analysis Date:** 2026-03-02

## Languages

**Primary:**
- Bash - Installation and build scripts
- Go - Podman and component development
- Rust - Runtime components (CRUN)

**Secondary:**
- C - Low-level container runtime components
- C++ - Container runtime components
- Dockerfile - Container test images

## Runtime

**Environment:**
- Linux (amd64/arm64) - Target platform
- Debian/Ubuntu - Base distribution
- Podman - Container runtime

**Package Manager:**
- apt - System package management
- No lockfile - Direct package installation

## Frameworks

**Core:**
- Go 1.23+ - Podman development
- Rust toolchain - CRUN compilation
- Protocol Buffers - Component communication

**Build/Dev:**
- Make - Build system for components
- Git - Source code management
- Rustup - Rust toolchain installation

## Key Dependencies

**Critical:**
- Podman - Container orchestration system
- Buildah - Container image building
- Skopeo - Container image manipulation
- Netavark - Container networking
- Aardvark DNS - Container DNS resolution
- Runc - Container runtime OCI implementation
- CRUN - Alternative container runtime

**Infrastructure:**
- Rust - CRUN development
- Go - Podman and helper binaries
- Protocol Buffers - RPC/IPC communication
- Btrfs - Filesystem support
- AppArmor - Security framework
- Seccomp - syscall filtering
- systemd - System integration

## Configuration

**Environment:**
- Architecture detection (amd64/arm64)
- Version auto-detection from GitHub API
- Build paths in `/opt/` directory
- Non-interactive package installation

**Build:**
- config.sh - Version and path configuration
- functions.sh - Shared build functions
- containers.conf - Podman configuration

## Platform Requirements

**Development:**
- Ubuntu/Debian Linux
- Internet access for Git/HTTP downloads
- sudo privileges for installation

**Production:**
- Linux kernel with container support
- systemd for service management
- AppArmor/Seccomp for security

---

*Stack analysis: 2026-03-02*
