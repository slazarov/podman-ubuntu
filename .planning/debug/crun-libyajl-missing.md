---
status: awaiting_human_verify
trigger: "crun-libyajl-missing: After installing podman-suite, running podman run quay.io/podman/hello fails because crun cannot find libyajl.so.2"
created: 2026-03-06T00:00:00Z
updated: 2026-03-06T00:02:00Z
---

## Current Focus

hypothesis: CONFIRMED - crun is built with dynamic linking to libyajl but the .deb package neither includes libyajl nor declares it as a dependency
test: fix applied -- awaiting CI rebuild and user verification
expecting: rebuilt crun binary will have yajl statically embedded, eliminating the libyajl.so.2 runtime error
next_action: user triggers CI build and tests podman run on a clean system

## Symptoms

expected: podman run quay.io/podman/hello should pull and run the container successfully
actual: Container creation fails with shared library error from crun
errors: /usr/bin/crun: error while loading shared libraries: libyajl.so.2: cannot open shared object file: No such file or directory
reproduction: Install podman-suite from APT repo, then run any container with podman
started: First attempt after fresh install of podman-suite

## Eliminated

## Evidence

- timestamp: 2026-03-06T00:00:30Z
  checked: scripts/build_crun.sh line 54
  found: crun is configured with `./configure --prefix=/usr` -- no flags for static yajl linking
  implication: crun links dynamically against libyajl.so.2 at runtime

- timestamp: 2026-03-06T00:00:35Z
  checked: scripts/install_dependencies.sh line 59
  found: `libyajl-dev` is installed as a BUILD dependency, but `-dev` packages provide headers + .so symlink, not the runtime .so.2 file on target systems
  implication: libyajl is only present on the BUILD machine, not on user machines that install the .deb

- timestamp: 2026-03-06T00:00:40Z
  checked: packaging/nfpm/crun.yaml
  found: No `depends:` section at all -- the podman-crun .deb declares zero runtime dependencies
  implication: When users install podman-crun, apt has no way to know libyajl2 is needed

- timestamp: 2026-03-06T00:00:45Z
  checked: All other nfpm configs
  found: No package in the suite declares any system library dependencies -- only inter-package deps (podman-* -> podman-*)
  implication: This is a systemic gap, but crun is the only one that crashes because of it (Go/Rust binaries are statically linked)

- timestamp: 2026-03-06T00:00:50Z
  checked: crun upstream configure options (web search)
  found: crun supports `--enable-embedded-yajl` to use the bundled yajl from its libocispec submodule, eliminating the runtime libyajl dependency entirely
  implication: Best fix is to use embedded yajl so the binary is self-contained, matching the Go/Rust components' approach

## Resolution

root_cause: crun is built with `./configure --prefix=/usr` which dynamically links against system libyajl. The resulting binary requires libyajl.so.2 at runtime, but the podman-crun .deb package (a) does not include libyajl.so.2 and (b) does not declare libyajl2 as a runtime dependency. On user machines without libyajl-dev installed, crun fails to load.
fix: |
  1. Primary: Added `--enable-embedded-yajl` to crun's ./configure in scripts/build_crun.sh.
     This uses the bundled yajl from crun's libocispec submodule, statically linking it into the
     binary. The resulting crun has no runtime dependency on libyajl.so.2.
  2. Secondary: Added `depends: [libseccomp2]` to packaging/nfpm/crun.yaml to declare the
     remaining dynamic library dependency that crun needs at runtime.
verification: awaiting CI rebuild and user test -- user must run podman on a clean system without libyajl-dev installed
files_changed:
  - scripts/build_crun.sh
  - packaging/nfpm/crun.yaml
