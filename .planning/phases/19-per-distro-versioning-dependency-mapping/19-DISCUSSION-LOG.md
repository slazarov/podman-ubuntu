# Phase 19: Per-Distro Versioning & Dependency Mapping - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-05
**Phase:** 19-per-distro-versioning-dependency-mapping
**Areas discussed:** Dependency detection mechanism, Distro identity plumbing, Version string composition, Scope of dep replacement (all resolved via "Apply best practices" directive)

---

## Gray Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Dependency detection mechanism | dpkg -S automatic vs curated table vs hybrid; failure mode | — |
| Distro identity plumbing | os-release auto-detect vs explicit env var; where suffix is composed | — |
| Version string composition | Exact suffix form, stacking with nightly ~git suffix, pasta special case | — |
| Scope of dep replacement | Replace all 7 hardcoded lib deps vs only the renamed ones | — |
| Other: "Apply best practices" | User delegated all four areas to Claude with best-practices guidance | ✓ |

**User's choice:** "Apply best practices" (free-text via Other)
**Notes:** User opted not to discuss areas individually; Claude resolved all four gray areas using best practices grounded in codebase precedents. Resolutions presented to user inline before writing CONTEXT.md.

---

## Resolutions Applied (Claude, per user directive)

1. **Dependency detection:** ldd → `dpkg -S` per-binary resolution (dpkg-shlibdeps-style); exclude priority-required base libs (libc6, libgcc-s1); hard-fail on unresolvable sonames; crun parser special case absorbed.
2. **Distro identity:** auto-detect from `/etc/os-release` with `DISTRO` env override; suffix composed in `config.sh`.
3. **Version string:** `~ubuntu{VERSION_ID}.podman1`; nightly = `{base}~git{date}.{sha}~ubuntu{VERSION_ID}.podman1`; pasta date version gets same suffix; `dpkg --compare-versions` assertions required in-phase.
4. **Scope:** replace ALL hardcoded system lib deps with detected set; internal suite deps stay static; 24.04 detected set must equal current hardcoded set (no-regression proof).

## Claude's Discretion

- Templating mechanism for multi-entry `depends:` injection into nFPM configs (envsubst is awkward for YAML lists)
- 26.04 installability validation vehicle within this phase (e.g. local ubuntu:26.04 container)
- Exclusion-list contents beyond libc6/libgcc-s1 if more priority-required libs surface

## Deferred Ideas

None — discussion stayed within phase scope.
