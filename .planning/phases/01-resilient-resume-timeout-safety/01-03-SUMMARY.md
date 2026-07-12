---
phase: 01-resilient-resume-timeout-safety
plan: 03
subsystem: infra
tags: [parallel, timeout, dns, signals, sigterm, sigkill, heartbeat, bash]

# Dependency graph
requires:
  - phase: 01-resilient-resume-timeout-safety
    provides: status-persistence pattern (.status_<fn> + .status_reason_<fn>) inherited from existing modules/core.sh end_func
provides:
  - "_timeout_kill_job helper in lib/parallel.sh: TERM-then-KILL with PARALLEL_KILL_GRACE_SECONDS grace; persists FAIL + reason=timeout to status files"
  - "Timeout enforcement inside both heartbeat loops (batch-flush + final-wait) in parallel_funcs; two-loop symmetry preserved"
  - "Widened reason-render conditional in _parallel_emit_job_output so FAIL badges also surface reason key (e.g. 'reason: timeout') in summary/tail/full modes"
  - "PARALLEL_JOB_TIMEOUT_SECONDS knob (default 0=disabled, opt-in) and PARALLEL_KILL_GRACE_SECONDS knob (default 10s) in reconftw.cfg with example values (3600 long scans, 600 CI)"
  - "Non-zero DNS_BRUTE_TIMEOUT=6h and DNS_RESOLVE_TIMEOUT=4h defaults so a hung resolver no longer blocks a run indefinitely"
  - "Kill-latency formula documented in reconftw.cfg: threshold + ~1s heartbeat poll cadence + PARALLEL_KILL_GRACE_SECONDS before SIGKILL"
affects: [01-01 (lifecycle sentinel work — same .status_<fn> pipeline), 04-test-coverage (TEST-01 will assert timeout-kill path), 05-config-docs (DOCS-01 followup for sibling helpers using bare function form)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Reuse-not-extend: timeout reporting reuses existing FAIL badge + .status_<fn>/.status_reason_<fn> files rather than introducing a new badge value"
    - "Two-loop symmetry: any block added to the batch-flush heartbeat must also be added to the final-wait heartbeat (and vice versa)"
    - "Helper naming gate: new lib/parallel.sh code uses canonical 'function name() {' form per CONVENTIONS.md even though sibling helpers omit it (in-file note flags them as Phase-5 DOCS-01 followup, not a precedent)"

key-files:
  created: []
  modified:
    - "lib/parallel.sh - new _timeout_kill_job helper + timeout check in both heartbeat loops + reason render widening"
    - "reconftw.cfg - DNS timeout defaults flipped to 6h/4h; PARALLEL_JOB_TIMEOUT_SECONDS + PARALLEL_KILL_GRACE_SECONDS added with doc comments"

key-decisions:
  - "Ship PARALLEL_JOB_TIMEOUT_SECONDS=0 (disabled by default, opt-in) per D-11 to preserve backwards compatibility; aggressive default would risk killing in-flight scans"
  - "Reuse existing FAIL/reason=timeout pipeline (modules/core.sh:1505-1509 pattern) rather than introducing a new badge value; widening _parallel_emit_job_output's reason gate is the only console-rendering change"
  - "No CLI flag for new knobs per CONTEXT §Established Patterns — env-var/cfg override is sufficient for v1"
  - "No code change to _run_dns_with_heartbeat (already accepts h-suffix durations); only cfg defaults flip"
  - "Document effective kill latency in cfg comment (threshold + ~1s heartbeat + PARALLEL_KILL_GRACE_SECONDS) so CI tuners set realistic deadlines"

patterns-established:
  - "TERM-then-KILL grace pattern with kill -0 poll loop (Unix-signal-correct shutdown semantics) — sibling _timeout_kill_job is reusable model for any future supervised-process kill"
  - "log_json call inside lib/parallel.sh helpers uses 'declare -F log_json >/dev/null 2>&1' guard since lib/ is sourced before modules/ at startup but runtime invocations come from inside modules where log_json is defined"
  - "FAIL badges in parallel_funcs may carry a reason_code (rendered as 'reason: <code>' in summary/tail/full); existing pattern was SKIP/CACHE only — now FAIL/timeout joins the same surface"

requirements-completed: [RESIL-03, PERF-02]

# Metrics
duration: 12min
completed: 2026-05-13
---

# Phase 01 Plan 03: PARALLEL_JOB_TIMEOUT_SECONDS + DNS Timeout Defaults Summary

**Stuck parallel jobs are now TERM/KILL-able via PARALLEL_JOB_TIMEOUT_SECONDS (opt-in), and DNS_BRUTE_TIMEOUT=6h / DNS_RESOLVE_TIMEOUT=4h defaults stop hung resolvers from blocking a run indefinitely.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-05-13T08:57:40Z (worktree agent spawn)
- **Completed:** 2026-05-13 (this commit)
- **Tasks:** 2 (both auto-type)
- **Files modified:** 2

## Accomplishments

- New `_timeout_kill_job` helper in `lib/parallel.sh`: SIGTERM, polls `kill -0` once per second up to `PARALLEL_KILL_GRACE_SECONDS`, then SIGKILL if still alive — persists `FAIL` + `reason=timeout` to the existing `.status_<fn>` / `.status_reason_<fn>` files end_func uses
- Timeout check inserted in BOTH heartbeat loops (batch-flush at `lib/parallel.sh:443` neighbourhood and final-wait at `:547` neighbourhood) — two-loop symmetry preserved; existing `job_dur` computation reused
- `_parallel_emit_job_output` reason-render conditional widened in all three branches (summary, tail, full) to also fire on `badge == "FAIL"` so timeout reasons surface as `reason: timeout` lines on the console
- `PARALLEL_JOB_TIMEOUT_SECONDS=0` (disabled by default, opt-in) and `PARALLEL_KILL_GRACE_SECONDS=10` added to `reconftw.cfg` with doc comment listing `3600` (long scans) / `600` (CI) examples plus explicit kill-latency formula
- `DNS_BRUTE_TIMEOUT=6h` and `DNS_RESOLVE_TIMEOUT=4h` (was `0=disabled`) ship as the new defaults — `_run_dns_with_heartbeat` already accepts `h`-suffix durations via `timeout`/`gtimeout`, so zero code change there

## Task Commits

Each task was committed atomically:

1. **Task 1: _timeout_kill_job helper + timeout enforcement in both heartbeat loops** — `de0aea13` (feat)
2. **Task 2: Update reconftw.cfg — DNS timeout defaults + two new parallel knobs** — `b70b3ad1` (feat)

Plan metadata (this SUMMARY) commit follows separately per execute-plan.md.

## Files Created/Modified

- `lib/parallel.sh` — Added `_timeout_kill_job` between `_throttle_jobs` and `_parallel_live_break`; inserted timeout-check inside both heartbeat loops; widened reason-render conditional in summary/tail/full branches to surface FAIL reason
- `reconftw.cfg` — Flipped `DNS_BRUTE_TIMEOUT=0`→`6h` and `DNS_RESOLVE_TIMEOUT=0`→`4h`; appended `PARALLEL_JOB_TIMEOUT_SECONDS=0` and `PARALLEL_KILL_GRACE_SECONDS=10` block after `PARALLEL_TRACE_SLOW_SECONDS` with doc comment (recommended values + kill-latency formula)

## Decisions Made

- Used canonical `function _timeout_kill_job() {` form per CONVENTIONS.md §Function Naming; added in-file note marking sibling helpers (`_throttle_jobs`, `_parallel_live_break`, etc.) that omit the keyword as a Phase 5 DOCS-01 followup, not a precedent
- Guarded the `log_json` call with `declare -F log_json >/dev/null 2>&1` since `lib/parallel.sh` is sourced before `modules/core.sh` at startup. At runtime when `parallel_funcs` is invoked from inside a module function, `log_json` is already defined; the guard makes the helper robust to ordering edge cases (e.g., test scaffolds that source only `lib/`)
- Did not modify `_parallel_emit_job_output`'s `case "$badge" in OK|WARN|FAIL|SKIP|CACHE|INFO` whitelist — `FAIL` is already accepted (line 206), so the timeout status persists cleanly through the existing read path

## Deviations from Plan

None — plan executed exactly as written. All `must_haves.truths`, `acceptance_criteria`, and `success_criteria` verified.

Auto-fixes applied during execution: none (no bugs, no missing functionality, no blocking issues encountered).

## Issues Encountered

- The plan's acceptance-criteria grep patterns include double-escaped backslashes (`printf "FAIL\\\\n"`) that don't match cleanly under `grep` regex. Verified the intent with `grep -F` (fixed-string) instead — both `printf "FAIL\n"` and `printf "timeout\n"` writes are present and correct. The actual file content matches the plan's explicit specification (`printf "FAIL\n" >".../.status_${func_name}"`).

## User Setup Required

None — both new knobs ship with safe defaults (`PARALLEL_JOB_TIMEOUT_SECONDS=0` is disabled; `DNS_*_TIMEOUT=Xh` durations were already supported by `_run_dns_with_heartbeat` and apply transparently). Opt-in tuning happens by editing `reconftw.cfg` or exporting the env vars.

## Next Phase Readiness

- RESIL-03 and PERF-02 requirements closed; both v1 success criteria satisfied (parallel_funcs kills timeouts via SIGTERM with grace; DNS resolvers no longer block indefinitely)
- Phase 4 (TEST-01) will assert the timeout-kill path — the status persistence contract (`.status_<fn>=FAIL` + `.status_reason_<fn>=timeout`) and FAIL-reason rendering are the surfaces those tests need
- Phase 5 (DOCS-01) followup: align sibling helpers in `lib/parallel.sh` (and similar files) to the canonical `function name() {` form; the in-file note flags this explicitly
- No blockers for downstream phases

## Self-Check: PASSED

- FOUND: lib/parallel.sh
- FOUND: reconftw.cfg
- FOUND: .planning/phases/01-resilient-resume-timeout-safety/01-03-SUMMARY.md
- FOUND: de0aea13 (Task 1 commit)
- FOUND: b70b3ad1 (Task 2 commit)

All claimed files exist; all claimed commits are in git history. `bash -n` and `shellcheck --severity=error` both exit 0 on `lib/parallel.sh` and `reconftw.cfg`. Behavior smoke test for `_timeout_kill_job` confirmed: a spawned `sleep 30` process is killed within `grace+1s`, and `.status_my_slow_func` contains `FAIL`, `.status_reason_my_slow_func` contains `timeout`. Sourcing `reconftw.cfg` exports exactly `6h 4h 0 10` for the four affected vars.

---
*Phase: 01-resilient-resume-timeout-safety*
*Completed: 2026-05-13*
