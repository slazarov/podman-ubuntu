# Phase 4: User Experience - Context

**Gathered:** 2026-03-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Provide visibility into build progress and confidence in script operations through progress feedback, build logging, and a working uninstall capability. This phase improves the user-facing experience of installation — it does not add new components or change what gets installed.

</domain>

<decisions>
## Implementation Decisions

### Progress Granularity
- Step-level progress within each script (not just script-level "Starting/Completed")
- Show all significant operations: Clone, Checkout, Log version, Pre-build fixes, Build, Install, Post-install config
- Hierarchical format with indented sub-steps under script headers for visual hierarchy
- Show per-step elapsed time AND total script time when each script completes

### Build Output Logging
- Capture full build output (stdout/stderr) to log files
- Per-component log files: `logs/build_podman.log`, `logs/build_crun.log`, etc.
- Suppress verbose build output on console — show only progress messages
- Store logs in existing `logs/` directory (alongside version logs)

### Uninstall Robustness
- Skip gracefully when components weren't installed or directories don't exist (no errors)
- Show detailed summary at end: what was removed, what was skipped, any manual cleanup needed
- No confirmation prompt before uninstalling (runs immediately)
- Use strict mode (`set -euo pipefail`) with error handler like other scripts

### Progress Presentation Style
- Simple text markers (e.g., `>>> Cloning repository...`, `>>> Done: Cloning repository (45s)`)
- No progress bars or spinner animations

### Claude's Discretion
- Exact wording of progress messages
- Timestamp format for elapsed time
- Summary output format for uninstall

</decisions>

<specifics>
## Specific Ideas

- Hierarchical output example:
  ```
  ========================================
  >>> Starting: build_podman.sh
  ========================================
    Cloning repository... Done (12s)
    Checking out tag... Done (2s)
    Logging version... Done
    Applying pre-build fixes... Done (1s)
    Building... Done (3m 22s)
    Installing... Done (8s)
    Post-install configuration... Done
  >>> Completed: build_podman.sh in 3m 45s
  ========================================
  ```

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `run_script()` wrapper in setup.sh: Already shows "Starting/Completed" — extend for timing and tracking
- `log_component()` in functions.sh: Logs version info — can be extended for build output logging
- `error_handler()` in functions.sh: Already exists — uninstall.sh should use this pattern
- `remove_if_user_installed()` in functions.sh: Checks dpkg before removing — useful for uninstall

### Established Patterns
- All scripts use `set -euo pipefail` and `trap 'error_handler ...' ERR`
- Scripts use `source` to load config.sh and functions.sh
- Build scripts follow consistent structure: cd to BUILD_ROOT, git_clone_update, git_checkout, build, install

### Integration Points
- `setup.sh`: Main entry point — run_script() wrapper is where progress timing should be added
- `functions.sh`: Add new `log_build_output()` function for capturing build output to log files
- Individual build scripts (`scripts/build_*.sh`): Add step-level progress messages within each script
- `uninstall.sh`: Needs error handling, skip-on-missing logic, and summary output

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-user-experience*
*Context gathered: 2026-03-02*
