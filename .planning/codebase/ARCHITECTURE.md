<!-- refreshed: 2026-05-13 -->
# Architecture

**Analysis Date:** 2026-05-13

## System Overview

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                            reconftw.sh                                       │
│  macOS re-exec → lib/validation.sh → lib/common.sh → lib/ui.sh             │
│  → lib/parallel.sh → modules/* (all sourced on startup)                     │
│  getopt CLI parse → reconftw.cfg → secrets.cfg → CLI overrides re-applied  │
└───────────────────────┬─────────────────────────────────────────────────────┘
                        │  opt_mode dispatch (case $opt_mode)
          ┌─────────────┼────────────────────┐
          ▼             ▼                    ▼
    ┌──────────┐  ┌──────────┐  ┌────────────────────────┐
    │ passive()│  │ subs_menu│  │  recon() / all()       │
    │   -p     │  │   -s     │  │   -r / -a              │
    └──────────┘  └──────────┘  │  OSINT → Subdomains    │
          ▼             ▼       │  → Web Detection        │
    ┌──────────┐  ┌──────────┐  │  → Web Analysis         │
    │ osint()  │  │webs_menu │  │  → Finalization         │
    │   -n     │  │   -w     │  └────────────────────────┘
    └──────────┘  └──────────┘           │
                        │                ▼
                        │      ┌──────────────────┐
                        │      │ vulns() (all/-a) │
                        │      └──────────────────┘
                        ▼
          ┌──────────────────────────────────────┐
          │  Module Functions (leaf operations)   │
          │  modules/subdomains.sh  sub_passive() │
          │  modules/web.sh         webprobe_full │
          │  modules/vulns.sh       xss(), sqli() │
          │  modules/osint.sh       domain_info() │
          └──────────────────────────────────────┘
                        │
                        ▼
          ┌──────────────────────────────────────┐
          │  Per-target output tree               │
          │  Recon/<domain>/{subdomains,webs,     │
          │  hosts,vulns,osint,nuclei_output,...} │
          └──────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| Entry point & CLI parser | getopt argument parsing, config sourcing, mode dispatch | `reconftw.sh` |
| Mode orchestration | `start`/`end`, workflow functions (`recon`, `passive`, `all`, `vulns`, `osint`, `subs_menu`, `webs_menu`, `zen_menu`, `monitor_mode`) | `modules/modes.sh` |
| Function lifecycle | `start_func`/`end_func`, checkpointing, logging, notifications, reporting, plugins, health check | `modules/core.sh` |
| Subdomain enumeration | All `sub_*` functions, `subtakeover`, `zonetransfer`, `s3buckets`, `geo_info` | `modules/subdomains.sh` |
| Web analysis | `webprobe_full`, `screenshot`, `nuclei_check`, `fuzz`, `jschecks`, `urlchecks`, `waf_checks`, and 20+ others | `modules/web.sh` |
| Vulnerability scanning | `xss`, `ssrf_checks`, `sqli`, `crlf_checks`, `lfi`, `ssti`, `smuggling`, `fuzzparams`, `nuclei_dast`, and others | `modules/vulns.sh` |
| OSINT collection | `domain_info`, `ip_info`, `emails`, `google_dorks`, `github_leaks`, `github_actions_audit`, `cloud_enum_scan`, etc. | `modules/osint.sh` |
| Shared utilities | `run_command`, `sed_i`, `deleteOutScoped`, `validate_config`, `cache_*`, `checkpoint_*`, `circuit_breaker_*`, rate-limit adaption | `modules/utils.sh` |
| Axiom/distributed mode | `axiom_launch`, `axiom_shutdown`, `axiom_selected`, `resolvers_update`, `ipcidr_target` | `modules/axiom.sh` |
| Parallel execution | `parallel_funcs`, `_throttle_jobs`, job heartbeat, progress live display, log mode output | `lib/parallel.sh` |
| Input validation/sanitization | `sanitize_domain`, `sanitize_ip`, `validate_domain`, `validate_integer`, `_sanitize_list_entry` | `lib/validation.sh` |
| Shared file/counter utilities | `ensure_dirs`, `ensure_webs_all`, `safe_backup`, `count_lines`, incident tracking | `lib/common.sh` |
| UI presentation layer | `_print_status`, `_print_msg`, `_print_section`, `_print_rule`, `ui_header`, `ui_summary`, TTY detection, color management, JSONL output | `lib/ui.sh` |
| Configuration | All runtime settings (~350 variables); sourced after CLI parse | `reconftw.cfg` |

## Pattern Overview

**Overall:** Monolithic bash orchestrator with sourced modular sub-scripts

**Key Characteristics:**
- Single process: `reconftw.sh` sources all libraries and modules at startup; every function lives in the same shell environment
- No subshell isolation between modules — all state is shared via global variables
- File-based checkpointing: `called_fn_dir/.funcname` sentinel files prevent re-running completed functions across invocations
- CLI-over-config: `reconftw.cfg` provides defaults; CLI flags set `CLI_*` variables that are re-applied after config sourcing to guarantee they cannot be overwritten
- All external tool invocations go through `run_command()` which handles dry-run mode, adaptive rate limiting, axiom dispatch, and debug logging

## Layers

**Entrypoint Layer:**
- Purpose: Bootstrap, macOS re-exec, module loading, getopt CLI parsing, config sourcing, CLI override re-application, mode dispatch
- Location: `reconftw.sh`
- Contains: `normalize_vps_count_args()`, the main `while/case` getopt loop, the config `source` sequence, CLI override if-blocks, the final `case $opt_mode` dispatch
- Depends on: All libraries (sourced first), all modules (sourced second)
- Used by: End user / CI

**Library Layer (pure utilities, no recon logic):**
- Purpose: Reusable utilities with no side effects; loadable independently for tests
- Location: `lib/validation.sh`, `lib/common.sh`, `lib/ui.sh`, `lib/parallel.sh`
- Contains: Input sanitization, file helpers, UI/color/progress, parallel job management
- Depends on: Nothing (source-guarded with `_*_LOADED` pattern)
- Used by: All modules and reconftw.sh

**Module Layer (recon logic):**
- Purpose: Implement all scanning, analysis, and orchestration functions
- Location: `modules/`
- Contains: All recon, vuln, OSINT, web, subdomain functions
- Depends on: Libraries (always loaded first), `reconftw.cfg` variables, external tools on PATH
- Used by: modes.sh orchestrates all others; reconftw.sh dispatches to modes.sh

**Configuration Layer:**
- Purpose: Default runtime values for ~350 flags/paths/limits; can be overridden by `secrets.cfg` and custom config
- Location: `reconftw.cfg`, optionally `secrets.cfg`, optionally `$CUSTOM_CONFIG`
- Contains: Module enable/disable flags, tool flags, API key env-var references, paths, parallelism settings, verbosity, Axiom settings
- Depends on: Nothing
- Used by: Sourced by `reconftw.sh` between CLI parse and CLI override re-application

**Output Layer (runtime-created):**
- Purpose: Store per-target findings in a stable directory hierarchy
- Location: `Recon/<domain>/` (created at `start()` time by `modules/modes.sh`)
- Contains: Standard subdirectories listed below
- Depends on: `start()` in modes.sh creates the directory tree

## Data Flow

### Primary Recon Request Path (`-r` / `--recon`)

1. macOS re-exec with Homebrew bash if needed (`reconftw.sh:40-55`)
2. Source all libs and modules (`reconftw.sh:80-93`)
3. CLI parse via `getopt` into `while/case` loop; sanitize `-d`/`-l` inputs (`reconftw.sh:159-489`)
4. Source `reconftw.cfg` (sets ~350 defaults) (`reconftw.sh:497-500`)
5. Source optional `secrets.cfg` (`reconftw.sh:503`)
6. Re-apply all `CLI_*` overrides so config cannot clobber CLI flags (`reconftw.sh:513-578`)
7. `ui_init()` — TTY detection, color setup, log-format detection (`reconftw.sh:638`)
8. `check_critical_dependencies()` — abort if mandatory tools missing (`reconftw.sh:657-658`)
9. `start()` — create `Recon/<domain>/` tree, init log, cache, incremental state, DNS resolver, plugins (`modules/modes.sh:13-163`)
10. `recon()` — sequential/parallel dispatch across 5 module groups: OSINT → Subdomains → Web Detection → Web Analysis → Finalization (`modules/modes.sh:848-997`)
11. `end()` — AI report (optional), cleanup empty files, Faraday export, screenshot diffs, plugin end event, hotlist build, incremental report, `export_reports()`, `ui_summary()` (`modules/modes.sh:286-485`)

### Function Execution Path (every leaf module function)

1. Guard check: `if [[ ! -f "$called_fn_dir/.${FUNCNAME[0]}" ]] || [[ $DIFF == true ]]; then`
2. Optional config-flag guard: `&& [[ $SUBPASSIVE == true ]]`
3. `start_func "${FUNCNAME[0]}" "Description"` — timestamps, per-function start time variable, JSONL log
4. Tool invocations via `run_command <tool> <args>` — handles dry-run, axiom dispatch, adaptive rate, debug log
5. Results written to subdirectory files in `Recon/<domain>/`
6. `end_func "Description" "${FUNCNAME[0]}"` — creates checkpoint file `called_fn_dir/.funcname`, emits `_print_status` badge, records timing

### Parallel Execution Path

1. `parallel_funcs N func1 func2 ...` — launches each function in a background subshell (`lib/parallel.sh`)
2. `_throttle_jobs N` — blocks spawning until running job count < N
3. Heartbeat goroutine calls `_parallel_snapshot()` every `PARALLEL_HEARTBEAT_SECONDS`
4. On completion each job emits output via `_parallel_emit_job_output` using `PARALLEL_LOG_MODE` (summary|tail|full)
5. Exit codes aggregated; non-zero count returned so caller can set `RECON_PARTIAL_RUN=true`

### Axiom Distributed Scan Flow

1. `-v` flag sets `AXIOM=true`; `--vps-count N` sets `AXIOM_FLEET_COUNT`
2. `axiom_launch()` — calls `axiom-fleet2` to provision N VMs, then `axiom-select` (`modules/axiom.sh:122-180`)
3. Module functions detect `axiom_runtime_enabled` and dispatch via `axiom-scan` instead of local tools
4. `run_module_with_axiom_failover fn` wraps each module: if axiom fails mid-run, retries the module locally (`modules/modes.sh:656-700`)
5. `axiom_shutdown()` — tears down fleet if `AXIOM_FLEET_SHUTDOWN=true` (`modules/axiom.sh:182-197`)

**State Management:**
- Global bash variables throughout (no encapsulation). Config vars, target vars (`domain`, `dir`, `called_fn_dir`, `LOGFILE`), and result counters are all globals
- `passive()` saves/restores module-enable globals before overriding them (`modules/modes.sh:549-611`)

## Key Abstractions

**`start_func` / `end_func`:**
- Purpose: Lifecycle wrapper around every leaf scanning function
- Examples: Used in every function in `modules/subdomains.sh`, `modules/web.sh`, `modules/vulns.sh`, `modules/osint.sh`
- Pattern: `start_func "${FUNCNAME[0]}" "description"` at top; `end_func "output path" "${FUNCNAME[0]}"` at bottom; creates checkpoint file on end

**Checkpoint files (`called_fn_dir/.funcname`):**
- Purpose: Prevent re-running completed functions across multiple invocations of the same target
- Location: `Recon/<domain>/.called_fn/.funcname`
- Pattern: Each function tests `[[ ! -f "$called_fn_dir/.${FUNCNAME[0]}" ]] || [[ $DIFF == true ]]`; `end_func` writes the sentinel via `touch "$called_fn_dir/.${fn}"`

**`run_command` wrapper:**
- Purpose: Universal external-tool gate for dry-run preview, axiom dispatch, adaptive rate limiting, and debug logging
- Location: `modules/utils.sh:468`
- Pattern: All tool calls inside module functions use `run_command <binary> <args>` rather than direct invocation

**Source guard pattern:**
- Purpose: Allow modules to be sourced multiple times (test re-sourcing, `--source-only`) without re-executing
- Pattern: `[[ -n "$_FOO_LOADED" ]] && return 0` at top of each lib file (`lib/common.sh:6`, `lib/parallel.sh:6`, `lib/ui.sh:5`, `lib/validation.sh` — validation uses error-code guards instead)

**`parallel_funcs` batches:**
- Purpose: Run independent module functions concurrently up to `PARALLEL_MAX_JOBS`
- Pattern: `parallel_funcs N func_a func_b func_c` — each function spawned as a background subshell; used in `recon()`, `osint()`, `vulns()` for independent groups

**`run_module_with_axiom_failover`:**
- Purpose: Transparent axiom/local fallback wrapper — if axiom fails during a module, retries locally
- Location: `modules/modes.sh:656`
- Pattern: All module calls inside `subs_menu`, `webs_menu`, `recon`, `passive` use this wrapper

## Entry Points

**`reconftw.sh` (main execution):**
- Location: `reconftw.sh`
- Triggers: Direct execution (`./reconftw.sh -d example.com -r`)
- Responsibilities: Bootstrap, all module loading, CLI parse, config source, mode dispatch

**`--source-only` flag:**
- Location: `reconftw.sh:123-125`
- Triggers: `./reconftw.sh --source-only` (used by bats test `setup()` blocks)
- Responsibilities: Sources all modules without executing any recon

**`start()` function:**
- Location: `modules/modes.sh:13`
- Triggers: Called at the top of most workflow functions (`recon`, `subs_menu`, `passive`, `osint`, `zen_menu`)
- Responsibilities: Create output directory tree, init LOGFILE, init cache/incremental/DNS/plugins, set global `dir` and `called_fn_dir`

**`end()` function:**
- Location: `modules/modes.sh:286`
- Triggers: Called at the bottom of most workflow functions
- Responsibilities: AI report, cleanup, Faraday, screenshot diffs, plugin events, hotlist, `export_reports()`, timing summary

## Output Directory Structure

```
Recon/
└── <domain>/
    ├── subdomains/          # subdomains.txt, zonetransfer.txt, s3buckets.txt, cloud_assets.txt
    ├── hosts/               # ips.txt, ipinfo.txt, favirecon.json, web_full_info*.txt
    ├── webs/                # webs.txt, webs_all.txt, webs_uncommon_ports.txt
    ├── vulns/               # (takeover.txt lives here)
    ├── osint/               # OSINT artifacts (emails, dorks, leaks, metadata)
    ├── nuclei_output/       # info.txt, low.txt, medium.txt, high.txt, critical.txt (+ *_json.txt)
    ├── screenshots/         # *.png, hashes.txt, diff_changed.txt
    ├── js/                  # JS analysis outputs
    ├── fuzzing/             # fuzzing artifacts
    ├── gf/                  # URL pattern classification outputs
    ├── cms/                 # CMS scanner outputs
    ├── report/              # report.json, index.html, findings.jsonl, *.csv
    ├── ai_result/           # reconftw_analysis.json (opt-in AI report)
    ├── assets.jsonl         # Asset store (opt-in, ASSET_STORE=true)
    ├── debug.log            # Persistent debug log
    ├── hotlist.txt          # Risk-scored findings summary
    ├── .log/                # Timestamped run logs: YYYY-MM-DD_HH:MM:SS.txt
    ├── .tmp/                # Temporary working files (optionally deleted on exit)
    ├── .called_fn/          # Checkpoint sentinels (.funcname files)
    └── .incremental/        # Incremental/monitor mode state
```

## Verbosity and Output Controls

**`OUTPUT_VERBOSITY`** (set in `reconftw.cfg`, overridden by `--quiet`/`--verbose`):
- `0` (quiet): Only errors and final summary printed to terminal; banner suppressed
- `1` (normal, default): Errors + warnings printed; `notification()` info/good suppressed
- `2` (verbose): All `notification()` calls, PID info, full parallel output, `start_func` messages, `print_timing_summary`

**`PARALLEL_LOG_MODE`** (`summary`|`tail`|`full`):
- `summary`: One badge line per completed parallel job
- `tail`: Last `PARALLEL_TAIL_LINES` (default 20, doubled on failure) from each job's log
- `full`: Complete captured stdout from each job

**`LOG_FORMAT`** (`plain`|`jsonl`|`jsonl-strict`):
- `jsonl-strict`: Forces `OUTPUT_VERBOSITY=0`, emits only machine-readable JSONL

## Architectural Constraints

- **Threading:** Single-threaded bash with optional background subshells via `parallel_funcs`; `wait -n` (bash 4.3+) used for job throttling in `_throttle_jobs`
- **Global state:** All config vars, `domain`, `dir`, `called_fn_dir`, `LOGFILE`, `start`, `runtime`, `DIFF`, `AXIOM`, and hundreds of module-enable flags are module-level globals; any sourced function can read or mutate them
- **Circular imports:** None by design — reconftw.sh sources libs first, then modules in explicit dependency order (`utils.sh` → `core.sh` → `osint.sh` → `subdomains.sh` → `web.sh` → `vulns.sh` → `axiom.sh` → `modes.sh`)
- **macOS bash version:** reconftw.sh re-execs itself under Homebrew bash ≥ 4 on macOS (system bash is 3.2); `lib/parallel.sh` requires bash 4.3+ for `wait -n`
- **Working directory:** `start()` calls `cd "$dir"` (the per-target output dir) before any module function runs; all relative paths inside modules resolve against the target dir. `reconftw.sh` captures `startdir=${PWD}` before this
- **No subshell isolation per module:** Modules are sourced functions, not subprocess commands. A `return` inside a module returns from the function; an `exit` would kill the whole shell

## Anti-Patterns

### Direct external tool calls without `run_command`

**What happens:** Calling `subfinder -d $domain ...` directly instead of `run_command subfinder -d $domain ...`
**Why it's wrong:** Bypasses dry-run preview, adaptive rate limiting, axiom dispatch detection, and debug-log routing
**Do this instead:** Always use `run_command <binary> <args>` for external tool invocations inside module functions

### Writing checkpoint files manually

**What happens:** Calling `touch "$called_fn_dir/.myfunc"` directly in a function body
**Why it's wrong:** `end_func` already creates the checkpoint and also records timing, emits the status badge, and logs the JSONL event; manual touch skips all of that
**Do this instead:** Call `end_func "description" "${FUNCNAME[0]}"` — it handles the checkpoint, timing, and badge atomically

### Skipping the `[[ ! -f "$called_fn_dir/.${FUNCNAME[0]}" ]] || [[ $DIFF == true ]]` guard

**What happens:** A leaf function body runs unconditionally without the checkpoint check
**Why it's wrong:** Function will re-run on every invocation even when the target was already scanned, wasting time and API quota
**Do this instead:** Open the function body with the checkpoint guard pattern before any tool invocation

### Overriding config globals without save/restore in workflow functions

**What happens:** A workflow function sets `PORTSCAN_ACTIVE=false` globally without saving/restoring
**Why it's wrong:** The override leaks into subsequent monitor cycles or multi-domain runs
**Do this instead:** Follow the pattern in `passive()` (`modules/modes.sh:549-611`): save all overridden vars to `_saved_*` locals, restore them before returning

## Error Handling

**Strategy:** Fail-soft by default (`set +e` in `reconftw.sh`; `set -o pipefail` retained). Tool failures are logged but do not abort unless `CONTINUE_ON_TOOL_ERROR=false`.

**Patterns:**
- ERR trap in `start()` logs function name, line number, and command to `$LOGFILE` and calls `explain_err()` (`modules/modes.sh:140`)
- Non-zero exit from `parallel_funcs` increments `RECON_OSINT_PARALLEL_FAILURES` and sets `RECON_PARTIAL_RUN=true`
- `run_module_with_axiom_failover` catches axiom mid-run failures and retries locally
- Circuit-breaker helpers (`circuit_breaker_is_open`, `circuit_breaker_record_failure`) in `modules/utils.sh:1190` for persistent tool failures

## Cross-Cutting Concerns

**Logging:** `$LOGFILE` (`Recon/<domain>/.log/<date>_<time>.txt`) receives all `[timestamp] Start/End function:` lines; `$DEBUG_LOG` (`Recon/<domain>/debug.log`) receives stderr from tool invocations when `OUTPUT_VERBOSITY >= 2`. Structured JSONL logging to `$STRUCTURED_LOG_FILE` when `STRUCTURED_LOGGING=true`.

**Secret redaction:** `redact_secrets()` scrubs `REDACT_VARS` env-var values and `REGISTERED_SECRETS` raw values from any string; used in dry-run previews and xtrace lines routed through `_trace_redact_stream` (`modules/core.sh:64-103`)

**Validation:** All user-supplied domain/IP/list inputs pass through `lib/validation.sh` sanitizers (`sanitize_domain`, `sanitize_ip`, `_sanitize_list_entry`) before any use, injecting protection against command injection

**Notifications:** `notification()` in `modules/core.sh:1302` gates level+verbosity checks before printing and optionally forwards to `notify` (Slack/Telegram/Discord via the `notify` tool) when `NOTIFICATION=true`

**Plugins:** `plugins_load()` sources `plugins/*.sh` at `start()` time; `plugins_emit start|end` called at workflow boundaries (`modules/core.sh:1603`)

---

*Architecture analysis: 2026-05-13*
