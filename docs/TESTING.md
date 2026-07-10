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
containers-common), the date-based pasta scheme, 2-part-to-3-part version
normalization (toolbox), and Debian tilde-sort ordering.

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
  non-zero if any test fails, so a failing unit test **blocks** the run.
- **gitleaks** — a secret scan over full history, **informational** for now
  (to be promoted to blocking once history is confirmed clean).

The **build-packages** workflow
([`.github/workflows/build-packages.yml`](../.github/workflows/build-packages.yml),
"Build and Publish Packages") is the build-and-publish pipeline, triggered by:

- a daily schedule (`cron: '30 4 * * *'`, 4:30 AM UTC) for nightly builds, and
- manual `workflow_dispatch` runs (with a `stable` / `edge` / `nightly` choice).

Its matrix `build` job compiles the component packages natively across four
cells — 24.04 and 26.04, each on amd64 (`ubuntu-24.04`) and arm64
(`ubuntu-24.04-arm`) — and a separate `publish` job assembles and deploys the
reprepro APT repository to GitHub Pages. That publish job also runs a subset of
`tests/` inline as deploy gates (doc/HTML tests and the repo-assembly
regression tests) before uploading, so a regression there blocks the deploy.
