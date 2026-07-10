# AGENTS.md

Guidance for AI agents working in this repository.

## What This Project Is

A **shell-orchestrated build pipeline** (not an application) that compiles the
Podman container stack (12 components) from upstream source on Ubuntu 24.04
(amd64 + arm64), packages it into `.deb` files with nFPM, and publishes a
reprepro APT repository via GitHub Pages with three suites: **stable** (pinned
tags), **edge** (latest upstream tags), **nightly** (upstream HEAD, daily CI).

There is no package.json, no compiler, no app server. Everything is Bash.

## Critical Constraints

- **Builds only run on Debian/Ubuntu (Linux).** The dev machine may be macOS —
  you can edit scripts but cannot execute the pipeline locally. Don't try to
  "verify" by running `setup.sh` or `build_*.sh` outside Linux; use
  `bash -n <script>` for syntax checks and reason through the logic instead.
  For real execution, use the Lima VMs (see "Lima VM Testing" below).
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
| `versions-stable.env` / `versions-nightly.env` | Track version pins (sourced before `setup.sh`) |
| `tests/` | Bash unit tests, run directly: `bash tests/<test>.sh` |
| `.github/workflows/build-packages.yml` | CI: native amd64 + arm64 builds, repo publish |
| `docs/` | Architecture, configuration, testing, APT repo details, project/deployment guides |

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
source versions-stable.env && sudo -E ./setup.sh   # stable
sudo ./setup.sh                                     # edge (auto-detect latest tags)
sudo NIGHTLY_BUILD=true SHALLOW_CLONE=false ./setup.sh  # nightly (HEAD)

# Single component (Linux only; sources config.sh/functions.sh itself)
./scripts/build_conmon.sh

# Package staging tree into .debs (Linux, needs DESTDIR set + nfpm)
./scripts/package_all.sh
```

## Lima VM Testing

On-Ubuntu verification (UAT, `verify_depends.sh`, `smoke_install_2604.sh`, full
builds) runs in Lima VMs: **`ubuntu-24`** (24.04) and **`ubuntu-26`** (26.04).
Configs live in `lima/*.yaml`; the repo is mounted **writable** at
`/opt/podman-debian` in both VMs.

```bash
# Command pattern (ignore the harmless "cd: /Users/...: No such file" noise —
# lima tries to chdir to the host CWD first)
limactl shell ubuntu-24 -- bash -c 'cd /opt/podman-debian && <command>'

# Full pipeline must run as root with DESTDIR set; detach long builds and log
limactl shell ubuntu-24 -- bash -c \
  'sudo -b env HOME=/root nohup bash -c \
   "cd /opt/podman-debian && source versions-stable.env && \
    export DESTDIR=/root/podman-staging && ./setup.sh" > /tmp/setup.log 2>&1'
```

Rules learned the hard way:

- **Run `sudo apt-get update` before the first build** — fresh VMs carry stale
  apt indexes and `install_dependencies.sh` will 404 on superseded versions.
- **`setup.sh` requires root** (`apt-get` is called directly, no sudo wrapper).
  Use `sudo env HOME=/root ...`; convention: `DESTDIR=/root/podman-staging`.
- **`nfpm` is NOT installed by `setup.sh`.** After the Go toolchain exists:
  `sudo env HOME=/root PATH="/opt/go/<ver>/bin:$PATH" go install
  github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.45.0` → lands in `/root/go/bin`;
  put that on PATH for `package_all.sh` / `verify_depends.sh`.
- **Never build both distros against the shared mount.** `BUILD_ROOT` is
  `<repo>/build` — shared by both VMs through the mount. make/cargo reuse by
  mtime would install binaries linked against the *other* distro's libs. Build
  one distro on the mount, and for the second VM rsync the repo to VM-local
  disk first (exclude `build/`, `output/`, `.git/`), e.g. to
  `/root/podman-debian-build`, and build there.
- **`smoke_install_2604.sh` needs a container runtime** — `ubuntu-26` has
  distro podman installed for this; run as root with `SMOKE_RUNTIME=podman`.
- 24.04/26.04-built `.deb`s coexist in `output/` (distinct
  `~ubuntu{24.04,26.04}.podman1` suffixes in filenames).

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
- Run ShellCheck over touched scripts before finishing (not enforced by CI,
  but expected).

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

- `docs/ARCHITECTURE.md` — pipeline stages end to end
- `docs/CONFIGURATION.md` — every env var
- `docs/TESTING.md` — test patterns and CI integration
- `docs/build-scripts.md` / `docs/ci-pipeline.md` / `docs/apt-repository.md`
- `docs/project-overview.md` / `docs/tech-stack.md` / `docs/source-tree-analysis.md` / `docs/deployment-guide.md`
