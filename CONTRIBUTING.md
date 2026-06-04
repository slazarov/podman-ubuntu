<!-- generated-by: gsd-doc-writer -->
# Contributing to podman-ubuntu

Thanks for your interest in contributing. This project compiles the Podman
container stack from upstream sources and publishes it as Debian/Ubuntu
packages through a hosted APT repository. Contributions to the build scripts,
packaging definitions, CI pipeline, and documentation are all welcome.

## Development Setup

This is a shell-based build pipeline; there is no compiled application to set up.
To work on the build itself, clone the repository and run the build on a Debian
or Ubuntu host (tested on Ubuntu 24.04):

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

## Coding Standards

All build logic is written in Bash. There is no automated linter or formatter
configured in the repository, so follow the conventions already present in the
existing scripts:

- Start scripts with `#!/bin/bash` and `set -euo pipefail`, matching the
  existing `scripts/*.sh` and `tests/*.sh` files.
- Quote variable expansions (`"${VAR}"`) and use `${...}` braces consistently,
  as the existing scripts do.
- Put shared logic (git clone/checkout, logging, error handling, architecture
  and toolchain detection) in `functions.sh` rather than duplicating it in
  individual build scripts.
- Keep build configuration (versions, architecture strings, cache toggles) in
  `config.sh` and the `versions-*.env` files, not hard-coded in scripts.
- Running [`shellcheck`](https://www.shellcheck.net/) over changed scripts
  locally before submitting is strongly encouraged, even though CI does not
  enforce it.

## PR Guidelines

The CI workflow (`.github/workflows/build-packages.yml`) builds and publishes
packages; it does not currently run a separate lint or test gate, so review
relies on clear, self-checked pull requests. When opening a PR:

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

This repository does not yet provide issue templates. Please open bugs and
feature requests through GitHub Issues at
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
