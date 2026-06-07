---
phase: 21
slug: ci-build-matrix-extension-to-26-04
status: verified
threats_open: 0
asvs_level: 1
created: 2026-06-07
---

# Phase 21 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| upstream git → CI build cells | Untrusted upstream source (nightly = HEAD) compiled inside each distro×arch cell | Source code, build artifacts |
| matrix value → shell env (DISTRO) | Matrix-supplied distro label (`2404`/`2604`) expanded into env passed to `setup.sh`/`package_all.sh` | DISTRO override; determines VERSION_SUFFIX in produced `.deb` files |
| build cell → Go cache (actions/cache) | Cache restored into a build cell can poison the produced binary if cross-distro contamination occurs | Go module + build cache blobs |
| build cell → artifact (upload-artifact) | Artifact name determines which suite a binary later lands in during publish | `.deb` packages keyed by distro+arch |
| build cells → publish job | Per-distro artifacts cross the job boundary; wrong-distro merge would mis-route binaries into the wrong suite | `.deb` packages, distro identity |
| matrix aggregate result → publish gate | The `build` job's aggregate `result` decides whether the live APT repository is touched at all | CI pass/fail signal |
| downloaded artifacts → ci_publish.sh deb-dir | The deb directory passed to `ci_publish.sh` determines which binaries enter which suite | `.deb` packages, per-distro directories |
| repo-output → GitHub Pages (deploy-pages) | The single `deploy-pages` action replaces the live repository in one shot | Full APT repository tree |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status |
|-----------|----------|-----------|-------------|------------|--------|
| T-21-01 | Tampering | Go cache cross-distro reuse | mitigate | Cache key `go-<distro>-<arch>-<track>-<run>` isolates per distro+arch; restore-keys scoped to same distro+arch prefix only — a 26.04 cell can never restore a 24.04 cell's cache | closed |
| T-21-02 | Spoofing/Tampering | Artifact cross-contamination (upload) | mitigate | Each cell uploads `debs-<distro>-<arch>`; no cell can write another cell's artifact name; download-side no-merge guaranteed by T-21-05 | closed |
| T-21-03 | Injection | matrix.distro → DISTRO env | mitigate | Matrix values are a fixed `include` allowlist (`2404`/`2604` only, not free-form input); dotted form derived via closed case map (`2604`→`26.04`); `detect_distro_version_id` re-validates against `^[0-9]+\.[0-9]+$` before reaching any filename | closed |
| T-21-04 | Tampering | 26.04 container base image | accept | `ubuntu:26.04` is the official Docker Hub Ubuntu image pulled by GitHub's container runtime; same trust model as host runner images already in use; digest-pinning deferred | closed |
| T-21-SC-01 | Tampering | apt installs in 26.04 container bootstrap | mitigate | Bootstrap step installs only Ubuntu-archive packages (`sudo git curl ca-certificates`); no language package managers, no third-party sources, no `## Package Legitimacy Audit` required | closed |
| T-21-05 | Tampering | Cross-distro artifact merge in publish | mitigate | Two distro-scoped download steps (`debs-2404-*`→`all-debs-2404/`, `debs-2604-*`→`all-debs-2604/`); no bare `pattern: debs-*` step exists; each `ci_publish.sh` run fed only its own distro directory; `test_ci_matrix.sh` assertion 9 enforces the no-merge contract | closed |
| T-21-06 | Denial of Service / Elevation | Publish-gate bypass on partial failure | mitigate | `if: always() && needs.build.result == 'success'`; single matrix-cell failure makes aggregate `build.result` non-success so publish is skipped and live repo is untouched (CICD-08); `test_ci_matrix.sh` assertion 8 enforces the gating expression | closed |
| T-21-07 | Injection | distro label → ci_publish.sh/config.sh | mitigate | Publish job passes string literals `2404`/`2604` only (not free-form input); `resolve_publish_targets`/`VALID_DISTROS=(2404 2604)` in `config.sh` re-validates and aborts on anything else | closed |
| T-21-08 | Tampering | 2nd ci_publish.sh run clobbering 1st distro's suites | mitigate | `ci_publish.sh` mirror-then-include model (`OTHER_SUITES = ALL_SUITES − PUBLISH_TARGETS`) means the 2604 run mirrors the 2404 run's freshly-published suites into the same `repo-output` without overwriting them (Phase-20 verified); 2404-first ordering is explicit in the workflow | closed |
| T-21-SC-02 | Tampering | apt install of reprepro in publish | accept | Unchanged from Phase 20 — `reprepro` from Ubuntu's signed archive; no new package source, no language-package-manager installs | closed |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-21-01 | T-21-04 | `ubuntu:26.04` is the official Docker Hub Ubuntu image; same trust model as the host runner images already in use by the pipeline. Digest-pinning deferred — not a new trust boundary compared to the existing 24.04 runner dependency. | gsd-security-auditor (orchestrator) | 2026-06-07 |
| AR-21-02 | T-21-SC-02 | `reprepro` installed from Ubuntu's signed apt archive in the publish job — unchanged from Phase 20. No new package source introduced. No language-package-manager installs in this phase. | gsd-security-auditor (orchestrator) | 2026-06-07 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-06-07 | 10 | 10 | 0 | /gsd-secure-phase (orchestrator) — short-circuit: register_authored_at_plan_time: true, threats_open: 0 |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-06-07
