---
phase: quick-6
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - config/containers.conf
  - scripts/repo_manage.sh
  - scripts/ci_publish.sh
  - scripts/package_all.sh
  - README.md
  - docs/apt-repository.md
  - packaging/nfpm/aardvark-dns.yaml
  - packaging/nfpm/buildah.yaml
  - packaging/nfpm/catatonit.yaml
  - packaging/nfpm/conmon.yaml
  - packaging/nfpm/container-configs.yaml
  - packaging/nfpm/crun.yaml
  - packaging/nfpm/fuse-overlayfs.yaml
  - packaging/nfpm/netavark.yaml
  - packaging/nfpm/pasta.yaml
  - packaging/nfpm/skopeo.yaml
  - packaging/nfpm/suite.yaml
  - packaging/nfpm/toolbox.yaml
  - packaging/repo/conf/distributions
  - .planning/REQUIREMENTS.md
  - .planning/STATE.md
  - .planning/milestones/v1.2-REQUIREMENTS.md
autonomous: true
must_haves:
  truths:
    - "All user-facing references say podman-ubuntu instead of podman-debian"
    - "GPG key filename is podman-ubuntu.gpg everywhere"
    - "APT repo URLs reference podman-ubuntu"
    - "Package metadata shows Podman Ubuntu maintainer and vendor"
    - "No functional code is broken by the rename"
  artifacts:
    - path: "scripts/repo_manage.sh"
      provides: "GPG key reference updated"
      contains: "podman-ubuntu.gpg"
    - path: "scripts/ci_publish.sh"
      provides: "Landing page and URLs updated"
      contains: "podman-ubuntu"
    - path: "packaging/repo/conf/distributions"
      provides: "Repo origin and label updated"
      contains: "podman-ubuntu"
  key_links:
    - from: "scripts/repo_manage.sh"
      to: "scripts/ci_publish.sh"
      via: "GPG key filename must match"
      pattern: "podman-ubuntu\\.gpg"
---

<objective>
Rename all references from "podman-debian" to "podman-ubuntu" across the entire codebase.

Purpose: The project targets Ubuntu (24.04), not Debian. All branding, URLs, GPG key filenames, package metadata, and documentation should reflect "podman-ubuntu".
Output: Every file referencing "podman-debian" updated to "podman-ubuntu"; "Podman Debian" updated to "Podman Ubuntu".
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Rename podman-debian to podman-ubuntu in all source files</name>
  <files>
    config/containers.conf
    scripts/repo_manage.sh
    scripts/ci_publish.sh
    scripts/package_all.sh
    packaging/nfpm/aardvark-dns.yaml
    packaging/nfpm/buildah.yaml
    packaging/nfpm/catatonit.yaml
    packaging/nfpm/conmon.yaml
    packaging/nfpm/container-configs.yaml
    packaging/nfpm/crun.yaml
    packaging/nfpm/fuse-overlayfs.yaml
    packaging/nfpm/netavark.yaml
    packaging/nfpm/pasta.yaml
    packaging/nfpm/skopeo.yaml
    packaging/nfpm/suite.yaml
    packaging/nfpm/toolbox.yaml
    packaging/repo/conf/distributions
  </files>
  <action>
    Perform case-sensitive find-and-replace across all listed files:

    1. Replace "podman-debian" with "podman-ubuntu" (lowercase, used in GPG filenames, URLs, vendor fields, Origin)
    2. Replace "Podman Debian" with "Podman Ubuntu" (title case, used in maintainer names, Label, descriptions, banner text)
    3. Replace "Podman-Debian" with "Podman-Ubuntu" if any exist (check first)

    IMPORTANT exclusions — do NOT change:
    - `DEBIAN_FRONTEND=noninteractive` (standard apt env var, not project branding)
    - References to "Debian" as a packaging system (e.g., "Debian policy", dpkg comments)
    - `ubuntu-24.04` runner references (already correct)

    Use `sed -i ''` on macOS or read-and-write approach for each file. After replacement, visually scan the diff to confirm no false positives.
  </action>
  <verify>
    Run: `rtk grep -r "podman-debian" config/ scripts/ packaging/` — should return zero matches.
    Run: `rtk grep -r "Podman Debian" config/ scripts/ packaging/` — should return zero matches.
    Run: `rtk grep -r "DEBIAN_FRONTEND" scripts/` — should still have matches (not renamed).
  </verify>
  <done>All source files (configs, scripts, packaging) reference podman-ubuntu consistently. No false positives (DEBIAN_FRONTEND untouched).</done>
</task>

<task type="auto">
  <name>Task 2: Rename podman-debian to podman-ubuntu in documentation and planning files</name>
  <files>
    README.md
    docs/apt-repository.md
    .planning/REQUIREMENTS.md
    .planning/STATE.md
    .planning/milestones/v1.2-REQUIREMENTS.md
  </files>
  <action>
    Perform case-sensitive find-and-replace:

    1. Replace "podman-debian" with "podman-ubuntu" (URLs, git clone paths, GPG key paths)
    2. Replace "Podman Debian" with "Podman Ubuntu" (project title, descriptions)

    For README.md specifically:
    - Update the project title/heading
    - Update all `git clone` URLs from podman-debian.git to podman-ubuntu.git
    - Update APT repository URLs (e.g., github.io/podman-debian → github.io/podman-ubuntu)
    - Update GPG key download paths

    For docs/apt-repository.md:
    - Update all installation instruction URLs and GPG key paths

    For planning files:
    - Update project description references

    Do NOT change references to "Debian" as an OS/packaging system (e.g., "Debian/Ubuntu system" is fine to keep as-is since it describes OS compatibility).
  </action>
  <verify>
    Run: `rtk grep -r "podman-debian" README.md docs/ .planning/REQUIREMENTS.md .planning/STATE.md .planning/milestones/` — should return zero matches.
    Run: `rtk grep -rn "podman-ubuntu" README.md docs/` — should show the updated references.
  </verify>
  <done>All documentation and planning files reference podman-ubuntu. Git clone URLs, APT repo URLs, GPG key paths all updated. Debian OS references preserved where appropriate.</done>
</task>

</tasks>

<verification>
Full codebase scan: `rtk grep -r "podman-debian" . --include='*.md' --include='*.sh' --include='*.yaml' --include='*.yml' --include='*.conf'` returns zero results (excluding .git/).
Spot-check: `rtk grep -rn "podman-ubuntu" scripts/ packaging/ README.md docs/` confirms new references are in place.
No broken references: GPG key filename consistent between repo_manage.sh and ci_publish.sh.
</verification>

<success_criteria>
Zero occurrences of "podman-debian" remain in the codebase (outside .git/ and .planning/phases/ historical summaries).
All user-facing references (README, docs, APT repo config, package metadata) say "podman-ubuntu".
GPG key filename is "podman-ubuntu.gpg" consistently across all scripts.
</success_criteria>

<output>
After completion, create `.planning/quick/6-rename-repo-from-podman-debian-to-podman/6-SUMMARY.md`
</output>
