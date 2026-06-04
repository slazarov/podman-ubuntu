<!-- generated-by: gsd-doc-writer -->
# Development

This guide covers local development of the podman-ubuntu build and packaging
pipeline: how to set up a working tree, the scripts that drive each stage, code
style conventions, and the branch and PR process.

The project is a **shell-orchestrated build pipeline**, not an application.
There is no `package.json`, no compiler, and no application server. "Building"
the project means running the pipeline that compiles the upstream Podman stack
from source and packages it into `.deb` files. See
[ARCHITECTURE.md](ARCHITECTURE.md) for the full pipeline overview.

## Local Setup

The pipeline compiles Linux packages and must run on Debian or Ubuntu (it is
tested on Ubuntu 24.04, amd64 and arm64). You can edit the shell scripts on any
platform, but running the build requires a Debian/Ubuntu host (or VM/container).

1. Fork the repository on GitHub, then clone your fork:

   ```bash
   git clone https://github.com/<your-username>/podman-ubuntu.git
   cd podman-ubuntu
   ```

2. Add the upstream remote so you can pull in changes:

   ```bash
   git remote add upstream https://github.com/slazarov/podman-ubuntu.git
   ```

3. No dependency install step is required for editing. The pipeline installs its
   own toolchain (Go, Rust, protoc, and system build dependencies) at build time
   via `scripts/install_*.sh`. The Go and Rust versions are auto-detected from
   upstream sources (Podman's `go.mod` and Netavark's `Cargo.toml`), so you do
   not pin them manually.

4. To run a full local build (compiles all 12 components from source — this is
   slow and writes to system paths, so prefer a disposable VM or container):

   ```bash
   source versions-stable.env
   sudo -E ./setup.sh
   ```

   The `-E` flag preserves the version-pin environment variables sourced from
   `versions-stable.env`. Without it, the build falls back to the empty defaults
   in `config.sh` and auto-detects the latest upstream tags (edge behavior).

### Build Tracks During Development

The same scripts serve three release tracks, selected entirely by environment:

| Track | How to invoke | Behavior |
|-------|---------------|----------|
| **stable** | `source versions-stable.env && sudo -E ./setup.sh` | Builds the pinned tags in `versions-stable.env`. |
| **edge** | `sudo ./setup.sh` (no version env sourced) | Leaves component tags empty so the latest upstream tag is auto-detected. |
| **nightly** | `sudo NIGHTLY_BUILD=true SHALLOW_CLONE=false ./setup.sh` | Builds from upstream HEAD; full (non-shallow) clones. |

`versions-nightly.env` holds nightly-specific overrides and can be sourced the
same way as `versions-stable.env`.

## Build Commands

There is no task runner; the pipeline is a set of shell scripts invoked
directly. Run all of them from the repository root unless noted.

| Command | Description |
|---------|-------------|
| `sudo -E ./setup.sh` | Top-level orchestrator. Runs pre-flight validation, installs the toolchain, then compiles and installs all 12 components into the `DESTDIR` staging tree. |
| `sudo ./uninstall.sh` | Removes all components previously installed from source. |
| `./scripts/preflight_check.sh` | Validates the host (sourced and run by `setup.sh`; can be inspected standalone). |
| `./scripts/build_<component>.sh` | Builds a single component (e.g. `build_conmon.sh`, `build_podman.sh`). Sources `config.sh`/`functions.sh` on its own, so it can run independently for iterating on one component. |
| `./scripts/install_dependencies.sh` | Installs system build dependencies via `apt`. |
| `./scripts/install_go.sh` / `install_rust.sh` / `install_protoc.sh` | Install the auto-detected toolchain versions. |
| `./scripts/package_all.sh` | Converts the `DESTDIR` staging tree into `.deb` packages with nFPM, writing them to `output/`. Requires `DESTDIR` to be set and `nfpm` on `PATH`. |
| `./scripts/repo_manage.sh` | Builds a single-suite reprepro APT repository from packages. |
| `./scripts/ci_publish.sh` | Multi-suite repository assembly and `index.html` generation, used by CI. |

Key environment variables that influence a build (defined with defaults in
`config.sh`):

| Variable | Default | Purpose |
|----------|---------|---------|
| `DESTDIR` | unset | Staging tree where compiled artifacts are installed before packaging. |
| `NPROC` | `$(nproc)` | Parallel job count for `make`/`cargo`. |
| `SHALLOW_CLONE` | `true` | Shallow-clones upstream repos (~95% less transfer); set `false` for nightly/debugging. |
| `NIGHTLY_BUILD` | unset | Builds from upstream HEAD instead of a tag. |
| `SCCACHE_ENABLED` | `false` | Enables sccache for Rust build caching (50-90% rebuild speedup). |
| `CCACHE_ENABLED` | `false` | Enables ccache for C build caching (~30x warm-cache rebuilds). |
| `MOLD_ENABLED` | `false` | Enables the mold linker for Rust builds (5-10x faster linking). |
| `GOCACHE` / `GOMODCACHE` | `/var/cache/go-build`, `/var/cache/go-mod` | Persisted Go caches shared across component builds. |

## Code Style

The codebase is Bash. There are no committed linter or formatter configuration
files (no `.shellcheckrc`, `.editorconfig`, or equivalent) and CI does not run a
shell linter. Style is enforced by convention; follow the patterns already
present in `scripts/`:

- **Shebang + strict mode.** Every script starts with `#!/bin/bash` followed by
  `set -euo pipefail` (exit on error, undefined-variable guard, pipe-failure
  propagation).
- **Toolpath bootstrap.** Each script computes `toolpath` and sources
  `config.sh` and `functions.sh` before doing work, so it can be run from any
  directory or sourced by `setup.sh`:

  ```bash
  relativepath="../"
  if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi
  source "${toolpath}/config.sh"
  source "${toolpath}/functions.sh"
  ```

- **Error trap.** After sourcing config/functions, install the shared trap:
  `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR`.
- **Shared helpers.** Use the functions in `functions.sh` rather than inlining
  logic — `git_clone_update` / `git_checkout` for cloning, `run_logged` for
  verbose build output, `step_start` / `step_done` for progress markers, and
  `detect_architecture` for arch handling.
- **Environment defaults.** Make settings overridable with the
  `${VAR:-default}` pattern (as done throughout `config.sh`) so the same script
  serves all three release tracks.
- **Quote variable expansions** (`"${VAR}"`) and indent with 4 spaces inside
  functions, matching the existing scripts.

Recommended (not enforced) before opening a PR: run
[ShellCheck](https://www.shellcheck.net/) over any scripts you touched.

## Branch Conventions

The default branch is `main`. There is no documented branch-naming policy file
in the repository. Observed practice from history is to create short
topic/feature branches (for example, a versioned feature branch such as
`v2.0-apt-packaging`) and merge them into `main`. When contributing, branch off
`main` with a descriptive name, e.g. `fix/crun-json-c-dependency` or
`feat/arm64-toolbox`.

Commit messages follow the [Conventional Commits](https://www.conventionalcommits.org/)
style used across the existing history. Common prefixes seen in the log:

- `feat:` — new functionality
- `fix:` — bug fixes (often scoped, e.g. `fix(ci):`, `fix(packaging):`)
- `ci:` — CI/workflow changes
- `chore:` — tooling and housekeeping

## PR Process

See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution guidelines. There is
no `.github/PULL_REQUEST_TEMPLATE.md` in the repository, so the following is the
conventional process for this project:

- Branch off `main` and keep each PR focused on a single concern (a single
  component fix, one CI change, etc.).
- Write commit messages in Conventional Commits style (see above).
- For changes that affect the build, validate on a Debian/Ubuntu host. At
  minimum confirm the affected `scripts/build_<component>.sh` runs cleanly into a
  `DESTDIR` staging tree; ideally run the full `sudo -E ./setup.sh`.
- Run the test suite and ensure it passes (see [TESTING.md](TESTING.md)).
- If you change versioning, packaging metadata, or repository layout, exercise
  `scripts/package_all.sh` and confirm `.deb` files are produced in `output/`.
- Open the PR against `slazarov/podman-ubuntu` `main`. The GitHub Actions
  workflow (`.github/workflows/build-packages.yml`) builds packages on native
  amd64 and arm64 runners; ensure your change does not break that pipeline.

## Next Steps

- [ARCHITECTURE.md](ARCHITECTURE.md) — how the build pipeline fits together.
- [TESTING.md](TESTING.md) — running and writing tests.
- [apt-repository.md](apt-repository.md) — the published APT repository and
  per-package details.
