# Coding Conventions

**Analysis Date:** 2026-05-13

## Shell Settings

**Entry point** (`reconftw.sh` top of file):
```bash
set -o pipefail
set -E
set +e          # fail-soft: individual commands may fail
IFS=$'\n\t'
```

**Libraries** (`lib/*.sh`) use `set -o pipefail` only — not `set -e`, because most functions return non-zero deliberately.

**Modules** (`modules/*.sh`) use NO `set` directives; they inherit from the sourcing shell.

## Source Guard Pattern

Every library file (`lib/`) begins with:
```bash
[[ -n "$_FOO_LOADED" ]] && return 0
declare -r _FOO_LOADED=1
```

Examples:
- `lib/common.sh`: `[[ -n "$_COMMON_SH_LOADED" ]] && return 0`
- `lib/parallel.sh`: `[[ -n "$_PARALLEL_SH_LOADED" ]] && return 0`
- `lib/ui.sh`: `[[ -n "${_UI_SH_LOADED:-}" ]] && return 0`

Tests that need to re-source a library must first unset the guard: `_COMMON_SH_LOADED=""`.

Modules (`modules/*.sh`) use a different guard — they check that `SCRIPTPATH` is set:
```bash
[[ -z "${SCRIPTPATH:-}" ]] && { echo "Error: This module must be sourced by reconftw.sh" >&2; exit 1; }
```

## Function Naming

**Declaration syntax:** Always use `function name() { ... }` form, never the POSIX `name() {` form.

```bash
function start_func() { ... }
function end_func() { ... }
function validate_domain() { ... }
```

Exception: `lib/ui.sh` and `lib/common.sh` helper functions omit `function` keyword to stay consistent with the POSIX-style helpers (`ui_init()`, `ensure_dirs()`, etc.). Both styles appear; prefer `function name()` for any new public API.

**Naming conventions:**
- Public module functions: `snake_case` prefixed with module context (`sub_passive`, `sub_crt`, `geo_info`)
- Private helpers: `_snake_case` prefix (`_print_status`, `_print_error`, `_print_module_start`, `_parallel_emit_job_output`)
- UI layer: `ui_` prefix (`ui_init`, `ui_header`, `ui_summary`, `ui_batch_end`)
- Lifecycle wrappers: `start_func` / `end_func` (call these at top/bottom of every recon function)
- Validation functions: `validate_*` / `sanitize_*` (defined in `lib/validation.sh` and `modules/utils.sh`)

## Variable Naming

**Globals (UPPER_SNAKE_CASE):**
- Config flags: `SUBPASSIVE`, `SUBCRT`, `PARALLEL_MODE`, `OUTPUT_VERBOSITY`
- Runtime state: `LOGFILE`, `SCRIPTPATH`, `DIFF`, `DRY_RUN`, `AXIOM`
- Error codes: `E_SUCCESS=0`, `E_INVALID_DOMAIN=20`, `E_INVALID_IP=21` (readonly, defined in `lib/validation.sh`)

**Locals (lowercase):**
```bash
local file="$1"
local domain="$2"
local count=0
```
Always declare locals with `local`. Always quote variable expansions.

**Color variables** (`bred`, `bgreen`, `bblue`, `byellow`, `yellow`, `reset`, `cyan`) are defined in `reconftw.cfg` and overridden to empty strings in no-color mode by `lib/ui.sh`.

## CLI Flag Pattern

CLI flags are captured as `CLI_*` variables during argument parsing, then re-applied AFTER `reconftw.cfg` is sourced (lines ~513-575 of `reconftw.sh`). This ensures config file defaults do not clobber command-line flags.

```bash
# During parsing (before config load):
'--quiet')    CLI_OUTPUT_VERBOSITY=0 ;;
'--verbose')  CLI_OUTPUT_VERBOSITY=2 ;;
'--parallel') CLI_PARALLEL_MODE=true ;;

# After config load (reconftw.sh ~line 513):
if [[ -n "${CLI_OUTPUT_VERBOSITY:-}" ]]; then
    OUTPUT_VERBOSITY="${CLI_OUTPUT_VERBOSITY}"
fi
if [[ -n "${CLI_PARALLEL_MODE:-}" ]]; then
    PARALLEL_MODE="${CLI_PARALLEL_MODE}"
fi
```

When adding a new CLI flag: add `CLI_NEWFLAG` during the `getopt` parsing loop, then add a re-apply block after config sourcing.

## Output / UI Conventions

**Status badges:** `OK`, `WARN`, `FAIL`, `SKIP`, `CACHE`, `INFO`, `RUN`

**Status line format** (dot-fill, right-aligned timing):
```
OK    sub_passive                    12s
WARN  sub_crt                        3s  (no results)
SKIP  sub_brute                      0s
FAIL  sub_dns                        7s  (see debug.log)
```
Produced by `_print_status STATE "func_name" "duration"` in `lib/common.sh`.

**Section headers** use thin `───` rules:
```bash
_print_section "OSINT"    # calls _print_module_start()
```
Output: `── OSINT ────────────────────────────────────────────────────────────────`

**Verbosity gating:**
- `OUTPUT_VERBOSITY=0` (quiet): only errors/FAIL printed
- `OUTPUT_VERBOSITY=1` (normal, default): OK/WARN/FAIL/SKIP status lines
- `OUTPUT_VERBOSITY=2` (verbose): all of the above + INFO messages + start_func messages

The `notification()` function in `modules/core.sh` gates by level:
```bash
# error → always visible
# warn  → OUTPUT_VERBOSITY >= 1
# info|good → OUTPUT_VERBOSITY >= 2
```

## Function Lifecycle (start_func / end_func)

Every recon function that runs a tool wraps its body with the lifecycle pair:

```bash
function sub_passive() {
    if { [[ ! -f "$called_fn_dir/.${FUNCNAME[0]}" ]] || [[ $DIFF == true ]]; } && [[ $SUBPASSIVE == true ]]; then
        start_func "${FUNCNAME[0]}" "Passive subdomain enum"
        # ... tool invocations ...
        end_func "Passive subdomain enum" "${FUNCNAME[0]}"
    else
        skip_notification "processed"   # or "disabled"
    fi
}
```

- `start_func name desc` — logs to LOGFILE, sets per-function start timestamp, emits INFO at verbosity >= 2
- `end_func message name [status]` — touches checkpoint file, calculates elapsed time, calls `_print_status`
- `skip_notification reason` — emits SKIP/CACHE badge; reasons: `"disabled"`, `"mode"`, `"processed"`, `"processed-visible"`, `"noinput"`

## File Checkpointing (Resumability)

Checkpoint files under `${called_fn_dir}/` prevent functions from re-running on resume:

```bash
# Check pattern used in every module function:
if { [[ ! -f "$called_fn_dir/.${FUNCNAME[0]}" ]] || [[ $DIFF == true ]]; } && [[ $FLAG == true ]]; then
```

- `end_func` creates the checkpoint: `touch "$called_fn_dir/.${fn}"`
- DIFF mode (`DIFF=true`) bypasses checkpoint — forces re-execution
- Helper `should_run()` in `lib/common.sh` provides a cleaner gate: `if should_run "FLAG_VAR"; then`

## Error Handling

**`count_lines()`** in `lib/common.sh` — counts non-empty lines in a file; returns 0 if missing or empty:
```bash
NUMOFLINES=$(count_lines "subdomains/subdomains.txt")
```
For stdin-pipe inputs, use `count_lines_stdin` (e.g., `result=$(some_cmd | count_lines_stdin)`).

**Return codes:** Functions return 0 on success, non-zero on failure. Error codes are defined as `readonly` in `reconftw.sh`:
- `E_SUCCESS=0`, `E_GENERAL=1`, `E_MISSING_DEP=2`, `E_INVALID_INPUT=3`

**`_print_error`** goes to stderr and is always visible regardless of verbosity:
```bash
_print_error "Cannot read file: $path"
```

**`print_warnf` / `print_errorf`** for formatted messages:
```bash
print_warnf "Function %s failed (rc=%d)" "$func" "$rc"
print_errorf "Invalid domain: '%s'" "$domain"
```

**`warn_once`** prevents duplicate warning spam:
```bash
warn_once "missing-tool-dnstake" "subtakeover: dnstake not found"
```

## Validation Functions

Canonical validation lives in `lib/validation.sh`. Key functions:

| Function | Purpose |
|----------|---------|
| `validate_domain()` | RFC domain check + injection character rejection |
| `validate_ipv4()` | Octet range validation |
| `validate_integer()` | Numeric range check |
| `validate_boolean()` | Accepts `true`/`false` only (not `1`/`0`/`yes`/`no`) |
| `validate_file_readable()` | Exists + readable + is-a-file |
| `sanitize_interlace_input()` | Removes shell metacharacters from input files (canonical in `lib/validation.sh`) |
| `sanitize_domain()` | Strips URL components, lowercases, rejects injection (in `modules/utils.sh`) |
| `is_in_scope_host()` | Anchored hostname scope check (prevents substring false positives) |
| `filter_in_scope_urls()` | Python3-based URL scope check (scheme, userinfo, host) |

**Injection characters blocked:** `;`, `|`, `&`, `$`, `` ` ``, `\`, `(`, `)`, `{`, `}`

Error codes for validation failures: `E_INVALID_DOMAIN=20`, `E_INVALID_IP=21`, `E_INVALID_PATH=22`, `E_INVALID_URL=23`.

## Path and CWD Conventions

Use subshells instead of `pushd`/`popd`:
```bash
# Correct:
( cd "${output_dir}" && run_tool ... )

# Never:
pushd "${output_dir}"
run_tool ...
popd
```

All `pushd`/`popd` were removed in the 2026-03 audit.

## Parallel Execution

**`parallel_funcs max_jobs func1 func2 ...`** in `lib/parallel.sh` — the canonical way to parallelize module functions:
```bash
parallel_funcs 3 sub_passive sub_crt sub_active
```

Background per-target loops use `_throttle_jobs max`:
```bash
for target in "${targets[@]}"; do
    ( process_target "$target" ) &
    _throttle_jobs "${MAX_CONCURRENT_JOBS:-4}"
done
wait
```

**PARALLEL_LOG_MODE** controls job output: `summary` (default), `tail`, `full`.

**PARALLEL_UI_MODE** controls progress display: `clean` (default), `balanced`, `trace`.

## Import / Sourcing Order

In `reconftw.sh` (lines ~80-93):
1. `lib/validation.sh`
2. `lib/common.sh`
3. `lib/ui.sh`
4. `lib/parallel.sh`
5. `modules/utils.sh`
6. `modules/core.sh`
7. `modules/osint.sh`
8. `modules/subdomains.sh`
9. `modules/web.sh`
10. `modules/vulns.sh`
11. `modules/axiom.sh`
12. `modules/modes.sh`

Libraries must not depend on modules. Modules may depend on libraries and on earlier-sourced modules.

## Logging

- All tool output redirected to `$LOGFILE`: `command ... 2>>"$LOGFILE" >/dev/null`
- Structured JSON logging via `log_json level func message [key=val]` (optional, `STRUCTURED_LOGGING=true`)
- `redact_secrets()` scrubs `REDACT_VARS` and `REGISTERED_SECRETS` from log lines
- `register_secret "$value"` must be called before logging any secret value

## Comments

Functions intended as public API receive a multi-line doc block:
```bash
# Function purpose
# Usage: func_name arg1 [arg2]
# Returns: 0 on success, N on failure
function func_name() { ... }
```

Inline `# shellcheck disable=SC2154` suppresses false-positives for variables defined in `reconftw.cfg`. Suppress only at file level with a comment explaining why.

---

*Convention analysis: 2026-05-13*
