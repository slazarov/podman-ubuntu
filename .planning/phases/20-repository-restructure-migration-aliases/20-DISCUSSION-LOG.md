# Phase 20: Repository Restructure & Migration Aliases - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-06
**Phase:** 20-repository-restructure-migration-aliases
**Areas discussed:** Legacy alias mechanism, Acquire-By-Hash strategy, Publish state & routing, Rollout & validation

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Legacy alias mechanism | Real reprepro suites vs post-publish dists copy vs symlink | ✓ (via directive) |
| Acquire-By-Hash strategy | reprepro post-process + re-sign vs switch tooling (aptly) | ✓ (via directive) |
| Publish state & routing | Rebuild-the-world extended to 6 suites vs incremental gh-pages state | ✓ (via directive) |
| Rollout & validation | Staging Pages vs direct deploy; empty 2604 suites; deprecation note | ✓ (via directive) |

**User's choice:** Free-text directive: "apply best practices, no overengineering" — same pattern as Phase 19. All four areas resolved by Claude using best practices grounded in the existing pipeline; resolutions presented back and explicitly confirmed ("Yes, lock them in").

---

## Legacy alias mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Real reprepro suites | Bare stable/edge/nightly stay first-class distributions fed the same 24.04 debs; Release keeps `Suite: stable` — no apt prompt | ✓ |
| Post-publish dists copy | `cp -r dists/stable-2404 dists/stable`; copied Release embeds `Suite: stable-2404` → trips apt "Suite value changed" error | |
| createsymlinks | Roadmap-excluded — Pages tarballs may not preserve symlinks | |

**Notes:** Closes STATE.md research flag in favor of real suites; legacy Description gets a one-line deprecation note (timeline = Phase 22).

## Acquire-By-Hash strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Keep reprepro + post-export by-hash + re-sign | ~50 lines of bash; by-hash/SHA256 copies, inject field into Release, re-sign with the already-imported CI key | ✓ |
| Switch to aptly | Native by-hash but rebuilds the entire proven publish pipeline — overengineering | |

## Publish state & routing

| Option | Description | Selected |
|--------|-------------|----------|
| Rebuild-the-world (extended) | Mirror untouched suites from live URL + fresh debs for published `<track>-<distro>`; 24.04 publishes also feed the bare alias | ✓ |
| Incremental gh-pages state | Persistent reprepro db / branch checkout — stateful, overengineered; Phase 21 layers atomicity instead | |

## Rollout & validation

| Option | Description | Selected |
|--------|-------------|----------|
| Direct deploy, all six suites day one (2604 empty-but-signed), Lima VM legacy-client test | CI artifact inspectable pre-deploy; ubuntu-24 VM with pre-v3.0 .sources proves no Suite-changed prompt | ✓ |
| Staging Pages repo/branch | Parallel staging site — overengineering for this project | |

---

## Claude's Discretion

- Alias feed mechanism: `includedeb` twice vs reprepro `conf/pulls` — planner picks
- `repo_manage.sh` CLI surface (single-suite arg vs track+distro args)
- Where by-hash post-processing lives (inline, scripts/ helper, or functions.sh)
- Suite whitelist expression (array in config.sh vs regex)

## Deferred Ideas

- REPO-09: remove legacy aliases after deprecation window (already tracked)
- REPO-10: codename-aliased suites for `$VERSION_CODENAME` auto-detect (already tracked)
- MIGR-01/02: per-distro DEB822 instructions + index.html setup blocks — Phase 22
- MIGR-03: deprecation timeline docs — Phase 22
