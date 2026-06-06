---
phase: quick-5
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - README.md
autonomous: true
requirements: ["quick-5"]
must_haves:
  truths:
    - "Visitor immediately understands what the project does (Podman from source on Debian/Ubuntu)"
    - "Visitor can add the APT repo and install packages in under 60 seconds of reading"
    - "Visitor can find build-from-source instructions if they prefer that route"
    - "Visitor sees which components are included and their current versions"
  artifacts:
    - path: "README.md"
      provides: "Complete project README"
      min_lines: 120
  key_links:
    - from: "README.md"
      to: "https://slazarov.github.io/podman-debian"
      via: "APT repository URL in quick-start snippet"
      pattern: "slazarov.github.io/podman-debian"
---

<objective>
Generate a comprehensive, well-structured README.md for the podman-debian repository.

Purpose: The current README is a bare-bones stub with outdated version exports. The project now offers both a hosted APT repository (the easy path) and build-from-source scripts (the power-user path). The README should make both paths clear, with the APT repo as the primary call-to-action.

Output: A polished README.md replacing the existing stub.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@README.md
@docs/apt-repository.md
@versions-stable.env
@config.sh
@setup.sh
@uninstall.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Write comprehensive README.md</name>
  <files>README.md</files>
  <action>
Replace the existing README.md with a well-structured document covering:

**Header section:**
- Project name: `podman-debian`
- One-liner: Compile and install the latest Podman stack from source on Debian/Ubuntu, or install pre-built packages from the APT repository.
- Badges (optional): License AGPL-3.0, platform Ubuntu 24.04, architectures amd64/arm64
- Fork attribution: Forked from luckylinux/podman-debian, with significant additions (arm64, non-interactive, APT repo, CI/CD, 12 components).

**Section 1 - "Install via APT (Recommended)":**
- Copy the quick-start snippet from `docs/apt-repository.md` (download GPG key, add DEB822 source, apt update, apt install podman-suite).
- Mention the three suites: stable (pinned releases), edge (latest tags), nightly (HEAD commits daily at 4:30 AM UTC).
- Brief note on switching suites (change the Suites: line).
- Link to `docs/apt-repository.md` for full details (troubleshooting, individual packages, etc.).

**Section 2 - "Individual Packages":**
- Table of all 12 packages from `docs/apt-repository.md` (podman-podman, podman-crun, podman-conmon, podman-netavark, podman-aardvark-dns, podman-pasta, podman-fuse-overlayfs, podman-catatonit, podman-buildah, podman-skopeo, podman-toolbox, podman-container-configs).
- Note that `podman-suite` is a meta-package that installs all of them.
- Note: packages use `podman-*` prefix with Conflicts/Replaces on official Ubuntu packages.

**Section 3 - "Build from Source":**
- Prerequisites: Debian/Ubuntu system (tested on Ubuntu 24.04), root or sudo, internet access.
- Clone, source versions-stable.env, run setup.sh.
- Mention env var overrides (SCCACHE_ENABLED, CCACHE_ENABLED, MOLD_ENABLED for build caching).
- Mention uninstall.sh for clean removal.
- Note: builds 12 components from source (Podman, Buildah, Skopeo, crun, conmon, Netavark, Aardvark-DNS, pasta, fuse-overlayfs, catatonit, Toolbox, container-configs).
- Note: auto-detects architecture (amd64/arm64), fully non-interactive, ~15-20 min fresh build.

**Section 4 - "Components":**
- Table with component name, upstream repo URL, and brief description.
- Components: Podman, Buildah, Skopeo, crun, conmon, Netavark, Aardvark-DNS, pasta/passt, fuse-overlayfs, catatonit, Toolbox, container-libs (containers-common).

**Section 5 - "Current Versions" (stable track):**
- A compact table or list showing the versions from versions-stable.env (Podman v5.8.0, Buildah v1.43.0, etc.).
- Note: edge track pulls latest upstream tags automatically.

**Section 6 - "Supported Platforms":**
- Ubuntu 24.04 (Noble Numbat)
- Architectures: amd64 (x86_64), arm64 (aarch64)
- Both built natively in CI (not cross-compiled).

**Section 7 - "Build Caching" (brief):**
- Mention opt-in caching layers: sccache (Rust), ccache (C), Go cache (shared), mold linker.
- One-liner on how to enable each.

**Section 8 - "License":**
- AGPL-3.0

**Section 9 - "Credits":**
- Forked from luckylinux/podman-debian
- Links to upstream Podman project (https://github.com/containers/podman)

**Style guidelines:**
- Use clean, scannable markdown. No walls of text.
- Code blocks for all commands.
- Tables for structured data.
- Keep it practical -- a user should be able to get Podman running by reading just the first section.
- Do NOT use emojis.
  </action>
  <verify>
    <automated>test -f README.md && wc -l README.md | awk '{if ($1 >= 120) print "PASS: " $1 " lines"; else print "FAIL: only " $1 " lines"}'</automated>
  </verify>
  <done>README.md exists with 120+ lines covering APT install (primary), build-from-source (secondary), component table, version table, platform info, and attribution. The APT quick-start is the first actionable section a visitor sees.</done>
</task>

</tasks>

<verification>
- README.md contains APT quick-start snippet with correct GPG key URL and repo URL
- README.md contains build-from-source instructions referencing setup.sh and versions-stable.env
- README.md lists all 12 component packages
- README.md mentions all three suites (stable, edge, nightly)
- README.md has correct license (AGPL-3.0) and fork attribution
</verification>

<success_criteria>
A visitor to https://github.com/slazarov/podman-debian sees a polished README that (1) lets them install via APT in 4 commands, (2) explains the build-from-source path, (3) lists all components and current versions, and (4) credits the upstream fork.
</success_criteria>

<output>
After completion, create `.planning/quick/5-generate-a-nice-readme-for-the-repo/5-SUMMARY.md`
</output>
