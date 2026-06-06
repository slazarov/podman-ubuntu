---
status: awaiting_human_verify
trigger: "conmon v2.2.1 build succeeds but make install fails with exit code 2 in CI"
created: 2026-03-05T00:00:00Z
updated: 2026-03-05T00:00:00Z
---

## Current Focus

hypothesis: CONFIRMED - conmon v2.2.1 `make install` fails because `docs` target requires `go-md2man` which is not yet built
test: Applied fix: use `make install.bin` to skip docs, added verbose logging, disabled arm64
expecting: CI build should pass on next run
next_action: User verifies by running the GitHub Actions workflow

## Symptoms

expected: conmon v2.2.1 should build and install successfully in CI (like v2.1.13 does)
actual: Build succeeds, but the install step fails with exit code 2. CI log shows "Installing..." then "Error: Process completed with exit code 2" with no further detail.
errors: Exit code 2 during `make install` phase. No verbose output available.
reproduction: Run the GitHub Actions build-packages workflow on v2.0-apt-packaging branch with edge track. The build_conmon.sh script fails at the install step for conmon v2.2.1.
started: conmon v2.1.13 (stable pin) works fine. v2.2.1 (latest/edge tag) fails.

## Eliminated

(none - root cause found on first hypothesis)

## Evidence

- timestamp: 2026-03-05T00:01:00Z
  checked: conmon v2.2.1 Makefile install target (line 113)
  found: `install: install.bin docs` followed by `$(MAKE) -C docs install` -- the install target depends on building docs first
  implication: Any `make install` will trigger a docs build

- timestamp: 2026-03-05T00:02:00Z
  checked: conmon docs/Makefile (line 4, 8-9)
  found: `GOMD2MAN ?= go-md2man` and the docs target runs `$(GOMD2MAN) -in $^ -out $@` to convert .md to man pages
  implication: Building docs requires go-md2man binary in PATH

- timestamp: 2026-03-05T00:03:00Z
  checked: setup.sh build order (lines 77 vs 86)
  found: build_conmon.sh runs at line 77, build_go-md2man.sh runs at line 86 -- conmon is built BEFORE go-md2man
  implication: go-md2man is NOT available when conmon tries `make install`

- timestamp: 2026-03-05T00:04:00Z
  checked: git diff v2.1.13..v2.2.1 -- Makefile
  found: In v2.1.13, the docs target had `ifeq ($(GOMD2MAN),) docs: install.tools endif` guard. In v2.2.1, this guard was removed -- docs target is now unconditional.
  implication: v2.1.13 gracefully handled missing go-md2man; v2.2.1 does not -- this is the breaking change

- timestamp: 2026-03-05T00:05:00Z
  checked: docs/Makefile install target (line 14)
  found: `install -m 0644 conmon*.8 ${DESTDIR}/${MANDIR}/man8` -- if .8 files don't exist (go-md2man failed), this glob fails with exit code 2
  implication: Even if go-md2man failure is somehow silent, the install step itself fails on missing .8 files

- timestamp: 2026-03-05T00:06:00Z
  checked: run_logged function in functions.sh (line 293-297)
  found: `"$@" >> "$BUILD_LOG" 2>&1` -- ALL output (stdout+stderr) goes to log file, nothing to console
  implication: This is why CI shows no error detail -- the actual make error is hidden in the build log file which is not preserved as an artifact

## Resolution

root_cause: conmon v2.2.1 changed its Makefile to unconditionally require `go-md2man` for the `install` target (the conditional guard from v2.1.13 was removed). Since setup.sh builds conmon (line 77) before go-md2man (line 86), `make install` triggers a `docs` build that fails because `go-md2man` is not yet available. The error is invisible in CI because `run_logged` redirects all output to a log file that is never uploaded as an artifact.

fix: (1) Change build_conmon.sh to use `make install.bin` instead of `make install` to skip the docs dependency, matching what we actually need (just the binary). (2) Add verbose logging: on failure, dump the build log tail to stderr so it appears in CI output. (3) Limit CI to amd64-only temporarily to save minutes while debugging.
verification: Awaiting CI run. The fix is structurally correct based on Makefile analysis -- `install.bin` target (line 120-122) installs only the conmon binary without triggering the docs dependency chain.
files_changed:
  - scripts/build_conmon.sh: Changed `make install` to `make install.bin` to skip docs target
  - functions.sh: Enhanced `run_logged` to dump last 40 lines of build log to stderr on failure
  - .github/workflows/build-packages.yml: Temporarily disabled arm64 job (commented out), publish depends only on amd64
