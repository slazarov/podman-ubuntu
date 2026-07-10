#!/bin/bash

# test_docs_suites.sh - doc-grep assertions over docs/apt-repository.md (MIGR-01/MIGR-03).
#
# Asserts the six distro-qualified suite names, the single Signed-By keyring path,
# the migration section header, and the verbatim deprecation phrase are present, and
# that the CI-internal `trusted=yes` smoke-test shortcut never leaks into the
# user-facing docs (T-22-DOC-01 security boundary).
#
# Run via `bash tests/test_docs_suites.sh`. Also auto-run in CI via the
# "Run doc and HTML unit tests" step in the publish job (WR-05).

set -euo pipefail

PASS=0
FAIL=0

assert_contains() {
    local file="$1" pattern="$2" label="$3"
    if grep -qF "$pattern" "$file"; then
        echo "PASS: $label"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label — '$pattern' not found in $file" >&2
        FAIL=$((FAIL + 1))
    fi
}

DOC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs/apt-repository.md"

# --- Positive assertions: per-distro suite names ---
assert_contains "$DOC" "stable-2404"  "24.04 stable suite name present"
assert_contains "$DOC" "stable-2604"  "26.04 stable suite name present"
assert_contains "$DOC" "edge-2404"    "24.04 edge suite name present"
assert_contains "$DOC" "edge-2604"    "26.04 edge suite name present"
assert_contains "$DOC" "nightly-2404" "24.04 nightly suite name present"
assert_contains "$DOC" "nightly-2604" "26.04 nightly suite name present"

# --- Positive assertions: keyring path, migration header, deprecation wording ---
assert_contains "$DOC" "Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg" "single Signed-By keyring path present"
assert_contains "$DOC" "Migrating from Bare Suite Names" "migration section header present"
assert_contains "$DOC" "Bare suite names will be removed in a future release" "verbatim deprecation phrase present"

# --- Negative assertion: trusted=yes must NOT leak into user-facing docs (T-22-DOC-01) ---
if grep -q "trusted=yes" "$DOC"; then
    echo "FAIL: trusted=yes leaked into user-facing docs (T-22-DOC-01)" >&2
    FAIL=$((FAIL + 1))
else
    echo "PASS: no trusted=yes in user-facing docs (T-22-DOC-01)"
    PASS=$((PASS + 1))
fi

echo "Results: ${PASS} passed, ${FAIL} failed"
[[ $FAIL -eq 0 ]]
