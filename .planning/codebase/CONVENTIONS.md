# Coding Conventions

**Analysis Date:** 2026-06-07

## Script Header

Every script must open with these three lines in this exact order:

```bash
#!/bin/bash

# Abort on Error
set -euo pipefail
```

`set -euo pipefail` is mandatory. The `-u` flag means every variable reference
must be initialized; use `${VAR:-default}` for optional values and
`${VAR:?message}` where a value is required.

## Toolpath Bootstrap

Every script that needs to reference project files must include the canonical
toolpath block immediately after the error-mode line, before sourcing anything:

```bash
relativepath="../"   # adjust depth: "./" for root-level, "../" for scripts/
if [[ ! -v toolpath ]]; then
    scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
    toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath})
fi
```

Root-level scripts (`setup.sh`, `config.sh`, `functions.sh`) use `relativepath="./"`.
Scripts under `scripts/` use `relativepath="../"`.

## Source Order

For build scripts under `scripts/`, source in this fixed order:

```bash
source "${toolpath}/config.sh"
source "${toolpath}/functions.sh"
trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR
```

The error trap is set AFTER sourcing, not before. `config.sh` sources
`functions.sh` internally; `functions.sh` sources `config.sh` at its tail —
they are mutually aware but guard against re-entrant sourcing with the
`_SOURCED` pattern (see below).

## Guard Against Recursive Sourcing

Files that are sourced (not executed directly) guard themselves:

```bash
[[ -n "${_FUNCTIONS_SH_SOURCED:-}" ]] && return 0
_FUNCTIONS_SH_SOURCED=1
```

Use a unique variable per file: `_CONFIG_SH_SOURCED`, `_FUNCTIONS_SH_SOURCED`,
etc. The variable is NOT exported so child processes re-source independently.

## Naming Conventions

**Variables:**
- `UPPERCASE` for all environment and config variables: `ARCH`, `BUILD_ROOT`, `PODMAN_TAG`
- `lowercase` for local script variables: `arch`, `latest`, `toolchain_ver`
- Function parameters prefixed with `l` for clarity: `lrepository`, `lfolder`, `lcomponent`, `ltag`
- Always quote variable expansions: `"${VAR}"` — never bare `$VAR`

**Functions:**
- `snake_case` for function names: `git_clone_update`, `detect_architecture`, `log_build_output`
- Function-local variables declared with `local`: `local lrepository="$1"`

**Files:**
- Build scripts: `build_<component>.sh` (e.g., `build_podman.sh`, `build_conmon.sh`)
- Install scripts: `install_<tool>.sh` (e.g., `install_go.sh`, `install_rust.sh`)
- Test scripts: `test_<subject>.sh` (e.g., `test_detect_distro_depends.sh`)

## Configuration Pattern

All tuneable values live in `config.sh` and use `${VAR:-default}` overridable
defaults. Never hardcode a version or distro value in a build script:

```bash
# Correct — overridable
export PODMAN_TAG="${PODMAN_TAG:-}"
export SHALLOW_CLONE="${SHALLOW_CLONE:-true}"
export NIGHTLY_BUILD="${NIGHTLY_BUILD:-false}"

# Wrong — hardcoded
PODMAN_TAG="v5.5.2"
```

## Error Handling

**Error trap:** `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR`

`error_handler` is defined in `functions.sh`. It prints script name, line
number, and exit code to stderr with a banner, then calls `exit "${exit_code}"`.

**Hard-fail vs skip:**
- Missing/invalid required input: hard-fail with `return 1` or `exit 1`
- Optional/platform-specific operations (e.g., dpkg on macOS): skip with a
  `SKIP:` message and `continue` or `|| true`
- Commands in pipelines that may fail: append `|| true` explicitly when failure
  is acceptable: `git pull origin "${default_branch}" || true`

**Running commands outside pipelines:** When the exit status of a command is
needed, run it outside a pipeline and capture output separately (CR-01 pattern):

```bash
# Correct
if ! dpkg_out="$(dpkg-query -S "${resolved}" 2>&1)"; then
    echo "ERROR: ..." >&2
    return 1
fi

# Wrong — exit status lost in pipeline under set -euo pipefail
dpkg-query -S "${resolved}" | awk '{print $1}'
```

## Progress Reporting

Use `functions.sh` helpers for progress output in build scripts:

```bash
step_start "Cloning repository"
git_clone_update https://github.com/containers/podman.git podman
step_done

step_start "Building"
run_logged make -j "$NPROC" PREFIX=/usr
step_done
```

`step_start` prints `"  ${name}..."` and records a timestamp.
`step_done` prints `"  Done: ${name} (Xm Ys)"`.

`run_logged` suppresses stdout/stderr on success; on failure it dumps the last
40 lines of the build log to stderr and returns non-zero.

## Helper Usage

Do NOT inline logic when a `functions.sh` helper exists:

| Task | Use |
|------|-----|
| Clone/fetch a repo | `git_clone_update <url> <dir>` |
| Checkout a tag | `git_checkout "${TAG}"` |
| Build with logged output | `run_logged make ...` |
| Detect CPU arch | `detect_architecture` |
| Detect distro version | `detect_distro_version_id` |

## Indentation

4-space indent inside function bodies. No tabs.

## ShellCheck

Run `shellcheck` over any touched script before finishing. CI does not enforce
it, but it is expected. Suppress false positives with inline directives:

```bash
# shellcheck disable=SC1091
source "${toolpath}/config.sh"
```

## Comments

- Section headers use `# ============` banners (40 `=` chars)
- Inline comments explain WHY (design decisions, pitfalls, requirement IDs)
  not WHAT (the code already says what)
- Requirement/decision IDs appear in comments: `(D-03)`, `(T-19-01)`, `(CR-01)`, `(WR-05)`
- Function header comments describe parameters, return values, and behavioral
  constraints when non-obvious

## Packages and Versioning

- All `.deb` packages are named `podman-*`
- Version suffix: `~ubuntu${DISTRO_VERSION_ID}.podman1` (e.g. `~ubuntu24.04.podman1`)
- Packages declare `Conflicts`/`Replaces`/`Provides` against official Ubuntu
  packages in `packaging/nfpm/*.yaml` — always preserve these fields

## Commit Messages

Conventional Commits style:
- `feat:`, `fix:`, `chore:`, `ci:`, `docs:`
- Phase-scoped: `fix(19):`, `docs(phase-21):`
- Branch names: `fix/...`, `feat/...`

---

*Convention analysis: 2026-06-07*
