# Codebase Structure

**Analysis Date:** 2026-03-02

## Directory Layout

```
/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/
├── config/                    # Configuration files
│   └── containers.conf         # Podman configuration for helper binaries
├── scripts/                   # Build scripts for each component
│   ├── install_*.sh           # Installation scripts
│   └── build_*.sh            # Component build scripts
├── build/                     # Build directory for cloned repositories
│   ├── podman/               # Podman source
│   ├── aardvark-dns/         # Aardvark DNS source
│   ├── netavark/            # Netavark source
│   ├── crun/                # CRUN source
│   ├── runc/                # RUNC source
│   ├── conmon/              # Conmon source
│   ├── buildah/             # Buildah source
│   ├── skopeo/              # Skopeo source
│   ├── fuse-overlayfs/      # Fuse-OverlayFS source
│   ├── slirp4netns/         # Slirp4NetNS source
│   ├── passt/               # Passt source
│   ├── pasta/               # Pasta source
│   ├── catatonit/           # Catatonit source
│   ├── toolbox/             # Toolbox source
│   ├── go-md2man/           # Go-MD2Man source
│   └── go/                  # Go toolchain
├── log/                      # Build logs
├── setup.sh                  # Main installation script
├── uninstall.sh              # Uninstallation script
├── config.sh                # Configuration management
├── functions.sh             # Shared functions library
└── README.md                # Project documentation
```

## Directory Purposes

**Root Directory:**
- Purpose: Main project directory and entry points
- Contains: Setup scripts, configuration, documentation
- Key files: `setup.sh`, `config.sh`, `functions.sh`

**config/ Directory:**
- Purpose: Runtime configuration files
- Contains: `containers.conf` for Podman helper binary discovery
- Key files: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/config/containers.conf`

**scripts/ Directory:**
- Purpose: Component build and installation logic
- Contains: 18 build scripts + 2 installation scripts
- Key files:
  - `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/scripts/install_dependencies.sh`
  - `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/scripts/build_podman.sh`

**build/ Directory:**
- Purpose: Working directory for source code and builds
- Contains: Cloned repositories and build artifacts
- Key directories: Each component has its own subdirectory

**log/ Directory:**
- Purpose: Build operation logs
- Contains: Daily log files with installation/update tracking

## Key File Locations

**Entry Points:**
- `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/setup.sh`: Main installation orchestrator
- `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/uninstall.sh`: Component removal

**Configuration:**
- `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/config.sh`: Central configuration and architecture detection
- `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/functions.sh`: Shared utilities

**Core Logic:**
- `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/scripts/`: All component build scripts
- `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/config/containers.conf`: Podman runtime config

**Testing:**
- No dedicated test directory (scripts are the testable units)

## Naming Conventions

**Files:**
- `setup.sh`, `uninstall.sh`: Main scripts
- `config.sh`: Configuration management
- `functions.sh`: Shared functions
- `install_*.sh`: Installation helpers
- `build_*.sh`: Component builders

**Directories:**
- Lowercase with hyphens: `build/`, `scripts/`, `config/`
- Component names: `podman/`, `aardvark-dns/`, `netavark/`

**Variables:**
- UPPERCASE: Environment variables and configuration
- Lowercase: Local variables in functions

**Functions:**
- snake_case: `detect_architecture()`, `git_clone_update()`
- Verbs: `log_component()`, `error_handler()`

## Where to Add New Code

**New Component:**
- Implementation: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/scripts/build_<component>.sh`
- Add to setup.sh: Insert `run_script "build_<component>.sh"` in installation sequence
- Create build directory: `/Users/slazarov/Documents/Scripts/Python/zhipu-projects/podman-debian/build/<component>/`

**New Configuration Option:**
- Add to config.sh: New environment variable with default
- Update documentation: Describe the new option and its purpose

**New Function:**
- Add to functions.sh: New utility function
- Document usage: Add comment explaining the function's purpose and parameters

**New Build Dependency:**
- Update install_dependencies.sh: Add new system package
- Update all relevant build scripts: Add dependency check if needed

## Special Directories

**build/ Directory:**
- Purpose: Contains cloned source repositories
- Generated: Yes (via git_clone_update)
- Committed: No (gitignored)

**log/ Directory:**
- Purpose: Installation and update logs
- Generated: Yes (created by log_component function)
- Committed: No (contains only runtime data)

---

*Structure analysis: 2026-03-02*