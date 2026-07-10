# Production-Readiness Checklist

A living checklist for making `podman-ubuntu` read as production-grade to an
outside reviewer. Ordered by **signal-per-effort** — Tier 1 changes the snap
judgment, Tier 3 improves the code an outsider never sees.

> **How to use:** tick items as you land them. Each carries an `impact/effort`
> tag. Nothing here is committed on your behalf until you say so.

---

## Baseline — what already reads as professional (don't "fix")

- [x] Conventional Commits with clear scopes throughout the history
- [x] `set -euo pipefail` + consistent script skeleton + shared `functions.sh` helpers
- [x] Env-driven config (`${VAR:-default}`), no hardcoded versions/distros
- [x] Real test suite (13 bash tests + reprepro/gpg integration harnesses)
- [x] Native multi-arch CI (amd64 + arm64 × 24.04/26.04) and comprehensive docs

---

## Tier 1 — Quick presentation wins (high impact, low effort)

### Quality gates
- [x] **ShellCheck CI job** — `.github/workflows/lint.yml`, blocking at `severity=error` (verified green: 0 error-level findings). Ratchet to `warning` then default as the 15 warnings get fixed.
- [x] **`shfmt` formatting check** — informational (non-blocking) job in `lint.yml`; promote to blocking after a one-time `shfmt -w` pass.
- [x] **Gate `tests/*.sh` on PRs** — `lint.yml` runs the full suite (all 13 pass; integration harnesses self-skip without reprepro/gpg). ShellCheck covers `bash -n`-level parsing.
- [x] **`.pre-commit-config.yaml`** added — hygiene hooks + ShellCheck + shfmt + gitleaks (Appendix A).
- [x] **`.editorconfig` and `.shellcheckrc`** added — conventions now machine-enforced (`external-sources`, SC1091 off).

### De-expose AI tooling
- [x] **Gitignore + untrack `_bmad/`** — kept on disk (BMAD still runs), no longer tracked
- [x] **Gitignore + untrack `_bmad-output/`** — `project-context.md` (AI-agent rules) stays local; `AGENTS.md` remains the tracked agent guidance
- [x] **`docs/bmad/` resolved (de-brand & fold)** — moved `project-overview`, `tech-stack`, `source-tree-analysis`, `deployment-guide` into `docs/` under neutral names; dropped the duplicates (`architecture`, `development-guide`, `contribution-guide`, `index`) and the scan-report; removed the `bmad/` folder; updated `AGENTS.md` references
- [x] Confirmed nothing else AI-tool-branded is tracked (`.claude/` and `_bmad*/` gitignored; GSD already removed)

### Presentation
- [x] **README badges** — lint + build status + license (value prop / license table already present)
- [x] **Rename `Podman for Debian` → `Podman for Ubuntu`** in the generated page (`scripts/ci_publish.sh`, ×2); test `test_index_html_distro.sh` still green. *Note: `lima/*.yaml` mount paths (`/opt/podman-debian`) left as-is — they're gitignored/machine-local and renaming without touching the local VM configs would break instructions.*
- [x] **Deleted the stale root `index.html`** (unused; the authoritative page is generated in `ci_publish.sh`) — recoverable from git history.

### Session config changes
- [x] Pointed BMAD `project_knowledge` → `_bmad-output/docs` so future generated docs stay in the gitignored area
- [x] Gitignored + untracked `harness-config.toml` (machine-specific secrets env paths; kept on disk)

---

## Tier 2 — Trust & security signals (medium effort)

- [ ] **Pin GitHub Actions to commit SHAs** (currently floating majors) + add `.github/dependabot.yml` to keep them fresh `impact:high / effort:low`
- [ ] Add `SECURITY.md` (how to report vulnerabilities — matters for a package repo) `impact:med / effort:low`
- [ ] Add `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE/` `impact:med / effort:low`
- [ ] Add `CHANGELOG.md` + cut a real **GitHub Release** from your existing version tags `impact:med / effort:med`
- [ ] Add a secret-scanning hook/CI step (e.g. `gitleaks`) — you already scan docs manually `impact:med / effort:low`
- [ ] Consider signing published Releases / documenting the GPG key rotation policy `impact:low / effort:med`

---

## Tier 3 — Structural code cleanup (real engineering, invisible to casual reviewers)

- [ ] **Remove dead `go 1.22.6` sed patches** in `build_buildah.sh`, `build_skopeo.sh`, `build_toolbox.sh`, `build_go-md2man.sh` (silent no-ops on newer `go.mod`) `impact:med / effort:low`
- [ ] **Kill sync-by-comment duplication**: extract `COMPONENT_BINARIES` / `INJECT_ONLY_DEPENDS` (duplicated in `package_all.sh` and `verify_depends.sh`) into one sourced file `impact:med / effort:med`
- [ ] **Decompose `ci_publish.sh`** (~740-line state machine) into named functions/sub-scripts — it's covered by `test_ci_publish_multipass.sh`, so you can refactor behind the gate `impact:med / effort:high`
- [ ] Replace hardcoded `/tmp/nfpm-*.yaml` render paths in `package_all.sh` with `mktemp` `impact:low / effort:low`
- [ ] Resolve the `container-configs` triple-naming mismatch (repo `container-libs` / package `podman-container-configs` / var `CONTAINER_LIBS_TAG`) or document it in one place `impact:low / effort:med`
- [ ] De-duplicate `get_latest_tag` double-call on the no-tag path in `git_checkout` `impact:low / effort:low`

---

## Appendix A — Proposed `.pre-commit-config.yaml`

```yaml
# Run: pipx install pre-commit && pre-commit install
# One-off over everything: pre-commit run --all-files
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-merge-conflict
      - id: check-executables-have-shebangs
      - id: mixed-line-ending
        args: [--fix=lf]
  - repo: https://github.com/koalaman/shellcheck-precommit
    rev: v0.10.0
    hooks:
      - id: shellcheck
  - repo: https://github.com/scop/pre-commit-shfmt
    rev: v3.10.0-1
    hooks:
      - id: shfmt
        args: [-i, '4', -ci, -sr, -w]   # 4-space indent, matches house style
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.21.2
    hooks:
      - id: gitleaks
```

## Appendix B — Proposed CI lint job (mirrors the pre-commit gate)

```yaml
# .github/workflows/lint.yml — runs on every PR and push
name: lint
on: [push, pull_request]
jobs:
  shell:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: ShellCheck
        uses: ludeeus/action-shellcheck@master
        env:
          SHELLCHECK_OPTS: -e SC1091   # sourced files not followed at lint time
      - name: shfmt
        run: |
          curl -sSfL https://raw.githubusercontent.com/mvdan/sh/master/scripts/install \
            | sh -s -- -b "$HOME/.local/bin"
          "$HOME/.local/bin/shfmt" -i 4 -ci -sr -d .
  bash-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: for t in tests/test_*.sh; do bash "$t"; done
```

> Note: pin the `rev:`/action versions to release tags or SHAs (Tier 2). ShellCheck
> may surface real findings on first run — triage into fix-now vs `# shellcheck disable`
> with a reason, and only then make the job blocking.
