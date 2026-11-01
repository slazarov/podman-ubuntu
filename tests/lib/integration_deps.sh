#!/bin/bash
# Shared helper for the reprepro/gpg integration harnesses. Sourced, not run.
#
# These harnesses need reprepro, gpg and dpkg-deb. On a host without them
# (the macOS dev host) they print SKIP and pass. In CI that would hide a
# broken publish path, so lint.yml installs the tools and sets
# REQUIRE_INTEGRATION_DEPS=1, which turns the skip into a failure.

[[ -n "${_INTEGRATION_DEPS_SH_SOURCED:-}" ]] && return 0
_INTEGRATION_DEPS_SH_SOURCED=1

# require_integration_deps <what> -> call where a test would print SKIP for
# a missing tool. With REQUIRE_INTEGRATION_DEPS=1, exit 1 instead.
require_integration_deps() {
    if [[ "${REQUIRE_INTEGRATION_DEPS:-0}" == "1" ]]; then
        echo "  FAIL: REQUIRE_INTEGRATION_DEPS=1 but $1 is missing." >&2
        echo "Results: 0 passed, 1 failed"
        exit 1
    fi
}
