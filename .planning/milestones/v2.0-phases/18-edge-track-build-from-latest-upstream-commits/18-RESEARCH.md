# Phase 18: Edge Track: Build from Latest Upstream Commits - Research

**Researched:** 2026-03-06
**Domain:** CI/CD, Git-based versioning, Debian packaging from development branches
**Confidence:** HIGH

## Summary

Phase 18 extends the existing dual-track build system (stable pinned versions + edge latest tags) with a third track that builds packages from the latest upstream commits on main/master branches. This gives users access to bleeding-edge features before official releases are tagged. The core challenge is not building itself -- the existing `setup.sh` already handles building from any git ref including HEAD -- but rather **version numbering**, **shallow clone limitations**, and **CI workflow integration** for commit-based builds.

The Debian packaging ecosystem has well-established conventions for snapshot/development versioning. The recommended format is `{next_version}~git{YYYYMMDD}.{short_hash}`, where the tilde (`~`) ensures the snapshot version sorts **lower** than the eventual release (e.g., `6.0.0~git20260306.abc1234` < `6.0.0`). This is critical so that users on the git-snapshot track are automatically upgraded when the real release lands in the edge suite.

All upstream containers/ projects store their development version in source files (Go `version.go`, Rust `Cargo.toml`, C `configure.ac`, or `VERSION` files), typically as `X.Y.Z-dev`. These can be parsed at build time to derive the base version without relying on `git describe`, which is unreliable with shallow clones.

**Primary recommendation:** Add a `nightly` suite to the APT repository alongside `stable` and `edge`. Build from HEAD of each component's default branch using full clones (not shallow), extract the dev version from source files, and produce packages versioned as `{base_version}~git{YYYYMMDD}.{short_sha}~podman1`.

## Standard Stack

### Core (Already In Use)
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| GitHub Actions | N/A | CI/CD orchestration | Already used in Phase 16 |
| reprepro | System package | APT repository management | Already used in Phase 15 |
| nFPM | v2.45.0 | .deb package creation | Already used in Phase 14 |
| git | System package | Source checkout | Already used everywhere |

### Supporting (New for Phase 18)
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `git describe --tags --abbrev=7` | N/A | Derive commit distance + short hash from HEAD | Version computation for components with tags |
| `git rev-parse --short=7 HEAD` | N/A | Get short commit hash | Always, for version suffix |
| `date +%Y%m%d` | N/A | Date component in version string | Always, for version ordering |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| New `nightly` suite | Reuse `edge` suite | Would overwrite tag-based edge packages; users lose ability to pin to tagged releases |
| Tilde (`~`) versioning | Plus (`+`) versioning | Plus sorts higher than release, so user would NOT auto-upgrade to release; tilde is correct |
| Source file version parsing | `git describe` only | `git describe` fails on shallow clones and repos without annotated tags; source parsing is more reliable |
| Full clone (`SHALLOW_CLONE=false`) | Shallow clone + unshallow | Unshallow adds complexity; full clone is simpler and needed for `git describe` |

## Architecture Patterns

### Recommended Repository Structure
```
APT Repository Suites:
  stable/   -- Pinned, tested versions (user-controlled)
  edge/     -- Latest upstream release tags (auto-detected)
  nightly/  -- Latest upstream commits from main/master (daily builds)
```

### Pattern 1: Three-Suite APT Repository
**What:** Add a `nightly` suite to the existing reprepro `distributions` config.
**When to use:** Always for this phase.
**Example:**
```
# Addition to packaging/repo/conf/distributions
Origin: podman-debian
Label: Podman Debian
Suite: nightly
Codename: nightly
Architectures: amd64 arm64
Components: main
Description: Podman compiled from source for Ubuntu 24.04 - nightly git snapshots
SignWith: yes
```

### Pattern 2: Dev Version Extraction from Source Files
**What:** Parse the development version from each component's source code rather than relying on git tags.
**When to use:** For every component when building from HEAD.

Each upstream project stores its version in a known location:

| Component | Version Source File | Format | Example Dev Value |
|-----------|-------------------|--------|-------------------|
| podman | `version/rawversion/version.go` | `const RawVersion = "X.Y.Z-dev"` | `6.0.0-dev` |
| buildah | `define/types.go` | `Version = "X.Y.Z-dev"` | `1.43.0-dev` |
| skopeo | `version/version.go` | `Version = "X.Y.Z-dev"` | `1.22.0-dev` |
| netavark | `Cargo.toml` | `version = "X.Y.Z-dev"` | `2.0.0-dev` |
| aardvark-dns | `Cargo.toml` | `version = "X.Y.Z-dev"` | `2.0.0-dev` |
| crun | `configure.ac` | `AC_INIT([crun], m4_esyscmd([build-aux/git-version-gen ...]))` | Dynamic from git |
| conmon | `VERSION` file | Plain text | `2.2.1` |
| fuse-overlayfs | `configure.ac` | `AC_INIT([fuse-overlayfs], [X.Y-dev], ...)` | `1.17-dev` |
| catatonit | `configure.ac` | `AC_INIT([catatonit], [X.Y.Z+dev], ...)` | `0.2.1+dev` |
| toolbox | `meson.build` | `version: 'X.Y'` | `0.3` |
| container-libs | Git tags (namespaced) | `common/vX.Y.Z` | N/A -- use latest tag |
| pasta/passt | Date-based (no tags) | `YYYYMMDD` | `20260306` |

**Example extraction function:**
```bash
extract_dev_version() {
    local component="$1"
    local repo_path="$2"
    local short_sha=$(git -C "$repo_path" rev-parse --short=7 HEAD)
    local datestamp=$(date +%Y%m%d)
    local base_version=""

    case "$component" in
        podman)
            base_version=$(grep 'RawVersion' "$repo_path/version/rawversion/version.go" \
                | sed 's/.*"\(.*\)".*/\1/' | sed 's/-dev//')
            ;;
        buildah)
            base_version=$(grep '^[[:space:]]*Version' "$repo_path/define/types.go" \
                | head -1 | sed 's/.*"\(.*\)".*/\1/' | sed 's/-dev//')
            ;;
        skopeo)
            base_version=$(grep 'Version' "$repo_path/version/version.go" \
                | head -1 | sed 's/.*"\(.*\)".*/\1/' | sed 's/-dev//')
            ;;
        netavark|aardvark-dns)
            base_version=$(grep '^version' "$repo_path/Cargo.toml" \
                | head -1 | sed 's/.*"\(.*\)".*/\1/' | sed 's/-dev//')
            ;;
        conmon)
            base_version=$(cat "$repo_path/VERSION" | tr -d '[:space:]')
            ;;
        fuse-overlayfs|catatonit)
            base_version=$(grep 'AC_INIT' "$repo_path/configure.ac" \
                | sed 's/.*\[\([^]]*\)\].*/\1/' | sed 's/[+-]dev//')
            ;;
        crun)
            # crun uses git-version-gen; fall back to git describe
            base_version=$(git -C "$repo_path" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
            ;;
        toolbox)
            base_version=$(grep "version:" "$repo_path/meson.build" \
                | head -1 | sed "s/.*'\(.*\)'.*/\1/")
            ;;
        container-configs)
            # Use latest common/ tag
            base_version=$(git -C "$repo_path" tag --list 'common/*' --sort=-version:refname \
                | head -1 | sed 's|common/v||')
            ;;
        pasta)
            # Date-based, no dev version concept
            echo "${datestamp}"
            return
            ;;
    esac

    # Output: X.Y.Z~gitYYYYMMDD.abcdef1
    echo "${base_version}~git${datestamp}.${short_sha}"
}
```

### Pattern 3: Nightly Version String Format
**What:** Version format that sorts correctly in Debian's dpkg version comparison.
**When to use:** All nightly packages.

**Format:** `{base_version}~git{YYYYMMDD}.{short_sha}~podman1`

**Sort order examples (dpkg --compare-versions):**
```
5.8.0~git20260301.abc1234~podman1   <   (any git snapshot of 5.8.0)
5.8.0~git20260305.def5678~podman1   <   (later snapshot, sorts higher)
5.8.0~podman1                       <   (tagged release 5.8.0 from edge)
6.0.0~git20260306.ghi9012~podman1   <   (git snapshot of next major)
6.0.0~podman1                           (future tagged release)
```

The tilde before `git` ensures snapshots always sort **below** the actual release. The date component (`YYYYMMDD`) ensures newer snapshots sort higher than older ones. The short SHA provides traceability.

### Pattern 4: Clone Strategy for Nightly Builds
**What:** Use `SHALLOW_CLONE=false` for nightly builds to enable `git describe`.
**When to use:** Nightly build track only.

**Rationale:** The existing build system uses `SHALLOW_CLONE=true` by default, which creates `--depth 1` clones. This breaks `git describe` because no tags are reachable from HEAD. For nightly builds:
- Set `SHALLOW_CLONE=false` as an environment variable in the CI workflow
- This makes `git_clone_update()` do full clones
- Adds ~2-5 minutes total clone time across all repos (acceptable for nightly)
- Enables `git describe --tags --abbrev=7` as a fallback version source

### Pattern 5: CI Workflow Trigger Strategy
**What:** Daily cron schedule + manual dispatch for nightly builds.
**When to use:** The nightly build workflow.

```yaml
on:
  schedule:
    - cron: '30 4 * * *'  # 4:30 AM UTC daily
  workflow_dispatch:
    inputs:
      build_track:
        description: 'Build track'
        type: choice
        options:
          - nightly
```

### Anti-Patterns to Avoid
- **Building from HEAD without version disambiguation:** Never use the raw `-dev` suffix in package versions -- it does not contain date or commit info and is not monotonically increasing.
- **Using `+` instead of `~` for snapshot versions:** `5.8.0+git20260306` sorts HIGHER than `5.8.0`, which means users would NOT auto-upgrade to the real release.
- **Relying solely on `git describe` with shallow clones:** `git describe` requires tag reachability from HEAD, which shallow clones break.
- **Building all components from HEAD simultaneously without compatibility testing:** Components may have cross-dependencies (e.g., podman depends on specific containers/common versions).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Version comparison | Custom version sorting logic | dpkg `~` (tilde) convention | dpkg handles tilde sorting natively; custom logic would be buggy |
| Version extraction from source | Manual regex per component | Structured `extract_dev_version()` function with per-component cases | Each upstream project stores version differently |
| APT suite management | Custom package index | reprepro with additional suite in `distributions` | reprepro handles signing, indices, multi-arch natively |
| Nightly scheduling | Custom timer/webhook | GitHub Actions `schedule` trigger | Built-in cron support, no external infrastructure |

**Key insight:** The existing build infrastructure already does 90% of what's needed. The `setup.sh` + `git_checkout()` flow already handles empty tags by checking out the latest tag. For nightly, the key change is to NOT check out a tag at all and instead build from the default branch HEAD.

## Common Pitfalls

### Pitfall 1: Shallow Clone + git describe = Failure
**What goes wrong:** `git describe --tags` fails with "fatal: No names found, cannot describe anything" on `--depth 1` clones.
**Why it happens:** Shallow clones don't fetch the full commit graph, so tags are unreachable from HEAD.
**How to avoid:** Set `SHALLOW_CLONE=false` for nightly builds. The version extraction function should also have a fallback that doesn't depend on `git describe`.
**Warning signs:** Build failures during the version extraction step.

### Pitfall 2: Tilde vs Plus Version Sorting
**What goes wrong:** Using `5.8.0+git20260306` instead of `5.8.0~git20260306` causes users to NOT receive the real 5.8.0 release as an upgrade.
**Why it happens:** In dpkg version comparison, `+` sorts higher than nothing, while `~` sorts lower. So `5.8.0+git...` > `5.8.0` but `5.8.0~git...` < `5.8.0`.
**How to avoid:** Always use `~` between the base version and the `git` snapshot identifier.
**Warning signs:** `apt upgrade` does not offer the tagged release as an update to nightly users.

### Pitfall 3: Cross-Component Incompatibility from HEAD
**What goes wrong:** Building all components from their respective main branches simultaneously may produce incompatible binaries (e.g., podman v6-dev expecting a containers/common API that container-libs hasn't implemented yet).
**Why it happens:** Upstream development branches don't guarantee cross-repo API stability at every commit.
**How to avoid:** Accept this as a known risk of the nightly track. Document it for users. If a component fails to build, the entire nightly build should fail loudly rather than ship partial updates. Consider adding a smoke test (`podman info`) after install.
**Warning signs:** Runtime errors like "undefined method" or "incompatible version" when running podman commands.

### Pitfall 4: crun's Autotools Version Detection
**What goes wrong:** crun uses `build-aux/git-version-gen` which requires git history and a `.tarball-version` file. On shallow clones, this produces garbage versions.
**Why it happens:** `git-version-gen` runs `git describe` internally and falls back to `.tarball-version` which may not exist on a fresh clone.
**How to avoid:** Full clone for crun, or create a `.tarball-version` file before running `autogen.sh` with the computed version.
**Warning signs:** crun package has version `0.0.0` or `UNKNOWN`.

### Pitfall 5: reprepro Duplicate Version Rejection
**What goes wrong:** If a nightly build produces a package with the exact same version as one already in the repository, reprepro refuses to include it.
**Why it happens:** The date component in `~gitYYYYMMDD` only changes daily. If two nightly builds run on the same day with the same commit, they produce identical versions.
**How to avoid:** Use `reprepro remove` before `reprepro includedeb`, or use `--ignore=alreadyincluded`. Alternatively, ensure only one nightly build runs per day.
**Warning signs:** `reprepro includedeb` exits with error about duplicate version.

### Pitfall 6: pasta/passt Has No Tags
**What goes wrong:** pasta/passt is hosted on `git://passt.top/passt` (not GitHub), has no semver tags, and the existing build script already uses date-based versioning.
**Why it happens:** The upstream project uses a rolling release model.
**How to avoid:** Keep the existing date-based version for pasta nightly builds. The pasta build script already pulls from HEAD and uses `$(date +"%Y%m%d")` as the version -- this is already "nightly" behavior.
**Warning signs:** None -- pasta already works this way.

## Code Examples

### Example 1: Modified git_checkout for Nightly Mode
```bash
# Source: project-specific adaptation
git_checkout_nightly() {
    # For nightly builds: stay on the default branch HEAD
    # Don't check out any tag -- build from latest commit
    local default_branch
    default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@') || default_branch="main"

    git checkout "${default_branch}"
    git pull origin "${default_branch}"

    # Set GIT_CHECKED_OUT_TAG to the nightly version string
    local short_sha=$(git rev-parse --short=7 HEAD)
    local datestamp=$(date +%Y%m%d)
    export GIT_CHECKED_OUT_TAG="nightly-${datestamp}-${short_sha}"
}
```

### Example 2: versions-nightly.env
```bash
#!/bin/bash

# Nightly build track - build from latest upstream commits
# Source this file before setup.sh for nightly builds
#
# When sourced, all TAG variables remain empty (defaults from config.sh).
# The NIGHTLY_BUILD flag signals the build system to:
#   1. Use full clones (SHALLOW_CLONE=false) for git describe support
#   2. Stay on HEAD instead of checking out a tag
#   3. Use dev version extraction instead of tag-based versioning

export NIGHTLY_BUILD="true"
export SHALLOW_CLONE="false"
```

### Example 3: Nightly-Aware git_checkout Modification
```bash
# Modification to existing git_checkout() in functions.sh
git_checkout() {
    local ltag=${1-""}

    if [[ "${NIGHTLY_BUILD:-false}" == "true" && -z "${ltag}" ]]; then
        # Nightly mode: stay on default branch HEAD
        local default_branch
        default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
            | sed 's@^refs/remotes/origin/@@') || default_branch="main"
        git checkout "${default_branch}"
        git pull origin "${default_branch}" || true
        export GIT_CHECKED_OUT_TAG="nightly"
    elif [[ -n "${ltag}" ]]; then
        # Tag specified - existing behavior
        if ! git rev-parse "${ltag}" &>/dev/null; then
            git fetch --depth 1 origin tag "${ltag}"
        fi
        git checkout "${ltag}"
        export GIT_CHECKED_OUT_TAG="${ltag}"
    else
        # No tag specified, not nightly - find latest tag (existing behavior)
        if [[ "${SHALLOW_CLONE:-true}" == "true" ]]; then
            git fetch --tags
        fi
        git checkout $(get_latest_tag)
        export GIT_CHECKED_OUT_TAG=$(get_latest_tag)
    fi
}
```

### Example 4: Nightly-Aware extract_version in package_all.sh
```bash
# Modified extract_version for nightly builds
extract_version_nightly() {
    local component="$1"
    local repo_path="${BUILD_ROOT}/${component}"

    # Adjust repo path for components with different build dir names
    case "$component" in
        container-configs) repo_path="${BUILD_ROOT}/container-libs" ;;
        pasta) repo_path="${BUILD_ROOT}/passt" ;;
    esac

    local short_sha=$(git -C "$repo_path" rev-parse --short=7 HEAD 2>/dev/null || echo "unknown")
    local datestamp=$(date +%Y%m%d)
    local base_version=""

    case "$component" in
        podman)
            base_version=$(grep 'RawVersion' "$repo_path/version/rawversion/version.go" \
                | sed 's/.*"\(.*\)".*/\1/' | sed 's/-dev//')
            ;;
        buildah)
            base_version=$(grep '^[[:space:]]*Version[[:space:]]*=' "$repo_path/define/types.go" \
                | head -1 | sed 's/.*"\(.*\)".*/\1/' | sed 's/-dev//')
            ;;
        skopeo)
            base_version=$(grep 'Version[[:space:]]*=' "$repo_path/version/version.go" \
                | head -1 | sed 's/.*"\(.*\)".*/\1/' | sed 's/-dev//')
            ;;
        netavark|aardvark-dns)
            base_version=$(grep '^version[[:space:]]*=' "$repo_path/Cargo.toml" \
                | head -1 | sed 's/.*"\(.*\)".*/\1/' | sed 's/-dev//')
            ;;
        conmon)
            base_version=$(cat "$repo_path/VERSION" | tr -d '[:space:]')
            ;;
        fuse-overlayfs)
            base_version=$(grep 'AC_INIT' "$repo_path/configure.ac" \
                | head -2 | sed 's/.*\[\([^]]*\)\].*/\1/' | head -1 | sed 's/-dev//')
            ;;
        catatonit)
            base_version=$(grep 'AC_INIT' "$repo_path/configure.ac" \
                | head -2 | sed 's/.*\[\([^]]*\)\].*/\1/' | head -1 | sed 's/+dev//')
            ;;
        crun)
            # Use git describe if available, else parse configure.ac
            base_version=$(git -C "$repo_path" describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")
            ;;
        toolbox)
            base_version=$(grep "version:" "$repo_path/meson.build" \
                | head -1 | sed "s/.*'\(.*\)'.*/\1/")
            # Toolbox versions are short (0.3); normalize to 3 parts
            if [[ "$base_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
                base_version="${base_version}.0"
            fi
            ;;
        container-configs)
            base_version=$(git -C "$repo_path" tag --list 'common/*' --sort=-version:refname \
                | head -1 | sed 's|common/v||')
            [[ -z "$base_version" ]] && base_version="0.0.0"
            ;;
        pasta)
            # Already date-based
            echo "${datestamp}"
            return
            ;;
    esac

    [[ -z "$base_version" ]] && base_version="0.0.0"
    echo "${base_version}~git${datestamp}.${short_sha}"
}
```

### Example 5: CI Workflow Addition for Nightly
```yaml
# Additional workflow or modification to build-packages.yml
name: Nightly Build

on:
  schedule:
    - cron: '30 4 * * *'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  build-amd64:
    runs-on: ubuntu-24.04
    timeout-minutes: 180
    steps:
      - uses: actions/checkout@v4

      - name: Update apt cache
        run: sudo apt-get update

      - name: Build all components from HEAD
        run: |
          DESTDIR="${{ runner.temp }}/podman-staging"
          mkdir -p "$DESTDIR" "$HOME/.cache/go-build" "$HOME/.cache/go-mod"
          ENV_ARGS="DEBIAN_FRONTEND=noninteractive DESTDIR=$DESTDIR"
          ENV_ARGS="$ENV_ARGS GOCACHE=$HOME/.cache/go-build GOMODCACHE=$HOME/.cache/go-mod"
          ENV_ARGS="$ENV_ARGS NIGHTLY_BUILD=true SHALLOW_CLONE=false"
          sudo env $ENV_ARGS ./setup.sh
          sudo chown -R "$(id -u):$(id -g)" "$HOME/.cache/go-build" "$HOME/.cache/go-mod"
        timeout-minutes: 150
      # ... (packaging and publish steps similar to existing workflow)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single build track | Stable + Edge tracks | Phase 16 (2026-03) | Users choose between pinned or latest-tag builds |
| Shallow clone always | Configurable via `SHALLOW_CLONE` env | Phase 8 (2026-03) | Enables full clone for nightly |
| Manual version pinning | Auto-detect from upstream tags | Phase 16 edge track | Edge builds find latest tags automatically |
| Tag-based versioning only | Source-file version extraction (Phase 18) | Planned | Enables versioning from commits without tags |

**Ecosystem precedents for snapshot packaging:**
- **Fedora:** Uses `X.Y.Z-0.N.YYYYMMDD.gitSHORTHASH` in Release field
- **Debian:** Uses `X.Y.Z~gitYYYYMMDD.SHORTHASH-1` in upstream version
- **Arch Linux (AUR):** Uses `X.Y.Z.rN.gSHORTHASH` via `git describe --long`
- **Ubuntu PPAs:** Commonly use `X.Y.Z+gitYYYYMMDD` (but `+` sorts higher -- not ideal for our use case)

## Open Questions

1. **Should nightly be a separate workflow file or a third option in the existing workflow?**
   - What we know: The existing `build-packages.yml` has a `build_track` choice input with `stable`/`edge`. Adding `nightly` as a third option is simple.
   - What's unclear: Whether the nightly build's longer clone time (full vs shallow) would impact stable/edge builds if they share the workflow.
   - Recommendation: Start with a third option in the existing workflow. If build times diverge significantly, split later.

2. **Should nightly builds run even when no commits have changed?**
   - What we know: GitHub Actions cron triggers regardless of upstream changes. Building identical commits wastes CI minutes.
   - What's unclear: How to efficiently detect "no new commits across any upstream repo" before triggering a full build.
   - Recommendation: Build daily regardless. The cost (CI minutes) is low, and checking 14 upstream repos for changes adds complexity. If CI costs become a concern, add a pre-check job.

3. **Should the nightly track be named `nightly` or `git`?**
   - What we know: `nightly` is widely understood (Firefox Nightly, Rust Nightly). `git` is used by Arch AUR convention.
   - Recommendation: Use `nightly` -- it communicates the daily cadence and instability expectations.

4. **How to handle nightly build failures for individual components?**
   - What we know: HEAD of any upstream repo may be temporarily broken. If one component fails, the entire build fails.
   - What's unclear: Whether to allow partial nightly publishes (skip broken component, ship rest).
   - Recommendation: Fail the entire build. Nightly users expect all components to work together. A partial suite with mismatched versions is worse than no update.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bash + dpkg (shell-based validation) |
| Config file | None -- validation is inline in scripts |
| Quick run command | `dpkg --compare-versions "6.0.0~git20260306.abc1234~podman1" lt "6.0.0~podman1" && echo PASS` |
| Full suite command | `./scripts/package_all.sh` (validates all version extraction) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EDGE-01 | Nightly versions sort below tagged releases | unit | `dpkg --compare-versions "$NIGHTLY_VER" lt "$RELEASE_VER"` | No -- Wave 0 |
| EDGE-02 | Dev version extracted from each component source | unit | `extract_dev_version "podman" "$BUILD_ROOT/podman"` returns non-empty | No -- Wave 0 |
| EDGE-03 | Nightly build produces valid .deb packages | integration | `sudo dpkg -i output/*.deb` exits 0 | No -- CI validates |
| EDGE-04 | reprepro accepts nightly packages into nightly suite | integration | `reprepro includedeb nightly output/*.deb` exits 0 | No -- CI validates |
| EDGE-05 | Nightly workflow triggers on cron schedule | manual-only | Verify via GitHub Actions run history | N/A |

### Sampling Rate
- **Per task commit:** `dpkg --compare-versions` spot checks on generated version strings
- **Per wave merge:** Full `package_all.sh` run in CI
- **Phase gate:** Successful nightly workflow run producing packages in all three suites

### Wave 0 Gaps
- [ ] Version comparison test script -- validates all component nightly versions sort correctly
- [ ] `nightly` suite added to `packaging/repo/conf/distributions`
- [ ] `versions-nightly.env` file created with `NIGHTLY_BUILD=true` and `SHALLOW_CLONE=false`

## Sources

### Primary (HIGH confidence)
- **Project source code:** `config.sh`, `functions.sh`, `setup.sh`, `package_all.sh`, `build_*.sh` -- examined directly
- **Upstream version files:** Fetched from GitHub raw content for podman, buildah, skopeo, netavark, aardvark-dns, conmon, fuse-overlayfs, catatonit, toolbox
  - podman `version/rawversion/version.go`: `6.0.0-dev`
  - buildah `define/types.go`: `1.43.0-dev`
  - skopeo `version/version.go`: `1.22.0-dev`
  - netavark `Cargo.toml`: `2.0.0-dev`
  - aardvark-dns `Cargo.toml`: `2.0.0-dev`
  - conmon `VERSION`: `2.2.1`
  - fuse-overlayfs `configure.ac`: `1.17-dev`
  - catatonit `configure.ac`: `0.2.1+dev`
  - toolbox `meson.build`: `0.3`
- **CI workflow:** `.github/workflows/build-packages.yml` -- examined directly
- [Debian Wiki - Versioning](https://wiki.debian.org/Versioning)
- [Debian deb-version manpage](https://man7.org/linux/man-pages/man7/deb-version.7.html)

### Secondary (MEDIUM confidence)
- [Fedora Packaging Guidelines - Versioning](https://docs.pagure.org/packaging-guidelines/Packaging:Versioning.html) -- snapshot naming conventions
- [Arch Wiki - VCS Package Guidelines](https://wiki.archlinux.org/title/Arch_package_guidelines) -- pkgver() patterns
- [Debian devel mailing list - version format for git snapshot](https://lists.debian.org/debian-devel/2015/09/msg00287.html) -- community conventions
- [git-buildpackage snapshots documentation](https://honk.sigxcpu.org/projects/git-buildpackage/manual-html/gbp.snapshots.html)
- [GitHub Actions - Workflow syntax (schedule)](https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions)

### Tertiary (LOW confidence)
- None -- all findings verified with multiple sources

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- using existing project tools, no new dependencies
- Architecture: HIGH -- extending proven patterns (additional suite, version extraction), well-documented Debian conventions
- Pitfalls: HIGH -- verified with dpkg documentation and upstream source code examination
- Version extraction: MEDIUM -- dev version locations verified for current HEAD but may change if upstream restructures

**Research date:** 2026-03-06
**Valid until:** 2026-04-06 (30 days -- stable domain, upstream version file locations unlikely to change)
