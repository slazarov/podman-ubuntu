# Deployment Guide

Deployment = building the `.deb`s in CI and publishing the assembled reprepro
APT repository to GitHub Pages. There is no server to deploy; the "deployment"
artifact is a static, GPG-signed APT repo.

## CI Workflow (`.github/workflows/build-packages.yml`)

**Triggers:** daily cron `30 4 * * *` (nightly) and `workflow_dispatch` with a
`build_track` choice (stable / edge / nightly).

**Permissions:** `pages: write`, `id-token: write`; concurrency group `pages`.

### Jobs

1. **check-changes** (schedule only) — compares upstream HEAD SHAs across the
   component repos against a cached `nightly-sha.json`; `skip=true` when nothing
   changed.
2. **check-republish** (manual stable/edge only) — runs
   `check_republish_needed.sh`; `skip=true` only when every would-build version
   already matches what's published.
3. **build** — a single matrix job (`fail-fast: false`, `timeout-minutes: 180`)
   with 4 explicit cells:

   | Cell | Runner | Container |
   |------|--------|-----------|
   | 2404 amd64 | `ubuntu-24.04` | none |
   | 2404 arm64 | `ubuntu-24.04-arm` | none |
   | 2604 amd64 | `ubuntu-24.04` | `ubuntu:26.04` |
   | 2604 arm64 | `ubuntu-24.04-arm` | `ubuntu:26.04` |

   Builds are **native** (arm64 on arm64 runners, no emulation). 26.04 cells
   bootstrap the bare container (sudo/git/curl/bash) then run bash; they set
   `SKIP_FUSE_CHECK=true` (the container's device cgroup denies `/dev/fuse` even
   for root; compilation never opens it). Go caches are keyed per distro+arch;
   artifacts are named `debs-<distro>-<arch>`. Build runs
   `sudo env $ENV_ARGS ./setup.sh` with track-specific env threaded in.

4. **publish** — gated:
   `if: always() && github.ref == 'refs/heads/main' && (build succeeded or failed)`.
   - **Main-branch-only** — the "skip publish on non-main branches" guard.
   - Runs even on partial (2604) failure, since publish skips empty deb dirs.
   - Runs doc/HTML unit tests + repo-assembly regression tests first.
   - Per-distro `ci_publish.sh` into one accumulating `repo-output` (2404 then 2604).
   - `smoke_repo_install.sh` gate (2404 always; 2604 only if its suite materialized).
   - `configure-pages` → `upload-pages-artifact` → `deploy-pages` (atomic, one-shot).

Because `build` is one matrix job, `needs.build.result == 'success'` requires
all four cells; both distros are assembled before the single deploy.

## Repository Assembly (local reproduction)

```bash
# Assemble one (track, distro) into an accumulating output dir
./scripts/ci_publish.sh <stable|edge|nightly> <2404|2604> <deb-dir> <repo-url> repo-output

# Single-suite build (no mirroring)
./scripts/repo_manage.sh <track> <distro> <deb-dir> [out]
```

`ci_publish.sh` computes untouched suites, preserves earlier-pass Release files
in place (no-clobber), mirrors untouched suites **verbatim** (byte-identical
signed tree so the CDN hash window stays closed), builds the target suites,
applies Acquire-By-Hash + re-sign to every non-verbatim suite, and generates the
`index.html` landing page.

## Published Repository Layout

- **9 reprepro distributions:** `{stable,edge,nightly}-{2404,2604}` + 3 bare
  legacy aliases (`stable`/`edge`/`nightly`, DEPRECATED, verbatim-served for
  migration). All signed, `Architectures: amd64 arm64`, `Components: main`.
- **Single URL, single GPG key**, Acquire-By-Hash enabled.
- End-user setup (deb822) and the version table are emitted into `index.html`.

## Signing

`GPG_PRIVATE_KEY` (base64 or ASCII-armored) is imported with ultimate
ownertrust; reprepro signs each suite; `repo_byhash.sh` re-signs after injecting
`Acquire-By-Hash` because editing `Release` invalidates reprepro's signature.
`packaging/repo/pubkey.gpg` is published as `podman-ubuntu.gpg`.

## Republish Gating

Manual stable/edge dispatches run `check_republish_needed.sh` to avoid
redundant republishes: it compares the versions that *would* build against
what's already published across both distros × both arches and emits
`skip=true` only on a full match. `pasta` is excluded (it floats by date).
The logic is strictly conservative — any fetch/resolve uncertainty →
`skip=false` — and is unit-pinned by `test_check_republish.sh`.
