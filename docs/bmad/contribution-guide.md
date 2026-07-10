# Contribution Guide

## Code Style

- `#!/bin/bash` + `set -euo pipefail` at the top of every script.
- **Toolpath bootstrap** before any work (copy the header from an existing
  script): resolve `toolpath` → `source config.sh` → `source functions.sh` →
  install the ERR trap `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR`
  (installed *after* sourcing).
- Use `functions.sh` helpers instead of inlining: `git_clone_update` /
  `git_checkout` for cloning, `run_logged` for build output,
  `step_start`/`step_done` for progress, `detect_architecture` for arch.
- **Variables:** `UPPERCASE` for env/config, `lowercase` for locals,
  function-parameter locals prefixed `l` (`lcomponent`, `lfolder`, `lsuite`).
  Always quote expansions: `"${VAR}"`. 4-space indent inside functions.
- snake_case function names; guard sourced files with the `_SOURCED` pattern.
- Run **ShellCheck** over touched scripts before finishing (expected, not
  CI-enforced).

## Core Constraints (do not break)

- **Never hardcode a version or distro** into a build script. Thread it through
  `config.sh` with an overridable `${VAR:-default}`. The same scripts serve all
  three tracks and both distros purely by environment.
- **Builds only run on Linux.** On macOS use `bash -n` + reasoning, or the Lima
  VMs. Don't try to "verify" by running `setup.sh` outside Linux.
- **Packages are `podman-*`** and declare Conflicts/Replaces/Provides against
  official Ubuntu package names — keep that intact when touching
  `packaging/nfpm/*.yaml`.
- If you change packaging, versioning, or repo layout, exercise
  `scripts/package_all.sh` in CI/VM and confirm `.deb` output.

## Commits & Branches

- **Conventional Commits:** `feat:`, `fix(ci):`, `chore:`, `ci:`, `test:`,
  `docs:` — matching existing history.
- Branch off `main` with descriptive names (`fix/...`, `feat/...`).

## Testing Expectations

- Add a `tests/test_<topic>.sh` for new pipeline logic; run it directly with
  `bash tests/test_<topic>.sh`. Tests are framework-free (plain bash assertions).
- Keep tests runnable off-Ubuntu where possible (sed-extract + `eval` helper
  bodies rather than sourcing `config.sh`, which hard-fails without
  `/etc/os-release`).
- For packaging/versioning/repo changes, also run the relevant on-Ubuntu proof
  gates (`verify_versions.sh`, `verify_depends.sh`, `smoke_*.sh`) in a VM/CI.

## Where Things Are Documented

- `docs/bmad/architecture.md` — pipeline stages end to end (generated)
- `docs/ARCHITECTURE.md` — hand-maintained architecture reference
- `docs/CONFIGURATION.md` — every environment variable
- `docs/TESTING.md` — test patterns and CI integration
- `docs/build-scripts.md` / `docs/ci-pipeline.md` / `docs/apt-repository.md`
- `AGENTS.md` — guidance for AI agents working in this repo
