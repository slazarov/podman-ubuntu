#!/bin/bash

# test_index_html_distro.sh — string assertions on the index.html heredoc
# emitted by scripts/ci_publish.sh Step 5. The heredoc is the authoritative
# string, so this greps the ci_publish.sh source directly (no need to run the
# generator). Also auto-run in CI via the "Run doc and HTML unit tests" step
# in the publish job (WR-05).
#
# Covers MIGR-02 (per-distro distro toggle + DEB822 snippets + setDistro JS)
# and MIGR-03 (deprecation callout linking to the docs migration anchor).
#
# Counters use the assignment form PASS=$((PASS+1)) (NOT ((PASS++))) so they do
# not return a non-zero status under `set -e` when the counter is 0.

set -euo pipefail

PASS=0
FAIL=0

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/ci_publish.sh"

# Positive assertion: SRC must contain the literal pattern (fixed-string grep so
# bracket/regex metacharacters in patterns are matched verbatim).
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

# Negative assertion: SRC must NOT contain the literal pattern. Uses -F so an
# unterminated bracket expression (e.g. 'deb [signed-by=') is matched verbatim
# rather than misread as a character class.
assert_absent() {
    local file="$1" pattern="$2" label="$3"
    if grep -qF "$pattern" "$file"; then
        echo "FAIL: $label — '$pattern' unexpectedly present in $file" >&2
        FAIL=$((FAIL + 1))
    else
        echo "PASS: $label"
        PASS=$((PASS + 1))
    fi
}

echo ""
echo "========================================"
echo "Test: index.html distro toggle / DEB822 snippets (ci_publish.sh heredoc)"
echo "========================================"
echo ""

# ----- Distro toggle + setDistro() JS (MIGR-02) -----
assert_contains "$SRC" "setDistro"              "setDistro() function defined"
assert_contains "$SRC" 'data-distro="2404"'     "data-distro 2404 snippet present"
assert_contains "$SRC" 'data-distro="2604"'     "data-distro 2604 snippet present"
assert_contains "$SRC" "distro-btn"             ".distro-btn CSS/markup present"

# ----- Per-distro DEB822 suite names (MIGR-02 / D-02) -----
assert_contains "$SRC" "stable-2404"            "suite stable-2404 in heredoc"
assert_contains "$SRC" "stable-2604"            "suite stable-2604 in heredoc"
assert_contains "$SRC" "v5-2404"                "suite v5-2404 in heredoc"
assert_contains "$SRC" "v5-2604"                "suite v5-2604 in heredoc"
assert_contains "$SRC" "nightly-2604"           "suite nightly-2604 in heredoc"

# ----- DEB822 Signed-By keyring path (ROADMAP SC-4) -----
assert_contains "$SRC" "Signed-By: /etc/apt/keyrings/podman-ubuntu.gpg" \
                                                "DEB822 Signed-By keyring path present"

# ----- Deprecation callout link (MIGR-03 — shared anchor with Plan 01) -----
assert_contains "$SRC" "migrating-from-bare-suite-names" \
                                                "deprecation callout links to docs migration anchor"

# ----- Negative: legacy keyring path / legacy one-liner / trusted=yes (T-22-HTML-02) -----
assert_absent "$SRC" "/usr/share/keyrings/"     "legacy /usr/share/keyrings/ path absent"
assert_absent "$SRC" "deb [signed-by="          "legacy deb one-liner snippet absent"
assert_absent "$SRC" "trusted=yes"               "trusted=yes absent from user-facing snippets"

# ----- D-10 guard: package-versions table preserved -----
assert_contains "$SRC" "<th>Package</th>"       "package-versions table header preserved (D-10)"

echo ""
echo "========================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "========================================"

[[ $FAIL -eq 0 ]]
