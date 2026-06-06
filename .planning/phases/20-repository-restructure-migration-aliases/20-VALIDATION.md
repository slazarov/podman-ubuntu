---
phase: 20
slug: repository-restructure-migration-aliases
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-06
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bash unit tests, run directly: `bash tests/<test>.sh` (project convention, no harness — RESEARCH Validation Architecture) |
| **Config file** | none — plain bash scripts in `tests/` |
| **Quick run command** | `bash tests/test_<name>.sh` (single file; runs anywhere with bash, including macOS) |
| **Full suite command** | `for t in tests/*.sh; do bash "$t" || exit 1; done` |
| **Estimated runtime** | ~seconds for unit tests; VM integration (assemble repo → `apt update` on ubuntu-24 Lima) adds minutes and runs on Lima/CI only |

---

## Sampling Rate

- **After every task commit:** Run `bash -n <touched script>` (macOS-safe) + relevant `bash tests/test_*.sh` unit test
- **After every plan wave:** Run full `tests/*.sh` suite + (if reachable) Lima-VM assemble-and-`apt update` smoke
- **Before `/gsd-verify-work`:** Full assembled-repo verification on ubuntu-24 Lima VM (legacy-client + by-hash signature verify) green
- **Max feedback latency:** <10 seconds for unit tests; VM integration deferred to wave gates

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| _filled by planner from plan task breakdown_ | | | REPO-06 | | 9 stanzas, unique Suite==Codename, SignWith on each | unit (parse) | `bash tests/test_distributions_suites.sh` | ❌ W0 | ⬜ pending |
| _filled by planner_ | | | REPO-06 | | track+distro → correct `<track>-<distro>` suite; whitelist rejects bad input | unit (pure function) | `bash tests/test_suite_routing.sh` | ❌ W0 | ⬜ pending |
| _filled by planner_ | | | REPO-07 | | 24.04 publish targets include bare alias; 26.04 does not | unit (routing) | `bash tests/test_alias_routing.sh` | ❌ W0 | ⬜ pending |
| _filled by planner_ | | | REPO-07 | | Legacy `.sources` on bare `stable` → no "Suite value changed", 24.04 deb resolves | integration (VM) | ubuntu-24 Lima `apt update` + `apt-cache policy` | ❌ W0 (VM) | ⬜ pending |
| _filled by planner_ | | | REPO-08 | | Every suite Release has `Acquire-By-Hash: yes`; by-hash dirs adjacent to each index; InRelease/Release.gpg verify after injection | integration (VM/CI) | `gpg --verify InRelease` + path-exists asserts on real export | ❌ W0 (VM/CI) | ⬜ pending |
| _filled by planner_ | | | REPO-08 | | by-hash parser extracts correct (hash, relpath) from sample reprepro Release | unit (fixture) | `bash tests/test_byhash_parse.sh` | ❌ W0 | ⬜ pending |
| _filled by planner_ | | | Crit. 4 | | Publishing one suite leaves the other suites' Packages intact (mirror-then-include) | integration (CI/VM) | assemble repo with 2 suites, publish 1, diff the other's Packages | ❌ W0 (VM/CI) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/test_distributions_suites.sh` — parses `conf/distributions`, asserts 9 stanzas, unique Suite==Codename, SignWith present (REPO-06)
- [ ] `tests/test_suite_routing.sh` — pure routing function track+distro→suite + whitelist rejection (REPO-06/07)
- [ ] `tests/test_alias_routing.sh` — 24.04 includes bare alias, 26.04 does not (REPO-07)
- [ ] `tests/test_byhash_parse.sh` — by-hash Release-section parser against a literal fixture (REPO-08)
- [ ] VM/CI integration harness — assemble repo → inject by-hash → `gpg --verify InRelease` → `apt update` on ubuntu-24 (REPO-07/08, Crit. 4). macOS cannot run this; runs on Lima/CI.
- [ ] Routing logic extracted into a sourceable function (config.sh or functions.sh) so unit tests call it without a full publish — mirrors Phase 19's pure-function pattern

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Legacy client continuity against the *deployed* GitHub Pages repo | REPO-07 | Production CDN behavior (caching, by-hash fetch path) only observable post-deploy | On ubuntu-24 Lima VM with bare `stable` `.sources`: `apt update` (expect no "Suite value changed" prompt), `apt-cache policy podman` resolves a 24.04 build |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s (unit); VM integration at wave gates
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
