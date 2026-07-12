# Phase 1: Resilient Resume & Timeout Safety - Pattern Map

**Mapped:** 2026-05-13
**Files analyzed:** 5 (all existing, modified — no new files)
**Analogs found:** 5 / 5

## File Classification

All Phase 1 files sit on the **function-lifecycle pipeline** (start_func → body → end_func) and the **parallel-batch pipeline** (`parallel_funcs` → background subshell → heartbeat → emit). No new files; every change extends an existing function or adds a sibling helper next to an existing analog.

| Modified File | Role | Data Flow | Lifecycle Stage Touched | Match Quality |
|---------------|------|-----------|-------------------------|---------------|
| `modules/core.sh` | lifecycle wrapper | event-driven (per-function boundary) | `start_func` / `end_func` body, checkpoint touch, status persistence | exact (self-analog) |
| `modules/modes.sh` | mode orchestration | request-response (workflow entry) | `start()` body, trap registration, banner emission, cleanup loop | exact (self-analog) |
| `modules/utils.sh` | shared utility | request-response (single-call helper) | sibling to `check_disk_space()`; no change to `_run_dns_with_heartbeat` | exact (self-analog) |
| `lib/parallel.sh` | parallel execution machinery | event-driven (poll loop) | batch-flush heartbeat loop body + final-wait heartbeat loop body + `_parallel_emit_job_output` reason path | exact (self-analog) |
| `reconftw.cfg` | config (defaults) | static declaration | timeouts block (`:387-388`) and parallel block (near `PARALLEL_HEARTBEAT_SECONDS` at `:312`) | exact (self-analog) |

**Note on classification:** Phase 1 is a brownfield extension — every new helper has a direct sibling in the same file with the same role and data flow. The "analog" for each is therefore the existing function it sits beside, and the patterns to copy are the surrounding idioms (badge vocabulary, `log_json` shape, `2>/dev/null || true` error suppression, subshell-not-pushd, `function name()` declaration style).

---

## Pattern Assignments

### `modules/core.sh` — `start_func` / `end_func` lifecycle (Plan 01-01 / RESIL-01 sentinel; Plan 01-02 / RESIL-02 disk hook)

**Role:** Lifecycle wrapper. **Data flow:** Event-driven (called at every function boundary; both before tool invocations and after checkpoint write).
**Analog:** Itself — `start_func` at `:1419-1435` and `end_func` at `:1437-1529` are the canonical patterns the new sentinel ops must mirror.

#### Existing `start_func` body (lines 1419-1435) — analog for sentinel-create + mid-run disk check

```bash
function start_func() {
    local current_date
    current_date=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[$current_date] Start function: ${1} " >>"${LOGFILE}"
    # Use per-function start time to avoid race conditions in parallel mode
    local _fn_name="${1}"
    printf -v "_start_time_${_fn_name//[^a-zA-Z0-9_]/_}" '%s' "$(date +%s)"
    # Keep global $start for backward compat (serial mode)
    start=$(date +%s)
    log_json "INFO" "${1}" "Function started" "description=${2}"
    if declare -F ui_log_jsonl >/dev/null 2>&1; then
        ui_log_jsonl "INFO" "${1}" "Function started" "description=${2}"
    fi
    if [[ "${OUTPUT_VERBOSITY:-1}" -ge 2 ]]; then
        _print_msg "INFO" "Running ${1}..."
    fi
}
```

**Insertion anchor (D-01 sentinel + D-07 disk check):**
- D-01 `.inprogress_<fn>` `touch` lands **after** the `printf -v "_start_time_..."` line (1425) and **before** the first `log_json` call (1428). The variable is already sanitized via `${_fn_name//[^a-zA-Z0-9_]/_}` — reuse the same `${1}` (raw function name) for the file name (per D-01: "plain empty `${called_fn_dir}/.inprogress_<fn>`"). Guard with `[[ -n "${called_fn_dir:-}" ]]` (same pattern as line 1505).
- D-07 `_check_disk_mid_run` call lands at the **very top** of the function body, before the `current_date` line, so the abort fires before any state is written. Pattern: `_check_disk_mid_run || _abort_disk_full`.

#### Existing `end_func` body (lines 1465-1510) — analog for sentinel-remove + checkpoint touch + status persistence

```bash
    touch "$called_fn_dir/.${fn}"
    local end
    end=$(date +%s)
    # ... (timing computation) ...

    # Persist per-function final status for parallel aggregator.
    if [[ -n "${called_fn_dir:-}" ]]; then
        printf "%s\n" "$badge" >"${called_fn_dir}/.status_${fn}" 2>/dev/null || true
        if [[ -n "$reason_code" ]]; then
            printf "%s\n" "$reason_code" >"${called_fn_dir}/.status_reason_${fn}" 2>/dev/null || true
        fi
    fi
```

**Insertion anchor (D-01 sentinel-remove + D-07 post-checkpoint disk check):**
- D-01 `rm -f "$called_fn_dir/.inprogress_${fn}"` lands **immediately before** the existing `touch "$called_fn_dir/.${fn}"` at line 1465. Use the same `2>/dev/null || true` suppression idiom seen at lines 1506/1508. Sentinel removal **before** the checkpoint touch means a crash between these two ops still re-runs the function on next invocation (the `.<fn>` is the source of truth; the `.inprogress_<fn>` is purely a surface-level indicator).
- D-07 `_check_disk_mid_run` call lands **after** the existing `printf` blocks at lines 1505-1509 and after the `_print_status` block at 1512-1524 — i.e. only after the checkpoint and status are durably written. This way, a disk-full abort detected at end_func still leaves a complete `.<fn>` + `.status_<fn>` pair on disk for the just-finished function.

#### Status persistence pattern (lines 1505-1509) — analog for D-14 (timeout reason)

The `.status_<fn>` / `.status_reason_<fn>` pair is **reused as-is** for D-14 timeout reporting (no schema extension). The parallel-batch path (`lib/parallel.sh`) writes these files when it kills a stuck job, and `_parallel_emit_job_output` reads them via the same `head -n 1 "$status_marker"` path already at `lib/parallel.sh:203-209` and `:224`.

#### Conventions to preserve in `modules/core.sh`

- **`function name()` declaration style** — new helpers (`_check_disk_mid_run`, `_abort_disk_full`) defined alongside `start_func`/`end_func` use `function _name() { ... }` form (consistent with `:1419`, `:1437`, and CONVENTIONS.md §Function Naming).
- **`log_json` call shape** — `log_json "<LEVEL>" "${fn}" "<message>" "key=value" "key2=value2"` (see `:1428`, `:1525`). New entries:
  - D-04 resume detection: `log_json "WARN" "resume" "Inprogress sentinels found" "reason=inprogress_leftover" "funcs=${joined}"`
  - D-09 disk abort: `log_json "ERROR" "${fn:-main}" "Disk space exhausted" "reason=disk_full" "available_gb=${avail}" "required_gb=${req}"`
  - D-17 DNS timeout (already emitted by `_run_dns_with_heartbeat`; only adds `reason=dns_hard_timeout` key).
- **Underscore-prefix-private helpers** — `_check_disk_mid_run`, `_abort_disk_full`, `_cleanup_inprogress`, `_timeout_kill_job` (CONVENTIONS.md §Function Naming: "Private helpers: `_snake_case` prefix").
- **Guard `called_fn_dir` references** — `if [[ -n "${called_fn_dir:-}" ]]; then` wrap (pattern at `:1505`) for any new write to that directory. Prevents accidental writes when invoked outside `start()` (e.g., `--source-only` in tests).
- **`2>/dev/null || true`** for filesystem ops that must not abort lifecycle (pattern at `:1506`, `:1508`).

---

### `modules/modes.sh` — `start()` orchestration entry (Plan 01-01 trap + banner + PRESERVE loop)

**Role:** Mode orchestration. **Data flow:** Request-response (single call per workflow entry; sets up traps and writes one-shot banner).
**Analog:** Itself — `start()` at `:13-163` is where all initialization happens; the existing INT/TERM trap at `:118` and ERR trap at `:140` are the templates the new EXIT trap must compose with.

#### Existing INT/TERM trap (line 118) — analog for D-02 EXIT trap composition

```bash
    # Trap for cleanup on unexpected exit
    trap 'cleanup_on_exit' INT TERM
```

The handler `cleanup_on_exit` lives in `modules/utils.sh:116-146` and currently handles tmp-chunk cleanup, child-pid kill, interactsh kill, and final `exit "$exit_code"`. It is registered for INT and TERM only — **EXIT is unused today**.

#### Existing ERR trap (line 140) — analog for trap composition

```bash
    # Non-fatal error trap: log and continue (plus short explanation for common cases)
    trap 'rc=$?; ts=$(date +"%Y-%m-%d %H:%M:%S"); cmd=${BASH_COMMAND}; loc_fn=${FUNCNAME[0]:-main}; loc_ln=${BASH_LINENO[0]:-0}; msg="[$ts] ERR($rc) @ ${loc_fn}:${loc_ln} :: ${cmd}"; if [[ -n "${LOGFILE:-}" ]]; then echo "$msg" >>"$LOGFILE"; else echo "$msg" >&2; fi; explain_err "$rc" "$cmd" "$loc_fn" "$loc_ln"' ERR
```

The ERR trap is a one-liner with the full handler inlined — this is the project's idiom (avoids defining a separate function). The new EXIT trap may either:
1. **Extend the existing INT/TERM trap** to also fire on EXIT: `trap 'cleanup_on_exit' EXIT INT TERM` — then add a `_cleanup_inprogress` call **at the top of** `cleanup_on_exit()` in `modules/utils.sh:116`. This is the simpler composition.
2. **Register a separate EXIT-only trap** that calls only `_cleanup_inprogress`, leaving INT/TERM behavior unchanged. Use this if the planner wants to avoid touching `cleanup_on_exit` semantics (which currently `exit "$exit_code"` at the end — fine for EXIT since the shell is already exiting).

**D-02 / D-05 / D-04 insertion anchors:**
- **D-05 PRESERVE=false orphan cleanup** lands at lines `:78-80` inside the existing `FORCE_RESCAN` block:
  ```bash
  if [[ "${FORCE_RESCAN:-false}" == "true" ]]; then
      rm -f "$called_fn_dir"/.* 2>>"${LOGFILE:-/dev/null}" || true
  fi
  ```
  The existing `rm -f "$called_fn_dir"/.*` already globs both `.<fn>` and any `.inprogress_<fn>` — so the `FORCE_RESCAN` path requires **no change** if dot-glob expansion is set. To be explicit and defensive, add an additional `rm -f "$called_fn_dir"/.inprogress_*` line at the same indent. Note this is `FORCE_RESCAN` (CLI `--force`), not `PRESERVE=false`; D-05 says "`PRESERVE=false` (default) already clears `.<fn>` checkpoints" — locate that loop. (It is the `end()` cleanup at `modes.sh:352-355` for empty files, not a checkpoint wipe. The actual checkpoint clear for `PRESERVE=false` happens implicitly because the **next** run with `PRESERVE=false` creates a fresh `dir` only when `FORCE_RESCAN=true`; otherwise existing `.<fn>` files persist.) Planner should re-verify the exact location: the leftover-clear must run during `start()` setup, **before** any `start_func` call, to prevent the resume banner from firing on a `PRESERVE=false` re-run.
- **D-04 resume banner** lands **after** the existing `_print_rule` / `ui_header` block (lines 142-152) and **before** `tools_installed` at line 160. Glob `$called_fn_dir/.inprogress_*`, count, list — emit one `_print_msg WARN` line (or a dedicated `_print_resume_banner` helper) and one `log_json WARN resume` line. Pattern at `:155`:
  ```bash
  if [[ "${FORCE_RESCAN:-false}" == "true" ]]; then
      _print_msg WARN "Force rescan enabled: ignoring cached module markers"
  fi
  ```
  Mirror this exactly for resume reporting. Detection logic must run **after** the FORCE_RESCAN block clears stale sentinels so a forced rescan never reports a resume.
- **D-02 EXIT trap** lands **immediately after** the existing INT/TERM trap at line 118. Two acceptable composition styles per CLAUDE'S DISCRETION above; option 1 (extend `cleanup_on_exit`) is recommended for minimal trap-surface churn.

#### Conventions to preserve in `modules/modes.sh`

- **Trap one-liner idiom** — handlers either name a function (`cleanup_on_exit`) or inline the full body (ERR trap). New EXIT handler should be a named function (`_cleanup_inprogress`) defined in `modules/utils.sh` next to `cleanup_on_exit`.
- **`_print_msg WARN "..."`** for banner-style notices (pattern at `:155`); always visible at `OUTPUT_VERBOSITY>=1`.
- **`notification` vs `_print_msg`** — `notification` (`modules/core.sh:1302`) goes through verbosity-gating-plus-notify-fanout; `_print_msg` is direct console only. Resume banner should use `_print_msg WARN` (per D-04 it's local UI only, not a notification-channel event); JSONL log is emitted separately via `log_json`.
- **No `pushd`/`popd`** — all CWD changes are direct `cd "$dir"` at `:82` (CONVENTIONS.md §Path and CWD).
- **Subshell pattern** — if any new helper needs a transient CWD or env, wrap in `( cd "$x" && cmd )` not `pushd`/`popd`.

---

### `modules/utils.sh` — `check_disk_space` sibling helpers (Plan 01-02 / RESIL-02) and `_run_dns_with_heartbeat` (no-op for Plan 01-03 / PERF-02)

**Role:** Shared utility. **Data flow:** Request-response (called once per function boundary; returns 0/1).
**Analog:** `check_disk_space()` at `:421-436` (the canonical `df`-based check); `_run_dns_with_heartbeat()` at `:1434-1452` (the DNS timeout consumer that already respects `0=disabled`).

#### Existing `check_disk_space` (lines 421-436) — analog for `_check_disk_mid_run`

```bash
# Check available disk space
# Usage: check_disk_space <required_gb> <path>
# Returns 0 if enough space, 1 otherwise
function check_disk_space() {
    local required_gb="$1"
    local check_path="${2:-.}"

    # Get available space in GB (portable across macOS/Linux).
    local available_gb
    available_gb=$(df -Pk "$check_path" 2>/dev/null | awk 'NR==2 {print int($4 / 1024 / 1024)}')

    if [ -z "$available_gb" ] || [ "$available_gb" -lt "$required_gb" ]; then
        DISK_SPACE_INFO="Disk space LOW: required ${required_gb}GB, available ${available_gb:-0}GB at ${check_path}"
        return 1
    fi

    DISK_SPACE_INFO="Disk space OK: ${available_gb}GB available at ${check_path}"
    return 0
}
```

**Insertion anchor (D-07/D-08/D-09):** New helpers sit **immediately after** `check_disk_space` (after line 436). Two helpers:
1. `_check_disk_mid_run` — thin wrapper that calls `check_disk_space "${MIN_DISK_SPACE_GB:-5}" "${dir:-.}"` (reuses D-08 single-threshold source-of-truth) and returns its exit code. **No re-implementation** of `df` parsing; the analog populates `DISK_SPACE_INFO` which the caller can read.
2. `_abort_disk_full` — emits `_print_error "$DISK_SPACE_INFO"` (always visible per CONVENTIONS.md §Error Handling), calls `log_json "ERROR" "${fn:-main}" "Disk space exhausted" "reason=disk_full" "info=${DISK_SPACE_INFO}"`, then `exit 1` (D-09 hard abort). The Bash EXIT trap from D-02 fires on the way out and clears any `.inprogress_<fn>` so a subsequent invocation does NOT see a fake resume.

#### Existing `_run_dns_with_heartbeat` (lines 1434-1452) — analog for D-16 (NO CODE CHANGE)

```bash
_run_dns_with_heartbeat() {
    local label="$1"
    local timeout_value="$2"
    shift 2

    local heartbeat_interval="${DNS_HEARTBEAT_INTERVAL_SECONDS:-20}"
    [[ "$heartbeat_interval" =~ ^[0-9]+$ ]] || heartbeat_interval=20

    if _dns_timeout_enabled "$timeout_value"; then
        if [[ -n "${TIMEOUT_CMD:-}" ]]; then
            run_with_heartbeat "$label" "$heartbeat_interval" "$TIMEOUT_CMD" -k 10s "$timeout_value" "$@"
        else
            warn_once "dns-timeout-command-missing" "DNS timeout requested but timeout command is unavailable; continuing without hard timeout."
            run_with_heartbeat "$label" "$heartbeat_interval" "$@"
        fi
    else
        run_with_heartbeat "$label" "$heartbeat_interval" "$@"
    fi
}
```

**No modification to this function.** D-16 only changes the two **default values** that this function reads from `reconftw.cfg`:
- `DNS_BRUTE_TIMEOUT=0` → `DNS_BRUTE_TIMEOUT=6h`
- `DNS_RESOLVE_TIMEOUT=0` → `DNS_RESOLVE_TIMEOUT=4h`

The `_dns_timeout_enabled` guard already short-circuits `0` (disabled), and non-zero `h`-suffix values are passed verbatim to `timeout`/`gtimeout` which accept that form. D-17 surfacing is via the existing `WARN` badge from `end_func` (the consuming function returns non-zero on timeout); the planner only adds `reason=dns_hard_timeout` to the existing JSONL log entry (if not already present in the helper's WARN path).

#### Conventions to preserve in `modules/utils.sh`

- **`function name() { ... }`** declaration for `_check_disk_mid_run` / `_abort_disk_full` (consistent with `check_disk_space` at `:421`).
- **Comment doc block** above each new helper (CONVENTIONS.md §Comments), mirroring the `# Check available disk space` block at `:418-420`.
- **`DISK_SPACE_INFO` global** is reused — no new global. Caller pattern: `_check_disk_mid_run || _abort_disk_full`.
- **`_print_error`** for the abort message (always-visible, `2>&1` to stderr). `log_json` for the structured event.
- **`exit 1`** for the hard-abort path is the only acceptable `exit` site in this code (rest of the file uses `return` per the "no subshell isolation per module" constraint). The EXIT trap from D-02 fires regardless and cleans up.

---

### `lib/parallel.sh` — heartbeat-loop timeout enforcement (Plan 01-03 / RESIL-03)

**Role:** Parallel execution machinery. **Data flow:** Event-driven (1Hz `sleep 1` poll inside `while :; do ... done` until all batch PIDs exit).
**Analog:** The heartbeat loop appears **twice** in `parallel_funcs` — once at lines 432-465 (batch-flush phase, when an in-progress batch fills to `max_jobs`) and once at lines 537-569 (final-wait phase, for the trailing partial batch). Both loops have identical structure; the timeout kill logic must be inserted in **both**.

#### Existing batch-flush heartbeat loop (lines 432-465) — primary analog

```bash
# Heartbeat while long-running jobs are executing, to avoid "stuck" perception.
local hb="${PARALLEL_HEARTBEAT_SECONDS:-20}"
if [[ "${PARALLEL_MODE:-true}" == "true" ]] && [[ "${OUTPUT_VERBOSITY:-1}" -ge 1 ]] && [[ "$hb" =~ ^[0-9]+$ ]] && ((hb > 0)); then
    local last_hb now alive hb_active_list job_dur dur_fmt queue_count batch_elapsed hb_done_count
    last_hb=$(date +%s)
    while :; do
        alive=0
        hb_done_count=0
        hb_active_list=""
        now=$(date +%s)
        for idx in "${!batch_pids[@]}"; do
            if kill -0 "${batch_pids[$idx]}" 2>/dev/null; then
                alive=1
                job_dur=$((now - batch_starts[$idx]))
                dur_fmt=$(format_duration "$job_dur")
                if [[ -z "$hb_active_list" ]]; then
                    hb_active_list="${batch_funcs[$idx]} ${dur_fmt}"
                else
                    hb_active_list="${hb_active_list}, ${batch_funcs[$idx]} ${dur_fmt}"
                fi
            else
                hb_done_count=$((hb_done_count + 1))
            fi
        done
        ((alive == 0)) && break
        if ((now - last_hb >= hb)); then
            queue_count=$((total_funcs - queued_count))
            batch_elapsed=$((now - batch_start_ts))
            _parallel_snapshot "${hb_active_list:-none}" "$done_list" "$queue_count" "$hb_done_count" "${#batch_pids[@]}" "$batch_elapsed"
            last_hb=$now
        fi
        sleep 1
    done
fi
```

**Insertion anchor (D-11/D-12/D-13/D-14):** Inside the `if kill -0 "${batch_pids[$idx]}" 2>/dev/null; then` branch (line 443), **after** the `job_dur=$((now - batch_starts[$idx]))` line (445). The `job_dur` is already computed — reuse it. Pseudocode for the new block:

```bash
# Timeout enforcement (D-11..D-14): if PARALLEL_JOB_TIMEOUT_SECONDS > 0 and
# job_dur > threshold, kill the job and persist FAIL status with reason=timeout.
local _to="${PARALLEL_JOB_TIMEOUT_SECONDS:-0}"
if [[ "$_to" =~ ^[0-9]+$ ]] && (( _to > 0 )) && (( job_dur > _to )); then
    _timeout_kill_job "${batch_pids[$idx]}" "${batch_funcs[$idx]}" "$job_dur"
fi
```

`_timeout_kill_job` is a new private helper defined **above** `parallel_funcs` in `lib/parallel.sh` (near `_throttle_jobs` at `:33` and `_parallel_emit_job_output` at `:172`). It performs:
1. `kill -TERM "$pid" 2>/dev/null || true`
2. Poll loop: `for ((i=0; i<${PARALLEL_KILL_GRACE_SECONDS:-10}; i++)); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done`
3. `kill -KILL "$pid" 2>/dev/null || true` if still alive
4. **Persist FAIL + reason=timeout** to the same files `end_func` uses (`called_fn_dir/.status_<fn>` and `.status_reason_<fn>`), so `_parallel_emit_job_output` picks them up via the existing read path at `:203-209` / `:223-224`:
   ```bash
   if [[ -n "${called_fn_dir:-}" ]]; then
       printf "FAIL\n" >"${called_fn_dir}/.status_${func_name}" 2>/dev/null || true
       printf "timeout\n" >"${called_fn_dir}/.status_reason_${func_name}" 2>/dev/null || true
   fi
   ```
5. `log_json "ERROR" "${func_name}" "Job timed out" "reason=timeout" "duration_sec=${job_dur}"`

The post-loop `wait "${batch_pids[$idx]}"` at line 470 then collects the killed process's non-zero rc, and `_parallel_emit_job_output` at line 483 reads the `FAIL` + `timeout` from the status files and emits the console badge per the existing reason-rendering code path (`:261-263`, `:279-281`).

#### Existing final-wait heartbeat loop (lines 537-569) — identical analog, second insertion site

Structure is identical to the batch-flush loop above (lines 432-465). Same insertion: at line ~549 inside the `kill -0` branch, after the `job_dur=$((now - batch_starts[$idx]))` line.

#### Existing `_parallel_emit_job_output` (lines 172-300) — reason-rendering path is reused (D-14)

The function already reads `.status_<fn>` (`:204`) and `.status_reason_<fn>` (`:224`) and renders the reason via:
```bash
if [[ -n "$reason_code" ]] && { [[ "$badge" == "SKIP" ]] || { [[ "$badge" == "CACHE" ]] && [[ "${SHOW_CACHE:-false}" == "true" ]]; }; }; then
    printf "         reason: %s\n" "$reason_code"
fi
```

**This conditional currently renders reason only for SKIP/CACHE.** To surface `reason=timeout` for `FAIL` badges per D-14 ("Console badge: `FAIL  func_name  600s  (timeout)`"), extend the condition (in all three mode branches: `summary`, `tail`, `full`) to **also** print reason when `badge == "FAIL"`. The line-pattern stays the same — only the gate widens. Alternatively, render the reason inline on the badge line itself (right-side parenthetical, matching the FAIL example in CONVENTIONS.md §Output: `FAIL  sub_dns  7s  (see debug.log)`).

#### Conventions to preserve in `lib/parallel.sh`

- **Source-guard pattern at top of file** — `[[ -n "$_PARALLEL_SH_LOADED" ]] && return 0` at `:6` is preserved (no changes to the guard).
- **`PARALLEL_*` variable naming** — new knobs follow the convention: `PARALLEL_JOB_TIMEOUT_SECONDS`, `PARALLEL_KILL_GRACE_SECONDS` (UPPER_SNAKE_CASE, prefix-aligned with `PARALLEL_HEARTBEAT_SECONDS` at `:15`).
- **Default-via-parameter-expansion** — `local _to="${PARALLEL_JOB_TIMEOUT_SECONDS:-0}"` mirrors the existing `local hb="${PARALLEL_HEARTBEAT_SECONDS:-20}"` at `:433`. The integer-regex guard `[[ "$hb" =~ ^[0-9]+$ ]] && ((hb > 0))` at `:434` is the canonical "var must be a positive int" check — reuse it for `_to`.
- **Helper-name convention** — `_timeout_kill_job` is `_snake_case` private prefix, matching `_throttle_jobs`, `_parallel_live_break`, `_parallel_emit_job_output`, `_parallel_snapshot`.
- **`2>/dev/null || true`** for all `kill` calls (the target PID may have already exited between the check and the action). Already idiomatic — see `:443`, `:547`.
- **Two-loop symmetry** — any block added inside the batch-flush loop **must** be added to the final-wait loop. The two loops are structurally identical and the audit history (CONCERNS.md §parallel_funcs Batch Flushing) treats them as one logical pattern.
- **D-15 axiom uniformity** — the timeout kill operates on the local subshell PID; axiom-distributed jobs run inside that subshell as `axiom-scan` invocations, so killing the subshell signals `axiom-scan` which in turn signals remote nodes. No special-casing needed at the parallel layer.

---

### `reconftw.cfg` — DNS timeouts and new parallel knobs (Plan 01-03 / PERF-02 + RESIL-03)

**Role:** Configuration defaults. **Data flow:** Static declaration sourced once at startup.
**Analog:** Itself — `DNS_BRUTE_TIMEOUT` / `DNS_RESOLVE_TIMEOUT` at `:387-388` (the values that change) and `PARALLEL_HEARTBEAT_SECONDS` region (the new knobs are grouped beside it).

#### Existing DNS timeouts block (lines 387-389) — D-16 modification site

```bash
PERMUTATIONS_LIMIT=2147483648   # Bytes, default is 2 GB (prevents accidental disk exhaustion)
DNS_BRUTE_TIMEOUT=0             # timeout/gtimeout duration for DNS bruteforce (0 disables hard-timeout, e.g. 4h)
DNS_RESOLVE_TIMEOUT=0           # timeout/gtimeout duration for DNS resolve (0 disables hard-timeout, e.g. 6h)
DNS_HEARTBEAT_INTERVAL_SECONDS=20 # Progress heartbeat interval for long DNS jobs
```

**Modification (D-16):** Change the two default values in place. Note the existing comment example values (`e.g. 4h`, `e.g. 6h`) are **inverted** vs. CONTEXT.md D-16 (`DNS_BRUTE_TIMEOUT=6h`, `DNS_RESOLVE_TIMEOUT=4h`) — verify and align with CONTEXT.md authoritative values. Updated lines:

```bash
DNS_BRUTE_TIMEOUT=6h            # timeout/gtimeout duration for DNS bruteforce (0 disables hard-timeout)
DNS_RESOLVE_TIMEOUT=4h          # timeout/gtimeout duration for DNS resolve (0 disables hard-timeout)
```

Inline doc comment **must mention** that the non-zero default protects against hung resolvers (D-17 rationale).

#### Existing parallel knobs block (lines 302-312) — D-11/D-13 new-knob insertion site

```bash
# Parallelization
PARALLEL_MODE=true # Run independent functions in parallel (faster, uses more resources). Disable with --no-parallel or set false.
PERF_PROFILE="balanced" # Performance profile: low|balanced|max
CONTINUE_ON_TOOL_ERROR=true # Continue recon when a tool/module fails in parallel batches (set false for fail-fast).
PARALLEL_LOG_MODE="summary" # Parallel output mode: summary (compact) | tail (last N lines) | full (cat all)
PARALLEL_TAIL_LINES=20 # Number of tail lines shown per job in 'tail' mode (doubled on failure)
PARALLEL_UI_MODE="clean" # Parallel terminal UX: clean | balanced | trace
PARALLEL_PROGRESS_SHOW_ETA=true # Show ETA in live progress once estimate is stable
PARALLEL_PROGRESS_SHOW_ACTIVE=true # Show active tasks list in live parallel progress
PARALLEL_PROGRESS_COMPACT_ACTIVE_MAX=4 # Max active/done items shown before compacting with "+N more"
PARALLEL_TRACE_SLOW_SECONDS=30 # In balanced mode, show finished-line for jobs slower than this threshold
```

Note: `PARALLEL_HEARTBEAT_SECONDS` is defaulted only in `lib/parallel.sh:15` (not surfaced in `reconftw.cfg` today — that's a DOCS-01/Phase-5 concern). Per CONTEXT.md Integration Points: "parallel knobs should sit near `PARALLEL_HEARTBEAT_SECONDS` documentation" — interpret as: group the new knobs in this `# Parallelization` block, beside the existing `PARALLEL_*` declarations. Suggested insertion immediately after `PARALLEL_TRACE_SLOW_SECONDS` (line 312):

```bash
# Per-job timeout (D-11..D-14). Default 0 = disabled; suggested values:
#   3600 (1h) for long unattended scans, 600 (10min) for CI smoke runs.
# When set > 0, parallel_funcs heartbeat sends SIGTERM after the threshold
# and SIGKILL after PARALLEL_KILL_GRACE_SECONDS if the job ignores TERM.
PARALLEL_JOB_TIMEOUT_SECONDS=0
PARALLEL_KILL_GRACE_SECONDS=10 # Seconds between TERM and KILL when enforcing PARALLEL_JOB_TIMEOUT_SECONDS
```

#### Conventions to preserve in `reconftw.cfg`

- **Inline `#` comments** on every variable line — comment style is end-of-line (`VAR=value # doc`), not above-line. See every entry in this file.
- **Group by section header** — `# Parallelization`, `# Timeouts`, etc. New knobs go in the existing section that owns them.
- **No CLI flag for v1** — per CONTEXT.md §Established Patterns: "any new config knob (`PARALLEL_KILL_GRACE_SECONDS`) added in this phase does NOT need a CLI flag for v1". Skip the `CLI_*` re-apply pattern in `reconftw.sh`.
- **Suggested-values in doc comment** — per CONTEXT.md D-11: "doc comment in `reconftw.cfg` should list the recommended values explicitly (3600 for long scans, 600 for CI) but ship disabled". The multi-line `# Per-job timeout...` block above embeds those examples.
- **`0` as universal "disabled" sentinel** — matches existing convention (`DNS_BRUTE_TIMEOUT=0`, `WAF_PER_HOST_TIMEOUT=0`, `FFUF_RATELIMIT=0`).

---

## Shared Patterns

### Status badge vocabulary (locked)

**Source:** `lib/common.sh:467` (`_print_status`), `modules/core.sh:1485-1488` (`end_func` badge mapping), `lib/parallel.sh:203-227` (`_parallel_emit_job_output` badge resolution).
**Apply to:** All Phase 1 changes. **No new badge values introduced.**

| Concern | Badge | Reason key |
|---------|-------|------------|
| D-04 resume detection | `WARN` | `inprogress_leftover` |
| D-09 disk full abort | `FAIL` (via `_print_error`, not via `end_func`) | `disk_full` |
| D-14 timeout kill | `FAIL` | `timeout` |
| D-17 DNS hard timeout | `WARN` (from existing `end_func` path) | `dns_hard_timeout` |

### `log_json` event shape (locked)

**Source:** `modules/core.sh:680-709`. **Apply to:** All new structured-log events in this phase.

Canonical call:
```bash
log_json "<LEVEL>" "<function_name>" "<human_message>" "key1=value1" "key2=value2"
```

- Level: `INFO|WARN|ERROR|SUCCESS` (`modules/core.sh:712-725`).
- Function name: `${FUNCNAME[0]}` or `${FUNCNAME[1]:-main}` (mirror surrounding code).
- Always include a `reason=<snake_case>` key for non-INFO events (matches `.status_reason_<fn>` value convention).
- Body is no-op when `STRUCTURED_LOGGING != true` — safe to call unconditionally.

### Underscore-prefix-private helpers (locked)

**Source:** CONVENTIONS.md §Function Naming. **Apply to:** All new helpers in this phase.

| New helper | File | Sibling analog |
|------------|------|----------------|
| `_check_disk_mid_run` | `modules/utils.sh` | `check_disk_space` (`:421`) |
| `_abort_disk_full` | `modules/utils.sh` | (new, no analog; sits with `_check_disk_mid_run`) |
| `_cleanup_inprogress` | `modules/utils.sh` | `cleanup_on_exit` (`:116`) |
| `_timeout_kill_job` | `lib/parallel.sh` | `_throttle_jobs` (`:33`), `_parallel_emit_job_output` (`:172`) |
| `_print_resume_banner` *(optional)* | `lib/common.sh` or inline in `modules/modes.sh` | `_print_msg` / `_print_rule` |

### Subshell-not-pushd (locked)

**Source:** CONVENTIONS.md §Path and CWD. **Apply to:** Any new helper that needs a transient working directory.

```bash
# Correct:
( cd "${dir}" && _check_disk_mid_run )

# Forbidden:
pushd "${dir}"; _check_disk_mid_run; popd
```

(None of Phase 1's new helpers actually need a CWD change — `_check_disk_mid_run` calls `check_disk_space "$req" "${dir:-.}"` and the analog already accepts an explicit path argument. The subshell rule is enforced as a defensive guideline only.)

### `2>/dev/null || true` for filesystem fire-and-forget (locked)

**Source:** `modules/core.sh:1506` / `:1508`, `lib/parallel.sh:198` / `:202` / `:209`, `modules/utils.sh:32` (typical patterns). **Apply to:** All sentinel-create, sentinel-remove, kill, and status-write operations added in this phase. These ops must never abort the lifecycle even if they fail (e.g., the directory was already removed by a concurrent cleanup).

---

## No Analog Found

No files fall into this category. Every Phase 1 change has a direct sibling in the existing codebase.

---

## Metadata

**Analog search scope:** `modules/core.sh`, `modules/modes.sh`, `modules/utils.sh`, `lib/parallel.sh`, `lib/common.sh`, `reconftw.cfg`.
**Files scanned:** 6 (the 5 modified + `lib/common.sh` for `_print_*` helper sites).
**Key line ranges read:** `modules/core.sh:1410-1530, 675-727`; `modules/modes.sh:1-163, 285-300, 340-360, 780-800, 1240-1260`; `modules/utils.sh:108-170, 410-440, 1420-1500`; `lib/parallel.sh:1-50, 165-300, 390-620`; `reconftw.cfg:1-50, 300-400`.
**Pattern extraction date:** 2026-05-13.

## PATTERN MAPPING COMPLETE

Five existing files mapped to in-place insertion points with named sibling analogs, exact line anchors (`core.sh:1419/1437/1465/1505`, `modes.sh:13/78/118/140/152`, `utils.sh:421/1434`, `parallel.sh:172/432/537`, `reconftw.cfg:312/387`), and shared conventions (badge vocabulary, `log_json` shape, underscore-private helpers, subshell-not-pushd, `2>/dev/null || true`) — all driven by the existing reconFTW idioms with zero new badge values, no PID/timestamp staleness metadata, and no CLI flag additions.
