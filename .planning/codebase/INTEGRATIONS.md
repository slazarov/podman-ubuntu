# External Integrations

**Analysis Date:** 2026-06-07

## APIs & External Services

**Upstream Source Repositories (fetched at build time via git clone):**
- GitHub (containers org) - podman, buildah, skopeo, crun, conmon, netavark, aardvark-dns, fuse-overlayfs, catatonit, container-libs, toolbox, go-md2man
- GitHub (openSUSE) - catatonit
- `https://passt.top/passt` - pasta (alternative git host)
- Auth: none (public repositories, no credentials)

**Toolchain Downloads (fetched at install time):**
- `https://go.dev/dl/` - Go toolchain tarballs (`scripts/install_go.sh`)
- `https://static.rust-lang.org/rustup/` - rustup installer (`scripts/install_rust.sh`)
- GitHub Releases API - protoc binaries (`scripts/install_protoc.sh`), sccache binaries (`scripts/install_rust.sh` when `SCCACHE_ENABLED=true`)
- Auth: none (public downloads)

**Upstream Change Detection (CI nightly cron):**
- `git ls-remote` called against 13 upstream repos in `.github/workflows/build-packages.yml` (`check-changes` job)
- Results cached in `actions/cache@v4` at key `nightly-sha-v1` under `/tmp/nightly-sha.json`
- Auth: none (public repos)

## Data Storage

**Databases:**
- None

**File Storage:**
- Local filesystem during build: `BUILD_ROOT` (`<repo>/build/`), `DESTDIR` (e.g. `/root/podman-staging`)
- CI artifacts: GitHub Actions artifact storage (`actions/upload-artifact@v4`, `actions/download-artifact@v4`); retention 30 days; artifact names: `debs-2404-amd64`, `debs-2404-arm64`, `debs-2604-amd64`, `debs-2604-arm64`
- APT repository: GitHub Pages (`actions/upload-pages-artifact@v3`, `actions/deploy-pages@v4`); serves `repo-output/` as static site

**Caching:**
- Go module + build cache: `actions/cache@v4`; cache key pattern `go-<distro>-<arch>-<track>-<run_number>`; paths `~/.cache/go-mod`, `~/.cache/go-build`
- Nightly SHA state: `actions/cache@v4` at key `nightly-sha-v1`

## Authentication & Identity

**GPG Signing:**
- APT repository is GPG-signed by `repo_manage.sh` and `ci_publish.sh`
- CI: `GPG_PRIVATE_KEY` secret injected via `${{ secrets.GPG_PRIVATE_KEY }}`; imported into the runner's GPG keyring at publish time
- Public key served at `<repo-url>/podman-ubuntu.gpg`
- reprepro config: `SignWith: yes` in `packaging/repo/conf/distributions`

## Monitoring & Observability

**Error Tracking:**
- None (no external service)

**Logs:**
- GitHub Actions step logs (stdout/stderr of all scripts)
- Local builds: `run_logged` helper in `functions.sh` for build output
- Long Lima VM builds: redirected to `/tmp/setup.log` via nohup

## CI/CD & Deployment

**Hosting:**
- GitHub Pages - APT repository at `https://<owner>.github.io/<repo-name>/`

**CI Pipeline:**
- GitHub Actions, single workflow: `.github/workflows/build-packages.yml`
- Triggers: daily cron (`30 4 * * *` UTC) for nightly; `workflow_dispatch` for stable/edge/nightly
- Matrix: 4 cells — distro (2404, 2604) × arch (amd64, arm64); `fail-fast: false`
- Publish is atomic: all 4 build cells must succeed (`needs.build.result == 'success'`) before the `publish` job runs; partial publishes are prevented

**APT Repository Structure:**
- Tool: reprepro (`packaging/repo/conf/distributions`, `packaging/repo/conf/options`)
- 9 suites: 3 legacy aliases (`stable`, `edge`, `nightly`) + 6 versioned (`stable-2404`, `edge-2404`, `nightly-2404`, `stable-2604`, `edge-2604`, `nightly-2604`)
- Legacy aliases (`stable`, `edge`, `nightly`) map to the 2404 distro (backward compatibility via `resolve_publish_targets` in `config.sh`)
- Acquire-By-Hash enabled for all suites (`scripts/repo_byhash.sh` via `add_byhash_and_resign`)
- Non-target suites are mirrored verbatim from the live GitHub Pages repo (original GPG signatures preserved) in `scripts/ci_publish.sh`

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None (GitHub Actions publish to Pages is pull-based, not push webhook)

## Environment Configuration

**Required secrets (GitHub Actions):**
- `GPG_PRIVATE_KEY` - GPG key for signing the APT repository (`publish` job)

**Required GitHub Actions permissions:**
- `contents: read`
- `pages: write`
- `id-token: write`

**Key runtime env vars (not secrets):**
- `DESTDIR` - staging path for built binaries (set per CI run, e.g. `${{ runner.temp }}/podman-staging`)
- `DISTRO` - dotted distro version (e.g. `24.04`) threaded through `sudo env` into scripts
- `NIGHTLY_BUILD=true` - enables nightly mode
- `DEBIAN_FRONTEND=noninteractive` - suppresses apt interactive prompts in CI

---

*Integration audit: 2026-06-07*
