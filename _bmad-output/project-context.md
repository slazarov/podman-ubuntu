---
project_name: 'podman-ubuntu'
user_name: 'Stanislav'
date: '2026-07-10'
sections_completed: ['technology_stack', 'critical_implementation_rules']
existing_patterns_found: 12
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

> This is a **shell-orchestrated build pipeline**, not an application. There is
> no `package.json`, no compiler, no app server — everything is Bash driving
> upstream toolchains. Full reference docs live in `docs/bmad/` (start at
> `docs/bmad/index.md`) and `docs/`.

---

## Technology Stack & Versions

- **Orchestration:** Bash (`#!/bin/bash` + `set -euo pipefail`), Make, Git.
- **Built components (from upstream source):** Go (podman, buildah, skopeo, conmon, toolbox), Rust (netavark, aardvark-dns, fuse-overlayfs v2+), C/autotools (crun, catatonit, pasta, fuse-overlayfs v1), Meson (toolbox).
- **Toolchain versions are AUTO-DETECTED, not pinned by us:** Go from podman's `go.mod`, Rust from netavark's `Cargo.toml` MSRV, protoc from latest GitHub release. Never hardcode these.
- **Packaging:** nFPM `@v2.45.0` → `.deb`. **Repository:** reprepro + GPG + Acquire-By-Hash. **CI/hosting:** GitHub Actions (native amd64+arm64) + GitHub Pages.
- **Local testing:** Lima VMs `ubuntu-24` / `ubuntu-26`.

---

## Critical Implementation Rules

### Environment-driven, never hardcoded
- **Never hardcode a version or distro** into a build script. Thread every value through `config.sh` using the `${VAR:-default}` idiom. The *same* scripts serve all three tracks (stable/edge/nightly) and both distros (2404/2604) purely by environment.
- Track selection is by env only: **stable** = `source versions-stable.env` (sets every `*_TAG`); **edge** = no env (latest tag auto-resolved); **nightly** = `NIGHTLY_BUILD=true SHALLOW_CLONE=false` (HEAD). There is deliberately **no** `versions-edge.env`.
- `versions-*.env` files contain only `export` statements — no logic.

### Script skeleton (copy from an existing script, do not improvise)
Every script starts with, in order:
1. `#!/bin/bash` + `set -euo pipefail`
2. **Toolpath bootstrap** — resolve `toolpath` via `BASH_SOURCE` if unset (root scripts use `./`, `scripts/` use `../`).
3. `source "${toolpath}/config.sh"` then `source "${toolpath}/functions.sh"`
4. `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR` — **installed AFTER sourcing** (config/functions don't tolerate the trap during load).

### Use `functions.sh` helpers — don't inline
`git_clone_update` / `git_checkout` (cloning), `run_logged` (build output → `log/`, dumps last 40 lines on failure), `step_start`/`step_done` (timed progress), `detect_architecture`, `detect_runtime_depends`. Sourced files guard with the `_<FILE>_SH_SOURCED` pattern (NOT exported — children must re-source). `functions.sh` tail-sources `config.sh`.

### Naming & style
- `UPPERCASE` for env/config vars, `lowercase` for locals, function-parameter locals prefixed **`l`** (`lcomponent`, `lfolder`, `lsuite`).
- Always quote expansions: `"${VAR}"`. 4-space indent inside functions. snake_case function names.
- Run **ShellCheck** on touched scripts before finishing (expected; not CI-enforced).

### Packaging invariants (packaging/nfpm/*.yaml)
- Packages are named **`podman-<component>`** and MUST declare Conflicts/Replaces/Provides against the official Ubuntu package name (e.g. `podman-pasta` → `passt`, `podman-container-configs` → `golang-github-containers-common`). Keep these intact.
- Runtime deps are **auto-injected** by `detect_runtime_depends` (direct `DT_NEEDED` sonames via `objdump -p`, NOT `ldd` transitive closure). Inject-only components (crun, conmon, pasta) carry their own `depends:` header; don't add a literal `depends:` key to them.
- Every `.deb` gets `${VERSION_SUFFIX}` = `~ubuntu${DISTRO_VERSION_ID}.podman1`. `COMPONENT_BINARIES` / `INJECT_ONLY_DEPENDS` are duplicated in both `package_all.sh` and `verify_depends.sh` — **keep them in sync**.

### APT repo / publish
- reprepro has **no native Acquire-By-Hash** — `repo_byhash.sh` adds it and **re-signs** (editing `Release` invalidates the signature). Always export **per-suite**, never a bare `reprepro export` (it emits empty indexes and clobbers).
- `ci_publish.sh` has three clobber-prevention layers (per-suite export, earlier-pass in-place preservation, verbatim signed mirroring). It's a ~740-line state machine guarded by `test_ci_publish_multipass.sh` — change it carefully and re-run that test.
- Adding a suite/routing rule means editing `VALID_TRACKS`/`VALID_DISTROS`/`ALL_SUITES` + `resolve_publish_targets` in `config.sh` **and** `packaging/repo/conf/distributions`.

### CI
- Publish is **main-branch-only** (`github.ref == 'refs/heads/main'`) and runs even on partial failure (skips empty deb dirs). `build` is a single 4-cell matrix; `needs.build.result == 'success'` requires all four cells.

### Testing
- **Builds run on Linux only.** The dev host is macOS — you CANNOT run `setup.sh`/`build_*.sh` there. Use `bash -n <script>` for syntax checks and reasoning; use the Lima VMs for real execution.
- `tests/*.sh` are framework-free (plain bash assertions, exit codes) and run anywhere — they sed-extract + `eval` helper bodies to avoid `config.sh`'s os-release hard-fail. Keep new tests off-Ubuntu-runnable where possible.
- `nfpm` is **NOT** installed by `setup.sh` — install separately before packaging.
- Never build both distros against the shared Lima mount (`BUILD_ROOT` = `<repo>/build`); mtime reuse cross-contaminates libs. rsync to VM-local disk for the second distro.

### Commits & branches
- **Conventional Commits** (`feat:`, `fix(ci):`, `chore:`, `ci:`, `test:`, `docs:`). Branch off `main` with descriptive names (`fix/...`, `feat/...`).

### Known footguns
- Stale `go 1.22.6` sed patches in some Go build scripts are silent no-ops on newer `go.mod`.
- `container-configs` has a triple naming mismatch (repo `container-libs`, package `podman-container-configs`, var `CONTAINER_LIBS_TAG`).
- `pasta` cannot be pinned (always HEAD, versioned by date) — it's excluded from republish gating.
- `podman-debian` residue survives in `lima/*.yaml` mount paths and the generated page `<title>` (cosmetic; the repo is `podman-ubuntu`).
