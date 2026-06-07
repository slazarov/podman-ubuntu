---
phase: 20
slug: repository-restructure-migration-aliases
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-07
---

# Phase 20 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| repo metadata config → apt client | `conf/distributions` Suite/Codename values become the signed Release fields apt compares against its cached value | APT Release metadata (integrity-critical) |
| build env → signed Release | `SignWith: yes` selects the single imported GPG key that signs every suite | GPG signing key selection |
| reprepro Release output → by-hash copies | by-hash files are byte-identical copies of canonical indexes whose hashes are signed in Release | Signed index bytes |
| mutated Release → apt-secure signature chain | Editing Release after export invalidates reprepro's signatures; re-sign restores the trust anchor | InRelease / Release.gpg signatures |
| live repo URL → mirror-down → reassembled tree | Untouched suites' content is fetched from the live CDN and re-served; verbatim preservation keeps cached client signatures valid | Already-signed suite metadata + .debs |
| publish routing → which suite gets fresh content | A wrong target could overwrite or omit a suite (clobbering) | CI track/distro publish targets |
| deployed Pages CDN → real apt client | Production trust anchor: apt verifies InRelease signature + per-index hashes against served metadata | Full repo metadata + packages |
| pre-v3.0 client cached Suite → served alias Suite | apt refuses a silent Suite change; the bare alias must serve `Suite: stable` | Suite field continuity |
| throwaway test key → assembled fixture repo | Test harness signs with an ephemeral key in an isolated GNUPGHOME, never the production key | Test-only GPG material |
| upstream package version strings → generated index.html | Nightly versions derive from upstream HEAD; unescaped values cross into served HTML | Attacker-influenceable version strings |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-20-01 | Spoofing | Legacy alias Suite field | mitigate | Bare alias stanzas carry `Suite: stable`/`edge`/`nightly` — `packaging/repo/conf/distributions:3,12,21` | closed |
| T-20-02 | Tampering | Multi-key signing drift | mitigate | Exactly 9 `SignWith: yes` lines (one per stanza), single default key — `packaging/repo/conf/distributions` | closed |
| T-20-03 | Elevation/Spoofing | Routing helper input | mitigate | `resolve_publish_targets` (`config.sh:90-118`) + `is_valid_suite` (`config.sh:73-81`) reject out-of-whitelist track/distro/suite | closed |
| T-20-04 | Tampering/Spoofing | Stale signature after Acquire-By-Hash injection | mitigate | `rm -f InRelease Release.gpg` then regenerate both AFTER injection — `scripts/repo_byhash.sh:101-103` (injection at `:86-87`) | closed |
| T-20-05 | Tampering | Drift between by-hash copy and served Release | mitigate | Release by-hash computed after injection (`scripts/repo_byhash.sh:89-97`); index by-hash are `cp -f` of canonical files (`:80`) | closed |
| T-20-06 | DoS | CDN hash-sum mismatch race | mitigate | by-hash dir written adjacent to each index — `scripts/repo_byhash.sh:78` | closed |
| T-20-07 | Tampering | Clobbering untouched suites | mitigate | `OTHER_SUITES = ALL_SUITES − PUBLISH_TARGETS` (`scripts/ci_publish.sh:113-125`); per-suite export only (`:404`, `repo_manage.sh:176-177`) | closed |
| T-20-08 | Tampering/Spoofing | by-hash before re-sign / skipped suites | mitigate | `add_byhash_and_resign` invoked for every suite with a Release, after all exports — `scripts/ci_publish.sh:427-440` | closed |
| T-20-09 | Elevation/Spoofing | Malformed publish target from CI input | mitigate | Routing validation + empty-PUBLISH_TARGETS guard aborts before any includedeb — `scripts/ci_publish.sh:83-89`, `repo_manage.sh:64-72` | closed |
| T-20-10 | DoS | First-deploy 404 on new -2404/-2604 suites | accept | `curl -sfL ... \|\| true` + empty-Packages-continue tolerance preserved verbatim — `scripts/ci_publish.sh:289-294` | closed |
| T-20-11 | Spoofing | apt Suite-change re-acceptance prompt on legacy client | mitigate | Bare alias serves `Suite: stable` (distributions verified); D-15 local-VM simulation proved no "changed its 'Suite' value" prompt (`20-04-SUMMARY.md`); production-CDN re-confirm deferred to first CI publish per plan | closed |
| T-20-12 | Tampering | Invalid signature chain after by-hash mutation in production | mitigate | `gpg --verify InRelease` / `Release.gpg Release` asserted on assembled tree — `tests/test_repo_assemble_byhash.sh:301-304,346-349` | closed |
| T-20-13 | Tampering | Test key contaminating host keyring | mitigate | Isolated `GNUPGHOME` under mktemp + EXIT-trap `gpgconf --kill all` + `rm -rf` — `tests/test_repo_assemble_byhash.sh:123-129` | closed |
| T-20-14 | Tampering | `add_byhash_and_resign` half-signed suite | mitigate | Pipefail isolation (`set +e +o pipefail` + RETURN-trap restore) guarantees `rm` always reaches re-sign — `scripts/repo_byhash.sh:53-55,101` | closed |
| T-20-15 | Spoofing | GPG fingerprint extraction | mitigate | Anchored `--list-secret-keys --with-colons \| awk -F: '/^fpr:/{print $10; exit}'` — `scripts/repo_manage.sh:112,193` | closed |
| T-20-16 | DoS | realpath toolpath bootstrap | mitigate | All toolpath bootstraps quote `realpath --canonicalize-missing` args — `config.sh:9`, `repo_byhash.sh:8`, `repo_manage.sh:8`, `ci_publish.sh:13` | closed |
| T-20-17 | Tampering | Bare-alias re-export on 26.04 publish | mitigate | **FIXED (commit 53b778f, re-audited 2026-06-07)** — `mirror_suite_verbatim` rewritten as a Release-driven `curl` fetch with NO crawl / NO URL-depth dependency (`scripts/ci_publish.sh:183-266`). The signed Release is the manifest: top-level `Release`/`InRelease`/`Release.gpg` fetched verbatim (`:196,:204-205`), every listed index `curl`'d and verified against its signed SHA256/SHA512 (`:226,:235-242`), by-hash copies reconstructed locally per repo_byhash layout (`:243-245,:251-257`). IS_VERBATIM gate skips re-includedeb/re-export (`:379-382`) AND by-hash/re-sign (`:432-435`) for verbatim suites → original signatures byte-identical. Fails CLOSED: every failure path `rm -rf` the mktemp stage + `return 1` before any write to OUTPUT_DIR (`:196-198,:206-209,:226-230,:237-241`); caller sets `IS_VERBATIM=false` → consistent re-export fallback (`:272,:277`). `tests/test_mirror_verbatim.sh` sed-extracts and drives the PRODUCTION function against a path-segmented `file://` URL (the project-pages regression shape) — 19/19 here (macOS, all hash assertions exercised) + 19/19 Lima ubuntu-24; asserts byte-identity, by-hash reconstruction, no `<out>/<repo-name>/` nesting, and return-1+no-partial-tree on 404/missing-index/hash-mismatch/missing-sig. | closed |
| T-20-18 | Info Disclosure/Tampering | index.html package/version interpolation | mitigate | `esc()` HTML-escapes `& < > "` applied to `pkg_e`/`ver_e` before heredoc interpolation — `scripts/ci_publish.sh:460,581-582` | closed |
| T-20-19 | DoS | First-deploy / empty-2604 publish path | accept | `mirror_suite_verbatim` returns 1 when the live Release 404s and falls through to empty-but-signed D-14 behavior — `scripts/ci_publish.sh:196-199` | closed |
| T-20-SC | Tampering | Supply chain (npm/pip/cargo installs) | accept | No package-manager installs in any Phase-20 file; only distro-packaged reprepro (`build-packages.yml:303-306`), gpg, curl, coreutils | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-20-01 | T-20-10 | First publish of new -2404/-2604 suites 404s by design; existing `\|\| true` tolerance creates them empty-but-signed | plan 20-03 (user-approved) | 2026-06-07 |
| AR-20-02 | T-20-19 | Verbatim-mirror no-ops cleanly when live alias tree 404s; empty-but-signed D-14 behavior unchanged, covered by test group E | plan 20-06 (user-approved) | 2026-06-07 |
| AR-20-03 | T-20-SC | No package-manager installs across all six plans; only distro-packaged tooling | plans 20-01..06 (user-approved) | 2026-06-07 |

---

## Open Threat Remediation — T-20-17 (RESOLVED)

**Decision (2026-06-07): BLOCK — fix before phase advancement.** User declined risk acceptance; the wget-path defect must be fixed and re-audited.

Remediation guidance (from audit):
1. In `mirror_suite_verbatim`, locate the fetched tree independent of URL depth — e.g. `lsrc=$(find "${lmirror}" -type d -path "*/dists/${lsuite}" -print -quit)` and copy from `lsrc`; or compute `--cut-dirs=N` from the REPO_URL path depth.
2. Add a test driving `mirror_suite_verbatim` against a `file://`/loopback URL containing a path segment, asserting the tree lands at `${OUTPUT_DIR}/dists/<suite>` and `IS_VERBATIM=true` (test group G currently bypasses the wget path).
3. Re-run `/gsd:secure-phase 20` after the fix lands.

**Resolution (commit 53b778f, re-audited 2026-06-07):** Remediation chose a stronger design than option 1's tree-relocation hack — the crawl was removed entirely and replaced with a Release-manifest-driven `curl` fetch that has no URL-depth dependency at all (only ever fetches `${REPO_URL}/dists/<suite>/<listed-relpath>` into a fixed mktemp-rooted local path). Guidance point 2 satisfied by `tests/test_mirror_verbatim.sh` (sed-extracts and drives the production function against a path-segmented `file://` URL; asserts the tree lands at `<out>/dists/<suite>` byte-identical with no path-segment nesting). The old wget-path failure mode is provably gone (Test 1: `no <out>/podman-ubuntu/ nesting` / `no <out>/www/ nesting` PASS). Verbatim signature preservation, by-hash reconstruction, and fail-closed behaviour all verified.

**New-attack-surface assessment of the fix:** `relpath` is parsed from the pre-verification Release and used to build local write paths + fetch URLs. A path-traversal relpath is bounded to the throwaway `mktemp -d` staging dir (writes never land in the published tree until all integrity checks pass, then via staged `cp -a`), and the trust source `${REPO_URL}` is the project's own GitHub Pages CDN — already the trust anchor of the pre-existing mirror-down loop (`ci_publish.sh:286-335`, untouched) that fetches Packages indexes and `.deb`s from the same URL and feeds them to `reprepro includedeb`. No new external trust source; within the documented "live repo URL → mirror-down → reassembled tree" boundary. **No new high-severity issue introduced.**

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-07 | 20 | 19 | 1 | gsd-security-auditor (ASVS L1, block_on: high) |
| 2026-06-07 | 20 | 20 | 0 | gsd-security-auditor (focused re-audit, T-20-17 only — fix commit 53b778f verified; test 19/19; no new attack surface) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed — T-20-17 closed (commit 53b778f)
- [x] `status: verified` set in frontmatter

**Approval:** approved — all 20 threats closed (17 mitigate, 3 accept); T-20-17 fix re-audited 2026-06-07
