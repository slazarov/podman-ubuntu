---
phase: 22-migration-docs-installability-smoke-tests
verified: 2026-06-07T00:00:00Z
status: human_needed
score: 4/4 must-haves verified (static); 3 runtime behaviors need human confirmation
overrides_applied: 0
human_verification:
  - test: "Run the publish workflow — or manually invoke bash scripts/smoke_repo_install.sh 2404 <repo-output> and bash scripts/smoke_repo_install.sh 2604 <repo-output> in a Lima ubuntu-24/ubuntu-26 VM against an assembled repo-output tree — and confirm both legs print SMOKE PASS with apt install podman-suite and podman info --log-level=error exiting 0."
    expected: "Both containers exit 0; SMOKE PASS line printed for each distro; the gate step does not abort the workflow."
    why_human: "MIGR-04 requires an actual container runtime with a pullable ubuntu:24.04/ubuntu:26.04 image and a populated repo-output tree. The dev host is macOS; the plan itself explicitly defers end-to-end proof to CI or Lima: '/gsd-verify-work MUST treat MIGR-04 as CI-proven, not macOS-proven.' bash -n and YAML validity are the only checks runnable locally."
  - test: "Open the generated index.html in a browser (run ci_publish.sh against a real or stub repo-output to produce it), confirm the distro toggle defaults to Ubuntu 24.04 (active button), clicking Ubuntu 26.04 swaps all three track-tab snippets to the -2604 suite names, and the package-versions table still renders."
    expected: "Default state shows 2404 snippets; toggling to 26.04 shows 2604 snippets across stable/edge/nightly tabs; no visible layout breakage; table rows render package versions."
    why_human: "Interactive JS setDistro() show/hide logic and visual rendering of the generated HTML require a browser or at minimum a headless DOM evaluation. ci_publish.sh must actually run (Linux, privileged repo-output) before the file exists."
  - test: "On a real Ubuntu 24.04 system, follow the Ubuntu 24.04 section in docs/apt-repository.md verbatim (GPG key download, DEB822 sources block with Suites: stable-2404, apt install podman-suite) and confirm apt install succeeds and podman --version prints a version string. Repeat on Ubuntu 26.04 with the stable-2604 block."
    expected: "apt install podman-suite exits 0 on both distros; no signature or suite-not-found errors; podman --version returns a valid version."
    why_human: "SC-1 (MIGR-01) is phrased as a user outcome: copy-paste leads to a working install. The smoke gate (MIGR-04) uses Trusted: yes over file:// — it does NOT exercise the GPG Signed-By HTTPS path a real user hits. Per D-14 this is an accepted limitation, but it means no automated path verifies the actual signed HTTPS install path."
---

# Phase 22: Migration Docs & Installability Smoke Tests — Verification Report

**Phase Goal:** A user on either distro can set up the repo from copy-paste instructions specific to their version, understands the deprecation timeline for bare suite names, and every publish is gated on a real install + smoke test
**Verified:** 2026-06-07
**Status:** human_needed
**Re-verification:** No — initial verification

All four ROADMAP Success Criteria are satisfied in the codebase with substantive, wired implementations. Three runtime/visual behaviors require human confirmation before the phase can be stamped fully complete.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A 24.04 user can copy a DEB822 block with Suites: stable-2404 from docs and reach apt install podman-suite | VERIFIED (static) | `docs/apt-repository.md` L21-31: complete DEB822 block with Suites: stable-2404, Signed-By, apt install command. test_docs_suites.sh 10/10 green. |
| 2 | A 26.04 user can copy a DEB822 block with Suites: stable-2604 from docs | VERIFIED (static) | `docs/apt-repository.md` L40-53: parallel block with Suites: stable-2604. |
| 3 | Deprecation timeline (v3.0 deprecated, v3.1 removal, no fixed date) is documented | VERIFIED | Verbatim text "Deprecated in v3.0 (June 2026). Bare suite names will be removed in a future v3.1 release." present at L13 in docs, and in ci_publish.sh heredoc linking to the migration anchor. test_docs_suites.sh asserts exact phrase. |
| 4 | Migration section with sed one-liner + full replacement block | VERIFIED | `docs/apt-repository.md` L116-158: header exactly "## Migrating from Bare Suite Names", per-distro sed one-liners (L126-130), full replacement blocks for both distros. Anchor #migrating-from-bare-suite-names matches shared contract. |
| 5 | index.html presents per-distro toggle + DEB822 snippets | VERIFIED (static) | ci_publish.sh heredoc (L531-592): two distro-btn elements, six data-distro snippet pairs, setDistro() JS. test_index_html_distro.sh 15/15 green. |
| 6 | GPG key import documented once, identical Signed-By path across both distros | VERIFIED | docs/apt-repository.md L59-68: single GPG section, both distro blocks reference /etc/apt/keyrings/podman-ubuntu.gpg. ci_publish.sh: zero /usr/share/keyrings/ occurrences. |
| 7 | CI smoke gate installed between repo assembly and Pages upload, no if: guard | VERIFIED | Workflow L366-373: step between publish_distro 2604 (L355) and configure-pages (L375); no if: present in the step; TRACK from steps.track.outputs.track exported; both distro legs called. |
| 8 | Smoke helper validates distro label and installs podman-suite by name from file:// | VERIFIED (static) | smoke_repo_install.sh: case exact-match {2404,2604} L62-70; apt-get install -y -q podman-suite L202; podman info --log-level=error L205; SMOKE FAIL error names image+suite L210. |
| 9 | Runtime: apt install + podman info exit 0 in real containers | NEEDS HUMAN | Macros dev host; plan explicitly defers to CI/Lima. Smoke gate is correctly wired but unexecuted. |
| 10 | Visual: toggle defaults to 24.04 and swaps snippets in browser | NEEDS HUMAN | Generated HTML page requires ci_publish.sh execution + browser rendering. |
| 11 | Live signed APT install (HTTPS + Signed-By) works on real distro | NEEDS HUMAN | Smoke gate uses Trusted: yes / file://; does not exercise the Signed-By HTTPS path. Accepted limitation D-14. |

**Score:** 8/8 static verifiable truths VERIFIED; 3 runtime/visual truths need human confirmation.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `docs/apt-repository.md` | Per-distro DEB822 setup, single GPG key block, deprecation callout, migration section | VERIFIED | 219 lines. Ubuntu 24.04 section + Ubuntu 26.04 section + single GPG block + migration header + verbatim deprecation phrase. No trusted=yes. |
| `tests/test_docs_suites.sh` | Grep assertions for 6 distro suite names + deprecation wording | VERIFIED | 55 lines. 9 positive + 1 negative assertion. `bash tests/test_docs_suites.sh` exits 0 (10/10). |
| `scripts/ci_publish.sh` | Distro toggle markup + .distro-btn CSS + setDistro() JS + DEB822 per-distro snippets + deprecation callout | VERIFIED | setDistro(), data-distro="2404"/data-distro="2604", distro-btn, 6 per-distro DEB822 blocks, deprecation callout linking to #migrating-from-bare-suite-names. available_suites[] and table preserved (D-10). No trusted=yes. |
| `tests/test_index_html_distro.sh` | String assertions on ci_publish.sh heredoc | VERIFIED | 89 lines. 12 positive + 3 negative assertions. `bash tests/test_index_html_distro.sh` exits 0 (15/15). |
| `scripts/smoke_repo_install.sh` | File:// repo install of podman-suite + podman info, per distro | VERIFIED (static) | 222 lines. {2404,2604} whitelist, SMOKE_RUNTIME whitelist, ubuntu:26.04→resolute fallback, podman-suite by name, podman info gate, SMOKE FAIL/PASS messages naming distro+suite. `bash -n` passes. |
| `.github/workflows/build-packages.yml` | Smoke gate step in publish job | VERIFIED | Step at L366 between publish_distro 2604 (L355) and configure-pages (L375). No if: guard. TRACK from steps.track.outputs.track. YAML parses cleanly. |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| docs deprecation callout | docs #migrating-from-bare-suite-names | in-page anchor | WIRED | L13: `[Migrating from Bare Suite Names](#migrating-from-bare-suite-names)` — exact slug matches the L116 header |
| ci_publish.sh deprecation callout | docs migration section | absolute GitHub link | WIRED | ci_publish.sh L599: `https://github.com/slazarov/podman-ubuntu/blob/main/docs/apt-repository.md#migrating-from-bare-suite-names` |
| setDistro() JS | `<pre class="snippet" data-distro=...>` blocks | data-distro show/hide | WIRED (static) | ci_publish.sh L670-677: iterates .distro-btn + `.snippet` by `dataset.distro === ver` |
| .github/workflows publish job | scripts/smoke_repo_install.sh | step run invocation | WIRED | L372-373: `./scripts/smoke_repo_install.sh 2404 "$PWD/repo-output"` and `./scripts/smoke_repo_install.sh 2604 "$PWD/repo-output"` |
| smoke_repo_install.sh | assembled repo-output (file:///opt/podman-repo) | container bind-mount + DEB822 source | WIRED (static) | L177: `-v "${REPO_DIR}:/opt/podman-repo:ro"`; L187-188: `URIs: file:///opt/podman-repo`, `Suites: ${SUITE}` |

---

### Data-Flow Trace (Level 4)

Not applicable. This phase produces documentation (static content), test scripts (grep assertions), and a smoke helper (shell script). There are no data-rendering components with dynamic state variables that require data-flow tracing.

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| test_docs_suites.sh exits 0 | `bash tests/test_docs_suites.sh` | 10/10 passed | PASS |
| test_index_html_distro.sh exits 0 | `bash tests/test_index_html_distro.sh` | 15/15 passed | PASS |
| smoke_repo_install.sh syntax | `bash -n scripts/smoke_repo_install.sh` | exit 0 | PASS |
| ci_publish.sh syntax | `bash -n scripts/ci_publish.sh` | exit 0 | PASS |
| workflow YAML valid | `python3 -c "import yaml; yaml.safe_load(...)"` | yaml ok | PASS |
| smoke gate placement | line number ordering check | smoke (366) > publish_2604 (355) < configure-pages (375) | PASS |
| smoke gate has no if: guard | awk grep | 0 matches | PASS |
| Smoke gate end-to-end | `bash scripts/smoke_repo_install.sh 2404 <repo>` in ubuntu-24 Lima | not run (macOS host) | SKIP — needs human |

---

### Probe Execution

No `scripts/*/tests/probe-*.sh` probes declared for this phase. Step 7c: N/A.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MIGR-01 | 22-01-PLAN.md | User on either distro can set up repo from copy-paste DEB822 blocks specific to their Ubuntu version | VERIFIED (static) + NEEDS HUMAN (live signed install) | docs/apt-repository.md two distro sections; test_docs_suites.sh green. Live signed path requires human. |
| MIGR-02 | 22-02-PLAN.md | index.html presents per-distro setup instructions | VERIFIED (static) + NEEDS HUMAN (visual toggle) | ci_publish.sh heredoc: distro toggle + six DEB822 snippets; test_index_html_distro.sh 15/15 green. Browser rendering requires human. |
| MIGR-03 | 22-01-PLAN.md + 22-02-PLAN.md | Deprecation timeline for bare suite names documented | VERIFIED | Verbatim wording in docs and in ci_publish.sh; migration section with anchor present. |
| MIGR-04 | 22-03-PLAN.md | CI verifies installability (podman-suite install + podman info) in real containers before publish | VERIFIED (static) + NEEDS HUMAN (execution) | smoke_repo_install.sh correctly wired in workflow; execution deferred to CI/Lima per plan constraint. |

No orphaned requirements: REQUIREMENTS.md maps exactly MIGR-01, MIGR-02, MIGR-03, MIGR-04 to Phase 22; all four are claimed in plan frontmatter.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| scripts/ci_publish.sh | 537, 550, 557, 566, 573, 582, 589, 683 | `REPO_URL_PLACEHOLDER` | Info | Intentional template token, not a debt marker. L683 contains the sed substitution that replaces it. Not a stub. |

No TBD, FIXME, XXX, HACK, TODO, or PLACEHOLDER markers found in any of the six files modified by this phase. Debt-marker gate: CLEAN.

---

### Human Verification Required

#### 1. CI Smoke Gate Execution (MIGR-04)

**Test:** Run the publish workflow trigger, or in a Lima VM (`ubuntu-24` or `ubuntu-26`): `limactl shell ubuntu-24 -- bash -c 'cd /opt/podman-debian && bash scripts/smoke_repo_install.sh 2404 <assembled-repo-output>'` and the same with `2604`. An assembled `repo-output` with a `dists/` tree is required.

**Expected:** Both invocations print `SMOKE PASS: ubuntu:24.04 suite=nightly-2404` (or the relevant track) and `SMOKE PASS: ubuntu:26.04 suite=nightly-2604`; `apt-get install -y -q podman-suite` and `podman info --log-level=error` exit 0 inside each container.

**Why human:** macOS dev host cannot run containers against a Linux-assembled repo-output tree. Plan 03 explicitly states "/gsd-verify-work MUST treat MIGR-04 as CI-proven, not macOS-proven." The wiring is verified; the runtime outcome is not.

#### 2. index.html Distro Toggle Visual (MIGR-02)

**Test:** Trigger a CI run or locally invoke `ci_publish.sh` against a stub repo-output to produce `index.html`. Open the file in a browser. Confirm: (a) Ubuntu 24.04 button is active by default and the three track tabs show -2404 suite names; (b) clicking Ubuntu 26.04 swaps all three tabs to -2604 suite names; (c) the Package Versions table renders with package rows.

**Expected:** Distro toggle works without page reload; snippets swap across all tabs simultaneously; no JS console errors; package-versions table is present and populated (or shows "no data" gracefully if suites are empty).

**Why human:** setDistro() JS behavior and HTML rendering require a browser or headless DOM. The generated HTML only exists after a full ci_publish.sh run on Linux with a populated repo-output.

#### 3. Live Signed APT Install from Docs (MIGR-01 live path)

**Test:** On a real Ubuntu 24.04 system, execute the Ubuntu 24.04 section of `docs/apt-repository.md` verbatim: download GPG key to `/etc/apt/keyrings/podman-ubuntu.gpg`, write the DEB822 sources block with `Suites: stable-2404`, run `sudo apt update` and `sudo apt install -y podman-suite`. Repeat on Ubuntu 26.04 with `Suites: stable-2604`.

**Expected:** `apt update` resolves the repo without signature errors; `apt install podman-suite` exits 0; `podman --version` prints a version string.

**Why human:** The CI smoke gate uses `Trusted: yes` over a local `file://` mount — it does NOT exercise the GPG Signed-By HTTPS path from the actual docs instructions. This is an accepted limitation (D-14), but means no automated proof exists for the user-facing signed install path. This check also confirms the live GitHub Pages repo is serving the correct suite indexes.

---

### Gaps Summary

No gaps. All static deliverables are substantive and correctly wired. The three items above are runtime/visual verification that cannot be completed on the macOS dev host — they are not implementation failures; the implementation is complete. Status is `human_needed` because Step 9 rules require it whenever any human verification item exists, even at full static score.

---

_Verified: 2026-06-07_
_Verifier: Claude (gsd-verifier)_
