# Architecture

**Analysis Date:** 2026-03-02

## Pattern Overview

**Overall:** Multi-stage build orchestrator with dependency injection

**Key Characteristics:**
- Declarative configuration with environment variable overrides
- Modular build system with separate components
- Error handling with strict mode and centralized traps
- Architecture-aware build configuration
- Git-based version management with auto-detection

## Layers

**Configuration Layer:**
- Purpose: Centralized configuration management and architecture detection
- Location: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/config.sh`
- Contains: Architecture mappings, version variables, path configurations
- Depends on: functions.sh (for detection functions)
- Used by: All build scripts and setup.sh

**Function Library Layer:**
- Purpose: Shared utilities and common operations
- Location: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/functions.sh`
- Contains: Git operations, version fetching, logging, error handling
- Depends on: Bash built-ins only
- Used by: config.sh and all build scripts

**Build Orchestrator Layer:**
- Purpose: Main installation coordinator
- Location: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/setup.sh`
- Contains: Installation sequence, component tracking, error management
- Depends on: config.sh, functions.sh, scripts directory
- Used by: Direct execution by user

**Component Build Layer:**
- Purpose: Individual component build logic
- Location: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/scripts/`
- Contains: 18 specialized build scripts for each component
- Depends on: config.sh, functions.sh, build directory structure
- Used by: setup.sh script

## Data Flow

**Installation Flow:**

1. **Initialization**: setup.sh sets strict mode and loads configuration
2. **Environment Setup**: config.sh detects architecture and sets variables
3. **Dependency Installation**: install_dependencies.sh installs system dependencies
4. **Toolchain Installation**: rust, protoc, go installed
5. **Component Building**: Each component built in sequence:
   - Repository cloned/updated via git_clone_update()
   - Specific version checked out via git_checkout()
   - Component built with appropriate build system
   - Installation logged via log_component()
6. **Configuration**: containers.conf copied to enable helper binary discovery

**State Management:**
- Environment variables passed through chain
- Build artifacts installed to /usr and /usr/local
- Logs written to ${toolpath}/log/YYYYMMDD.log
- Version tracking via GIT_CHECKED_OUT_TAG

## Key Abstractions

**Architecture Abstraction:**
- Purpose: Normalize architecture naming across components
- Examples: `config.sh`, `functions.sh` (detect_architecture)
- Pattern: Case statement mapping uname to vendor strings

**Version Management Abstraction:**
- Purpose: Handle version detection and tagging
- Examples: `get_latest_tag()`, `get_latest_go_version()`, `get_latest_protoc_version()`
- Pattern: Git tag sorting and API-based version fetching

**Build Process Abstraction:**
- Purpose: Standardize component building pattern
- Examples: All scripts in `scripts/` directory
- Pattern: Clone → Checkout → Build → Install → Log

## Entry Points

**Main Entry Point:**
- Location: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/setup.sh`
- Triggers: Direct execution by user
- Responsibilities: Orchestrate full installation sequence

**Component Entry Points:**
- Location: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/scripts/build_*.sh`
- Triggers: Called by setup.sh
- Responsibilities: Build individual components

## Error Handling

**Strategy:** Centralized error handling with strict mode

**Patterns:**
- `set -euo pipefail` for script-level error handling
- `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR` for centralized error capture
- Consistent error messages with script name, line number, and exit code
- Debug instruction: `bash -x <script>` for troubleshooting

## Cross-Cutting Concerns

**Logging:** Centralized logging with timestamps to ${toolpath}/log/YYYYMMDD.log
**Configuration:** Environment variable driven with sensible defaults
**Version Management:** Auto-detection of latest versions with override capability
**Architecture Support:** Multi-architecture builds (amd64, arm64) with proper mapping

---

*Architecture analysis: 2026-03-02*