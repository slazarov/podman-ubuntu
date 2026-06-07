---
status: partial
phase: 20-repository-restructure-migration-aliases
source: 20-01-SUMMARY.md, 20-02-SUMMARY.md, 20-03-SUMMARY.md, 20-04-SUMMARY.md, 20-05-SUMMARY.md, 20-06-SUMMARY.md
started: 2026-06-07T02:03:01Z
updated: 2026-06-07T02:20:00Z
---

## Current Test

[testing paused — 1 item outstanding (production-URL smoke, blocked on first CI publish)]

## Tests

### 1. macOS-safe unit tests pass
expected: Running `bash tests/test_distributions_suites.sh`, `bash tests/test_suite_routing.sh`, `bash tests/test_alias_routing.sh`, `bash tests/test_byhash_parse.sh` on the macOS dev host — each exits 0 with all assertions passing (15 + 8 + 12 + 8), no reprepro/gpg/apt needed.
result: pass
evidence: "All four suites run on macOS dev host: 15/0, 8/0, 12/0, 8/0 — exit 0 each (43 assertions total)."

### 2. Nine-suite distributions config
expected: `packaging/repo/conf/distributions` contains exactly 9 stanzas — 6 versioned (`stable-2404`, `stable-2604`, `edge-2404`, `edge-2604`, `nightly-2404`, `nightly-2604`) plus 3 bare legacy aliases (`stable`, `edge`, `nightly`). Every stanza has Suite==Codename and `SignWith: yes`; the 3 bare aliases carry a DEPRECATED note in their Description.
result: pass
evidence: "Direct inspection: 9 Suite lines, 9 Codename lines, 9 `SignWith: yes`, 3 DEPRECATED; all 6 versioned + 3 bare suites present."

### 3. Suite routing helper implements the D-12 alias rule
expected: `resolve_publish_targets stable 2404` emits two lines — `stable-2404` then `stable` — while `resolve_publish_targets stable 2604` emits only `stable-2604`. An invalid track or distro prints a clear error to stderr and returns non-zero.
result: pass
evidence: "Direct invocation (bash, sed-extracted from config.sh): stable 2404 → stable-2404 + stable (rc=0); stable 2604 → stable-2604 only (rc=0); bogus track → 'Invalid track' rc=1; 2410 distro → 'Invalid distro' rc=1."

### 4. Integration harness green on Lima ubuntu-24
expected: `bash tests/test_repo_assemble_byhash.sh` on Lima ubuntu-24 runs the real reprepro/gpg assemble and reports 62 passed, 0 failed across groups A–G — Acquire-By-Hash injection, by-hash adjacency, valid signature chain after mutation, no-clobber, empty-but-signed stable-2604, pipefail isolation (F), and verbatim bare-alias preservation on a 26.04 publish (G).
result: pass
evidence: "Run on Lima ubuntu-24 at HEAD e42d1df: Results: 62 passed, 0 failed, exit 0. Groups D/E/F/G all observed passing in output."

### 5. CI publish job passes the new 5-arg shape
expected: In `.github/workflows/build-packages.yml`, the publish job's `track` step emits `distro=2404` as a step output, and `ci_publish.sh` is invoked with 5 positional args with `${{ steps.track.outputs.distro }}` as the second arg. The reprepro install, artifact download, and atomic Pages deploy steps are unchanged.
result: pass
evidence: "Line 295: `echo \"distro=2404\" >> $GITHUB_OUTPUT` in publish job track step; lines 312–317: ci_publish.sh called with track, distro, all-debs, repo-url, repo-output; reprepro install (303), download-artifact (297), configure/upload/deploy-pages (319–326) intact."

### 6. Legacy-client continuity (D-15 simulation)
expected: Local-VM old-tree→new-tree swap on Lima ubuntu-24: `apt-get update` against the swapped 9-suite tree exits 0 with NO "changed its 'Suite' value" prompt, `apt-cache policy podman-suite` resolves a `~ubuntu24.04.podman1` candidate from bare `stable`, and by-hash URL fetch returns HTTP 200 on bare `stable` and `stable-2404`.
result: pass
evidence: "Re-ran the full D-15 simulation at HEAD e42d1df (not just relying on the Plan-04 record): old 3-stanza tree (dafa53c^) served on localhost:8099, apt cached old Suite, tree swapped to new 9-suite assembly built with repo_manage.sh stable 2404 + add_byhash_and_resign per suite. Results: 7 passed, 0 failed — update exit 0, no Suite-change prompt, no E:/Conflicting/Release-file errors, candidate 5.0.0~ubuntu24.04.podman1, by-hash HTTP 200 on both suites. VM left clean (sources, keyring, server, /tmp/d15-uat all removed)."

### 7. Production-URL smoke after first CI publish
expected: After the 9-suite tree is first published to GitHub Pages, the deferred commands from 20-04-SUMMARY.md against the real REPO_URL show: legacy bare-`stable` client `apt-get update` exits 0 with no Suite-change prompt, a `~ubuntu24.04.podman1` candidate resolves, and the by-hash fetch returns HTTP 200 from the production CDN.
result: blocked
blocked_by: release-build
reason: "The 9-suite tree has not been published: local main is 80 commits ahead of origin/main (all phase 19+20 work unpushed), and live Pages (https://slazarov.github.io/podman-ubuntu) still serves the old 3-suite tree — dists/stable|edge|nightly return HTTP 200, all versioned -2404/-2604 suites 404. Re-run the deferred commands after push + first CI publish. Per 20-04-SUMMARY.md this is a production confirmation, not a phase gate — the apt-client behavior is already proven locally (Test 6)."

## Summary

total: 7
passed: 6
issues: 0
pending: 0
skipped: 0
blocked: 1

## Gaps

[none — the single blocked test is a prerequisite gate (first CI publish), not a code issue]
