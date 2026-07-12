# Phase 1: Resilient Resume & Timeout Safety - Context

**Gathered:** 2026-05-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Long-running scans survive interruptions, disk pressure, and stuck tools without silently producing truncated output or wasting hours of re-work on resume. Three plans cover four v1 requirements:

- **01-01** — `.inprogress` sentinel lifecycle in `start_func`/`end_func` with resume detection (RESIL-01)
- **01-02** — Disk-full mid-run guard via periodic `df` check at function boundaries (RESIL-02)
- **01-03** — `PARALLEL_JOB_TIMEOUT_SECONDS` enforcement in `lib/parallel.sh` and DNS timeout defaults in `reconftw.cfg` (RESIL-03, PERF-02)

In scope: lifecycle wrappers in `modules/core.sh`, parallel job machinery in `lib/parallel.sh`, disk-space helper in `modules/utils.sh`, and the four config defaults in `reconftw.cfg`. Out of scope (deferred to other phases): the `MIN_DISK_SPACE_GB` 2-vs-5 discrepancy (DOCS-02, Phase 5), per-tool thread caps (PERF-01, Phase 3), and parallel-coverage tests for the new timeout/heartbeat paths (TEST-01, Phase 4).

</domain>

<decisions>
## Implementation Decisions

### `.inprogress` Sentinel Lifecycle (Plan 01-01, RESIL-01)

- **D-01:** Sentinel file is a plain empty `${called_fn_dir}/.inprogress_<fn>`. `start_func` `touch`es it; `end_func` removes it before `touch`ing the existing `.<fn>` success checkpoint. No JSON metadata, no PID, no timestamp inside.
- **D-02:** Staleness detection uses **clean-exit-gated trap cleanup**. `start()` in `modules/modes.sh` initialises a module-level `_RECON_CLEAN_EXIT=false` flag and installs a separate EXIT-only trap calling `_cleanup_inprogress`. The trap sweep is gated on `_RECON_CLEAN_EXIT=true`, which is set as the last executable statement of `end()` (the canonical workflow wrap-up). Clean traversals therefore leave NO `.inprogress_*` files. SIGINT/SIGTERM (via the separate `cleanup_on_exit` trap that calls `exit 130`) does NOT flip the flag, so the EXIT trap fires with `_RECON_CLEAN_EXIT=false` and the sentinels SURVIVE — the next run sees them and emits the WARN resume banner (CR-01 / SC1 fix). The single-operator-per-target constraint (PROJECT.md) makes this race-free: no concurrent shell can observe a different flag value for the same `called_fn_dir`.
- **D-03:** Rationale for the trap approach (vs PID, timestamp, or "PRESERVE wipes all"): the project is single-operator per target (PROJECT.md constraint), so we never race a concurrent run for the same `called_fn_dir`. That makes "anything still here = crashed previously" a safe inference and removes the need for PID liveness checks or staleness windows. PID schemes also break on PID recycling for long-running boxes.
- **D-04:** Resume report on detection — when one or more `.inprogress_*` files are found at `start()` time, emit **one summary line** at the top of the recon banner: `WARN  resume: N functions re-running after interruption (fn_a, fn_b)`. Then proceed silently — no per-function `RESUME` badges, no extra noise inside the module section. JSONL log gets `level=WARN func=resume reason=inprogress_leftover funcs=fn_a,fn_b`.
- **D-05:** `PRESERVE=false` (default) already clears `.<fn>` checkpoints before run start. Same loop must also clear any orphan `.inprogress_*` files so a `PRESERVE=false` run never reports a resume. With `PRESERVE=true`, the trap-cleanup + leftover-detection logic above is what makes resume work.
- **D-06:** Function re-execution on leftover is **transparent** — the existing checkpoint guard (`[[ ! -f "$called_fn_dir/.${FUNCNAME[0]}" ]] || [[ $DIFF == true ]]`) already re-runs functions whose `.<fn>` doesn't exist. Because a crashed function never reached `end_func`, its `.<fn>` is absent, so the guard naturally re-enters. The `.inprogress_*` file is purely for surface-level "what happened?" reporting; it does not drive control flow.

### Disk-Full Mid-Run Guard (Plan 01-02, RESIL-02)

- **D-07:** Check cadence is **at every `start_func` / `end_func` boundary**. New helper `_check_disk_mid_run` in `modules/utils.sh` (alongside existing `check_disk_space()`). `start_func` calls it BEFORE the existing body; `end_func` calls it AFTER touching the checkpoint. ~1ms per call × ~100 function boundaries per scan = negligible overhead. No background watcher process.
- **D-08:** Threshold is the **same `MIN_DISK_SPACE_GB`** used by the pre-flight check at `modules/modes.sh:23`. One source of truth. The Phase 5 DOCS-02 work (`reconftw.cfg:39` says `2`, `modes.sh:23` defaults to `5`) will resolve the discrepancy; Phase 1 does NOT touch that line and does NOT introduce a separate mid-run knob.
- **D-09:** Abort policy is **hard abort of the whole run**. `_check_disk_mid_run` returns non-zero → caller calls `_abort_disk_full` which emits `_print_error "disk_full: aborting (avail=${avail}GB, req=${MIN_DISK_SPACE_GB}GB at ${dir})"`, logs `log_json ERROR disk_full abort_run`, then `exit 1`. The Bash `EXIT` trap from D-02 fires on the way out, clearing all `.inprogress_*` (so a subsequent run does NOT see a fake resume condition). Soft-abort and pause-and-wait were both rejected — single-operator project, fail-fast is correct.
- **D-10:** ENOSPC detection mechanism is **boundary `df` only**. No `run_command` stderr scanning for `No space left on device`, no per-redirect failure traps. Acknowledged trade-off: a tool that exhausts disk inside a single function (e.g., `gotator` writing a 2GB wordlist) may produce truncated output for THAT function before the next boundary check catches it. The next `start_func` aborts the run before any further damage. Pre-flight 5GB margin + DOCS-02 alignment in Phase 5 make this a rare edge case; full per-write trapping is overengineered for v1.

### `PARALLEL_JOB_TIMEOUT_SECONDS` Enforcement (Plan 01-03, RESIL-03)

- **D-11:** Default value is **`PARALLEL_JOB_TIMEOUT_SECONDS=0`** (disabled, opt-in). Ships in `reconftw.cfg` with a doc comment explicitly suggesting `3600` for long scans and `600` for CI runs. Zero risk of an in-flight scan getting killed because the default was too aggressive. Backwards-compatible.
- **D-12:** Enforcement point is inside the existing **batch-flush heartbeat loop** in `lib/parallel.sh:432-465`. Today that loop polls `kill -0 ${batch_pids[$idx]}` every `PARALLEL_HEARTBEAT_SECONDS` (default 20s). Extend it: for each alive PID, compute `now - batch_starts[$idx]`; if `> PARALLEL_JOB_TIMEOUT_SECONDS` (and the var is `> 0`), call `_timeout_kill_job`.
- **D-13:** Kill behavior is **TERM then KILL after grace**. New knob `PARALLEL_KILL_GRACE_SECONDS=10` (also in `reconftw.cfg` with doc comment). `_timeout_kill_job` sends `kill -TERM $pid`, polls `kill -0 $pid` once per second up to the grace seconds, then `kill -KILL $pid` if still alive. Aligns with Unix shutdown semantics and protects against tools that ignore TERM.
- **D-14:** Reporting on timeout — the killed job's badge in `_parallel_emit_job_output` is **`FAIL`** with reason `timeout`. Persisted to `.status_<fn>` as `FAIL` and `.status_reason_<fn>` as `timeout` (reuses the existing pattern at `modules/core.sh:1505-1509`). `failed++` in the batch counter, so `RECON_PARTIAL_RUN=true` follows automatically via the existing aggregator. Console badge: `FAIL  func_name  600s  (timeout)`.
- **D-15:** Timeout applies to both **local and axiom-distributed** jobs — the parallel batch wrapper is the same code path for both. No special-casing.

### DNS Timeout Defaults (Plan 01-03, PERF-02)

- **D-16:** `reconftw.cfg:387-388` defaults change from `0` to:
  - `DNS_BRUTE_TIMEOUT=6h` (was `0`)
  - `DNS_RESOLVE_TIMEOUT=4h` (was `0`)
  Both already pass through `_run_dns_with_heartbeat` (`modules/utils.sh:1434`) which respects `0` (disabled) — non-zero hex/`h`-suffix values are honored by `timeout`/`gtimeout`. No code change to the helper, just the cfg defaults plus an inline doc comment.
- **D-17:** When the hard timeout trips, the existing `_run_dns_with_heartbeat` already returns non-zero and emits a clear log line. We add nothing new for surfacing the timeout — the existing badge path (`WARN` from `end_func`) is sufficient. JSONL log entry should carry `reason=dns_hard_timeout` so downstream tools (Phase 4 tests, AI report) can distinguish.

### Claude's Discretion

- Exact internal helper naming (`_check_disk_mid_run`, `_abort_disk_full`, `_timeout_kill_job`, `_cleanup_inprogress`) is a suggestion; planner may refine while keeping the underscore-prefix-for-private convention from CONVENTIONS.md.
- The JSONL log key/value spelling (`reason=inprogress_leftover`, `reason=timeout`, `reason=dns_hard_timeout`) follows the existing pattern at `modules/core.sh:1505-1509`. Researcher/planner may align with `STRUCTURED_LOGGING` schema if a more specific convention exists.
- How "summary line" (D-04) is printed exactly — most likely via existing `_print_msg WARN` or a new `_print_resume_banner` helper — is a planner-level rendering choice.
- Test coverage for the new code paths (`.inprogress_*` lifecycle, `_check_disk_mid_run`, timeout kill, DNS hard timeout) is OUT of scope for Phase 1 by design — Phase 4 (TEST-01) explicitly covers `parallel_funcs` timeout kill path. Planner should NOT add tests in this phase.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §"Phase 1: Resilient Resume & Timeout Safety" — phase goal, success criteria, 3 plans
- `.planning/REQUIREMENTS.md` §Resilience (RESIL-01, RESIL-02, RESIL-03) and §Performance (PERF-02) — the four v1 requirements this phase delivers

### Codebase intel (driving the changes)
- `.planning/codebase/CONCERNS.md` §"Checkpoint Files Not Created on Interrupted Runs" — drives RESIL-01 / Plan 01-01
- `.planning/codebase/CONCERNS.md` §"Disk-Full Detection Is Pre-Flight Only, Not Mid-Run" — drives RESIL-02 / Plan 01-02
- `.planning/codebase/CONCERNS.md` §"parallel_funcs Batch Flushing" — drives RESIL-03 / Plan 01-03
- `.planning/codebase/CONCERNS.md` §"DNS_BRUTE_TIMEOUT and DNS_RESOLVE_TIMEOUT Default to 0 (Disabled)" — drives PERF-02 / Plan 01-03

### Architectural and conventions (must align with)
- `.planning/codebase/ARCHITECTURE.md` §"Key Abstractions → start_func / end_func" and §"Function Execution Path" — lifecycle wrapper contract the sentinel work must preserve
- `.planning/codebase/CONVENTIONS.md` §"Function Lifecycle" and §"File Checkpointing" — checkpoint pattern, status badges (`OK/WARN/FAIL/SKIP/CACHE`), `_print_*` helpers, JSONL logging
- `.planning/codebase/CONVENTIONS.md` §"Path and CWD Conventions" and §"Parallel Execution" — subshells (no pushd/popd), `parallel_funcs` machinery

### Project constraints
- `.planning/PROJECT.md` §Constraints — single-operator constraint that makes D-02 trap-only staleness detection safe; macOS Bash 4+ re-exec requirement that `wait -n` and the timeout kill path depend on
- `CLAUDE.md` §Constraints — same single-process / shared-globals constraints applied at file scope

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`check_disk_space()` at `modules/utils.sh:421`** — already returns 0/1 and populates `DISK_SPACE_INFO`. The new `_check_disk_mid_run` wraps it with the new abort path (D-09); no need to re-implement `df` parsing.
- **`start_func`/`end_func` at `modules/core.sh:1419` and `:1437`** — existing parallel-safe per-function start timestamp (`_start_time_${fn}` variable) and `record_func_timing` calls remain; sentinel ops are inserted at the top of `start_func` (after the timestamp init) and inside `end_func` BEFORE the existing `touch "$called_fn_dir/.${fn}"` at line 1465.
- **`_run_dns_with_heartbeat` at `modules/utils.sh:1434`** — already respects `0=disabled` and accepts `timeout`/`gtimeout`-style duration arguments. No code change for DNS hard timeouts — only the `reconftw.cfg` defaults.
- **Heartbeat loop at `lib/parallel.sh:432-465`** — already iterates alive PIDs every `PARALLEL_HEARTBEAT_SECONDS`. Add the timeout kill check inside this loop (D-12).
- **Status persistence at `modules/core.sh:1505-1509`** — `.status_<fn>` and `.status_reason_<fn>` pattern already exists; timeout reporting (D-14) reuses it for `reason=timeout`.
- **`log_json` helper** — used throughout `start_func`/`end_func`; D-09, D-14, D-17 reuse the same call shape (`log_json LEVEL func msg key=val ...`).

### Established Patterns

- **Status badge vocabulary** is locked: `OK`, `WARN`, `FAIL`, `SKIP`, `CACHE`, `INFO`, `RUN` (CONVENTIONS.md). Timeout kill = `FAIL` (D-14), disk-full abort = `FAIL` (D-09), resume notice = `WARN` (D-04). No new badge values introduced.
- **Verbosity gating** — `OUTPUT_VERBOSITY=0/1/2` already governs which `_print_msg`/`notification` calls are visible. Resume summary line is `WARN`-level so it shows at default verbosity 1; disk-full error uses `_print_error` which is always visible.
- **CLI-over-config re-application** — any new config knob (`PARALLEL_KILL_GRACE_SECONDS`) added in this phase does NOT need a CLI flag for v1 (env-var/cfg override is sufficient). If a flag is added later, follow the `CLI_*` re-apply pattern at `reconftw.sh:513-578` per CONVENTIONS.md.
- **Source guards** — no new lib files in this phase; all changes go into existing `lib/parallel.sh`, `modules/core.sh`, `modules/utils.sh`, `modules/modes.sh`, `reconftw.cfg`. Source-guard pattern is preserved by editing existing files.

### Integration Points

- **`start()` in `modules/modes.sh:13`** — installs the EXIT/INT/TERM trap for `_cleanup_inprogress` (D-02), AND emits the resume-summary banner (D-04) before the first module begins. Also where the `PRESERVE=false` orphan-cleanup loop (D-05) lives.
- **Existing ERR trap in `start()` at `modules/modes.sh:140`** — the new EXIT trap must compose with it, not replace. Either chain (`trap` accepts multiple handlers per signal via single registered string) or refactor to a single `_recon_exit_hook` that calls both.
- **`reconftw.cfg`** — four config additions in this phase: `PARALLEL_JOB_TIMEOUT_SECONDS=0`, `PARALLEL_KILL_GRACE_SECONDS=10`, plus two value changes for `DNS_BRUTE_TIMEOUT=6h` and `DNS_RESOLVE_TIMEOUT=4h`. All grouped with surrounding context — DNS timeouts already at `:387-388`, parallel knobs should sit near `PARALLEL_HEARTBEAT_SECONDS` documentation.
- **No axiom changes** — timeout kill happens at the parent shell's `parallel_funcs` heartbeat level, before the per-job subshell. Axiom-distributed jobs invoked from inside a parallel batch are killed at the local subshell level (the `axiom-scan` command is terminated, which itself signals remote nodes — this is sufficient).

</code_context>

<specifics>
## Specific Ideas

- "Trap-on-exit cleanup" was chosen explicitly over PID-in-sentinel and timestamp-staleness alternatives because the single-operator constraint removes the only failure mode the alternatives addressed (concurrent runs sharing a `called_fn_dir`). Planner should NOT reintroduce PID/timestamp metadata "for safety" — the simpler design is the correct one given the constraint.
- Resume report format was chosen as a SINGLE banner line (D-04), not per-function `RESUME` badges. Planner should NOT decorate per-function output with extra resume context — keep `OK/WARN/FAIL/SKIP` badges as-is. The summary line is the only resume-specific UI.
- `PARALLEL_JOB_TIMEOUT_SECONDS=0` default (D-11) is deliberate. Do NOT propose a non-zero default. The doc comment in `reconftw.cfg` should list the recommended values explicitly (3600 for long scans, 600 for CI) but ship disabled.
- Boundary-only `df` checks (D-10) are an intentional simplicity decision. Planner should NOT add `run_command` stderr scanning for `No space left on device` or per-redirect ENOSPC traps in v1.

</specifics>

<deferred>
## Deferred Ideas

- **Per-tool timeout overrides** (e.g., `PARALLEL_TIMEOUT_DNS_BRUTE_SECONDS`) — discussed and rejected for v1. If users need it, they can tune `PARALLEL_JOB_TIMEOUT_SECONDS` upward to accommodate the slowest tool. Revisit only if real-world tuning needs surface.
- **Background heartbeat watcher for mid-function disk checks** — would catch a single function burning through disk before the next boundary fires. Rejected as overengineered for v1 given the 5GB pre-flight margin. Consider in a future "observability" milestone if telemetry shows truncated-output incidents.
- **Per-redirect ENOSPC trap wrapping every `>`/`>>`** — most thorough mid-function detection but intrusive across the entire codebase. Out of scope for v1.
- **`MIN_DISK_SPACE_GB` 2-vs-5 reconciliation** — explicitly Phase 5 (DOCS-02). Plan 01-02 deliberately does NOT touch `reconftw.cfg:39` or `modules/modes.sh:23`; we read whichever value is effective at runtime.
- **Tests for the new code paths** — Phase 4 (TEST-01) covers `parallel_funcs` timeout kill path. Sentinel-lifecycle and disk-full handling tests can join that same phase if the planner sees fit; Phase 1 ships behavior, Phase 4 ships coverage.

</deferred>

---

*Phase: 1-Resilient Resume & Timeout Safety*
*Context gathered: 2026-05-13*
