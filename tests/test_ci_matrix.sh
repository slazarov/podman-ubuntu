#!/bin/bash

# Test the Phase-21 CI build-matrix + publish-gating contract by parsing
# .github/workflows/build-packages.yml. Asserts:
#   - a single matrixed `build` job (no build-amd64/build-arm64)
#   - fail-fast: false under the build strategy
#   - exactly four distro×arch matrix cells (24.04/26.04 × amd64/arm64)
#   - 26.04 cells run inside ubuntu:26.04 containers; 24.04 cells do not
#   - distro-dimensioned Go cache key + artifact name
#   - publish job gated on the build job's aggregate result (atomic publish)
#   - no cross-distro download merge in the publish job
#   - ci_publish.sh invoked for both 2404 and 2604
#   - runs queue instead of cancelling (per-track workflow group, one
#     pages-deploy group for publish), with least-privilege permissions and
#     no persisted checkout credentials
#   - the resolver runs once, in resolve-track; a hold stops the build even
#     with force_rebuild; the nightly checkpoint is only restored before the
#     build and only saved after the deploy and the propagation check
#   - publish selects cells from their conclusions, downloads strictly, and
#     smoke-tests only the distros it built
#   - the compiler caches are enabled, keyed per distro and arch, and checked
#   - lint installs the integration test tools and makes skips fail
#
# Runs on the macOS dev host with NO CI: prefers python3 + PyYAML for precise
# structural checks, falls back to grep/awk against the raw YAML text when
# PyYAML is unavailable. Both paths run so the test is green either way.
# Grep-path assertions strip comment lines so workflow comments cannot
# self-satisfy a gate. Pure bash + optional python3 — no reprepro/gpg/apt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"

WORKFLOW="${PROJECT_ROOT}/.github/workflows/build-packages.yml"
LINT_WORKFLOW="${PROJECT_ROOT}/.github/workflows/lint.yml"

# ============================================
# Test Framework
# ============================================

PASS_COUNT=0
FAIL_COUNT=0

assert_equals() {
    local description="$1"
    local expected="$2"
    local actual="$3"
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

# assert_contains <description> <haystack> <needle>
assert_contains() {
    local description="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        echo "    Expected to contain: ${needle}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# assert_true <description> <0-or-1>  (1 == condition holds)
assert_true() {
    local description="$1"
    local cond="$2"
    if [[ "${cond}" == "1" ]]; then
        echo "  PASS: ${description}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "  FAIL: ${description}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo ""
echo "========================================"
echo "Test: CI build-matrix + publish-gating contract"
echo "========================================"
echo ""

# Defensive guard: SKIP cleanly only if the workflow file is entirely absent.
if [[ ! -f "${WORKFLOW}" ]]; then
    echo "SKIP: workflow file not found at ${WORKFLOW}"
    exit 0
fi

# Strip comment-only lines once for every grep-path assertion so workflow
# comments can never self-satisfy a gate (grep-gate hygiene).
NOCOMMENT="$(grep -v '^[[:space:]]*#' "${WORKFLOW}")"

HAVE_PYYAML=0
if python3 -c 'import yaml' 2>/dev/null; then
    HAVE_PYYAML=1
fi

# ============================================
# Path A: precise structural checks via PyYAML
# ============================================

run_python_assertions() {
    echo "--- Python/PyYAML structural assertions ---"

    # Each helper prints exactly "1" (holds) or "0" (fails) on stdout.
    py() { python3 -c "$1" "${WORKFLOW}"; }

    local r

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
jobs = d['jobs']
print('1' if ('build' in jobs and 'build-amd64' not in jobs and 'build-arm64' not in jobs) else '0')
")
    assert_true "py: single 'build' job (no build-amd64/build-arm64)" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print('1' if d['jobs']['build']['strategy']['fail-fast'] is False else '0')
")
    assert_true "py: build strategy fail-fast is False" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
inc = d['jobs']['build']['strategy']['matrix']['include']
print('1' if len(inc) == 4 else '0')
")
    assert_true "py: matrix include has exactly 4 cells" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
inc = d['jobs']['build']['strategy']['matrix']['include']
cells = {(str(c['distro']), str(c['arch'])) for c in inc}
want = {('2404','amd64'),('2404','arm64'),('2604','amd64'),('2604','arm64')}
print('1' if cells == want else '0')
")
    assert_true "py: all four distro×arch cells present" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
inc = d['jobs']['build']['strategy']['matrix']['include']
c2604 = [c for c in inc if str(c['distro']) == '2604']
c2404 = [c for c in inc if str(c['distro']) == '2404']
ok = (all(c.get('container') == 'ubuntu:26.04' for c in c2604)
      and all(not c.get('container') for c in c2404))
print('1' if ok else '0')
")
    assert_true "py: 2604 cells use ubuntu:26.04 container, 2404 cells do not" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print('1' if 'go-\${{ matrix.distro }}-\${{ matrix.arch }}' in open(sys.argv[1]).read() else '0')
")
    assert_true "py: Go cache key carries distro+arch dimension" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print('1' if 'debs-\${{ matrix.distro }}-\${{ matrix.arch }}' in open(sys.argv[1]).read() else '0')
")
    assert_true "py: artifact name carries distro+arch dimension" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
p = d['jobs']['publish']
ok = 'build' in p['needs'] and \"needs.build.result == 'success'\" in p['if']
print('1' if ok else '0')
")
    assert_true "py: publish gated on needs.build.result == 'success'" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = d['jobs']['publish']['steps']
dl = [s for s in steps if 'download-artifact' in str(s.get('uses', ''))]
pats = {s['with']['pattern'] for s in dl if s['with']['pattern'].startswith('debs-')}
ok = (pats == {'debs-2404-*','debs-2604-*'}
      and not any(s['with'].get('merge-multiple', False) for s in dl)
      and not any(s.get('continue-on-error') for s in steps))
print('1' if ok else '0')
")
    assert_true "py: publish downloads are per-distro, no merge, no continue-on-error" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
j = d['jobs']
wc = d['concurrency']
pc = j['publish']['concurrency']
ok = (d['permissions'] == {'contents': 'read'}
      and j['publish']['permissions'] == {'contents': 'read', 'actions': 'read', 'pages': 'write', 'id-token': 'write'}
      and all('permissions' not in v for k, v in j.items() if k != 'publish')
      and wc.get('queue') == 'max' and wc.get('cancel-in-progress') is False
      and str(wc.get('group', '')).startswith('build-packages-')
      and pc == {'group': 'pages-deploy', 'cancel-in-progress': False, 'queue': 'max'})
print('1' if ok else '0')
")
    assert_true "py: least-privilege permissions and queued concurrency" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
j = d['jobs']
rt = j['resolve-track']
cond = [c.strip() for c in str(j['build']['if']).split('&&')]
hold = [c for c in cond if 'hold' in c]
ok = ('hold' in rt['outputs'] and 'resolved_env' in rt['outputs']
      and any('resolve_track_versions' in str(s.get('run', '')) for s in rt['steps'])
      and len(hold) == 1 and 'force_rebuild' not in hold[0] and \"!= 'true'\" in hold[0]
      and \"hold != 'true'\" in str(j['check-republish']['if']))
print('1' if ok else '0')
")
    assert_true "py: resolve once; a hold stops the build even with force_rebuild" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
j = d['jobs']
cc = [str(s.get('uses', '')) for s in j['check-changes']['steps']]
ps = j['publish']['steps']
idx = lambda pred: next(i for i, s in enumerate(ps) if pred(s))
deploy = idx(lambda s: s.get('id') == 'deployment')
wait = idx(lambda s: 'wait_for_propagation' in str(s.get('run', '')))
save = idx(lambda s: 'actions/cache/save' in str(s.get('uses', '')))
ok = (any('actions/cache/restore' in u for u in cc)
      and not any('actions/cache@' in u or 'actions/cache/save' in u for u in cc)
      and deploy < wait < save
      and ps[save]['with']['path'] == '/tmp/nightly-revisions/checkpoint.txt')
print('1' if ok else '0')
")
    assert_true "py: nightly checkpoint restored before build, saved after deploy + propagation" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
b = d['jobs']['build']
ok = b.get('name') == 'build-\${{ matrix.distro }}-\${{ matrix.arch }}'
print('1' if ok else '0')
")
    assert_true "py: build cells are named build-<distro>-<arch> (publish reads them)" "${r}"

    # --- Auto-updating track wiring (stable/v5 crons + resolve-track) ---
    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
jobs = d['jobs']
ok = 'resolve-track' in jobs and 'track' in jobs['resolve-track'].get('outputs', {})
print('1' if ok else '0')
")
    assert_true "py: resolve-track job present with a 'track' output" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
# 'on' may parse as the boolean True key in YAML.
on = d.get('on', d.get(True))
crons = {c['cron'] for c in on['schedule']}
print('1' if {'30 4 * * *','30 5 * * *','30 6 * * *'} <= crons else '0')
")
    assert_true "py: three schedule crons (nightly 04:30, stable 05:30, v5 06:30)" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
on = d.get('on', d.get(True))
opts = on['workflow_dispatch']['inputs']['build_track']['options']
print('1' if opts == ['stable','v5','nightly'] else '0')
")
    assert_true "py: dispatch build_track options are [stable, v5, nightly]" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
# check-changes fires only on the nightly cron; check-republish keys on resolve-track.
cc = str(d['jobs']['check-changes']['if'])
cr = str(d['jobs']['check-republish']['if'])
ok = (\"github.event.schedule == '30 4 * * *'\" in cc
      and 'resolve-track' in str(d['jobs']['check-republish'].get('needs', []))
      and \"outputs.track == 'stable'\" in cr and \"outputs.track == 'v5'\" in cr)
print('1' if ok else '0')
")
    assert_true "py: check-changes is nightly-cron-only; check-republish gates stable/v5" "${r}"

    r=$(py "
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
print('1' if 'resolve-track' in d['jobs']['build']['needs'] else '0')
")
    assert_true "py: build job depends on resolve-track" "${r}"
}

# ============================================
# Path B: grep/awk floor (always runs)
# ============================================

run_grep_assertions() {
    echo "--- grep/awk floor assertions (comments stripped) ---"

    # 1. single build job, no build-amd64/build-arm64
    local has_build no_split
    has_build=$(printf '%s\n' "${NOCOMMENT}" | grep -Eqc '^[[:space:]]+build:' && echo 1 || echo 0)
    if printf '%s\n' "${NOCOMMENT}" | grep -Eq '^[[:space:]]+build-(amd64|arm64):'; then
        no_split=0
    else
        no_split=1
    fi
    assert_true "grep: 'build:' job present" "${has_build}"
    assert_true "grep: no build-amd64/build-arm64 jobs" "${no_split}"

    # 2. fail-fast: false
    local ff
    ff=$(printf '%s\n' "${NOCOMMENT}" | grep -Eqc 'fail-fast:[[:space:]]*false' && echo 1 || echo 0)
    assert_true "grep: fail-fast: false present" "${ff}"

    # 3. exactly four matrix cells (count '- distro:' lines)
    local cells
    cells=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec '^[[:space:]]*-[[:space:]]*distro:')
    assert_equals "grep: exactly 4 matrix '- distro:' cells" "4" "${cells}"

    # 4. two 2404 + two 2604, two amd64 + two arm64 among cells
    local d2404 d2604 aamd aarm
    d2404=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec "distro:[[:space:]]*'?2404'?")
    d2604=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec "distro:[[:space:]]*'?2604'?")
    aamd=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec '^[[:space:]]*arch:[[:space:]]*amd64')
    aarm=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec '^[[:space:]]*arch:[[:space:]]*arm64')
    assert_equals "grep: two distro 2404 cells" "2" "${d2404}"
    assert_equals "grep: two distro 2604 cells" "2" "${d2604}"
    assert_equals "grep: two amd64 cells" "2" "${aamd}"
    assert_equals "grep: two arm64 cells" "2" "${aarm}"

    # 5. ubuntu:26.04 container at least twice
    local cont
    cont=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec 'container:[[:space:]]*ubuntu:26\.04')
    assert_true "grep: container ubuntu:26.04 appears >= 2 times" \
        "$([[ "${cont}" -ge 2 ]] && echo 1 || echo 0)"

    # 6. Go cache key carries distro dimension
    assert_contains "grep: Go cache key has matrix.distro+arch" \
        "${NOCOMMENT}" 'go-${{ matrix.distro }}-${{ matrix.arch }}'

    # 7. artifact name carries distro+arch
    assert_contains "grep: artifact name has matrix.distro+arch" \
        "${NOCOMMENT}" 'debs-${{ matrix.distro }}-${{ matrix.arch }}'

    # 8. publish gating expression present
    assert_contains "grep: publish gating needs.build.result == 'success'" \
        "${NOCOMMENT}" "needs.build.result == 'success'"

    # 9. no cross-distro merge: both per-distro patterns, no bare debs-*
    local p2404 p2604 pbare
    p2404=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec 'pattern:[[:space:]]*debs-2404-\*')
    p2604=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec 'pattern:[[:space:]]*debs-2604-\*')
    if printf '%s\n' "${NOCOMMENT}" | grep -Eq 'pattern:[[:space:]]*debs-\*[[:space:]]*$'; then
        pbare=1
    else
        pbare=0
    fi
    assert_true "grep: pattern debs-2404-* present" "$([[ "${p2404}" -ge 1 ]] && echo 1 || echo 0)"
    assert_true "grep: pattern debs-2604-* present" "$([[ "${p2604}" -ge 1 ]] && echo 1 || echo 0)"
    assert_true "grep: no bare 'pattern: debs-*' (no cross-distro merge)" \
        "$([[ "${pbare}" -eq 0 ]] && echo 1 || echo 0)"

    # 10. ci_publish.sh runs for each selected distro (2404, 2604), taken in
    #     VALID_DISTROS order from config.sh, not hardcoded in the workflow.
    assert_contains "grep: publish takes the distros from config.sh" \
        "${NOCOMMENT}" "sed -n '/^VALID_TRACKS=/,/^VALID_DISTROS=/p' config.sh"
    assert_contains "grep: VALID_DISTROS lists 2404 then 2604" \
        "$(grep '^VALID_DISTROS=' "${PROJECT_ROOT}/config.sh")" "VALID_DISTROS=(2404 2604)"
    assert_contains "grep: ci_publish.sh invoked" "${NOCOMMENT}" "ci_publish.sh"

    # 10b. publish selection, strict downloads, signatures, propagation
    assert_contains "grep: publish selects cells from their conclusions" \
        "${NOCOMMENT}" 'published_cells "${RUNNER_TEMP}/cells.txt" artifacts'
    assert_contains "grep: publish reads the latest cell conclusions of the whole run" \
        "${NOCOMMENT}" '/actions/runs/${GITHUB_RUN_ID}/jobs?filter=latest'
    assert_contains "grep: publish refuses to deploy when no cell succeeded" "${NOCOMMENT}" 'refusing to deploy'
    assert_contains "grep: publish runs ci_publish.sh per selected distro" \
        "${NOCOMMENT}" './scripts/ci_publish.sh "${TRACK}" "${distro}" "${deb_dir}" "${REPO_URL}" "repo-output"'
    assert_contains "grep: smoke test runs per published distro" \
        "${NOCOMMENT}" './scripts/smoke_repo_install.sh "${distro}"'
    assert_true "grep: no step continues past an error" \
        "$(printf '%s\n' "${NOCOMMENT}" | grep -q 'continue-on-error' && echo 0 || echo 1)"
    assert_true "grep: no download merges artifacts" \
        "$(printf '%s\n' "${NOCOMMENT}" | grep -q 'merge-multiple: true' && echo 0 || echo 1)"
    assert_contains "grep: integrity gate checks signatures" "${NOCOMMENT}" 'verify_repo_integrity.sh --keyring'
    assert_contains "grep: propagation is checked after deploy" "${NOCOMMENT}" 'wait_for_propagation "${REPO_URL}"'

    # 10c. resolver once, queues, credentials
    assert_equals "grep: the resolver runs exactly once (resolve-track)" "1" \
        "$(printf '%s\n' "${NOCOMMENT}" | grep -c 'resolve_track_versions\|resolve_versions.sh')"
    assert_contains "grep: workflow runs queue per track" "${NOCOMMENT}" 'group: build-packages-${{'
    assert_contains "grep: publish has its own deploy queue" "${NOCOMMENT}" 'group: pages-deploy'
    assert_equals "grep: both concurrency groups use queue: max" "2" \
        "$(printf '%s\n' "${NOCOMMENT}" | grep -cE '^[[:space:]]*queue: max$')"
    assert_true "grep: no concurrency group cancels in-progress runs" \
        "$(printf '%s\n' "${NOCOMMENT}" | grep -q 'cancel-in-progress: true' && echo 0 || echo 1)"
    local nocomment_lint
    nocomment_lint="$(grep -v '^[[:space:]]*#' "${LINT_WORKFLOW}")"
    assert_equals "grep: every checkout drops its credentials" \
        "$(printf '%s\n%s\n' "${NOCOMMENT}" "${nocomment_lint}" | grep -c 'actions/checkout@')" \
        "$(printf '%s\n%s\n' "${NOCOMMENT}" "${nocomment_lint}" | grep -c 'persist-credentials: false')"

    # 10d. compiler caches
    assert_contains "grep: compiler cache key has distro, arch, track and toolchain" "${NOCOMMENT}" \
        'key: cc-v1-${{ matrix.distro }}-${{ matrix.arch }}-${{ steps.track.outputs.track }}-rust${{ steps.env.outputs.rust }}-sccache${{ steps.env.outputs.sccache }}-${{ github.run_id }}'
    assert_contains "grep: compiler caches enabled and strict" "${NOCOMMENT}" 'SCCACHE_ENABLED=true CCACHE_ENABLED=true CACHE_STRICT=true'
    assert_contains "grep: compiler cache use is checked" "${NOCOMMENT}" 'compiler_cache_report'
    assert_contains "grep: ccache counters are zeroed before the build" "${NOCOMMENT}" 'ccache --zero-stats'
    assert_contains "grep: compiler cache is saved only when it changed" "${NOCOMMENT}" "if: steps.ccreport.outputs.changed == 'true'"
    assert_true "grep: the compiler cache is not saved on every run by actions/cache" \
        "$(printf '%s\n' "${NOCOMMENT}" | grep -B3 '~/.cache/sccache' | grep -q 'uses: actions/cache@' && echo 0 || echo 1)"
    assert_contains "grep: build cells record nightly revisions per cell" "${NOCOMMENT}" \
        'nightly_record_revisions build "${{ matrix.distro }}-${{ matrix.arch }}"'

    # 10e. lint runs the integration tests
    assert_contains "grep: lint installs the integration test tools" "${nocomment_lint}" 'reprepro gnupg gpgv dpkg-dev'
    assert_contains "grep: lint makes integration skips fail" "${nocomment_lint}" "REQUIRE_INTEGRATION_DEPS: '1'"

    # 11. three schedule crons (nightly/stable/v5) + resolve-track job
    local ncron
    ncron=$(printf '%s\n' "${NOCOMMENT}" | grep -Ec "cron:[[:space:]]*'30 [456] \* \* \*'")
    assert_equals "grep: three schedule crons (30 4/5/6)" "3" "${ncron}"
    assert_contains "grep: resolve-track job present" "${NOCOMMENT}" "resolve-track:"

    # 12. dispatch offers v5, never the retired edge track
    assert_contains "grep: dispatch build_track offers v5" "${NOCOMMENT}" "- v5"
    local has_edge
    if printf '%s\n' "${NOCOMMENT}" | grep -Eq '^[[:space:]]*-[[:space:]]*edge[[:space:]]*$'; then
        has_edge=0
    else
        has_edge=1
    fi
    assert_true "grep: no retired 'edge' dispatch option" "${has_edge}"
}

if [[ "${HAVE_PYYAML}" -eq 1 ]]; then
    run_python_assertions
    echo ""
else
    echo "--- PyYAML not available; running grep floor only ---"
    if [[ "${REQUIRE_INTEGRATION_DEPS:-0}" == "1" ]]; then
        echo "  FAIL: REQUIRE_INTEGRATION_DEPS=1 but PyYAML is missing."
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
fi
run_grep_assertions

# ============================================
# Summary
# ============================================

echo ""
echo "========================================"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "========================================"

if [[ ${FAIL_COUNT} -gt 0 ]]; then
    exit 1
fi
exit 0
