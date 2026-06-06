# Requirements: Podman Ubuntu Compiler — v3.0 Ubuntu 26.04 Support

**Defined:** 2026-06-05
**Core Value:** Compile and install Podman on any Debian/Ubuntu system without user interaction.

## v3.0 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Packaging

- [x] **PKG-08**: Packages built for Ubuntu 26.04 declare the correct renamed runtime dependencies (libgpgme45, libsubid5) so `apt install` succeeds on 26.04
- [x] **PKG-09**: Package versions carry a per-distro suffix (e.g. `~ubuntu24.04.podman1` / `~ubuntu26.04.podman1`) so the same upstream version produces distinct .deb identities per distro and dist-upgrades order correctly
- [x] **PKG-10**: Runtime library dependencies are resolved at build time via ldd soname→package detection so future distro renames are caught automatically without manual config edits

### Repository

- [x] **REPO-06**: Repository serves six versioned suites (stable-2404, edge-2404, nightly-2404, stable-2604, edge-2604, nightly-2604) from a single URL with one GPG key
- [x] **REPO-07**: Existing users with bare `stable`/`edge`/`nightly` suite names in their .sources continue to receive 24.04 packages without any client-side change (legacy aliases during deprecation window)
- [ ] **REPO-08**: Repository metadata includes Acquire-By-Hash so apt clients never hit CDN hash-sum mismatches on GitHub Pages

### CI/CD

- [ ] **CICD-05**: A single workflow builds all four distro×arch combinations (24.04/26.04 × amd64/arm64) via a strategy matrix
- [ ] **CICD-06**: Ubuntu 26.04 packages are built inside ubuntu:26.04 containers on existing native runners, written runner-agnostic so native ubuntu-26.04 runners are a one-line switch when GA
- [ ] **CICD-07**: Build caches and artifacts carry a distro dimension (debs-<distro>-<arch> naming, distro in cache keys) so no cross-distro binary contamination can occur
- [ ] **CICD-08**: Publishing remains atomic — the publish job runs only when all four build cells succeed, leaving the live repository intact otherwise

### Migration & Docs

- [ ] **MIGR-01**: A user on either distro can set up the repo from copy-paste DEB822 .sources blocks specific to their Ubuntu version in the documentation
- [ ] **MIGR-02**: The repository index page (index.html) presents per-distro setup instructions
- [ ] **MIGR-03**: The deprecation timeline for bare `stable`/`edge`/`nightly` suite names is documented
- [ ] **MIGR-04**: CI verifies installability before publish — installs podman-suite and runs `podman info` in real ubuntu:24.04 and ubuntu:26.04 containers

## Future Requirements

Deferred to a later milestone. Tracked but not in current roadmap.

### Repository

- **REPO-09**: Remove legacy bare suite aliases after the deprecation window elapses
- **REPO-10**: Codename-aliased suites (noble/resolute) enabling `$VERSION_CODENAME`-based auto-detect in setup snippets

### Packaging

- **PKG-11**: Generalized N-distro templating for adding a third distro version

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Codename-in-version-string (`~noble`/`~resolute`) | Codenames sort alphabetically and break dist-upgrades — Docker's documented mistake (moby/for-linux #1315) |
| Separate repo path per distro (OBS-style) | Forces per-distro URIs: lines; breaks the single-root, one-URL setup |
| Hard suite rename cutover without aliases | Silently breaks every existing user's apt update |
| Publishing 24.04-built binaries to the 26.04 suite | Forward-compat shim; defeats native per-distro correctness this milestone exists for |
| Ubuntu 24.10/25.04/25.10 interim releases | Non-LTS; project targets LTS releases only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| PKG-08 | Phase 19 | Complete |
| PKG-09 | Phase 19 | Complete (19-01 suffix + 19-03 dpkg proof) |
| PKG-10 | Phase 19 | Complete |
| REPO-06 | Phase 20 | Complete |
| REPO-07 | Phase 20 | Complete |
| REPO-08 | Phase 20 | Pending |
| CICD-05 | Phase 21 | Pending |
| CICD-06 | Phase 21 | Pending |
| CICD-07 | Phase 21 | Pending |
| CICD-08 | Phase 21 | Pending |
| MIGR-01 | Phase 22 | Pending |
| MIGR-02 | Phase 22 | Pending |
| MIGR-03 | Phase 22 | Pending |
| MIGR-04 | Phase 22 | Pending |

**Coverage:**

- v3.0 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-05*
*Last updated: 2026-06-05 after roadmap creation (Phases 19-22)*
