# Codebase Concerns

**Analysis Date:** 2026-06-07

## Tech Debt

**`git_checkout` calls `get_latest_tag` twice:**
- Issue: In `functions.sh:384-385`, `git checkout $(get_latest_tag)` and `export GIT_CHECKED_OUT_TAG=$(get_latest_tag)` each invoke `get_latest_tag` independently. Between the two calls a new upstream tag could land, so the checked-out commit and the logged tag may differ.
- Files: `functions.sh` lines 384-385
- Impact: Low probability in practice but the tag logged to `log/*.log` could be wrong, and any build tooling that keys on `GIT_CHECKED_OUT_TAG` would get the wrong label.
- Fix approach: Capture `get_latest_tag` into a local variable once and reuse it for both `git checkout` and the export.

**`config.sh` emits output on every source:**
- Issue: `config.sh:37` and `config.sh:53` print `Architecture:` and `Distro:` lines unconditionally every time the file is sourced (from `functions.sh`, `package_all.sh`, `verify_depends.sh`, etc.). This pollutes subshell captures and test output.
- Files: `config.sh` lines 37, 53
- Impact: Scripts that source `functions.sh` inside a `$(...)` subshell get noise mixed into captured output; test assertions against these scripts' stdout become brittle.
- Fix approach: Guard prints behind a `[[ -z "${QUIET:-}" ]]` flag or route them to `>&2`.

**No `GOVERSION` pinned for stable track in `versions-stable.env`:**
- Issue: `config.sh` auto-detects `GOVERSION` at source-time by fetching Podman's `go.mod` from GitHub for the pinned `PODMAN_TAG`. On failure, `get_required_go_version` falls back to `get_latest_go_version`, installing a different Go version than intended.
- Files: `config.sh` lines 172-176, `functions.sh` lines 256-303, `versions-stable.env`
- Impact: A Go version mismatch on the stable track could silently produce binaries built with a different compiler than intended. The fallback path logs a warning but does not abort.
- Fix approach: Add `export GOVERSION="<pinned>"` to `versions-stable.env` (same pattern as `PROTOC_VERSION`/`PROTOC_TAG`). The `if [[ -z "${GOVERSION:-}" ]]` guard in `config.sh` means a pinned env var wins immediately with no network call.

**Commented-out version pin blocks clutter `config.sh`:**
- Issue: `config.sh` lines 185-209 contain commented-out `GOVERSION`, `GOTAG`, `PODMAN_VERSION`, etc. blocks from previous releases.
- Files: `config.sh` lines 185-209
- Impact: Maintenance confusion; a future editor may uncomment the wrong block.
- Fix approach: Remove historical comments; the canonical pin location is `versions-stable.env`.

**`functions.sh` and `config.sh` are mutually sourcing:**
- Issue: `config.sh:12` sources `functions.sh`, and `functions.sh` ends by sourcing `config.sh`. The `_SOURCED` guards prevent infinite recursion, but a script that sources `config.sh` first could silently lack helper functions.
- Files: `functions.sh` (final line), `config.sh` line 12
- Impact: Stable today because all scripts source `functions.sh` directly. A future script sourcing `config.sh` first would silently miss function definitions.
- Fix approach: Document the canonical sourcing order; consider removing the circular dependency by inlining the arch-detection logic that `config.sh` needs before functions are defined.

## Known Bugs

**`pasta`/`passt` AVX2 variants silently omitted from `.deb` packages:**
- Symptoms: `build_pasta.sh:56-58` conditionally installs `passt.avx2` and `pasta.avx2` to `DESTDIR` when the build produces them (hardware-dependent), but `packaging/nfpm/pasta.yaml` has no entry for these binaries.
- Files: `scripts/build_pasta.sh` lines 56-58, 68-70; `packaging/nfpm/pasta.yaml`
- Trigger: Any amd64 build host that generates AVX2 variants; the binaries land in `DESTDIR` but are silently dropped by nFPM.
- Workaround: Users needing AVX2 variants must build from source. Documented as known limitation in `.planning/debug/ci-pipeline-packaging-audit.md` (BUG-7).

**`ls /opt/go/` in CI workflow is fragile:**
- Symptoms: `.github/workflows/build-packages.yml` lines 237 and 251 use `$(ls /opt/go/)` to discover the installed Go version directory. If more than one subdirectory exists (e.g. from a cached previous run), `ls` returns multiple lines and `PATH` is malformed.
- Files: `.github/workflows/build-packages.yml` lines 237, 251
- Trigger: Go cache restored from a prior run; or if `install_go.sh` writes a version-prefixed directory alongside a symlink.
- Workaround: None automatic; CI currently succeeds because only one version is installed per run. Fix: use `"${GOROOT}/bin"` (exported by `config.sh`) instead of `$(ls /opt/go/)`.

## Security Considerations

**Network calls at `config.sh` source time with no integrity verification:**
- Risk: `get_required_go_version`, `get_required_rust_version`, and `get_latest_protoc_version` (functions.sh lines 241-316) make unauthenticated `curl` requests to `github.com` and `go.dev` at source time. A MITM or compromised CDN response can inject an arbitrary toolchain version string. `curl -sf` suppresses errors silently; `|| true` on Go/Rust fetches allows continued execution with an empty version.
- Files: `functions.sh` lines 241-316; `config.sh` lines 172-188
- Current mitigation: `GOVERSION`/`RUST_VERSION`/`PROTOC_VERSION` override env vars skip all network calls when pre-set. Stable track pins `PROTOC_VERSION`; Go and Rust rely on network fetches.
- Recommendations: Pin `GOVERSION` in `versions-stable.env`. Add `--connect-timeout` to curl calls so a hanging DNS does not stall the entire build. Consider verifying fetched content against a known-good checksum or tag.

**`uninstall.sh` removes system paths without a dry-run mode:**
- Risk: `uninstall.sh` runs `rm -f` against a list of system paths; a misconfigured `DESTDIR` or wrong variable could remove files outside the intended set.
- Files: `uninstall.sh`
- Current mitigation: Script validated in Phase 10 and Phase 13 for empty-pattern safety.
- Recommendations: Add a `--dry-run` flag that prints what would be removed before acting.

**GPG private key passed as a full armored env variable in CI:**
- Risk: `GPG_PRIVATE_KEY` contains the full private key as a GitHub Actions secret. If logs are ever made public or a step accidentally echoes environment variables, the private key is exposed.
- Files: `.github/workflows/build-packages.yml` (env block in publish job)
- Current mitigation: GitHub masks secrets in log output. Key is imported ephemerally per run; not stored to disk persistently.
- Recommendations: Standard CI pattern with known risk; acceptable as-is. Rotate the key if the repository becomes public.

## Performance Bottlenecks

**`config.sh` makes up to 3 sequential network round-trips on every source:**
- Problem: Sourcing `functions.sh` triggers `get_required_go_version` (1 curl to raw.githubusercontent.com), `get_required_rust_version` (1 curl to raw.githubusercontent.com), and `get_latest_protoc_version` (1 curl to api.github.com) — all sequential, all at script startup. Any script sourcing `functions.sh` waits on these.
- Files: `config.sh` lines 172, 179, 188; `functions.sh` lines 241, 256, 305
- Cause: Version auto-detection is network-bound; the `_SOURCED` guard prevents repeat calls within one shell but not across child shells spawned by the build.
- Improvement path: Export `GOVERSION` and `RUST_VERSION` in `versions-stable.env` for stable builds. For edge/nightly, cache results to a temp file within the current run.

**`get_latest_tag` sorts all upstream tags in a Bash while loop:**
- Problem: `functions.sh:215-230` fetches all tags from the local git repo, pipes them through a while loop doing `read` + `sort --version-sort`. For repos with many tags this incurs extra CPU.
- Files: `functions.sh` lines 215-230
- Cause: Pure-Bash sort of tag list with no early exit.
- Improvement path: Replace with `git tag --sort=-version:refname | grep -E '^v?[0-9]' | head -n1` to let git do the version sort natively and terminate after the first result.

## Fragile Areas

**`COMPONENT_BINARIES` map duplicated across two files:**
- Files: `scripts/package_all.sh` lines ~285-300; `scripts/verify_depends.sh` lines ~97-108
- Why fragile: Both files declare an identical `declare -A COMPONENT_BINARIES` map. Adding a new component or changing a binary path requires editing both files; a mismatch causes `verify_depends.sh` to test a different binary set than the one actually packaged.
- Safe modification: Edit both maps in the same commit; run `verify_depends.sh` in the Lima VM to confirm the packaged and tested sets match.
- Test coverage: No automated test asserts the two maps are in sync.

**`INJECT_ONLY_DEPENDS` map also duplicated:**
- Files: `scripts/package_all.sh` lines ~315-320; `scripts/verify_depends.sh` lines ~113-117
- Why fragile: Same issue as `COMPONENT_BINARIES` — two declarations must stay in sync manually.
- Safe modification: Edit both in one commit.
- Test coverage: None for cross-file consistency.

**`packaging/repo/conf/distributions` stanza count must match `ALL_SUITES` in `config.sh`:**
- Files: `packaging/repo/conf/distributions`; `config.sh` lines 59-63
- Why fragile: If a suite is added to `ALL_SUITES` without a matching stanza in `distributions` (or vice versa), `repo_manage.sh` hard-fails at `reprepro includedeb` with a cryptic error. `tests/test_distributions_suites.sh` asserts a hard-coded count of 9 stanzas — a future suite expansion requires updating the test too.
- Safe modification: Update `ALL_SUITES`, `distributions`, and `test_distributions_suites.sh` in the same commit.
- Test coverage: `tests/test_distributions_suites.sh` (15 assertions, counts and field names) but no cross-check between `config.sh` and `distributions`.

**Ubuntu-only pipeline with hard-coded distro assumptions:**
- Files: `functions.sh` lines 67-78; `config.sh` lines 44-53; `scripts/verify_depends.sh` lines 119-135
- Why fragile: `detect_distro_version_id` rejects any `VERSION_ID` not matching `^[0-9]+\.[0-9]+$` (rejects Debian `12`, rejects `sid`). The D-14 baseline in `verify_depends.sh` is Ubuntu 24.04-specific. Extending to Debian requires changes across at least 5 files.
- Safe modification: Follow PKG-11 when addressed. Do not add a new `VALID_DISTROS` entry without also adding a baseline in `verify_depends.sh` and a stanza in `packaging/repo/conf/distributions`.
- Test coverage: `test_detect_distro_depends.sh` tests the Ubuntu path only.

## Scaling Limits

**`nightly-sha.json` SHA cache stored in Actions cache (7-day TTL):**
- Current capacity: Tracks HEAD SHAs for 13 upstream repos under cache key `nightly-sha-v1`.
- Limit: Actions cache is evicted after 7 days of non-use. A week without a successful nightly build loses the baseline, causing a spurious full rebuild.
- Scaling path: Move the SHA store to a committed file in the repo, written by a dedicated step, making it persistent and auditable.

**All workflow runs share one `pages` concurrency group:**
- Current capacity: `concurrency: group: "pages"` with `cancel-in-progress: false` serializes all deploys correctly at current cadence.
- Limit: At higher publish frequency a queued `workflow_dispatch` may wait behind a long-running cron build.
- Scaling path: Acceptable at current publish cadence; no immediate action needed.

## Dependencies at Risk

**`nfpm` installed from the internet at CI build time with no checksum:**
- Risk: `.github/workflows/build-packages.yml:238` installs nFPM via `go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.45.0`. There is no `go.sum` in the repo for this module. A yanked or tampered module version could affect builds.
- Impact: nFPM output format changes could silently corrupt `.deb` metadata.
- Migration plan: Download the prebuilt nFPM binary release and verify its SHA256, or add a `tools/` module with `go.mod`/`go.sum` tracking nFPM.

**`pasta`/`passt` cloned from a self-hosted git server:**
- Risk: `scripts/build_pasta.sh` clones from `https://passt.top/passt`. This self-hosted instance has no CDN redundancy. An outage blocks all pasta builds even when GitHub-hosted components succeed.
- Impact: Nightly/edge pasta builds fail; stable builds still require network access to `passt.top`.
- Migration plan: Add a `PASTA_REPO` override env var so the clone URL is configurable; mirror to a GitHub fork as a fallback.

## Missing Critical Features

**No Debian (non-Ubuntu) distro support:**
- Problem: The pipeline hard-fails on any non-Ubuntu `VERSION_ID`. Debian users must build from source.
- Blocks: Packaging for Debian 12 (Bookworm) or Debian testing.
- Tracked as: PKG-11 (mentioned in `functions.sh:77`)

**No `--dry-run` mode for destructive operations:**
- Problem: `uninstall.sh` and system-level installs in build scripts have no preview mode.
- Blocks: Confident testing of uninstall behavior without actually removing system files.

## Test Coverage Gaps

**`IS_VERBATIM` gate wiring in `ci_publish.sh` not covered by integration harness:**
- What's not tested: `tests/test_repo_assemble_byhash.sh` Test group G models the desired byte-stable bare-alias behavior directly but does not call `mirror_suite_verbatim` or exercise the `IS_VERBATIM` guards at `ci_publish.sh:379-382` and `ci_publish.sh:432-435`. The function itself is covered by `tests/test_mirror_verbatim.sh` (19/19).
- Files: `tests/test_repo_assemble_byhash.sh` group G; `scripts/ci_publish.sh` lines 379-382, 432-435
- Risk: A regression in the IS_VERBATIM guard wiring would not be caught by the integration harness.
- Priority: Medium

**`COMPONENT_BINARIES` / `INJECT_ONLY_DEPENDS` cross-file sync not tested:**
- What's not tested: No test asserts that `package_all.sh` and `verify_depends.sh` declare identical `COMPONENT_BINARIES` and `INJECT_ONLY_DEPENDS` maps.
- Files: `scripts/package_all.sh`; `scripts/verify_depends.sh`; `tests/` (no such test)
- Risk: Silent divergence between what gets packaged and what gets verified.
- Priority: Low

**`config.sh` / `ALL_SUITES` vs. `distributions` cross-check not tested:**
- What's not tested: `tests/test_distributions_suites.sh` hard-codes count=9; it does not parse `config.sh`'s `ALL_SUITES` and assert equality.
- Files: `tests/test_distributions_suites.sh`; `config.sh`; `packaging/repo/conf/distributions`
- Risk: A suite added in one place but not the other is only caught at `reprepro` runtime.
- Priority: Low

**Build scripts have no unit tests:**
- What's not tested: `scripts/build_*.sh`, `scripts/install_*.sh`, and `setup.sh` have no corresponding test files. Correctness is validated only by full Linux builds in Lima VMs.
- Files: `scripts/build_podman.sh`, `scripts/build_buildah.sh`, `scripts/install_go.sh`, `scripts/install_rust.sh`, `setup.sh`, etc.
- Risk: Logic regressions (wrong `DESTDIR` path, wrong `make` target) are only caught by a full hour-long build cycle.
- Priority: Medium (`bash -n` syntax checks exist but do not test runtime behavior)

---

*Concerns audit: 2026-06-07*
