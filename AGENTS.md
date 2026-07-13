# AGENTS.md

Guidance for AI agents working in this repository.

## What This Project Is

A **shell-orchestrated build pipeline** (not an application) that compiles the
Podman container stack (12 components) from upstream source on Ubuntu 24.04 and
26.04 (amd64 + arm64), packages it into `.deb` files with nFPM, and publishes a
reprepro APT repository via GitHub Pages across three release tracks — **stable**
(Podman 6.x, auto-updated within the major via a resolver), **v5** (Podman 5.x
maintenance, same resolver), **nightly** (upstream HEAD, daily CI) — each
published as a per-distro suite (`{track}-{2404,2604}`). stable/v5 read a policy
file (`versions-{stable,v5}.env`: `*_SERIES` caps + `STABLE_SOAK_DAYS` soak
window) that `scripts/resolve_versions.sh` materializes into concrete `*_TAG`s.

There is no package.json, no compiler, no app server. Everything is Bash.

## Critical Constraints

- **Builds only run on Debian/Ubuntu (Linux).** The dev machine may be macOS —
  you can edit scripts but cannot execute the pipeline locally. Don't try to
  "verify" by running `setup.sh` or `build_*.sh` outside Linux; use
  `bash -n <script>` for syntax checks and reason through the logic instead.
  For real execution, use a disposable Ubuntu VM/container or CI.
- `setup.sh` writes to system paths and requires root — full builds belong in a
  disposable VM/container or CI.
- The same scripts serve all three release tracks, selected **entirely by
  environment variables** (`${VAR:-default}` pattern in `config.sh`). Never
  hardcode a version or distro value into a build script; thread it through
  `config.sh` with an overridable default.

## Repo Layout

| Path | Purpose |
|------|---------|
| `setup.sh` | Top-level orchestrator: preflight → toolchain → build all components |
| `uninstall.sh` | Remove everything installed from source |
| `config.sh` | Central config: arch detection, version vars, cache toggles |
| `functions.sh` | Shared helpers: `git_clone_update`, `run_logged`, `error_handler`, `step_start`/`step_done` |
| `scripts/build_<component>.sh` | One script per component; each runs standalone |
| `scripts/install_*.sh` | Toolchain + dependency installers (Go, Rust, protoc) |
| `scripts/package_all.sh` | DESTDIR staging tree → `.deb` files in `output/` |
| `scripts/repo_manage.sh`, `scripts/ci_publish.sh` | APT repo assembly (reprepro) |
| `scripts/verify_depends.sh`, `scripts/verify_versions.sh` | Post-build validation |
| `packaging/nfpm/*.yaml` | nFPM package definitions (one per component) |
| `versions-stable.env` / `versions-v5.env` | Track version *policy* (series caps + soak); resolved by `scripts/resolve_versions.sh` |
| `versions-nightly.env` | Nightly behaviour flags (sourced before `setup.sh`) |
| `tests/` | Bash unit tests, run directly: `bash tests/<test>.sh` |
| `.github/workflows/build-packages.yml` | CI: native amd64 + arm64 builds, repo publish |
| `.github/workflows/lint.yml` | CI gate: ShellCheck + shfmt + `tests/` + gitleaks (every PR) |
| `docs/` | Architecture (incl. CI/CD), configuration, APT repo, testing |

Component source checkouts (`podman/`, `crun/`, etc.) are cloned into `build/`
(`BUILD_ROOT`) at build time and are gitignored — never commit them.

## Commands

```bash
# Syntax-check a script (works anywhere)
bash -n scripts/build_podman.sh

# Run unit tests (work anywhere with bash)
bash tests/test_detect_distro_depends.sh
bash tests/test_extract_version_nightly.sh

# Full build (Linux only, as root)
eval "$(./scripts/resolve_versions.sh versions-stable.env)" && sudo -E ./setup.sh  # stable (Podman 6.x)
eval "$(./scripts/resolve_versions.sh versions-v5.env)" && sudo -E ./setup.sh      # v5 (Podman 5.x maintenance)
sudo NIGHTLY_BUILD=true SHALLOW_CLONE=false ./setup.sh  # nightly (HEAD)

# Single component (Linux only; sources config.sh/functions.sh itself)
./scripts/build_conmon.sh

# Package staging tree into .debs (Linux, needs DESTDIR set + nfpm)
./scripts/package_all.sh
```

## Code Style

- `#!/bin/bash` + `set -euo pipefail` at the top of every script.
- Toolpath bootstrap before any work (copy from an existing script):
  sources `config.sh` then `functions.sh`, then installs the error trap
  `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR`.
- Use `functions.sh` helpers instead of inlining: `git_clone_update`/`git_checkout`
  for cloning, `run_logged` for build output, `detect_architecture` for arch.
- Variables: `UPPERCASE` for env/config, `lowercase` locals, function-local
  parameters prefixed `l` (`lcomponent`, `lfolder`). Always quote expansions:
  `"${VAR}"`. 4-space indent inside functions.
- snake_case function names; guard sourced files with the `_SOURCED` pattern.
- Run ShellCheck over touched scripts before finishing (CI enforces it at
  `severity=error` via `.github/workflows/lint.yml`).

## Conventions

- Commits: Conventional Commits (`feat:`, `fix(ci):`, `chore:`, `ci:`),
  matching existing history.
- Branch off `main` with descriptive names (`fix/...`, `feat/...`).
- Packages are named `podman-*` and declare Conflicts/Replaces/Provides
  against official Ubuntu packages — keep that intact when touching
  `packaging/nfpm/*.yaml`.
- If you change packaging, versioning, or repo layout, exercise
  `scripts/package_all.sh` in CI/VM and confirm `.deb` output.

## Where Things Are Documented

- `docs/ARCHITECTURE.md` — pipeline stages end to end, incl. CI/CD & publishing
- `docs/CONFIGURATION.md` — every env var and config file
- `docs/apt-repository.md` — end-user APT setup and troubleshooting
- `docs/TESTING.md` — test suite and CI integration
