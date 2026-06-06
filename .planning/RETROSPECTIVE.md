# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — MVP

**Shipped:** 2026-03-03
**Phases:** 5 | **Plans:** 13 | **Sessions:** 1

### What Was Built
- Cross-platform architecture support enabling Podman compilation on both amd64 and ARM64 systems
- Zero-interaction installation with DEBIAN_FRONTEND=noninteractive throughout all scripts
- Robust error handling with strict mode (set -euo pipefail) in all 18 scripts
- User experience enhancements including progress tracking, build logging, and clean uninstall
- Build performance optimizations reducing estimated build time from 30+ minutes to 10-15 minutes

### What Worked
- **YOLO mode execution** - Auto-approval of verification gates enabled rapid progress
- **Quick depth planning** - 5 phases, 13 plans was right-sized for the scope
- **Verification-driven development** - Each phase had clear VERIFICATION.md files with automated checks
- **Architecture-first approach** - Phase 1 (architecture detection) enabled all subsequent work
- **Parallel execution** - Many plans within phases could run independently

### What Was Inefficient
- **Phase 5 documentation lag** - 05-02 was complete but ROADMAP.md wasn't updated until audit
- **Missing SUMMARY files** - Some plans (05-01) were verification-only and skipped SUMMARY generation
- **Circular sourcing** - config.sh ↔ functions.sh pattern works but is fragile

### Patterns Established
- **Architecture detection pattern**: Centralized detect_architecture() in config.sh with vendor-specific mappings (GOARCH, PROTOC_ARCH, RUSTUP_ARCH)
- **Strict mode everywhere**: set -euo pipefail in all scripts with trap-based error handling
- **Progress tracking pattern**: step_start/step_done with elapsed time for user feedback
- **Optimization configurability**: All performance settings overridable via environment variables
- **Safe removal pattern**: safe_rm_dir/safe_rm_file with tracking arrays for graceful handling

### Key Lessons
1. **Verification-only plans don't need SUMMARY files** - When work is already done, verification alone is sufficient
2. **Documentation sync is critical** - Audit revealed documentation gaps (ROADMAP, REQUIREMENTS) that needed manual updates
3. **Guard circular dependencies** - Circular sourcing works with guards but should be used sparingly
4. **Environment variable overrides are essential** - Users need control over optimizations (NPROC, SHALLOW_CLONE, etc.)
5. **Shallow clones by default** - --depth 1 should be the default for fresh clones with override option

### Cost Observations
- Model mix: 100% opus (single session, all execution)
- Sessions: 1
- Notable: Single-day execution from Phase 1 through Phase 5 completion - efficient planning and execution flow

---

## Milestone: v1.1 — Ecosystem Audit

**Shipped:** 2026-03-04
**Phases:** 5 | **Plans:** 7 | **Sessions:** ~3

### What Was Built
- Removed deprecated runc and slirp4netns build scripts — crun+pasta ecosystem only
- Pre-flight validation system (cgroups v2, subuid/subgid, FUSE, kernel version, noexec mounts)
- Multi-layer build caching: sccache (Rust), Go cache persistence, ccache (C), mold linker (Rust linking)
- Production-ready containers.conf with crun runtime, netavark networking, seccomp profile
- Symmetric uninstall — everything install adds, uninstall removes

### What Worked
- **Feature flag pattern** — All new build tools (sccache, ccache, mold) opt-in with `*_ENABLED=false` default. Zero behavior change for existing users.
- **Milestone audit before completion** — Caught 2 integration gaps (MISSING-01: mold/clang uninstall, BROKEN-01: redundant containers.conf copy) that led to Phase 10 gap closure.
- **Research-before-plan** — Phase 9 research identified ccache+mold as valuable additions beyond original scope. Research investment paid off.
- **Centralized config** — Moving Go cache to config.sh eliminated 5 per-script overrides. DRY wins.

### What Was Inefficient
- **seccomp.json oversight** — containers.conf references seccomp.json but nothing installs it. Discovered post-milestone via runtime error. Should have tested `podman run` as an E2E check during UAT.
- **Phase 9 naming** — Very long directory name made paths unwieldy. Shorter slugs are better.
- **Phase 10 for 2 small fixes** — A full phase for 2 one-line fixes was heavyweight. Could have been a quick fix.

### Patterns Established
- **Feature flag convention**: `*_ENABLED=false` in config.sh with conditional logic in build scripts
- **dpkg-gated removal**: Check `dpkg -s pkg` before `apt-get remove` in uninstall.sh
- **Centralized cache config**: All cache paths and settings in config.sh, build scripts inherit
- **Pre-flight validation**: Separate script with ERROR/WARNING severity levels

### Key Lessons
1. **Test E2E, not just components** — All individual features worked but `podman run` failed due to missing seccomp.json. E2E smoke test would have caught this.
2. **Source builds miss distro-provided files** — When building from source, files normally provided by `containers-common` package are absent. Need to account for these.
3. **Milestone audit is high-value** — Caught real integration issues that individual phase verifications missed. Worth the extra step.
4. **Opt-in features reduce risk** — Default-off feature flags let us ship new capabilities without breaking existing users.

### Cost Observations
- Model mix: ~80% opus (execution), ~20% sonnet (verification)
- Sessions: ~3 (planning, execution, gap closure)
- Notable: 2-day turnaround for 5 phases including research, planning, execution, audit, and gap closure

---

## Milestone: v1.2 — Include Common Libraries

**Shipped:** 2026-03-04
**Phases:** 3 | **Plans:** 3 | **Sessions:** 1

### What Was Built
- Build script for container-libs monorepo — clones, checks out latest tag, generates seccomp.json via Go codegen
- Install script for 6 runtime config files (seccomp.json, policy.json, registries.conf, storage.conf, registries.d/default.yaml, containers.conf)
- Man page build and install for 15 section-5 pages using go-md2man
- Symmetric uninstall coverage for all new artifacts (man pages, config files, build directory)

### What Worked
- **Tight 3-phase pipeline** — Build -> Install -> Document/Cleanup was clean and well-scoped
- **Live system verification** — Testing on actual Lima VM caught real issues (seccomp make target, meson DESTDIR)
- **Fast iteration** — Bugs found during live test were fixed and pushed within minutes

### What Was Inefficient
- **Wrong make target path** — `make seccomp.json` ran from repo root but target lives in `common/Makefile`. Should have read the Makefile before generating the build script.
- **Wrong meson DESTDIR** — `DESTDIR=/usr/local` with `--prefix /usr/local` doubled the path. Standard meson usage was not verified during planning.
- **Agents didn't verify upstream Makefiles** — Both the container-libs and toolbox build scripts had incorrect build commands because agents generated code without reading the actual repo Makefiles.

### Patterns Established
- **Verify upstream build systems** — Always read the Makefile/meson.build of the target repo before writing build scripts
- **`make -C subdir target` pattern** — For monorepos where targets live in subdirectories
- **`install -m 0644` convention** — Consistent with upstream for all config and man page files

### Key Lessons
1. **Read the source Makefile** — Never assume make target locations. container-libs is a monorepo; the seccomp target was in `common/Makefile`, not the root.
2. **Test on real system early** — Live testing caught two bugs that verification couldn't: wrong make path and wrong DESTDIR.
3. **DESTDIR + prefix = doubled paths** — With meson, DESTDIR prepends to prefix. Use one or the other, not both.
4. **run_logged hides errors** — Output redirection to log files makes failures silent. Consider showing the last N lines of the log on error.

### Cost Observations
- Model mix: ~90% opus (execution), ~10% sonnet (verification)
- Sessions: 1
- Notable: Execution was fast but required 2 manual bug fixes post-execution due to incorrect upstream assumptions

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | 1 | 5 | Initial MVP delivery with full GSD workflow |
| v1.1 | ~3 | 5 | Added research phase, milestone audit, gap closure cycle |
| v1.2 | 1 | 3 | Upstream source integration, live system verification |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | N/A | 100% (verification) | 0 (shell scripts only) |
| v1.1 | N/A | 100% (verification + audit) | 3 (sccache, ccache, mold — all opt-in) |
| v1.2 | N/A | 100% (verification + live test) | 0 (container-libs already in ecosystem) |

### Top Lessons (Verified Across Milestones)

1. Verification-driven development ensures requirements are met before declaring completion
2. Documentation must be updated in real-time to avoid audit findings
3. Milestone audits catch integration gaps that phase-level verification misses (v1.1 found 2 issues)
4. E2E smoke tests are essential — component verification alone is insufficient (seccomp.json miss in v1.1)
5. Always read upstream build systems before generating build scripts — wrong assumptions led to 2 bugs in v1.2
