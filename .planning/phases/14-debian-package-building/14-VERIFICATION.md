---
phase: 14-debian-package-building
verified: 2026-03-05T10:30:00Z
status: passed
score: 8/8 must-haves verified
re_verification: false
---

# Phase 14: Debian Package Building Verification Report

**Phase Goal:** Transform build scripts to support DESTDIR staging and create nFPM-based .deb packaging for all components
**Verified:** 2026-03-05T10:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | Running a build script with DESTDIR set stages files to DESTDIR tree without modifying the host system | VERIFIED | All 13 scripts use `if [[ -n "${DESTDIR:-}" ]]; then ... else sudo ...fi` pattern. No sudo in DESTDIR branch. |
| 2  | Running a build script without DESTDIR preserves existing direct-install behavior | VERIFIED | Else branch uses `sudo` + direct paths in all 13 scripts |
| 3  | All binaries install to /usr (not /usr/local) in both DESTDIR and direct-install modes | VERIFIED | All scripts use `/usr/bin` paths. `build_fuse-overlayfs.sh` uses `--prefix=/usr`. Note: `build_pasta.sh` has `rm -f /usr/local/bin/passt.*` lines which are cleanup of previously misplaced files — not install destinations. |
| 4  | Each of the 12 components has an nFPM YAML config with podman-* prefix naming | VERIFIED | 13 YAML files exist in `packaging/nfpm/` (12 components + 1 suite). All 12 component configs use `name: podman-{component}` prefix. |
| 5  | podman-suite meta-package config declares dependencies on all 12 component packages | VERIFIED | `suite.yaml` depends: section lists all 12 packages: podman-podman, podman-crun, podman-conmon, podman-netavark, podman-aardvark-dns, podman-pasta, podman-fuse-overlayfs, podman-catatonit, podman-buildah, podman-skopeo, podman-toolbox, podman-container-configs |
| 6  | container-configs nFPM config declares type: config for all /etc/ files and NOT for seccomp.json | VERIFIED | 5 `type: config` entries for /etc/containers/ files. `seccomp.json` at `/usr/share/containers/seccomp.json` has no `type: config`. |
| 7  | Each package that has a matching Ubuntu Noble package declares conflicts/replaces/provides | VERIFIED | All 11 component packages (all except suite) declare conflicts/replaces/provides. `pasta.yaml` correctly conflicts against `passt` (Ubuntu package name). `toolbox.yaml` conflicts against `podman-toolbox`. |
| 8  | podman-podman declares runtime dependencies on crun, conmon, netavark, aardvark-dns, pasta, fuse-overlayfs, catatonit, container-configs | VERIFIED | `podman.yaml` depends section has all 8 packages listed |

**Score:** 8/8 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `packaging/nfpm/podman.yaml` | nFPM config for podman-podman package | VERIFIED | Contains `name: podman-podman`, 8 depends, conflicts/replaces/provides podman, DESTDIR staging paths, tree type for man pages and systemd units |
| `packaging/nfpm/suite.yaml` | nFPM config for podman-suite meta-package | VERIFIED | Contains `name: podman-suite`, all 12 depends listed, no contents section (meta-package) |
| `packaging/nfpm/container-configs.yaml` | nFPM config with conffiles | VERIFIED | 5 `type: config` entries for /etc/containers/ files; seccomp.json excluded from conffile marking |
| `scripts/build_netavark.sh` | DESTDIR-aware install with /usr/bin paths | VERIFIED | Uses `install -D -m 0755 bin/netavark "${DESTDIR}/usr/bin/netavark"` in DESTDIR branch; `sudo install -D -m 0755 bin/netavark /usr/bin/netavark` in direct branch |
| `config/containers.conf` | Updated helper_binaries_dir without /usr/local references | VERIFIED | `helper_binaries_dir = ["/usr/bin", "/usr/libexec/podman", "/usr/lib/podman"]` — zero /usr/local references |
| `scripts/package_all.sh` | Packaging orchestrator invoking nFPM | VERIFIED | 237 lines, executable, bash syntax valid, sources config.sh and functions.sh, has extract_version(), iterates all 12 components + suite |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `packaging/nfpm/*.yaml` | `scripts/build_*.sh` | DESTDIR staging paths match nFPM contents src paths | VERIFIED | 12 of 13 YAMLs reference `${DESTDIR}/usr/` paths matching what scripts stage. Suite has no contents (correct). |
| `packaging/nfpm/podman.yaml` | `packaging/nfpm/crun.yaml` | depends field references other podman-* packages | VERIFIED | `podman.yaml` depends contains `podman-crun` and 7 other podman-* packages |
| `packaging/nfpm/container-configs.yaml` | `scripts/install_container-configs.sh` | DESTDIR staging tree provides files nFPM packages | VERIFIED | container-configs.yaml src paths (`${DESTDIR}/etc/containers/containers.conf` etc.) match destinations written by `install_container-configs.sh` using `"${DESTDIR:-}"` prefix |
| `scripts/package_all.sh` | `packaging/nfpm/*.yaml` | `nfpm pkg --config packaging/nfpm/${component}.yaml` | VERIFIED | Script invokes `nfpm pkg --config "${NFPM_DIR}/${component}.yaml" --target "${OUTPUT_DIR}" --packager deb` for each component |
| `scripts/package_all.sh` | `config.sh` | sources config.sh for ARCH and component TAG variables | VERIFIED | `source "${toolpath}/config.sh"` on line 11; COMPONENT_TAGS array maps all 12 components to their *_TAG variables |
| `scripts/package_all.sh` | `output/` | `nfpm --target output/` | VERIFIED | `OUTPUT_DIR="${toolpath}/output"` defined; `mkdir -p "${OUTPUT_DIR}"` called; `--target "${OUTPUT_DIR}"` passed to nfpm |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| PKG-01 | 14-01, 14-02 | User can install each component as individual .deb with podman-* prefix | SATISFIED | 13 nFPM YAML configs exist with podman-* names. `package_all.sh` orchestrates building all 12 + suite. |
| PKG-02 | 14-01 | Each package declares Conflicts/Replaces/Provides against corresponding Ubuntu package | SATISFIED | All 11 component configs (all except suite) have conflicts/replaces/provides blocks. pasta conflicts against `passt` (correct Ubuntu name). |
| PKG-03 | 14-01 | Package dependencies correctly declared | SATISFIED | podman-podman depends on 8 packages. podman-toolbox depends on podman-podman. podman-netavark, podman-buildah, podman-skopeo depend on podman-container-configs. Suite depends on all 12. |
| PKG-04 | 14-01, 14-02 | Each component has nFPM YAML with version and architecture substitution via placeholders | SATISFIED | All 13 YAMLs use `version: "${VERSION}"` and `arch: "${ARCH}"`. All 13 have `version_schema: none`. |
| PKG-05 | 14-01 | Build scripts support DESTDIR without modifying direct-install behavior | SATISFIED | All 13 scripts (11 build + 2 install) implement `if [[ -n "${DESTDIR:-}" ]]` conditional. Direct-install branch uses sudo; DESTDIR branch does not. |
| PKG-06 | 14-01, 14-02 | Meta-package podman-suite installs entire stack with one command | SATISFIED | `suite.yaml` with 12 depends entries exists. `package_all.sh` builds it as the 13th package. |
| PKG-07 | 14-01 | Config files in /etc/containers/ declared as conffiles | SATISFIED | `container-configs.yaml` has 5 `type: config` entries for all 5 /etc/containers/ files. seccomp.json correctly excluded. |

**Orphaned requirements check:** No requirements mapped to Phase 14 in REQUIREMENTS.md that are absent from plan frontmatter. All 7 PKG-* requirements are covered.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `scripts/build_pasta.sh` | 73-74 | `rm -f /usr/local/bin/passt.*` | INFO | These are cleanup lines removing files misplaced by an older version. They are inside the `else` (non-DESTDIR) branch and do not affect staging. Not a blocker. |

No TODOs, FIXMEs, placeholder comments, empty implementations, or stubs found in any modified file.

---

### Human Verification Required

The following cannot be verified programmatically and require a real build environment:

#### 1. DESTDIR staging produces complete filesystem tree

**Test:** Run `export DESTDIR=/tmp/test-staging` then run each build script. Verify `ls -R /tmp/test-staging` shows all expected files (binaries, man pages, systemd units, completions, /etc/ configs).
**Expected:** Complete tree with no missing files referenced in nFPM YAMLs (e.g., podman.yaml references `/usr/share/fish/` and `/usr/share/zsh/` — verify these exist after `make install`).
**Why human:** Requires actual compilation environment with all dependencies installed.

#### 2. nFPM produces valid installable .deb packages

**Test:** Run `scripts/package_all.sh` with a populated DESTDIR. Run `dpkg-deb --info` and `dpkg-deb --contents` on each produced .deb. Run `sudo dpkg -i podman-*.deb`.
**Expected:** All 13 .deb files produced. `dpkg -i` installs without errors. `dpkg -l | grep podman-` shows all packages installed.
**Why human:** Requires nFPM installed and populated staging tree from real builds.

#### 3. Conflicts/Replaces/Provides works against Ubuntu Noble packages

**Test:** On Ubuntu 24.04 with existing `podman` package installed, run `sudo dpkg -i podman-podman_*.deb`. On a system with `passt` installed, run `sudo dpkg -i podman-pasta_*.deb`.
**Expected:** dpkg handles the replacement cleanly without unresolvable conflicts.
**Why human:** Requires Ubuntu 24.04 system with official packages pre-installed.

#### 4. conffile preservation on upgrade

**Test:** Install `podman-container-configs`. Edit `/etc/containers/containers.conf`. Install a newer `podman-container-configs`. Verify dpkg prompts about the modified conffile.
**Expected:** dpkg merge prompt appears; user modification preserved.
**Why human:** Requires two versions of the package and an interactive dpkg session.

#### 5. tree type nFPM entries resolve correctly

**Test:** Run nFPM with a populated DESTDIR against `podman.yaml`. Verify nFPM does not error on `type: tree` entries for `/usr/share/man/man1/`, `/usr/lib/systemd/`, `/usr/share/bash-completion/`, `/usr/share/fish/`, `/usr/share/zsh/`.
**Expected:** nFPM processes tree entries and includes all files from those directories.
**Why human:** nFPM `type: tree` behavior depends on what podman's `make install` actually produces; if a directory doesn't exist in the staging tree, nFPM errors.

---

### Gaps Summary

No automated gaps found. All 8 must-have truths are verified against the actual codebase. All 7 requirements (PKG-01 through PKG-07) are satisfied with implementation evidence. All 6 key links are wired. No blocker anti-patterns detected.

The one INFO-level note (cleanup `rm -f /usr/local/bin/passt.*` in build_pasta.sh) is inside the non-DESTDIR direct-install branch and is intentional legacy cleanup — it does not affect staging or indicate a broken path.

Five human verification items remain for runtime behavior validation that cannot be confirmed statically.

---

_Verified: 2026-03-05T10:30:00Z_
_Verifier: Claude (gsd-verifier)_
