# Coding Conventions

**Analysis Date:** 2026-03-02

## Naming Patterns

**Files:**
- All lowercase with underscores: `functions.sh`, `setup.sh`, `install_rust.sh`
- Descriptive names that clearly indicate purpose
- No file extensions beyond `.sh`

**Functions:**
- Snake case: `detect_architecture()`, `git_clone_update()`, `log_component()`
- Prefix with underscores for private/internal functions (e.g., `_FUNCTIONS_SH_SOURCED`)
- Meaningful names that describe what the function does

**Variables:**
- Environment variables: UPPERCASE with underscores (e.g., `DEBIAN_FRONTEND`, `BUILD_ROOT`)
- Local variables: lowercase with underscores (e.g., `lcomponent`, `lfolder`)
- Global variables exported with `export` keyword
- Boolean flags follow shell convention (empty string = false, non-empty = true)

**Constants:**
- All uppercase: `ARCH`, `GOARCH`, `PROTOC_ARCH`
- Defined at script level or in config.sh

## Code Style

**Formatting:**
- Strict mode enabled at script start: `set -euo pipefail`
- Indentation: 2 spaces (consistent throughout)
- Line length: No strict limit, but wrapped for readability
- Trailing whitespace: None

**Linting:**
- No explicit linter configured
- Scripts run with bash strict mode for basic error checking

## Import Organization

**Order:**
1. Configuration variables (if any)
2. Toolpath determination
3. Load external scripts: `config.sh` then `functions.sh`
4. Set error traps
5. Main script logic

**Path Aliases:**
- `toolpath` variable used for consistent script root reference
- Relative paths calculated from script location
- `realpath --canonicalize-missing` for robust path resolution

## Error Handling

**Patterns:**
- Centralized `error_handler()` function in `functions.sh`
- Trap setup: `trap 'error_handler $? $LINENO "$BASH_SOURCE"' ERR`
- Error output sent to stderr (`>&2`)
- Detailed error messages with script name, line number, and exit code
- Debug suggestion: `bash -x ${script_name}`

**Error Handler Format:**
```bash
error_handler() {
    local exit_code=$1
    local line_number=$2
    local script_name="${3##*/}"  # basename

    echo "" >&2
    echo "========================================" >&2
    echo "ERROR: Installation Failed" >&2
    echo "========================================" >&2
    echo "  Script:    ${script_name}" >&2
    echo "  Line:      ${line_number}" >&2
    echo "  Exit Code: ${exit_code}" >&2
    echo "========================================" >&2
    echo "" >&2
    echo "To debug, run: bash -x ${script_name}" >&2
    echo "" >&2

    exit "${exit_code}"
}
```

## Comments

**When to Comment:**
- Complex logic sections
- Environment variable explanations
- Version compatibility notes
- Important configuration choices

**JSDoc/TSDoc:**
- Function headers explain parameters and purpose
- Example: `get_latest_tag() - Get latest Git tag excluding release candidates`

## Function Design

**Size:**
- Functions are focused and single-purpose
- Typical length: 10-50 lines
- Maximum: ~100 lines for complex operations

**Parameters:**
- Local parameter variables prefixed with `l` (e.g., `lcomponent`, `lfolder`)
- Validation at start of function
- Default values handled with parameter expansion

**Return Values:**
- Use `echo` for return values
- Functions that don't return explicitly should use `exit` for errors
- Results captured with command substitution: `result=$(function_name)`

## Module Design

**Exports:**
- Environment variables exported with `export`
- Functions defined globally for use by sourced scripts
- Script-level variables use `_SOURCED` pattern to prevent recursion

**Barrel Files:**
- `functions.sh` serves as main utility module
- `config.sh` contains all configuration variables
- No explicit barrel files pattern

---

*Convention analysis: 2026-03-02*
```