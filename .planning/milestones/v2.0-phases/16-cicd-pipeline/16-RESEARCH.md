# Phase 16: CI/CD Pipeline - Research

**Researched:** 2026-03-05
**Domain:** GitHub Actions workflow design, multi-architecture native builds, APT repository publishing via GitHub Pages, artifact management
**Confidence:** HIGH

## Summary

This phase creates a GitHub Actions workflow that compiles all Podman components from source on both amd64 and arm64 native runners, packages them as .deb files using the existing `scripts/package_all.sh`, and publishes the resulting APT repository to GitHub Pages using the existing `scripts/repo_manage.sh`. The workflow is triggered manually via `workflow_dispatch` with a `build_track` choice parameter selecting between `stable` (user-pinned versions in config.sh) and `edge` (latest upstream tags fetched at build time).

The architecture requires a three-stage workflow: (1) parallel build jobs on native runners (ubuntu-24.04 for amd64, ubuntu-24.04-arm for arm64), (2) a publish job that merges both architectures' .deb artifacts into a single reprepro repository, and (3) deployment to GitHub Pages. The publish job uses `needs: [build-amd64, build-arm64]` which inherently provides atomic publishing -- if either build fails, the publish job never runs and the existing live repository remains intact.

A critical architectural decision is whether to use `morph027/apt-repo-action` or the project's own `scripts/repo_manage.sh` for the publish step. Research reveals that `morph027/apt-repo-action` supports only a single suite per invocation and generates its own `conf/distributions` from inputs, bypassing the project's committed config. Since the workflow only builds one suite per trigger (stable OR edge), this is workable. However, the action's `import-from-repo-url` feature is essential for preserving packages from the OTHER suite when publishing. The project's `repo_manage.sh` does NOT handle importing existing packages from a live repository -- it creates a fresh repo each time. Therefore, `morph027/apt-repo-action` with `import-from-repo-url` is the recommended approach for the publish step, as it handles the critical problem of cross-suite package preservation.

**Primary recommendation:** Use a three-job workflow (build-amd64, build-arm64, publish) with `morph027/apt-repo-action@v3` for the publish step. Use `import-from-repo-url` to preserve packages from the suite NOT being built (e.g., when building `stable`, import existing `edge` packages and vice versa). For the `edge` build track, add a version resolution step that fetches latest upstream tags before build.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CICD-01 | GitHub Actions build workflow compiles and packages all components for both architectures | Three-job workflow: build-amd64 (ubuntu-24.04) and build-arm64 (ubuntu-24.04-arm) run setup.sh with DESTDIR, then package_all.sh; publish job merges both architectures via reprepro |
| CICD-02 | Builds run on native runners: ubuntu-24.04 for amd64, ubuntu-24.04-arm for arm64 | GitHub ARM64 runners are GA for public repos (free); use `runs-on: ubuntu-24.04` and `runs-on: ubuntu-24.04-arm` labels directly |
| CICD-03 | Builds can be triggered manually via workflow_dispatch | Use `on: workflow_dispatch` with `inputs.build_track` as a `type: choice` parameter with options `stable` and `edge` |
| CICD-04 | Two build tracks: stable (user-pinned versions) and edge (latest upstream tags) | Stable: use version tags from config.sh as-is; Edge: add a step that resolves latest tags from GitHub API (leveraging existing `get_latest_tag` function pattern) and exports them as environment variables before build |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| GitHub Actions | N/A | CI/CD platform | Project is hosted on GitHub; native ARM64 runners available free for public repos |
| actions/checkout | v4 | Clone repository | Standard first step for all GitHub Actions workflows |
| actions/upload-artifact | v4 | Upload .deb artifacts for debugging | Required by CICD success criteria #4 (retain artifacts) |
| actions/download-artifact | v4 | Download .deb artifacts in publish job | Required to merge both arch artifacts before reprepro |
| morph027/apt-repo-action | v3 | Create signed APT repository via reprepro | Handles import-from-repo-url for cross-suite preservation; generates proper repo structure |
| actions/configure-pages | v4 | Configure GitHub Pages deployment | Required before upload-pages-artifact |
| actions/upload-pages-artifact | v3 | Package repository for Pages deployment | Required by deploy-pages |
| actions/deploy-pages | v4 | Deploy to GitHub Pages | Standard GitHub Pages deployment action |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| actions/setup-go | v5 | Install Go with caching | Each build job needs Go; built-in module caching reduces repeated downloads |
| actions/cache | v4 | Cache Go build artifacts, Rust toolchain, ccache | Optional but significantly speeds up repeat builds |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| morph027/apt-repo-action | scripts/repo_manage.sh | repo_manage.sh does NOT import existing packages from the live repo; would lose the other suite's packages on each deploy. morph027/apt-repo-action handles this with import-from-repo-url |
| morph027/apt-repo-action | Custom reprepro + apt-mirror script | More control but duplicates what the action already handles; increases maintenance burden |
| actions/deploy-pages | peaceiris/actions-gh-pages | Third-party; official actions preferred; deploy-pages is the GitHub-supported approach |
| Native ARM64 runners | QEMU emulation | QEMU is 10-30x slower and unreliable for full compilation; explicitly out of scope per REQUIREMENTS.md |

## Architecture Patterns

### Recommended Workflow Structure
```
.github/
  workflows/
    build-packages.yml    # Main CI/CD workflow (workflow_dispatch)
```

### Workflow Job Graph
```
workflow_dispatch (build_track: stable|edge)
  |
  +-- build-amd64 (ubuntu-24.04)
  |     1. Checkout repo
  |     2. [edge only] Resolve latest upstream tags
  |     3. Install dependencies (setup.sh pipeline)
  |     4. Build all components with DESTDIR
  |     5. Package with nFPM (package_all.sh)
  |     6. Upload .deb artifacts
  |
  +-- build-arm64 (ubuntu-24.04-arm)  [parallel with amd64]
  |     (same steps as build-amd64)
  |
  +-- publish (ubuntu-24.04) [needs: build-amd64, build-arm64]
        1. Download all .deb artifacts from both build jobs
        2. Import GPG key from secrets
        3. Create APT repo via morph027/apt-repo-action
           - import-from-repo-url preserves other suite
        4. Upload Pages artifact
        5. Deploy to GitHub Pages
```

### Pattern 1: Three-Job Build-Publish-Deploy
**What:** Separate build jobs per architecture with a dependent publish job
**When to use:** Always -- this is the core workflow pattern
**Why:** The `needs` keyword ensures publish only runs when ALL builds succeed (atomic publishing). Each arch runs on its native runner, avoiding QEMU overhead.

```yaml
jobs:
  build-amd64:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - name: Build and package
        run: |
          export DEBIAN_FRONTEND=noninteractive
          export DESTDIR=/tmp/podman-staging
          mkdir -p "$DESTDIR"
          sudo ./setup.sh
          ./scripts/package_all.sh
      - uses: actions/upload-artifact@v4
        with:
          name: debs-amd64
          path: output/*.deb

  build-arm64:
    runs-on: ubuntu-24.04-arm
    steps:
      # Same as build-amd64

  publish:
    needs: [build-amd64, build-arm64]
    runs-on: ubuntu-24.04
    # Only runs if BOTH builds succeed
```

### Pattern 2: workflow_dispatch with Build Track Choice
**What:** Manual trigger with a dropdown choosing stable vs edge
**When to use:** Always -- this is the trigger mechanism

```yaml
on:
  workflow_dispatch:
    inputs:
      build_track:
        description: 'Build track'
        required: true
        type: choice
        options:
          - stable
          - edge
        default: stable
```

### Pattern 3: Edge Version Resolution
**What:** Fetch latest upstream tags via GitHub API before building
**When to use:** When `build_track == 'edge'`

```bash
# For each component, fetch latest tag from upstream GitHub repo
resolve_latest_tag() {
  local repo="$1"
  local filter="${2:-}"
  curl -sL "https://api.github.com/repos/${repo}/releases/latest" \
    | grep '"tag_name"' | sed 's/.*"\(.*\)".*/\1/'
}

# Export as environment variables that config.sh will pick up
export PODMAN_TAG=$(resolve_latest_tag "containers/podman")
export CRUN_TAG=$(resolve_latest_tag "containers/crun")
export CONMON_TAG=$(resolve_latest_tag "containers/conmon")
# ... etc
```

This works because `config.sh` already uses `${PODMAN_TAG:-}` pattern -- setting the env var before sourcing config.sh will override the default empty value.

### Pattern 4: Cross-Suite Preservation with import-from-repo-url
**What:** Preserve packages from the suite NOT being built
**When to use:** Always in the publish step

```yaml
- uses: morph027/apt-repo-action@v3
  with:
    repo-name: podman-debian
    signing-key: ${{ secrets.GPG_PRIVATE_KEY }}
    codename: ${{ inputs.build_track }}
    suite: ${{ inputs.build_track }}
    architectures: amd64 arm64
    import-from-repo-url: |
      deb-amd64 https://slazarov.github.io/podman-debian/ ${{ inputs.build_track == 'stable' && 'edge' || 'stable' }} main
      deb-arm64 https://slazarov.github.io/podman-debian/ ${{ inputs.build_track == 'stable' && 'edge' || 'stable' }} main
    import-from-repo-failure-allow: true
```

**CRITICAL NOTE:** `import-from-repo-failure-allow: true` is required because on the very first deployment, there is no existing repository to import from -- the import would fail and block the entire workflow without this flag.

### Pattern 5: Stable Version Pinning
**What:** Use user-defined version tags from config.sh for stable builds
**When to use:** When `build_track == 'stable'`

For stable builds, the version tags must be provided. Two approaches:

**Option A (recommended): Versions file checked into repo**
Create a `versions-stable.env` file that exports specific tags:
```bash
# versions-stable.env -- pinned versions for stable suite
export PODMAN_TAG="v5.5.2"
export CRUN_TAG="1.25.1"
export CONMON_TAG="v2.1.13"
# ... etc
```
Source this file before running setup.sh. This keeps versions explicit and auditable.

**Option B: GitHub Actions workflow_dispatch inputs for each version**
This would require 12+ input fields, making the dispatch UI unwieldy. Not recommended.

### Anti-Patterns to Avoid
- **Building both suites in one workflow run:** Each dispatch builds ONE suite. This keeps the workflow simple and avoids the problem of needing all 24 .deb files (12 components x 2 arches x 2 suites).
- **Using QEMU for ARM64:** Explicitly out of scope. Native `ubuntu-24.04-arm` runners are available free for public repos.
- **Deploying without import-from-repo-url:** This would wipe out all packages from the other suite on every deployment.
- **Hardcoding version tags in the workflow YAML:** Use either environment files (stable) or dynamic resolution (edge) to keep the workflow generic.
- **Using fail-fast: false in the matrix:** While this project does NOT use a matrix (separate jobs instead), if a matrix approach were used, fail-fast should remain true so a failing arch cancels the other to save runner minutes.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-suite package preservation | Custom apt-mirror/wget download script | morph027/apt-repo-action import-from-repo-url | Handles architecture-specific downloads, regex filtering, failure tolerance; tested in production |
| GitHub Pages deployment | Custom gh-pages branch management | actions/upload-pages-artifact + actions/deploy-pages | Official GitHub approach; handles artifact compression, OIDC tokens, deployment environments |
| Go toolchain setup | Manual wget + tar + PATH manipulation | actions/setup-go@v5 | Built-in module caching, version management, PATH setup |
| Artifact passing between jobs | Git commits or external storage | actions/upload-artifact + download-artifact v4 | Purpose-built for cross-job data passing; automatic cleanup |

**Key insight:** The workflow should be a thin orchestrator that calls the project's existing scripts (`setup.sh`, `package_all.sh`) and uses purpose-built GitHub Actions for infrastructure concerns (artifacts, pages, repo creation). The build logic already exists in the shell scripts.

## Common Pitfalls

### Pitfall 1: GitHub Pages Not Enabled
**What goes wrong:** Workflow succeeds but GitHub Pages URL returns 404
**Why it happens:** GitHub Pages must be manually enabled in repository settings with "GitHub Actions" as the source before the first deployment
**How to avoid:** Include a setup checklist in the plan: Settings > Pages > Source: GitHub Actions. This is a one-time manual step.
**Warning signs:** deploy-pages step succeeds but URL is not accessible

### Pitfall 2: Suite Packages Wiped on Deploy
**What goes wrong:** After deploying stable packages, edge suite packages disappear (or vice versa)
**Why it happens:** GitHub Pages is a complete replacement deploy -- the new artifact replaces ALL content. Without importing existing packages from the other suite, they are lost.
**How to avoid:** Use `import-from-repo-url` to download packages from the live repo's other suite before building the new repo. Set `import-from-repo-failure-allow: true` for the first run.
**Warning signs:** After deploying, `apt update` for the other suite shows 0 packages

### Pitfall 3: First Deploy Import Failure
**What goes wrong:** First workflow run fails because import-from-repo-url tries to download from a non-existent GitHub Pages URL
**Why it happens:** On the very first deployment, there is no existing repository to import from
**How to avoid:** Set `import-from-repo-failure-allow: true` in the morph027/apt-repo-action configuration
**Warning signs:** Workflow fails with apt-mirror download error on first run

### Pitfall 4: Artifact Name Collision in v4
**What goes wrong:** Upload fails with "artifact already exists" error
**Why it happens:** actions/upload-artifact v4 requires unique artifact names within a workflow run -- unlike v3, you cannot upload to the same name twice
**How to avoid:** Use architecture-specific artifact names: `debs-amd64` and `debs-arm64`. Download both with `merge-multiple: true` or download individually.
**Warning signs:** Second arch upload fails even though first succeeded

### Pitfall 5: Edge Version Resolution Rate Limiting
**What goes wrong:** GitHub API calls to resolve latest tags fail with 403/429
**Why it happens:** Unauthenticated GitHub API requests are limited to 60/hour; resolving 12+ component versions may hit this
**How to avoid:** Use `GITHUB_TOKEN` for authenticated API requests (5000/hour). Pass it as `Authorization: Bearer ${{ secrets.GITHUB_TOKEN }}` header in curl calls.
**Warning signs:** Intermittent failures in the version resolution step

### Pitfall 6: Build Times Exceeding Runner Limits
**What goes wrong:** Workflow times out before completing all component builds
**Why it happens:** Building 12 components from source (including Go, Rust, C components) can take 45-90 minutes; GitHub Actions default timeout is 360 minutes but large builds can still hit limits
**How to avoid:** Use Go build cache (actions/cache for GOCACHE and GOMODCACHE), consider enabling ccache and sccache. Set explicit `timeout-minutes: 180` on build jobs.
**Warning signs:** Builds that take progressively longer or time out inconsistently

### Pitfall 7: morph027/apt-repo-action Single-Suite Limitation
**What goes wrong:** Action only creates one suite in conf/distributions
**Why it happens:** The action generates its own conf/distributions from inputs with a single codename/suite stanza
**How to avoid:** This is fine for this workflow because only one suite is built per dispatch. The other suite's packages are imported via import-from-repo-url and are placed into the correct suite by the action's import mechanism.
**Warning signs:** N/A -- understood limitation, workflow designed around it

### Pitfall 8: morph027/apt-repo-action and Two-Suite Import
**What goes wrong:** Importing packages from the "other" suite via import-from-repo-url may not correctly place them into a separate suite because the action only defines ONE codename
**Why it happens:** The action runs `reprepro includedeb` with a single codename. Imported packages from the other suite get added to the CURRENT suite, not their original one.
**How to avoid:** This is the critical research flag from STATE.md. There are two approaches:
  1. **Use the project's repo_manage.sh instead of the action:** Run repo_manage.sh twice -- once for the current suite with new packages, and once to import the other suite. This requires downloading the existing repo's deb files via wget/curl first.
  2. **Run morph027/apt-repo-action twice:** Once for the current suite with new packages, and once for the other suite with imported packages from the live repo.
  3. **Use repo_manage.sh with a custom import step:** Download existing .deb files from the live repo before running repo_manage.sh, then run it for both suites.
**Recommendation:** Use approach 3 -- download existing .deb files from the live repo for the other suite, combine with newly built .debs for the current suite, and run the project's own `repo_manage.sh` for each suite. This gives full control and avoids the action's single-suite limitation.
**Warning signs:** After deploying stable, `apt update` for edge shows packages have different versions than expected

## Revised Architecture Recommendation

Based on Pitfall 8 analysis, the morph027/apt-repo-action has a fundamental limitation for two-suite repositories: it cannot maintain two separate suites in a single deployment. The recommended approach is:

### Custom Publish Job (using repo_manage.sh)

```yaml
publish:
  needs: [build-amd64, build-arm64]
  runs-on: ubuntu-24.04
  steps:
    # Download newly built .deb files
    - uses: actions/download-artifact@v4
      with:
        name: debs-amd64
        path: new-debs/
    - uses: actions/download-artifact@v4
      with:
        name: debs-arm64
        path: new-debs/

    # Download existing .deb files from the OTHER suite (from live repo)
    - name: Import existing packages from other suite
      run: |
        OTHER_SUITE=${{ inputs.build_track == 'stable' && 'edge' || 'stable' }}
        REPO_URL="https://slazarov.github.io/podman-debian"
        mkdir -p other-suite-debs/
        # Download Packages file to find existing .deb URLs
        curl -sfL "${REPO_URL}/dists/${OTHER_SUITE}/main/binary-amd64/Packages" \
          | grep "^Filename:" | awk '{print $2}' \
          | while read f; do curl -sfLO --output-dir other-suite-debs/ "${REPO_URL}/${f}"; done || true
        curl -sfL "${REPO_URL}/dists/${OTHER_SUITE}/main/binary-arm64/Packages" \
          | grep "^Filename:" | awk '{print $2}' \
          | while read f; do curl -sfLO --output-dir other-suite-debs/ "${REPO_URL}/${f}"; done || true

    # Build repo for CURRENT suite (with new packages)
    - name: Build current suite repository
      env:
        GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
      run: |
        sudo apt-get install -y reprepro
        ./scripts/repo_manage.sh "${{ inputs.build_track }}" new-debs/ repo-output/

    # Build repo for OTHER suite (with imported packages)
    - name: Build other suite repository
      env:
        GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
      run: |
        OTHER_SUITE=${{ inputs.build_track == 'stable' && 'edge' || 'stable' }}
        if [ -n "$(ls other-suite-debs/*.deb 2>/dev/null)" ]; then
          # Re-initialize repo_manage but append to existing repo-output
          # Need to re-add conf/ since repo_manage.sh cleans it up
          mkdir -p repo-output/conf
          cp packaging/repo/conf/distributions repo-output/conf/
          cp packaging/repo/conf/options repo-output/conf/
          for deb in other-suite-debs/*.deb; do
            reprepro -Vb repo-output includedeb "${OTHER_SUITE}" "$deb"
          done
          reprepro -b repo-output export
          rm -rf repo-output/db repo-output/conf
        fi

    # Deploy to GitHub Pages
    - uses: actions/upload-pages-artifact@v3
      with:
        path: repo-output/
    - uses: actions/deploy-pages@v4
```

**NOTE:** This is the recommended approach because repo_manage.sh already handles GPG import, reprepro invocation, and cleanup. The only addition needed is importing the other suite's existing packages.

However, this approach has a complication: `repo_manage.sh` currently cleans up `conf/` and `db/` after running. To add the other suite's packages, we need to either:
1. Modify `repo_manage.sh` to accept a `--no-cleanup` flag, OR
2. Reconstruct the conf/ directory before the second reprepro invocation

**The planner should decide** whether to modify `repo_manage.sh` or create a CI-specific wrapper script.

## Code Examples

### Complete Workflow Skeleton

```yaml
name: Build and Publish Packages

on:
  workflow_dispatch:
    inputs:
      build_track:
        description: 'Build track (stable = pinned versions, edge = latest upstream)'
        required: true
        type: choice
        options:
          - stable
          - edge
        default: stable

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  build-amd64:
    runs-on: ubuntu-24.04
    timeout-minutes: 180
    steps:
      - uses: actions/checkout@v4

      - name: Set version tags
        run: |
          if [ "${{ inputs.build_track }}" = "edge" ]; then
            # Resolve latest tags from upstream
            # ... (version resolution logic)
          else
            # Source pinned versions
            source versions-stable.env
          fi

      - name: Build all components
        run: |
          export DEBIAN_FRONTEND=noninteractive
          export DESTDIR=/tmp/podman-staging
          mkdir -p "$DESTDIR"
          sudo -E ./setup.sh

      - name: Package with nFPM
        run: |
          # Install nfpm
          go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.45.0
          export PATH="$HOME/go/bin:$PATH"
          ./scripts/package_all.sh

      - uses: actions/upload-artifact@v4
        with:
          name: debs-amd64
          path: output/*.deb
          retention-days: 30

  build-arm64:
    runs-on: ubuntu-24.04-arm
    timeout-minutes: 180
    # ... (same steps as build-amd64)

  publish:
    needs: [build-amd64, build-arm64]
    runs-on: ubuntu-24.04
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: debs-amd64
          path: new-debs/
      - uses: actions/download-artifact@v4
        with:
          name: debs-arm64
          path: new-debs/

      - name: Import other suite packages
        # ... (download from live repo)

      - name: Build repository
        env:
          GPG_PRIVATE_KEY: ${{ secrets.GPG_PRIVATE_KEY }}
        run: |
          sudo apt-get install -y reprepro
          ./scripts/repo_manage.sh "${{ inputs.build_track }}" new-debs/ repo-output/
          # Then add other suite...

      - uses: actions/configure-pages@v4
      - uses: actions/upload-pages-artifact@v3
        with:
          path: repo-output/
      - id: deployment
        uses: actions/deploy-pages@v4
```

### GitHub Pages Permissions Block

```yaml
permissions:
  contents: read
  pages: write
  id-token: write
```

Both `pages: write` and `id-token: write` are mandatory for GitHub Pages deployment via the official actions.

### workflow_dispatch Choice Input

```yaml
on:
  workflow_dispatch:
    inputs:
      build_track:
        description: 'Build track'
        required: true
        type: choice
        options:
          - stable
          - edge
        default: stable
```

Accessed in steps as `${{ inputs.build_track }}`.

### Artifact Upload/Download Pattern (v4)

```yaml
# Upload (in build job) -- unique name per architecture
- uses: actions/upload-artifact@v4
  with:
    name: debs-${{ runner.arch == 'ARM64' && 'arm64' || 'amd64' }}
    path: output/*.deb
    retention-days: 30

# Download (in publish job) -- get all artifacts to one directory
- uses: actions/download-artifact@v4
  with:
    pattern: debs-*
    path: all-debs/
    merge-multiple: true
```

Note: `merge-multiple: true` merges all matching artifacts into a single directory, which is ideal for combining amd64 and arm64 .deb files.

### Edge Version Resolution with GITHUB_TOKEN

```bash
resolve_latest_tag() {
  local repo="$1"
  curl -sL \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${repo}/releases/latest" \
    | grep '"tag_name"' | sed 's/.*"\([^"]*\)".*/\1/'
}

export PODMAN_TAG=$(resolve_latest_tag "containers/podman")
export BUILDAH_TAG=$(resolve_latest_tag "containers/buildah")
export CRUN_TAG=$(resolve_latest_tag "containers/crun")
export CONMON_TAG=$(resolve_latest_tag "containers/conmon")
export NETAVARK_TAG=$(resolve_latest_tag "containers/netavark")
export AARDVARK_DNS_TAG=$(resolve_latest_tag "containers/aardvark-dns")
export SKOPEO_TAG=$(resolve_latest_tag "containers/skopeo")
export FUSE_OVERLAYFS_TAG=$(resolve_latest_tag "containers/fuse-overlayfs")
export CATATONIT_TAG=$(resolve_latest_tag "openSUSE/catatonit")
export TOOLBOX_TAG=$(resolve_latest_tag "containers/toolbox")
export GOMD2MAN_TAG=$(resolve_latest_tag "cpuguy83/go-md2man")

# container-libs uses namespaced tags: common/vX.Y.Z
CONTAINER_LIBS_TAG=$(curl -sL \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/containers/common/tags" \
  | grep '"name"' | grep 'common/v' | head -1 | sed 's/.*"\(.*\)".*/\1/')
export CONTAINER_LIBS_TAG

# pasta uses date-based versioning -- handled by package_all.sh automatically
```

### Stable Version File Pattern

```bash
# versions-stable.env
export PODMAN_TAG="v5.5.2"
export BUILDAH_TAG="v1.40.1"
export CRUN_TAG="1.25.1"
export CONMON_TAG="v2.1.13"
export NETAVARK_TAG="v1.15.2"
export AARDVARK_DNS_TAG="v1.15.0"
export SKOPEO_TAG="v1.19.0"
export FUSE_OVERLAYFS_TAG="v1.14"
export CATATONIT_TAG="v0.2.1"
export TOOLBOX_TAG="0.1.2"
export GOMD2MAN_TAG="v2.0.7"
export CONTAINER_LIBS_TAG="common/v0.67.0"
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| QEMU-emulated ARM64 builds | Native `ubuntu-24.04-arm` runners | Jan 2025 (public preview), Aug 2025 (GA) | 10-30x faster ARM64 builds; free for public repos |
| `actions/upload-artifact@v3` (mutable) | `actions/upload-artifact@v4` (immutable) | Feb 2024 | Artifacts must have unique names; use architecture suffix |
| `gh-pages` branch for Pages | `actions/deploy-pages@v4` with OIDC | 2023-2024 | No need for deploy keys or PATs; uses id-token for auth |
| `peaceiris/actions-gh-pages` | `actions/upload-pages-artifact` + `actions/deploy-pages` | 2024 | Official GitHub Actions; better integration with Pages environments |

**Deprecated/outdated:**
- `actions/upload-artifact@v3`: Still functional but v4 is current with better performance
- QEMU for ARM64 CI: Unnecessary now that native runners are free for public repos
- Deploying to `gh-pages` branch: Still works but `actions/deploy-pages` is the modern approach

## Open Questions

1. **Stable Version Source**
   - What we know: Stable build track needs user-pinned versions; config.sh uses `${TAG:-}` pattern allowing env var override
   - What's unclear: Should versions be in a checked-in file (`versions-stable.env`), workflow dispatch inputs, or hard-coded in config.sh?
   - Recommendation: Use a checked-in `versions-stable.env` file. This is auditable, diffable, and doesn't require editing the workflow to change versions. The edge track resolves dynamically.

2. **Two-Suite Repository Integrity**
   - What we know: Each workflow dispatch builds ONE suite. The other suite's packages must be preserved in the deployed repository.
   - What's unclear: Exact mechanism for importing + re-signing existing packages from the live repo. Does reprepro need the same GPG key to re-sign imported packages?
   - Recommendation: Yes, reprepro re-signs all packages when running `export`. Since we use the same GPG key for both suites, this works. The planner should include explicit testing of cross-suite preservation.

3. **repo_manage.sh Modifications**
   - What we know: repo_manage.sh cleans up `conf/` and `db/` after running, making it impossible to add packages from a second suite
   - What's unclear: Should repo_manage.sh be modified to support multi-suite builds, or should a CI-specific wrapper handle this?
   - Recommendation: Create a CI wrapper script (e.g., `scripts/ci_publish.sh`) that handles: importing existing packages, running repo_manage.sh for the current suite (with a `--no-cleanup` modification), then adding the other suite's packages and cleaning up. This keeps repo_manage.sh simple for local use.

4. **Build Caching Strategy**
   - What we know: Full builds from source take 45-90 minutes. Go modules, Rust crates, and C compilation are cacheable.
   - What's unclear: Whether the complexity of caching (Go build cache, Rust sccache, ccache) is worth it for a workflow_dispatch-only trigger
   - Recommendation: Start without caching. Add it in a follow-up if build times are problematic. The workflow already uses setup.sh which supports cache configuration via env vars.

5. **nFPM Installation in CI**
   - What we know: nFPM is required for package_all.sh. It can be installed via `go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.45.0`
   - What's unclear: Whether Go is available on the PATH after setup.sh completes (Go is installed to /opt/go/VERSION/bin)
   - Recommendation: Install nFPM after setup.sh completes, using the Go binary that was just installed. Alternatively, download the pre-built binary from GitHub releases.

## Sources

### Primary (HIGH confidence)
- [GitHub Actions workflow syntax](https://docs.github.com/actions/using-workflows/workflow-syntax-for-github-actions) - workflow_dispatch, inputs, choice type, needs, permissions
- [GitHub ARM64 runners announcement](https://github.blog/changelog/2025-01-16-linux-arm64-hosted-runners-now-available-for-free-in-public-repositories-public-preview/) - ubuntu-24.04-arm label, free for public repos
- [GitHub ARM64 GA announcement](https://github.blog/changelog/2025-08-07-arm64-hosted-runners-for-public-repositories-are-now-generally-available/) - Confirms GA status
- [actions/upload-artifact v4](https://github.com/actions/upload-artifact) - Immutable artifacts, unique names, merge-multiple
- [actions/deploy-pages](https://github.com/actions/deploy-pages) - OIDC permissions, id-token:write requirement
- [actions/upload-pages-artifact](https://github.com/actions/upload-pages-artifact) - Pages artifact packaging

### Secondary (MEDIUM confidence)
- [morph027/apt-repo-action](https://github.com/morph027/apt-repo-action) - Action inputs, import-from-repo-url, single-suite limitation confirmed from action.yml and repo.sh analysis
- [Building and Publishing Apt Repos to GitHub Pages (linsomniac, 2025-03)](https://linsomniac.com/post/2025-03-18-building_and_publishing_apt_repos_to_github_pages/) - Complete workflow example for single-arch reprepro with GitHub Pages
- [GitHub Actions v4 artifacts migration](https://github.com/actions/upload-artifact/blob/main/docs/MIGRATION.md) - v3 to v4 migration guide, name uniqueness requirement

### Tertiary (LOW confidence)
- morph027/apt-repo-action import behavior with multiple suites -- needs validation during implementation (flagged in STATE.md)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - GitHub Actions, native ARM64 runners, and Pages deployment are all well-documented official features
- Architecture: HIGH - Three-job pattern (build-amd64, build-arm64, publish) is the standard approach verified from multiple sources
- workflow_dispatch: HIGH - Choice input type verified from official docs
- Cross-suite preservation: MEDIUM - The import mechanism works in principle but the exact interaction between morph027/apt-repo-action and multi-suite repos needs implementation-time validation. Custom approach with repo_manage.sh is more predictable.
- Pitfalls: HIGH - Each pitfall documented from official docs or known GitHub Actions behavior

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (GitHub Actions features change slowly; runner labels are stable)
