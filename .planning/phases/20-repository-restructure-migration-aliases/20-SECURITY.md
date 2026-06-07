---
phase: 20
slug: repository-restructure-migration-aliases
status: blocked
threats_open: 1
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
| T-20-07 | Tampering | Clobbering untouched suites | mitigate | `OTHER_SUITES = ALL_SUITES − PUBLISH_TARGETS` (`scripts/ci_publish.sh:113-125`); per-suite export only (`:349`, `repo_manage.sh:176-177`) | closed |
| T-20-08 | Tampering/Spoofing | by-hash before re-sign / skipped suites | mitigate | `add_byhash_and_resign` invoked for every suite with a Release, after all exports — `scripts/ci_publish.sh:372-385` | closed |
| T-20-09 | Elevation/Spoofing | Malformed publish target from CI input | mitigate | Routing validation + empty-PUBLISH_TARGETS guard aborts before any includedeb — `scripts/ci_publish.sh:83-89`, `repo_manage.sh:64-72` | closed |
| T-20-10 | DoS | First-deploy 404 on new -2404/-2604 suites | accept | `curl -sfL ... \|\| true` + empty-Packages-continue tolerance preserved verbatim — `scripts/ci_publish.sh:234-239` | closed |
| T-20-11 | Spoofing | apt Suite-change re-acceptance prompt on legacy client | mitigate | Bare alias serves `Suite: stable` (distributions verified); D-15 local-VM simulation proved no "changed its 'Suite' value" prompt (`20-04-SUMMARY.md`); production-CDN re-confirm deferred to first CI publish per plan | closed |
| T-20-12 | Tampering | Invalid signature chain after by-hash mutation in production | mitigate | `gpg --verify InRelease` / `Release.gpg Release` asserted on assembled tree — `tests/test_repo_assemble_byhash.sh:301-304,346-349` | closed |
| T-20-13 | Tampering | Test key contaminating host keyring | mitigate | Isolated `GNUPGHOME` under mktemp + EXIT-trap `gpgconf --kill all` + `rm -rf` — `tests/test_repo_assemble_byhash.sh:123-129` | closed |
| T-20-14 | Tampering | `add_byhash_and_resign` half-signed suite | mitigate | Pipefail isolation (`set +e +o pipefail` + RETURN-trap restore) guarantees `rm` always reaches re-sign — `scripts/repo_byhash.sh:53-55,101` | closed |
| T-20-15 | Spoofing | GPG fingerprint extraction | mitigate | Anchored `--list-secret-keys --with-colons \| awk -F: '/^fpr:/{print $10; exit}'` — `scripts/repo_manage.sh:112,193` | closed |
| T-20-16 | DoS | realpath toolpath bootstrap | mitigate | All toolpath bootstraps quote `realpath --canonicalize-missing` args — `config.sh:9`, `repo_byhash.sh:8`, `repo_manage.sh:8`, `ci_publish.sh:13` | closed |
| T-20-17 | Tampering | Bare-alias re-export on 26.04 publish | mitigate | **NOT FUNCTIONAL** — `mirror_suite_verbatim` (`scripts/ci_publish.sh:167-211`) exists but `wget -nH --cut-dirs=0` against the project-pages REPO_URL (`build-packages.yml:316`) lands the tree under `${lmirror}/<repo>/dists/...`; guard at `:201` fails → `IS_VERBATIM=false` → alias falls through to re-export/re-sign, reopening the CDN hash-mismatch window. Latent in Phase 20 (CI hardcodes `distro=2404`); live in Phase 21 (`distro=2604`). Test group G never exercises the wget path. See `20-VERIFICATION.md` (3/4 blocker). | **open** |
| T-20-18 | Info Disclosure/Tampering | index.html package/version interpolation | mitigate | `esc()` HTML-escapes `& < > "` applied to `pkg_e`/`ver_e` before heredoc interpolation — `scripts/ci_publish.sh:405,526-529` | closed |
| T-20-19 | DoS | First-deploy / empty-2604 publish path | accept | `mirror_suite_verbatim` returns 1 on 404 and falls through to empty-but-signed D-14 behavior — `scripts/ci_publish.sh:171-174` | closed |
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

## Open Threat Remediation — T-20-17

**Decision (2026-06-07): BLOCK — fix before phase advancement.** User declined risk acceptance; the wget-path defect must be fixed and re-audited.

Remediation guidance (from audit):
1. In `mirror_suite_verbatim`, locate the fetched tree independent of URL depth — e.g. `lsrc=$(find "${lmirror}" -type d -path "*/dists/${lsuite}" -print -quit)` and copy from `lsrc`; or compute `--cut-dirs=N` from the REPO_URL path depth.
2. Add a test driving `mirror_suite_verbatim` against a `file://`/loopback URL containing a path segment, asserting the tree lands at `${OUTPUT_DIR}/dists/<suite>` and `IS_VERBATIM=true` (test group G currently bypasses the wget path).
3. Re-run `/gsd:secure-phase 20` after the fix lands.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-07 | 20 | 19 | 1 | gsd-security-auditor (ASVS L1, block_on: high) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [ ] `threats_open: 0` confirmed — **1 open (T-20-17)**
- [ ] `status: verified` set in frontmatter

**Approval:** pending — blocked on T-20-17 remediation
