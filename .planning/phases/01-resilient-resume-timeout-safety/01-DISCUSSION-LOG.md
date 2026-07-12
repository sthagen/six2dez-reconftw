# Phase 1: Resilient Resume & Timeout Safety - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-13
**Phase:** 1-Resilient Resume & Timeout Safety
**Areas discussed:** Stale `.inprogress_*` cleanup policy, Disk-full check cadence + threshold, Disk-full abort policy + ENOSPC trap mechanism, `PARALLEL_JOB_TIMEOUT_SECONDS` default + kill behavior

---

## Stale `.inprogress_*` cleanup policy

### Recognition mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Trap-on-exit cleanup | Sentinel = empty file. `start()` installs EXIT/INT/TERM trap that clears all `.inprogress_*` on graceful exit. Leftover next time = previous crash = re-run. | ✓ |
| PID + hostname in sentinel content | Sentinel contains `PID HOST start_ts`. Check `kill -0 PID` on resume; if dead or host differs = stale. | |
| Timestamp-based staleness window | Sentinel content is start_ts. Older than `INPROGRESS_STALE_HOURS` (default 24h) = stale. | |
| PRESERVE=false wipes everything | Don't detect staleness. Trust `PRESERVE=false` to clear all state; `.inprogress_*` presence always means re-run with `PRESERVE=true`. | |

**User's choice:** Trap-on-exit cleanup
**Notes:** Aligns with single-operator constraint from PROJECT.md — no concurrent runs to disambiguate. PID schemes break on long-running boxes with PID recycling; timestamp staleness windows misfire on legitimately long DNS brute runs. Simplest correct design wins.

### Resume report verbosity

| Option | Description | Selected |
|--------|-------------|----------|
| Summary line at recon start | One `WARN  resume: N functions re-running after interruption (...)` line at the top of the banner; then silent. | ✓ |
| Per-function `RESUME` badge | Emit a `RESUME` badge alongside `OK/WARN/FAIL` each time an interrupted function re-enters. | |
| Silent re-run, JSONL only | No terminal output; just log `resume=true reason=inprogress_leftover` to JSONL. | |

**User's choice:** Summary line at recon start
**Notes:** Existing `OK/WARN/FAIL/SKIP/CACHE` badge vocabulary stays untouched. Resume context is announced once, not interleaved with module output.

---

## Disk-full check cadence + threshold

### Check cadence

| Option | Description | Selected |
|--------|-------------|----------|
| At every `start_func` / `end_func` boundary | Cheap `df` per function entry/exit; ~100 calls per scan, no background process. | ✓ |
| Background heartbeat (every N seconds) | Long-lived background subshell loops every `DISK_CHECK_INTERVAL_SECONDS`. Catches mid-function pressure. | |
| Only inside known long loops (explicit insertion) | Manually wire `_check_disk_mid_run` into `sub_brute`, DNS heartbeat helpers, gotator/regulator batches. | |
| Hybrid: boundary + parallel heartbeat | Boundary checks for serial path + tie into existing `parallel_funcs` heartbeat for concurrent jobs. | |

**User's choice:** At every `start_func` / `end_func` boundary
**Notes:** Cheap, deterministic, no extra process lifetime to manage. Composes cleanly with the lifecycle wrapper changes from Plan 01-01.

### Threshold

| Option | Description | Selected |
|--------|-------------|----------|
| Same `MIN_DISK_SPACE_GB` as pre-flight | Reuse the existing knob. One source of truth. | ✓ |
| Separate `MIN_DISK_SPACE_MID_RUN_GB` knob | Tighter mid-run knob (default 1GB) on top of the pre-flight gate. | |
| Percentage of initial free (relative) | Capture free at `start()`, abort if drops below 10% of that. | |

**User's choice:** Same `MIN_DISK_SPACE_GB`
**Notes:** Phase 5 (DOCS-02) resolves the 2-vs-5 cfg-vs-modes.sh mismatch separately; Phase 1 does not touch that lever.

---

## Disk-full abort policy + ENOSPC trap mechanism

### Abort policy

| Option | Description | Selected |
|--------|-------------|----------|
| Hard abort whole run with clear ENOSPC error | First detection → emit FAIL line, `exit 1`. EXIT trap clears `.inprogress_*` on the way out. | ✓ |
| Soft abort: skip current module, continue | Mark current function FAIL, let `recon()` continue. Risk: subsequent modules can truncate too. | |
| Pause-and-wait | Block in `_check_disk_mid_run` until disk frees; poll every 30s. Looks frozen interactively. | |

**User's choice:** Hard abort whole run with clear ENOSPC error
**Notes:** Matches RESIL-02 success criterion verbatim ("aborts with a clear `ENOSPC` error message rather than producing zero-byte or truncated output files"). Single-operator project, fail-fast is correct.

### Detection mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| `df` boundary check only | Trust the `start_func`/`end_func` `df` check. Single-function truncation accepted as edge-case trade-off. | ✓ |
| `df` boundary check + `run_command` stderr scan | Add grep for `No space left on device` in `run_command`. Catches mid-function failures one tool invocation later. | |
| Bash EXIT trap + write-failure detection on all redirects | Wrap every `>`/`>>`; thorough but intrusive across `modules/*.sh`. | |

**User's choice:** `df` boundary check only
**Notes:** Acknowledged trade-off documented in CONTEXT.md D-10 — a function that exhausts disk inside a single tool invocation can still produce truncated output before the next boundary check. Pre-flight 5GB margin makes this a rare edge case; per-redirect trapping is overengineered for v1.

---

## `PARALLEL_JOB_TIMEOUT_SECONDS` default + kill behavior

### Default value

| Option | Description | Selected |
|--------|-------------|----------|
| `0` (disabled, opt-in only) | Default behavior unchanged. Doc comment lists recommended values (3600 / 600). | ✓ |
| `3600` (1 hour) | Generous; most legitimate functions finish in minutes. Risk: a >1h DNS brute gets killed. | |
| `14400` (4 hours) | Aligns with `DNS_RESOLVE_TIMEOUT=4h`. Conservative. | |

**User's choice:** `0` (disabled, opt-in only)
**Notes:** Zero risk of an in-flight scan being killed because the default was too aggressive. Backwards-compatible. Mechanism still ships and is tested for the success criterion (`PARALLEL_JOB_TIMEOUT_SECONDS=600` kills jobs >10 min).

### Kill behavior

| Option | Description | Selected |
|--------|-------------|----------|
| TERM then KILL after 10s grace | `kill -TERM`, poll alive once/sec up to `PARALLEL_KILL_GRACE_SECONDS=10`, escalate to `KILL`. Badge `FAIL` with `reason=timeout`. | ✓ |
| TERM only | Strict to the requirement. Tools ignoring TERM stay around until `wait` reaps. | |
| TERM + WARN badge (not FAIL) | Same kill mechanism; badge as `WARN` since timeout is a configured limit being respected. | |

**User's choice:** TERM then KILL after 10s grace
**Notes:** Aligns with Unix shutdown semantics. `FAIL` badge with `reason=timeout` reuses the existing `.status_<fn>` / `.status_reason_<fn>` persistence pattern (`modules/core.sh:1505-1509`). `RECON_PARTIAL_RUN=true` follows automatically from `failed++`.

---

## Claude's Discretion

- Exact internal helper naming (`_check_disk_mid_run`, `_abort_disk_full`, `_timeout_kill_job`, `_cleanup_inprogress`) — suggested in CONTEXT.md; planner may refine while keeping the underscore-prefix-for-private convention.
- JSONL log key/value spelling for new reasons (`inprogress_leftover`, `timeout`, `dns_hard_timeout`) — aligns with the existing `reason_code` pattern; planner may adjust if a more specific schema exists under `STRUCTURED_LOGGING`.
- Whether the resume-summary banner uses an existing `_print_msg WARN` call or a new `_print_resume_banner` helper — planner-level rendering choice.

## Deferred Ideas

- Per-tool timeout overrides (`PARALLEL_TIMEOUT_DNS_BRUTE_SECONDS`, etc.) — rejected for v1; users tune `PARALLEL_JOB_TIMEOUT_SECONDS` upward to accommodate the slowest tool.
- Background heartbeat watcher for mid-function disk checks — rejected as overengineered for v1; pre-flight 5GB margin covers the common case. Revisit if telemetry shows truncated-output incidents.
- Per-redirect ENOSPC trap wrapping every `>`/`>>` — most thorough but intrusive; out of scope for v1.
- `MIN_DISK_SPACE_GB` 2-vs-5 reconciliation — explicitly Phase 5 (DOCS-02); Phase 1 does not touch `reconftw.cfg:39` or `modules/modes.sh:23`.
- Test coverage for the new code paths (sentinel lifecycle, `_check_disk_mid_run`, timeout kill, DNS hard timeout) — Phase 4 (TEST-01) covers `parallel_funcs` timeout kill explicitly; planner may extend coverage there if appropriate.
