---
status: resolved
trigger: "build_catatonit.sh fails with `configure.ac:24: error: required file './ltmain.sh' not found` during autoreconf"
created: 2026-02-28T19:47:00Z
updated: 2026-02-28T20:00:00Z
---

## Current Focus

hypothesis: (CONFIRMED) libtoolize puts ltmain.sh in wrong directory because catatonit lacks AC_CONFIG_AUX_DIR
test: Create m4 directory before autoreconf to fix auxiliary directory detection
expecting: libtoolize will now put ltmain.sh in current directory
next_action: Verify fix by having user test the build script

## Symptoms

expected: autoreconf should complete successfully and generate configure script
actual: autoreconf fails because automake cannot find ltmain.sh in current directory
errors: |
  libtoolize: putting auxiliary files in '../..'.
  libtoolize: copying file '../../ltmain.sh'
  configure.ac:24: error: required file './ltmain.sh' not found
  autoreconf: error: automake failed with exit status: 1
reproduction: Run `scripts/build_catatonit.sh` on a fresh clone of catatonit
started: When building catatonit v0.2.1 with fresh autoreconf

## Eliminated

(none yet)

## Evidence

- timestamp: 2026-02-28T19:48:00Z
  checked: catatonit configure.ac for AC_CONFIG_AUX_DIR
  found: NOT present - configure.ac has LT_INIT but no AC_CONFIG_AUX_DIR
  implication: libtoolize will try to guess auxiliary directory location

- timestamp: 2026-02-28T19:48:30Z
  checked: fuse-overlayfs configure.ac for AC_CONFIG_AUX_DIR
  found: PRESENT - line 6 has `AC_CONFIG_AUX_DIR([build-aux])`
  implication: fuse-overlayfs works because it explicitly specifies aux directory

- timestamp: 2026-02-28T19:49:00Z
  checked: Fresh catatonit clone directory structure
  found: No m4 directory, no build-aux directory, no config directory
  implication: libtoolize heuristics fail without these directories, defaults to parent

- timestamp: 2026-02-28T19:49:30Z
  checked: Existing build/catatonit that succeeded
  found: Has ltmain.sh in ./ (current directory), build succeeded
  implication: Previous builds may have had m4 directory created or different environment

## Resolution

root_cause: catatonit's configure.ac lacks AC_CONFIG_AUX_DIR directive, causing libtoolize to incorrectly determine auxiliary file location (../.. instead of .) during autoreconf
fix: Added `mkdir -p m4` before running autogen.sh in build_catatonit.sh. The m4 directory's presence causes libtoolize to use current directory for auxiliary files.
verification: User confirmed fix works - bash -x trace shows mkdir -p m4 executed, libtoolize now reports "putting auxiliary files in '.'", autoreconf completed successfully, ./configure ran, make compiled catatonit, sudo make install installed to /usr/local/bin/catatonit
files_changed:
  - scripts/build_catatonit.sh: Added mkdir -p m4 before autogen.sh
