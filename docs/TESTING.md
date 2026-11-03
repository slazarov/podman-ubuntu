# Testing

This project is a shell-orchestrated build and packaging pipeline, not an
application with a runtime test suite. Its tests are plain Bash scripts that
exercise the version-derivation logic used during packaging. They run directly,
with no external test framework or dependency installation required.

## Test Framework and Setup

The project uses a **self-contained Bash test harness** — there is no Jest,
pytest, Bats, or other third-party framework, and no package manager or
toolchain install is needed to run the tests.

- **Language:** Bash (scripts use `#!/bin/bash` and `set -euo pipefail`).
- **Assertion helpers:** Each test file defines its own helpers inline —
  `assert_matches`, `assert_equals`, and `assert_true` — and tracks
  `PASS_COUNT` / `FAIL_COUNT` to produce a final summary and exit code.
- **Fixtures:** Tests build throwaway Git fixture repositories under a `mktemp -d`
  directory in a `setup` function and remove them in `teardown`, so they require
  only `git` and standard coreutils on the host.

The only optional external tool is `dpkg` (for the Debian version-sort
assertion). When `dpkg` is not available — for example, on macOS — that single
assertion is skipped and the expected Debian tilde-sort behavior is documented
inline instead, so the suite still completes on non-Debian hosts.

## Running Tests

There is no `Makefile`, `npm` script, or other test runner. Each test is an
executable script you invoke directly.

Run the version-extraction test:

```bash
./tests/test_extract_version_nightly.sh
```

Or invoke it explicitly through Bash:

```bash
bash tests/test_extract_version_nightly.sh
```

Run every test in the `tests/` directory:

```bash
for t in tests/*.sh; do
  echo "=== $t ==="
  bash "$t" || echo "FAILED: $t"
done
```

Each test prints a per-assertion `PASS` / `FAIL` line, a final
`Results: N passed, M failed` summary, and exits non-zero if any assertion
failed — so the scripts are safe to chain in CI or a shell loop.

Some tests need Ubuntu tools and print `SKIP` without them:

- `reprepro`, `gpg`, `gpgv`, `dpkg-deb`, `python3`, `curl`: the repository
  assembly tests (`test_repo_assemble_byhash.sh`, `test_ci_publish_multipass.sh`,
  `test_ci_publish_shared_pool.sh`).
- `gpg` and `gpgv`: the signature checks in `test_verify_repo_integrity.sh`.
- `python3`, `curl`, `git`: `test_ci_helpers.sh` and the server-error checks in
  `test_mirror_verbatim.sh`.

A skipped check passes, which is convenient on a laptop and dangerous in CI.
Set `REQUIRE_INTEGRATION_DEPS=1` and every skip caused by a missing tool
becomes a failure. Both CI workflows set it:

```bash
REQUIRE_INTEGRATION_DEPS=1 bash tests/test_ci_publish_multipass.sh
```

The tests never touch the live repository. The assembly tests generate a
throwaway GPG key in a temporary `GNUPGHOME`, build fixture `.deb` files, and
serve a mock "live" repository over HTTP. Tests that need a misbehaving server
use `tests/lib/mock_http_server.py`, which serves a directory and answers
chosen paths with an HTTP error or a cut-off body, for every request or only
the first few. `tests/lib/mock_http.sh` starts and stops it.

What the CI-pipeline tests cover:

| Test | Covers |
|------|--------|
| `test_ci_helpers.sh` | `scripts/ci_helpers.sh`: `fetch_url` against injected 404, 410, 429, 503, 403 and cut-off bodies (absent versus error, retry counts, no partial files); `validate_resolved_env` (and that its names match the resolver); recording, detecting and merging nightly revisions per build cell, including a failed cell keeping its old entries; build cell selection (a distro with one failed arch still publishes; `CI_BUILD_ARCHES` matches the workflow matrix); `wait_for_propagation`; the compiler cache statistics |
| `test_check_republish.sh` | The republish guard's helpers, and its decision with a resolved-env file against `file://` repositories: all current skips; a stale distro/arch, a differing `podman-suite` or an unpublished suite builds; an invalid file fails; the resolver is not run |
| `test_ci_matrix.sh` | The workflow structure: four distro × arch cells, per-cell cache keys and artifacts, queued concurrency, least-privilege permissions, no persisted checkout credentials, a single resolver run whose hold stops the build even with `force_rebuild`, the nightly checkpoint saved only after deploy and propagation, cell selection from conclusions, strict downloads, compiler caches, lint running the integration tests |
| `test_mirror_verbatim.sh` | `mirror_suite_verbatim`, and that a server error is reported as an error, never as an unpublished suite |
| `test_verify_repo_integrity.sh` | The integrity gate, including a missing `Codename` or `SHA256` section, an unlisted architecture, a stanza without `Size`/`SHA256`, an `InRelease` that signs different text, a foreign signature and a missing `Release.gpg` |
| `test_repo_assemble_byhash.sh` | Real reprepro assembly with by-hash and re-signing, including that a failing clearsign or detached sign is reported |
| `test_ci_publish_multipass.sh` | Two `ci_publish.sh` passes into one output: no clobbering, the previous by-hash generation kept, signatures verified. Then the failure paths: a pool file answering 503, 404 or cut off, or a live `Release`/`Packages` answering 503, stops the publish; one 503 is retried; a failing signature step stops it; an amd64-only build keeps arm64 at its last-good version, and a failed arm64 download stops the publish instead of wiping arm64 |
| `test_ci_publish_shared_pool.sh` | The shared pool: a rebuild of a published version adopts the published bytes (from another suite, or from the live target index itself), a corrupted live repository is healed with its previous by-hash generation kept, and a missing arch is preserved |

## Writing New Tests

New tests follow the conventions established by
[`tests/test_extract_version_nightly.sh`](../tests/test_extract_version_nightly.sh):

- **File naming and location.** Place test scripts in `tests/`, name them
  `test_<thing-under-test>.sh`, and mark them executable (`chmod +x`).
- **Strict mode.** Start with `set -euo pipefail`.
- **Locate the project root** relative to the script so tests run from any
  working directory:

  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
  ```

- **Reuse the assertion helpers.** Copy the `assert_matches`, `assert_equals`,
  and `assert_true` helpers (and the `PASS_COUNT` / `FAIL_COUNT` counters) from
  the existing test, or factor them into a shared helper file if more tests are
  added.
- **Isolate side effects.** Create fixtures in a `mktemp -d` directory inside a
  `setup` function and delete them in `teardown`. The existing test builds small
  mock upstream repos (Podman, Buildah, crun, Netavark, etc.) with `git init`
  and commits/tags to simulate real source layouts.
- **Source the unit under test in isolation.** Because the build scripts execute
  work at load time, the existing test extracts just the target function with
  `sed` and `eval`s it rather than sourcing the whole script:

  ```bash
  eval "$(sed -n '/^extract_version_nightly()/,/^}/p' \
    "${PROJECT_ROOT}/scripts/package_all.sh")"
  ```

- **Guard platform-specific assertions.** Wrap checks that depend on tools like
  `dpkg` in a `command -v dpkg &>/dev/null` test, and provide a documented skip
  path for hosts that lack them.
- **Exit codes.** End the script by exiting non-zero when `FAIL_COUNT > 0` so
  the result is machine-detectable.

## Coverage Requirements

No coverage tooling or threshold is configured; the Bash harness does not
measure line, branch, or function coverage.

Current test scope is focused on the packaging version-derivation logic
(`extract_version_nightly` in `scripts/package_all.sh`), covering each
component's version format: Go-based projects (Podman, Buildah, Skopeo),
Rust projects (Netavark, Aardvark-DNS, fuse-overlayfs v2.0+), C/autotools
projects (fuse-overlayfs v1.x, catatonit), tag-based projects (crun,
containers-common), the nightly pasta `1:<YYYY.MM.DD>~git<sha>` scheme, 2-part-to-3-part version
normalization (toolbox), and Debian tilde-sort ordering.

`tests/test_resolve_versions.sh` covers the stable/v5 version resolver offline
(`scripts/resolve_versions.sh`): the `*_SERIES` anchored-prefix cap, the
`STABLE_SOAK_DAYS` soak window, deriving Buildah's version from Podman's
`go.mod`, and ranking/soaking passt's date-shaped `YYYY_MM_DD.<sha>` release
tags for pasta, including same-day releases ordered by commit time
(`functions.sh:pasta_version` → `1:2026.10.02`, `1:2026.10.02.1`).
`tests/test_check_republish.sh` pins the guard's pasta base to
`package_all.sh:extract_version` on a same-day fixture, replays package_all.sh's
epoch split, renders `pasta.yaml`, and checks that the rendered `epoch:` and
`version:` rebuild the guard target (`1:2026.10.02~…`) with an epoch-free
filename (it does not run nFPM; `scripts/verify_depends.sh` Part B runs nFPM on
the rendered `pasta.yaml` and checks the control `Version:` starts with `1:`),
checks the guard compares `podman-pasta`, and asserts the dpkg ordering
`1:2026.10.02 < 1:2026.10.02.1 < 1:2026.10.03` plus pre-epoch upgrades
(`20261101`, `20261024`, `YYYYMMDD~git<sha>` < every `1:` version).
`scripts/verify_versions.sh` asserts the same upgrade orderings.

## CI Integration

Two GitHub Actions workflows cover this repository.

The **lint** workflow
([`.github/workflows/lint.yml`](../.github/workflows/lint.yml)) is the fast
quality gate, running on every push to `main` and every pull request. It has
four jobs:

- **ShellCheck** — `severity=error`, **blocking**. Reads `.shellcheckrc`
  (external-sources, SC1091 off) and fails the run on real breakage.
- **shfmt** — a formatting diff against the house style (`shfmt -i 4 -ci -sr`),
  **informational** (`continue-on-error`), surfacing drift without blocking.
- **bash unit tests** — runs every `tests/test_*.sh` script in a loop and exits
  non-zero if any test fails, so a failing unit test **blocks** the run. It
  installs `reprepro`, `gnupg`, `gpgv`, `dpkg-dev`, `libsystemd-dev` and
  `python3-yaml` and sets `REQUIRE_INTEGRATION_DEPS=1`, so the reprepro/gpg
  integration harnesses run on every PR: with that variable set, a harness
  whose tools are missing fails (via `tests/lib/integration_deps.sh`) instead
  of printing SKIP and passing. The publish job runs the repo-assembly tests
  and `test_ci_helpers.sh` again, with the same setting, before it deploys.
- **gitleaks** — a secret scan over full history, **informational** for now
  (to be promoted to blocking once history is confirmed clean).

The **build-packages** workflow
([`.github/workflows/build-packages.yml`](../.github/workflows/build-packages.yml),
"Build and Publish Packages") is the build-and-publish pipeline, triggered by:

- three daily schedules — `30 4` (nightly), `30 5` (stable), `30 6` (v5) UTC —
  with a `resolve-track` job mapping the firing cron to a track, and
- manual `workflow_dispatch` runs (with a `stable` / `v5` / `nightly` choice).

Its matrix `build` job compiles the component packages natively across four
cells — 24.04 and 26.04, each on amd64 (`ubuntu-24.04`) and arm64
(`ubuntu-24.04-arm`) — and a separate `publish` job assembles and deploys the
reprepro APT repository to GitHub Pages. That publish job also runs a subset of
`tests/` inline as deploy gates (doc/HTML tests and the repo-assembly
regression tests) before uploading, so a regression there blocks the deploy.

The last gate before upload is `scripts/smoke_repo_install.sh`, run once per
distro this run built and published (suites carried over from the live
repository were tested when they were published). apt reads the assembled repo
with `Signed-By` set to its `podman-ubuntu.gpg`, so the signatures are checked
as on a user's machine. Each scenario runs in a fresh privileged
`ubuntu:<distro>` container, and any failure blocks the deploy:

- **fresh** — install `podman-suite`, `podman info` as root, then as a rootless
  user *with their own* `~/.config/containers/containers.conf` run a container
  on a bridge network and resolve its name through aardvark-dns.
- **migrate** — install Ubuntu's own `podman`, then `podman-suite` over it;
  `dpkg --audit` must be clean.
- **upgrade** — install from the live published repo, then `apt full-upgrade`
  to the new build, and check that every installed package of the suite (and
  `podman-suite`) is `install ok installed` at the assembled version. Skipped
  when the live `InRelease` returns 404 (the suite is not published yet); a
  network or server error fails instead.

Run it locally against any assembled repo with
`TRACK=stable LIVE_REPO_URL=https://... ./scripts/smoke_repo_install.sh 2404 repo-output`.
