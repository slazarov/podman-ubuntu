# Testing Patterns

**Analysis Date:** 2026-06-07

## Test Framework

**Runner:** Plain Bash — no external test framework. Tests are standalone scripts
executed directly: `bash tests/<test>.sh`

**No config file.** Tests require no setup; they run anywhere bash is available.
Most tests run on macOS (dev host) as well as Linux.

**Run Commands:**
```bash
bash tests/test_detect_distro_depends.sh   # distro detection + runtime deps
bash tests/test_extract_version_nightly.sh # nightly version string extraction
bash tests/test_suite_routing.sh           # APT suite routing contract
bash tests/test_ci_matrix.sh              # CI workflow YAML structure
bash tests/test_alias_routing.sh          # Legacy suite alias routing
bash tests/test_mirror_verbatim.sh        # Mirror verbatim copy behavior
bash tests/test_byhash_parse.sh           # By-hash URL parsing
bash tests/test_repo_assemble_byhash.sh   # Repo assembly with by-hash
bash tests/test_distributions_suites.sh  # Distribution suite declarations
```

## Test File Organization

**Location:** All test files live in `tests/` at the project root.

**Naming:** `test_<subject>.sh` — the subject matches the function, script, or
contract being tested (e.g., `test_detect_distro_depends.sh` tests
`detect_distro_version_id()` and `detect_runtime_depends()` in `functions.sh`).

**Structure:**
```
tests/
├── test_alias_routing.sh
├── test_byhash_parse.sh
├── test_ci_matrix.sh
├── test_detect_distro_depends.sh
├── test_distributions_suites.sh
├── test_extract_version_nightly.sh
├── test_mirror_verbatim.sh
├── test_repo_assemble_byhash.sh
└── test_suite_routing.sh
```

## Test Structure

Every test file follows the same skeleton:

```bash
#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

# ============================================
# Test Framework
# ============================================

PASS_COUNT=0
FAIL_COUNT=0

assert_equals() { ... }
assert_fails()  { ... }
assert_succeeds() { ... }

# ============================================
# Load functions under test (extraction pattern)
# ============================================

# ============================================
# Test cases (numbered, labeled with echo)
# ============================================

echo "Test 1: ..."
result="$(function_under_test "input")"
assert_equals "description" "expected" "${result}"

# ============================================
# Summary
# ============================================

echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
[[ ${FAIL_COUNT} -gt 0 ]] && exit 1
exit 0
```

## Built-In Assert Functions

Each test file defines its own assert helpers inline (no shared library).
The canonical set across tests:

```bash
assert_equals() {
    local description="$1" expected="$2" actual="$3"
    if [[ "${actual}" == "${expected}" ]]; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Expected: ${expected}"
        echo "    Got: ${actual}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

assert_fails() {
    local description="$1"; shift
    if ( "$@" ) >/dev/null 2>&1; then
        echo "  FAIL: ${description}"
        echo "    Command unexpectedly succeeded: $*"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
}

assert_succeeds() {
    local description="$1"; shift
    if ( "$@" ) >/dev/null 2>&1; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Command unexpectedly failed: $*"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}
```

Some tests also define `assert_matches` (regex), `assert_contains` (substring),
and `assert_true` (command exit 0).

## Function Extraction Pattern

Tests that target functions in `functions.sh` or `config.sh` cannot source
those files directly (they trigger side effects: arch detection, os-release
reads, config.sh sourcing config.sh sourcing functions.sh). Instead, they
extract only the target function body using `sed`:

```bash
extract_fn() {
    local fn="$1"
    sed -n "/^${fn}()/,/^}/p" "${FUNCTIONS_SH}"
}

load_functions() {
    if ! grep -q "^detect_distro_version_id()" "${FUNCTIONS_SH}"; then
        echo "FATAL: detect_distro_version_id() not found in functions.sh"
        return 1
    fi
    eval "$(extract_fn detect_distro_version_id)"
    eval "$(extract_fn detect_runtime_depends)"
}
```

This pattern is used in `test_detect_distro_depends.sh` and
`test_suite_routing.sh`. It requires function definitions to start at column 0
(`^functionname()`), which is enforced by the code style.

## Mocking

**No mocking framework.** Mocks are implemented via:

1. **Subshell environment overrides** — override env vars in a clean subshell:
   ```bash
   distro_with() {
       local override="$1"
       ( unset DISTRO; export DISTRO="${override}"; detect_distro_version_id )
   }
   ```

2. **Temporary git repos** — for version-extraction tests, `setup()` creates
   real git repos with staged commits in `mktemp -d`:
   ```bash
   setup() {
       TEST_TMPDIR="$(mktemp -d)"
       git -C "${TEST_TMPDIR}" init podman --quiet
       echo 'const RawVersion = "5.9.0-dev"' > "${podman_dir}/version/rawversion/version.go"
       git -C "${podman_dir}" add -A && git -C "${podman_dir}" commit -m "init" --quiet
   }
   ```

3. **Compiled C fixtures** — `test_detect_distro_depends.sh` compiles minimal
   C programs with `gcc` to produce real ELF binaries (static and dynamic) for
   testing `detect_runtime_depends()`:
   ```bash
   gcc -static "${_tmp_dir}/hello.c" -o "${_fixture_a}"      # static — empty deps
   gcc "${_tmp_dir}/systemd_hello.c" -lsystemd -o "${_fixture_b}"  # dynamic — direct deps only
   ```

## Setup and Teardown

Tests that create temporary state use:

```bash
TEST_TMPDIR=""

setup() {
    TEST_TMPDIR="$(mktemp -d)"
    # ... create fixtures ...
}

teardown() {
    [[ -n "${TEST_TMPDIR}" ]] && rm -rf "${TEST_TMPDIR}"
}

trap 'teardown' EXIT
```

Teardown is registered via `trap EXIT` so it runs on test failure too.

## Platform-Conditional Tests

Tests that require Linux-only tools (dpkg-query, ldd, objdump) check availability
and skip gracefully on macOS:

```bash
if command -v dpkg-query &>/dev/null && command -v ldd &>/dev/null; then
    # Run dpkg-dependent assertion
    ...
else
    echo "  SKIP: dpkg-query/ldd not available (non-Debian dev host)"
    echo "  NOTE: exercised on Ubuntu host in Plan 04"
fi
```

The `SKIP:` prefix is a convention. Skipped tests do not increment `FAIL_COUNT`.

## YAML Structure Tests

`test_ci_matrix.sh` verifies the GitHub Actions workflow YAML structure. It
prefers `python3 + PyYAML` for structural checks but falls back to `grep/awk`
when PyYAML is unavailable. Grep-path assertions strip comment lines so workflow
comments cannot self-satisfy assertions.

## Test Output Format

Each test case prints one labeled result line:

```
  PASS: <description>
  FAIL: <description>
    Expected: <value>
    Got: <value>
  SKIP: <description> (non-Debian dev host)
```

The summary line always appears:
```
Results: N passed, N failed
```

## Coverage

**No coverage tooling.** There is no lcov, kcov, or similar setup.

Coverage is tracked manually. Key coverage areas:

| Area | Test File |
|------|-----------|
| `detect_distro_version_id()` | `tests/test_detect_distro_depends.sh` |
| `detect_runtime_depends()` — direct DT_NEEDED semantics | `tests/test_detect_distro_depends.sh` |
| Static binary → empty dep set (regression) | `tests/test_detect_distro_depends.sh` |
| Transitive-closure rollback (regression) | `tests/test_detect_distro_depends.sh` |
| Nightly version string extraction | `tests/test_extract_version_nightly.sh` |
| APT suite routing (`resolve_publish_targets`) | `tests/test_suite_routing.sh` |
| CI matrix YAML structure | `tests/test_ci_matrix.sh` |
| Suite alias routing | `tests/test_alias_routing.sh` |
| By-hash URL parsing | `tests/test_byhash_parse.sh` |
| Mirror verbatim behavior | `tests/test_mirror_verbatim.sh` |
| Repo assembly by-hash | `tests/test_repo_assemble_byhash.sh` |
| Distribution/suite declarations | `tests/test_distributions_suites.sh` |

Build scripts themselves (`scripts/build_*.sh`) have no unit tests; correctness
is verified via full pipeline runs in Lima VMs.

## Running in CI

Tests run as part of the GitHub Actions workflow defined in
`.github/workflows/build-packages.yml`. They are pure bash and execute on the
CI runner without Linux dependencies (except the platform-conditional blocks
which self-skip).

---

*Testing analysis: 2026-06-07*
