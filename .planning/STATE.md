---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: Ubuntu 26.04 Support
status: executing
stopped_at: Phase 20 complete, ready to plan Phase 21
last_updated: "2026-06-07T02:47:13.545Z"
last_activity: 2026-06-07 -- Phase 20 complete (UAT 8/9 on Lima VMs, verification 4/4)
progress:
  total_phases: 4
  completed_phases: 2
  total_plans: 11
  completed_plans: 11
  percent: 50
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-06-07)

**Core value:** Compile and install Podman on any Debian/Ubuntu system without user interaction.
**Current focus:** Phase 21 — CI Build Matrix Extension to 26.04

## Current Position

Phase: 21 (ci-build-matrix-extension-to-26.04)
Plan: Not started
Status: Ready to execute
Last activity: 2026-06-07 -- Phase 20 complete (UAT 8/9 on Lima VMs, verification 4/4)

Progress: [█████░░░░░] 50% (2/4 v3.0 phases)

## Performance Metrics

**Velocity:**

- Total plans completed: 41 (all milestones, v1.0-v2.0)
- Average duration: 3min
- Total execution time: 24min

**By Phase (v2.0):**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 14. Debian Package Building | 2/2 | 8min | 4min |
| 15. APT Repository and Signing | 2/2 | 5min | 2.5min |
| 18. Edge Track / Nightly Builds | 2/2 | 10min | 5min |
| 19 | 5 | - | - |
| 20 | 6 | - | - |

*Updated after each plan completion*
| Phase 19 P05 | 25min | 3 tasks | 6 files |
| Phase 20 P01 | 2min | 3 tasks | 5 files |
| Phase 20 P02 | 4min | 2 tasks | 2 files |
| Phase 20 P03 | 5min | 3 tasks | 3 files |
| Phase 20 P20-04 | checkpoint-resume | 2 tasks | 1 files |
| Phase 20 P05 | 4min | 2 tasks | 5 files |
| Phase 20 P06 | 12min | 2 tasks | 2 files |

## Previous Milestones

### v2.0 APT Packaging & CI/CD (Shipped 2026-03-08)

**Phases:** Phases 14-18 (17 absorbed into 18) | **Plans:** 8/8

### v1.2 Include Common Libraries (Shipped 2026-03-04)

**Phases:** 3/3 | **Plans:** 3/3

### v1.1 Ecosystem Audit (Shipped 2026-03-04)

**Phases:** 5/5 | **Plans:** 7/7

### v1.0 MVP (Shipped 2026-03-03)

**Phases:** 5/5 | **Plans:** 13/13

## Accumulated Context

### Decisions

All decisions logged in PROJECT.md Key Decisions table. Recent decisions affecting v3.0 work:

- Phase 15-01: Set Codename = Suite name (stable/edge) to avoid createsymlinks complexity — revisited in v3.0 (suite renames need aliases)
- Phase 18-01: Nightly versions use tilde (~git) convention for dpkg sort below tagged releases — v3.0 extends tilde form with per-distro suffix
- Phase 18-02: Go cache key uses track + run_number for cache isolation — v3.0 adds distro dimension to cache keys
- Phase 19-01: DISTRO override carries the dotted VERSION_ID form (26.04), not the compact CI label (2604); the `^[0-9]+\.[0-9]+$` regex rejects 2604 by design (T-19-01 fail-closed)
- Phase 19-01: Soname→package mapping delegated to the host dpkg DB (detect_runtime_depends), never a hand-maintained table — absorbs the crun parser special case (D-04); excludes only libc6/libgcc-s1 (D-02); hard-fails on any unmapped lib (D-03)
- Phase 19-01: config.sh is the single source of truth for VERSION_SUFFIX = `~ubuntu{VERSION_ID}.podman1` (D-07/D-08); package_all.sh's hardcoded `~podman1` removed in Plan 02
- Phase 19-03: scripts/verify_versions.sh uses literal in-script fixtures + `dpkg --compare-versions` as the authoritative oracle (no reimplemented version math), so it runs on any dpkg host independent of the build pipeline (CI-runnable pre-build)
- Phase 19-02: nFPM `${DETECTED_DEPENDS}` placeholder sits at column 0 under `depends:`; the `sed 's/^/  - /'` fragment carries its own indent so it merges cleanly with literal internal `podman-*` deps (D-12/D-13). No `|| true` around `detect_runtime_depends` — unmapped soname hard-fails the build (D-03)
- Phase 19-04: 24.04 no-regression asserted as t64-aware functional equivalence (libgpgme11→libgpgme11t64, libglib2.0-0→libglib2.0-0t64; non-t64 names unchanged), NOT string identity — avoids the t64 false-failure trap (RESEARCH Pitfall 1). verify_depends.sh + smoke_install_2604.sh authored on macOS; the four on-host proofs (24.04 verify_depends exit 0, verify_versions exit 0, 26.04 apt-install of skopeo pulling libgpgme45/libsubid5, 26.04 self-corrected dep set with zero YAML edits) DEFERRED to real-Ubuntu UAT — NOT executed (macOS dev host has no dpkg/ldd/nfpm). fuse-overlayfs/catatonit YAML follow-up conditional on the on-host detector run
- [Phase ?]: Phase 19-05: detect_runtime_depends derives deps from direct DT_NEEDED sonames (objdump -p NEEDED -> per-binary ldd soname=>path -> dpkg-query), matching dpkg-shlibdeps; full ldd transitive closure NOT used. Loader pseudo-entry skipped; static binaries yield empty deps; D-03/D-01/D-04 preserved
- [Phase ?]: Phase 19-05: skopeo 24.04 baseline corrected to libgpgme11t64 libsubid4 — libsqlite3-0 was a stale pre-v3.0 datum (skopeo v1.22.0, no sqlite BUILDTAG, links no sqlite); falsified on-host in UAT
- [Phase ?]: Phase 19-05: smoke_install_2604.sh installs internal podman-container-configs sibling .deb alongside skopeo in one apt-get call so apt needs the archive only for system deps; skopeo install stays HARD (T-19-12)
- [Phase ?]: Phase 20-01: bare-alias reprepro distribution (Suite: stable, not stable-2404) is the REPO-07 mechanism preserving apt's cached Suite value; resolve_publish_targets in config.sh appends the bare alias only for 24.04 (D-12), 26.04 publishes versioned-only
- [Phase ?]: Phase 20-02: add_byhash_and_resign is a cp+gpg bolt-on around reprepro Release output — writes by-hash adjacent to each index plus Release-level, injects Acquire-By-Hash after Suite:, then re-signs (D-08). Release by-hash computed AFTER injection (Pitfall 2); single generation only (D-09).
- [Phase ?]: Phase 20-03: publish path now driven by a single (track, distro) input. ci_publish.sh mirror-then-include reassembles all 9 suites with OTHER_SUITES = ALL_SUITES − PUBLISH_TARGETS (no clobber); per-suite export only (Pitfall 4); add_byhash_and_resign called for every suite with a Release after all exports. repo_manage.sh feeds the bare alias on 24.04 (D-12). NOTE: resolve_publish_targets runs in a process-substitution subshell so its non-zero exit cannot abort the parent — both scripts guard with an empty-PUBLISH_TARGETS check. CI passes distro=2404 via a step output; matrix fan-out deferred to Phase 21.
- [Phase ?]: Resolved 20-04 blocking checkpoint via a local-VM D-15 simulation (old 3-stanza tree -> new 9-suite tree swapped at a constant localhost URL on Lima ubuntu-24): apt-client legacy continuity (no Suite-change prompt, 24.04 candidate from bare stable) and by-hash-over-HTTP (200) proven without the production deploy; production-URL smoke deferred to first CI publish.
- [Phase ?]: Phase 20-05: CR-01 fix uses RETURN-trap option restore (save set +o, set +e +o pipefail, trap 'eval _saved_opts' RETURN) as the single restore point so add_byhash_and_resign always reaches its re-sign block; helper never re-enables set -e/pipefail itself
- [Phase ?]: Phase 20-05: WR-01 reads the signing-key fingerprint via 'gpg --list-secret-keys --with-colons | awk -F: /^fpr:/' at both repo_manage.sh sites, deterministically selecting the signing key on a multi-key keyring; WR-03 quotes all four realpath toolpath bootstraps
- [Phase ?]: 20-06: Chose verbatim-mirror for non-target bare aliases on 26.04 publishes (vs Release-Date stabilization) — lowest-risk, stays within the D-10 rebuild-the-world model (CR-02 closed)
- [Phase 20]: Post-20-06 fix 53b778f: mirror_suite_verbatim rebuilt as a Release-driven fetch (signed Release is the manifest; indexes curled + hash-verified, by-hash reconstructed locally) — the wget -r crawl broke on path-segmented project-pages URLs AND Pages serves no directory listings. Proven by test_mirror_verbatim.sh (19/19 macOS + VM) and an end-to-end ci_publish.sh run against a path-segmented URL (UAT Test 9, 12/12)

### Tech Debt

- Minor: install_dependencies.sh lacks DEBIAN_FRONTEND (relies on setup.sh)
- Minor: Circular sourcing pattern config.sh <-> functions.sh (guarded but fragile)

### Research Flags (v3.0)

- ✓ Phase 20 (closed by UAT 2026-06-07): physical-copy alias strategy chosen (no symlinks); "Suite changed value" apt prompt disproven twice via the D-15 old→new swap simulation on Lima ubuntu-24 (Plan 04 and UAT re-run at HEAD: no prompt, 24.04 candidate from bare `stable`). REMAINING: one-time production-CDN confirmation after first CI publish of the 9-suite tree (commands in 20-04-SUMMARY.md; local main is 80 commits ahead of origin — nothing published yet)
- ✓ Phase 19 (closed by Plan 03): version suffix form confirmed via `dpkg --compare-versions` in scripts/verify_versions.sh — yields to official, 24.04 < 26.04, nightly < tagged, legacy ~podman1 < new ~ubuntu24.04.podman1
- Phase 21: re-check whether `ubuntu-26.04` / `ubuntu-26.04-arm` runner labels are GA at implementation time; container fallback is the safe default

### Blockers/Concerns

- ✓ RESOLVED (Plan 05, 2026-06-06): the Phase 19 on-host proofs now all pass on the Lima VMs. (1) `DISTRO=24.04 verify_depends.sh` exits 0 on ubuntu-24 (Part A all PASS, Part B 26/26); (2) `verify_versions.sh` was already green per Plan 03; (3) `smoke_install_2604.sh` exits 0 on ubuntu-26 — apt pulls libgpgme45/libsubid5/libassuan9 from the archive, skopeo --version prints 1.22.0; (4) the 26.04 detected set shows the renamed packages (libgpgme45/libsubid5) with zero nFPM YAML edits. Gap closure fixed the detector (direct DT_NEEDED only) and the smoke harness (sibling configs .deb), and corrected the stale skopeo libsqlite3-0 baseline. fuse-overlayfs/catatonit are statically linked (detected dep set = empty) so they need no system-dep YAML injection. Phase 19 success criteria 1 and 4 are now met.

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 5 | Generate a nice README for the repo | 2026-03-06 | 3ec1a20 | [5-generate-a-nice-readme-for-the-repo](./quick/5-generate-a-nice-readme-for-the-repo/) |
| 6 | Rename podman-debian to podman-ubuntu | 2026-03-08 | 0fa5450 | [6-rename-repo-from-podman-debian-to-podman](./quick/6-rename-repo-from-podman-debian-to-podman/) |

## Session Continuity

Last session: 2026-06-07T02:50:00Z
Stopped at: Phase 20 complete, ready to plan Phase 21
Resume file: None
