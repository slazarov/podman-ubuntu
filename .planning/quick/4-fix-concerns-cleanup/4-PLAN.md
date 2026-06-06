---
phase: 4-user-experience
plan: 4
type: execute
wave: 1
depends_on: []
files_modified: [setup.sh, uninstall.sh, functions.sh]
autonomous: true
requirements: []
---

<objective>
Fix three codebase concerns identified in CONCERNS.md

Purpose: Resolve technical debt and improve script reliability
Output: Cleaned scripts with redundant operations removed and proper cleanup
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/codebase/CONCERNS.md
</context>

<tasks>

<task type="auto">
  <name>Fix redundant dependency installation in setup.sh</name>
  <files>setup.sh</files>
  <action>
    Remove duplicate call to install_dependencies.sh at line 46
    Keep only the call at line 40 before Rust installation
    This eliminates unnecessary apt operations and improves installation speed
  </action>
  <verify>
    <automated>grep -n "install_dependencies.sh" setup.sh | wc -l</automated>
  </verify>
  <done>setup.sh has exactly one call to install_dependencies.sh</done>
</task>

<task type="auto">
  <name>Fix double path removal in uninstall.sh</name>
  <files>uninstall.sh</files>
  <action>
    Fix double "/usr/local/" paths in lines 70-84:
    - Change "/usr/local/usr/local/share/toolbox" to "/usr/local/share/toolbox"
    - Change "/usr/local/usr/local/share/zsh/site-functions" to "/usr/local/share/zsh/site-functions"
    - Change "/usr/local/usr/lib/tmpfiles.d" to "/usr/local/lib/tmpfiles.d"
    - Change "/usr/local/usr/local/etc/containers" to "/usr/local/etc/containers"
    - Change "/usr/local/usr/local/bin/toolbox" to "/usr/local/bin/toolbox"
    - Change "/usr/local/usr/local/etc" to "/usr/local/etc"
  </action>
  <verify>
    <automated>grep -n "usr/local/usr/local" uninstall.sh</automated>
  </verify>
  <done>No double /usr/local/ paths in uninstall.sh</done>
</task>

<task type="auto">
  <name>Add cleanup function for build artifacts</name>
  <files>functions.sh</files>
  <action>
    Add cleanup_build_artifacts() function after line 165:

```bash
cleanup_build_artifacts() {
    echo "Cleaning up build artifacts..."

    # Remove downloaded archives if build directories exist
    if [ -d "${BUILD_ROOT}/aardvark-dns" ]; then
        rm -f "${toolpath}/build/go*.linux-${ARCH}.tar.gz"
        rm -f "${toolpath}/build/protoc*-linux-${ARCH}.zip"
        rm -f "${toolpath}/build/rustup-init.sh"
    fi

    # Clean up other temporary build files
    find "${BUILD_ROOT}" -name "*.tar.*" -type f -delete 2>/dev/null || true
    find "${BUILD_ROOT}" -name "*.zip" -type f -delete 2>/dev/null || true

    echo "Cleanup completed"
}
```

    Call this function at the end of each build script that downloads archives.
    Start with build_go.sh and build_protoc.sh for initial implementation.
  </action>
  <verify>
    <automated>grep -n "cleanup_build_artifacts" functions.sh</automated>
  </verify>
  <done>cleanup_build_artifacts function defined in functions.sh</done>
</task>

</tasks>

<verification>
Verify all three concerns are addressed:
1. No duplicate dependency installation
2. No double path removals
3. Cleanup function added for build artifacts
</verification>

<success_criteria>
All three concerns from CONCERNS.md are resolved:
- Redundant dependency installation removed
- Double path fixes applied to uninstall.sh
- Cleanup function implemented for build artifacts
</success_criteria>

<output>
After completion, create `.planning/quick/4-fix-concerns-cleanup/4-4-SUMMARY.md`
</output>