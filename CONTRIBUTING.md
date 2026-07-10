# Contributing to podman-ubuntu

Thanks for your interest in contributing. This project compiles the Podman
container stack from upstream sources and publishes it as Debian/Ubuntu
packages through a hosted APT repository. Contributions to the build scripts,
packaging definitions, CI pipeline, and documentation are all welcome.

## Development Setup

This is a shell-based build pipeline; there is no compiled application to set up.
To work on the build itself, clone the repository and run the build on a Debian
or Ubuntu host (Ubuntu 24.04 and 26.04, amd64 and arm64):

```bash
git clone https://github.com/slazarov/podman-ubuntu.git
cd podman-ubuntu
source versions-stable.env
sudo -E ./setup.sh
```

For prerequisites and a full walkthrough of the build, see the
[README](README.md). For how the pipeline is structured (orchestrator,
per-component build scripts, packaging, and publishing stages), see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

A few notes for contributors specifically:

- The build is destructive to the host (it installs toolchains and system
  packages). Prefer a disposable VM or container when iterating locally.
- Build output, cloned sources, and logs land in `build/` and `log/`, which are
  ignored by git. Inspect `log/` when a component build fails.
- Run `sudo ./uninstall.sh` to remove source-installed components from a test
  host.

### Build tracks

The same scripts serve three release tracks, selected entirely by environment:

| Track | Invoke | Behavior |
|-------|--------|----------|
| **stable** | `source versions-stable.env && sudo -E ./setup.sh` | Builds the pinned tags in `versions-stable.env`. |
| **edge** | `sudo ./setup.sh` | Tags left empty → latest upstream tag auto-detected. |
| **nightly** | `sudo NIGHTLY_BUILD=true SHALLOW_CLONE=false ./setup.sh` | Builds from upstream HEAD with full clones. |

The full set of build-influencing environment variables is documented in
[docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## Coding Standards

All build logic is written in Bash. Conventions are machine-enforced by
`.shellcheckrc`, `.editorconfig`, and `.pre-commit-config.yaml` (ShellCheck +
shfmt + gitleaks), and `.github/workflows/lint.yml` re-runs ShellCheck and the
test suite on every PR. Follow the patterns already in `scripts/`:

- Start scripts with `#!/bin/bash` and `set -euo pipefail`.
- **Toolpath bootstrap** before any work — source `config.sh` then
  `functions.sh`, then install the error trap, so a script runs standalone or
  sourced by `setup.sh`:

  ```bash
  relativepath="../"
  if [[ ! -v toolpath ]]; then scriptpath=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd ); toolpath=$(realpath --canonicalize-missing ${scriptpath}/${relativepath}); fi
  source "${toolpath}/config.sh"
  source "${toolpath}/functions.sh"
  trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR
  ```

- Use `functions.sh` helpers (`git_clone_update`/`git_checkout`, `run_logged`,
  `step_start`/`step_done`, `detect_architecture`) rather than inlining logic.
- Keep versions, architecture strings, and cache toggles in `config.sh` /
  `versions-*.env` with the `${VAR:-default}` pattern — never hard-coded.
- Quote expansions (`"${VAR}"`); 4-space indent inside functions.
- Install the gate locally with `pipx install pre-commit && pre-commit install`
  to run ShellCheck/shfmt/gitleaks before you push.

## Where to add code

| Change | Where |
|--------|-------|
| New build component | `scripts/build_<c>.sh` (copy an existing header) + `packaging/nfpm/<c>.yaml` + a `*_TAG` in both `versions-*.env`, then wire it into `setup.sh`'s `run_script` at the right dependency position |
| New toolchain installer | `scripts/install_<tool>.sh`, wired into `setup.sh` before its dependents |
| New config variable | `config.sh` (`${VAR:-default}` + export), documented in [docs/CONFIGURATION.md](docs/CONFIGURATION.md) |
| New packaging logic | `packaging/nfpm/<c>.yaml` (per-component) or `scripts/package_all.sh` (pipeline-wide) |
| New APT suite / routing | `VALID_TRACKS` / `VALID_DISTROS` / `ALL_SUITES` + `resolve_publish_targets` in `config.sh`, plus `packaging/repo/conf/distributions` |

## PR Guidelines

Two workflows run on every PR — `.github/workflows/lint.yml` (ShellCheck at
`severity=error`, shfmt, the `tests/` suite, and a gitleaks scan) and
`.github/workflows/build-packages.yml` (native amd64 + arm64 package builds).
The `.github/PULL_REQUEST_TEMPLATE.md` pre-fills the checklist below. When
opening a PR:

- Branch from `main` and use a short, descriptive branch name (for example
  `fix/crun-json-c-dependency` or `feat/arm64-runner`), matching the style of
  the project's existing commit history.
- Keep each PR focused on a single change (one component, one packaging fix, one
  CI adjustment) so it is easy to review and revert.
- Run the relevant build script or the full `setup.sh` for any component you
  touch, and run the test suite (see below) for changes to version-extraction or
  packaging logic.
- Update the affected documentation (`README.md`, `docs/`) when you change
  behavior, supported versions, or commands.
- Describe what you changed, how you verified it, and the build track(s)
  (`stable`, `edge`, `nightly`) and architecture(s) (amd64, arm64) you tested.

### Running Tests

Shell unit tests live in `tests/`. Each test file is a standalone, executable
script with its own assertion helpers:

```bash
bash tests/test_extract_version_nightly.sh
```

The script exits non-zero if any assertion fails, so it is safe to run in a
pre-commit check or locally before opening a PR.

### Triggering a Build

Maintainers can run the pipeline manually from the Actions tab via the
**Build and Publish Packages** workflow's `workflow_dispatch` trigger, choosing
the `stable`, `edge`, or `nightly` build track. The same workflow runs
automatically on a daily schedule (4:30 AM UTC) to produce nightly builds.

## Issue Reporting

Bug-report and feature-request templates live under `.github/ISSUE_TEMPLATE/`.
Open bugs and feature requests through GitHub Issues at
<https://github.com/slazarov/podman-ubuntu/issues>.

When reporting a build or packaging problem, include:

- The build track (`stable`, `edge`, or `nightly`) and the component involved.
- Your host OS and architecture (Ubuntu 24.04 amd64 or arm64).
- Whether you installed via the APT repository or built from source with
  `setup.sh`.
- The exact command you ran and the relevant output from `log/` (the failing
  component's log tail is the most useful).
- What you expected to happen versus what actually happened.

For feature requests, describe the use case and which component(s) or release
track it affects.
