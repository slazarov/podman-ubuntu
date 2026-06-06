---
phase: 3-git-protocol-hardcoding
plan: 3
type: execute
wave: 1
depends_on: []
files_modified: []
autonomous: true
requirements: []
---

<objective>
Verify and ensure git protocol is correctly set for passt repository

Purpose: Address the hardcoded git protocol concern to prevent HTTPS 504 errors
Output: Verification report and confirmed fix
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.cl-templates/summary.md
</execution_context>

<context>
@.planning/codebase/CONCERNS.md
@.planning/STATE.md
</context>

<tasks>

<task type="auto">
  <name>Verify git protocol in build_pasta.sh</name>
  <files>scripts/build_pasta.sh</files>
  <action>
  1. Check if build_pasta.sh is using git:// protocol for passt repository
  2. Verify the commit b689cce already fixed this issue
  3. Ensure no other hardcoded https:// protocols exist for passt
  4. Search all files for any remaining https://passt.top references
  </action>
  <verify>
  <automated>grep -n "git://passt.top" scripts/build_pasta.sh && echo "✓ Protocol is correct" || echo "✗ Protocol issue found"</automated>
  </verify>
  <done>Confirmed that git:// protocol is being used for passt repository</done>
</task>

</tasks>

<verification>
- Verify no https://passt.top references exist in the codebase
- Confirm build_pasta.sh uses git:// protocol (line 22)
- Verify the fix was implemented in commit b689cce
</verification>

<success_criteria>
All git protocol references use git:// instead of https:// for passt repository
</success_criteria>

<output>
After completion, create `.planning/quick/3-git-protocol-hardcoding/3-3-SUMMARY.md`
</output>