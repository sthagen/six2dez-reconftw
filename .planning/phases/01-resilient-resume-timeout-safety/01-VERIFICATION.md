---
phase: 01-resilient-resume-timeout-safety
verified: 2026-05-13T13:30:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 2/4
  gaps_closed:
    - "SC1: .inprogress_<fn> indicator preserved on SIGINT/SIGTERM (CR-01 / Gap A closed by Plan 01-04)"
    - "SC3 defect #1: PARALLEL_JOB_TIMEOUT_SECONDS now fires under --quiet (CR-02 / Gap B closed by Plan 01-05)"
    - "SC3 defect #2: _timeout_kill_job now signals the entire process tree, not just the wrapper subshell (CR-03 / Gap C closed by Plan 01-05)"
  gaps_remaining: []
  regressions: []
deferred:
  - truth: "Unit tests cover the new .inprogress_<fn> lifecycle / _check_disk_mid_run / timeout-kill paths"
    addressed_in: "Phase 4"
    evidence: "Phase 4 Goal: 'Test Coverage Reinforcement — parallel_funcs batch behaviour, mocked end-to-end pipeline, axiom failover'. Phase 4 SC1 explicitly names 'the new PARALLEL_JOB_TIMEOUT_SECONDS kill path'. CONTEXT.md §Claude's Discretion: 'Test coverage for the new code paths (.inprogress_* lifecycle, _check_disk_mid_run, timeout kill, DNS hard timeout) is OUT of scope for Phase 1 by design.'"
  - truth: "MIN_DISK_SPACE_GB 2-vs-5 reconciliation between reconftw.cfg:39 (=2) and modules/modes.sh:23 (defaults :-5)"
    addressed_in: "Phase 5"
    evidence: "REQUIREMENTS.md DOCS-02 maps to Phase 5. Roadmap Phase 5 SC2: 'MIN_DISK_SPACE_GB has a single source of truth — either reconftw.cfg:39 lifts to 5 to match modes.sh, or modes.sh:23 drops the :-5 fallback.'"
human_verification:
  - test: "End-to-end resume on real Ctrl+C interruption"
    expected: "Run ./reconftw.sh -d <safe-domain> -r --parallel against a target known to take >30s in sub_brute. Press Ctrl+C mid-sub_brute. Re-run with PRESERVE=true (default). The WARN banner 'resume: 1 functions re-running after interruption (sub_brute)' should appear at the top and only sub_brute should re-execute; completed prior functions retain their .<fn> checkpoints. Post-CR-01 fix, the EXIT trap no longer wipes the sentinel because _RECON_CLEAN_EXIT remains false on the SIGINT path."
    why_human: "Requires a multi-minute real recon run with a real SIGINT — not safely automatable in this verification context. Code-path correctness already confirmed by behavioral smoke (see Spot-Check #6 below)."
  - test: "Timeout-kill under --quiet on a real long-running tool (e.g., puredns)"
    expected: "Set PARALLEL_JOB_TIMEOUT_SECONDS=600 in reconftw.cfg and run ./reconftw.sh --quiet -d <target> -r. A stuck parallel_funcs child should be killed at the 600s mark with FAIL + reason=timeout persisted. Post-CR-02 fix, the timeout-enforcement gate is decoupled from OUTPUT_VERBOSITY so the kill fires under --quiet. Synthetic-tool smoke confirms code path; real-tool wallclock confirmation requires a 10+ minute run."
    why_human: "Behavioral confirmation against a real external tool inside a real parallel batch — not automatable in a fast verification."
  - test: "Process-tree kill on a real tool with descendants (e.g., puredns + massdns)"
    expected: "With PARALLEL_JOB_TIMEOUT_SECONDS=10 and a real puredns bruteforce, monitor `ps` during and after the 10s timeout fires. Both the wrapper subshell AND the underlying puredns/massdns processes should terminate within PARALLEL_KILL_GRACE_SECONDS. Post-CR-03 fix, _kill_tree walks pgrep -P descendants children-first so the actual external tool dies, not just the wrapper. Synthetic two-level subshell+sleep smoke confirms recursion; real-tool process-table confirmation needs human eyes."
    why_human: "Requires monitoring `ps` while a timeout fires on a real external tool inside a real parallel batch — not safely automatable."
---

# Phase 01: Resilient Resume & Timeout Safety — Verification Report (Re-verification)

**Phase Goal:** Long-running scans survive interruptions, disk pressure, and stuck tools without silently producing truncated output or wasting hours of re-work on resume.
**Verified:** 2026-05-13T13:30:00Z
**Status:** passed
**Re-verification:** Yes — after gap closure plans 01-04 (CR-01) and 01-05 (CR-02, CR-03) landed

## Re-verification Context

Initial verification on 2026-05-13T10:02:41Z returned `gaps_found` with score 2/4: SC1 PARTIAL (CR-01) and SC3 PARTIAL (CR-02 + CR-03). Two targeted gap-closure plans were landed:

- **Plan 01-04** (commits `5fbbbf1d`, `79967d71`, `17ae1e17`) — introduced `_RECON_CLEAN_EXIT` flag, gated `_cleanup_inprogress` on it, flipped the flag at the end of `end()`. Closes CR-01.
- **Plan 01-05** (commits `d9a5a01a`, `3ad3bdf0`) — decoupled the heartbeat-loop verbosity gate from the timeout-enforcement gate; added `_kill_tree` helper; refactored `_timeout_kill_job` to walk the process tree via `pgrep -P`. Closes CR-02 and CR-03.

All three CR fixes were re-verified against the codebase and confirmed working via behavioral smokes.

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                                                                                                                                                          | Status     | Evidence                                                                                                                                                                                                                                                                                |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Interrupting recon mid-sub_brute and re-running with PRESERVE=true produces a clear .inprogress_sub_brute indicator AND re-executes only that function — completed functions retain .<func> checkpoints and are skipped     | VERIFIED   | Both halves now hold. (a) Indicator: `_RECON_CLEAN_EXIT=false` at modes.sh:16; `_cleanup_inprogress` gated at utils.sh:154; flag flipped to true only at end()'s last statement (modes.sh:517). SIGINT smoke (`/tmp/sc1_final.sh`) shows `.inprogress_sub_brute` SURVIVES SIGINT. (b) Re-run via existing checkpoint guard (.<fn> never written on crash). |
| 2   | A scan that exhausts disk space mid-run aborts with a clear ENOSPC error message rather than producing zero-byte or truncated output files                                                                                   | VERIFIED   | `_check_disk_mid_run` at modules/utils.sh:450 (boundary calls at core.sh start_func:1422 and end_func:1553); `_abort_disk_full` at utils.sh:456 emits `[FAIL] disk_full: aborting (...)` to stderr, JSONL `reason=disk_full`, then `exit 1`. Empirical smoke: rc=1 with `MIN_DISK_SPACE_GB=99999999`. |
| 3   | Setting PARALLEL_JOB_TIMEOUT_SECONDS=600 terminates any single parallel_funcs child exceeding 10 minutes via kill -TERM, allowing the batch to continue                                                                       | VERIFIED   | Both defects closed. (a) CR-02: heartbeat loop gate at parallel.sh:508 and :629 now `_loop_active && (_verbose_progress || _to > 0)` — timeout fires under --quiet. (b) CR-03: `_timeout_kill_job` calls `_kill_tree $pid TERM/KILL` at parallel.sh:87/93; `_kill_tree` at :55 walks `pgrep -P` descendants children-first. Smokes: `--quiet` job killed in 5s; inner sleep 30 dead alongside wrapper. |
| 4   | Fresh installs of reconftw.cfg ship with non-zero DNS_BRUTE_TIMEOUT=6h and DNS_RESOLVE_TIMEOUT=4h defaults, and a stuck DNS run aborts with a logged timeout rather than blocking indefinitely                              | VERIFIED   | reconftw.cfg:394 `DNS_BRUTE_TIMEOUT=6h`, :395 `DNS_RESOLVE_TIMEOUT=4h`. `_dns_timeout_enabled` at utils.sh:1418 treats both as enabled. `_run_dns_with_heartbeat` at :1458 wraps with `$TIMEOUT_CMD -k 10s $timeout_value` when enabled. Sourcing cfg confirms exact values.            |

**Score:** 4/4 truths verified

### Deferred Items

Items not yet met but explicitly addressed in later milestone phases. Filtered against ROADMAP.md Phase 4 + Phase 5 success criteria.

| # | Item                                                                                                                            | Addressed In | Evidence                                                                                                              |
|---|-------------------------------------------------------------------------------------------------------------------------------|--------------|---------------------------------------------------------------------------------------------------------------------|
| 1 | Unit tests cover the new .inprogress_<fn> lifecycle / _check_disk_mid_run / timeout-kill paths                                  | Phase 4      | TEST-01 covers `parallel_funcs batch behaviour` including `the new PARALLEL_JOB_TIMEOUT_SECONDS kill path` (SC1).   |
| 2 | MIN_DISK_SPACE_GB 2-vs-5 reconciliation between reconftw.cfg:39 (=2) and modules/modes.sh:23 (defaults :-5)                     | Phase 5      | DOCS-02 → Phase 5 SC2: "MIN_DISK_SPACE_GB has a single source of truth."                                            |

### Required Artifacts

| Artifact                | Expected                                                                                                                              | Status     | Details                                                                                                                                                                                          |
|-------------------------|----------------------------------------------------------------------------------------------------------------------------------------|------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `modules/core.sh`       | start_func touches `.inprogress_<fn>`; end_func removes it before touching `.<fn>`; both boundaries call `_check_disk_mid_run || _abort_disk_full`; sentinel comment block updated to reflect gated-trap semantics | VERIFIED   | start_func at :1419 — disk check :1422, sentinel touch :1438. end_func at :1449 — sentinel rm :1483, checkpoint touch :1485, disk check :1553. Comment block at :1431-1436 updated to reference `_RECON_CLEAN_EXIT=true`, CR-01, and SC1 fix. Misleading "EXIT trap clears it on graceful exit" phrasing fully removed (grep returns 0). |
| `modules/utils.sh`      | `_cleanup_inprogress` gated on `_RECON_CLEAN_EXIT`; `cleanup_on_exit` UNCHANGED; `_check_disk_mid_run`/`_abort_disk_full` helpers | VERIFIED   | `_cleanup_inprogress` at :153 — gate `[[ "${_RECON_CLEAN_EXIT:-false}" == "true" ]] || return 0` at :154, then `rm -f` at :155. `cleanup_on_exit` at :116-146 UNCHANGED: still prints "Interrupted. Cleaning up..." and exits with `exit "$exit_code"`. `_check_disk_mid_run` at :450, `_abort_disk_full` at :456. |
| `modules/modes.sh`      | `_RECON_CLEAN_EXIT=false` init at top of start(); separate EXIT-only trap; FORCE_RESCAN orphan clear; resume banner emission; `_RECON_CLEAN_EXIT=true` flip at end of end() | VERIFIED   | start() :16 — `_RECON_CLEAN_EXIT=false` between `global_start` (:15) and `set +m` (:17). Trap install at :122 (INT/TERM) and :123 (EXIT). FORCE_RESCAN orphan clear at :83. Resume banner :167-182. end() at :313, flag flip at :517 as last executable statement before closing brace at :518. |
| `lib/parallel.sh`       | `_timeout_kill_job` helper; `_kill_tree` helper walking pgrep -P descendants; decoupled gate in BOTH heartbeat loops; FAIL reason render widened | VERIFIED   | `_kill_tree` at :55 with children-first recursion and `command -v pgrep` graceful degradation. `_timeout_kill_job` at :77 calls `_kill_tree $pid TERM` at :87 and `_kill_tree $pid KILL` at :93. Both heartbeat loops (batch-flush :495-544 and final-wait :616-665) have hoisted `_to`/`_verbose_progress`/`_loop_active` locals and the decoupled compound gate. FAIL reason render widened in `_parallel_emit_job_output`. |
| `reconftw.cfg`          | DNS timeouts non-zero; two PARALLEL knobs; doc comments                                                                              | VERIFIED   | `MIN_DISK_SPACE_GB=2` (:39), `PARALLEL_JOB_TIMEOUT_SECONDS=0` (:318), `PARALLEL_KILL_GRACE_SECONDS=10` (:319), `DNS_BRUTE_TIMEOUT=6h` (:394), `DNS_RESOLVE_TIMEOUT=4h` (:395). Doc comments for 3600/600 examples + kill-latency note retained. |
| `01-CONTEXT.md` D-02    | Body reworded to match implemented gated-trap semantics                                                                              | VERIFIED   | D-02 now reads "Staleness detection uses clean-exit-gated trap cleanup..." references `_RECON_CLEAN_EXIT=false` init, `_RECON_CLEAN_EXIT=true` flip in end(), SIGINT/SIGTERM preserving sentinels for resume banner. Decision ID preserved; only body wording changed. D-01 and D-03..D-17 unchanged (each appears exactly once). |

### Key Link Verification

| From                                       | To                                                | Via                                                                                                  | Status      | Details                                                                                                                                                                                                |
|--------------------------------------------|---------------------------------------------------|------------------------------------------------------------------------------------------------------|-------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| modules/core.sh:start_func                 | $called_fn_dir/.inprogress_<fn>                   | `touch` guarded by `[[ -n "${called_fn_dir:-}" ]]`                                                  | WIRED       | Line 1438. Empirical smoke (`/tmp/sc1_final.sh`) confirms file is created.                                                                                                                              |
| modules/core.sh:end_func                   | $called_fn_dir/.inprogress_<fn>                   | `rm -f` BEFORE existing `touch .<fn>`                                                               | WIRED       | rm at :1483 precedes checkpoint touch at :1485.                                                                                                                                                         |
| modules/modes.sh:start()                   | _cleanup_inprogress (gated)                       | `trap '_cleanup_inprogress' EXIT` immediately after INT/TERM trap; flag-gated body                  | WIRED       | Line 123. Trap fires on EXIT but body returns early when `_RECON_CLEAN_EXIT=false`. Empirical SIGINT smoke confirms sentinel survives (was the CR-01 inversion test).                                  |
| modules/modes.sh:end()                     | `_RECON_CLEAN_EXIT=true`                          | Last executable statement before closing brace                                                       | WIRED       | Line 517 — flag flips at the end of every clean traversal of end(). Clean-exit smoke (`/tmp/clean_recheck.sh`) confirms sentinel swept on clean exit.                                                  |
| lib/parallel.sh heartbeat (batch-flush)    | _timeout_kill_job                                 | `_loop_active && (_verbose_progress || _to > 0)` → unconditional `(( _to > 0 )) && (( job_dur > _to ))` | WIRED       | Lines 508 (gate), 522-524 (enforcement). Empirical `/tmp/quiet_timeout.sh` smoke confirms job killed in 5s under OUTPUT_VERBOSITY=0.                                                                  |
| lib/parallel.sh heartbeat (final-wait)     | _timeout_kill_job                                 | identical decoupled gate                                                                             | WIRED       | Lines 629 (gate), 643-645 (enforcement). Two-loop symmetry preserved.                                                                                                                                  |
| _timeout_kill_job                          | _kill_tree                                        | `_kill_tree $pid TERM` then poll then `_kill_tree $pid KILL`                                        | WIRED       | Lines 87 (TERM), 93 (KILL). Empirical `/tmp/inner_kill.sh` smoke confirms inner `sleep 30` is dead after wrapper kill.                                                                                |
| _kill_tree                                 | descendants                                       | `pgrep -P` children-first recursion, fallback `command -v pgrep`                                    | WIRED       | Lines 55-66. Children-first ordering at :60-63 before parent kill at :65.                                                                                                                              |
| _timeout_kill_job                          | $called_fn_dir/.status_<fn> + .status_reason_<fn> | printf FAIL + printf timeout                                                                         | WIRED       | Lines 97-98. Files written then consumed by `_parallel_emit_job_output` :266-272/:286-288 to render FAIL badge with "reason: timeout".                                                                |
| _abort_disk_full                           | exit 1                                            | after _print_error + log_json                                                                        | WIRED       | Line 459. Empirical smoke confirms rc=1 with stderr `[FAIL] disk_full: aborting`.                                                                                                                       |
| modules/modes.sh FORCE_RESCAN block        | .inprogress_* orphan removal                      | explicit `rm -f` after the existing `.*` wipe                                                        | WIRED       | Lines 80, 83. Empirical smoke confirms both checkpoints and sentinels wiped when FORCE_RESCAN=true.                                                                                                    |
| modules/modes.sh resume-banner block       | _print_msg WARN + log_json reason=inprogress_leftover | guarded `[[ -n "${called_fn_dir:-}" ]] && [[ FORCE_RESCAN != true ]]`                              | WIRED       | Lines 167-182. Empirical smoke shows banner: `WARN  resume: 2 functions re-running after interruption (sub_brute,sub_crt)`.                                                                            |

### Data-Flow Trace (Level 4)

Not applicable — phase produces infrastructure (helpers, traps, config knobs). No artifacts render dynamic data; data flows are bash control-flow only. The `.status_*` / `.status_reason_*` files are the closest analogue and they ARE produced by `_timeout_kill_job` and consumed by `_parallel_emit_job_output` (transient by design — the consumer deletes the files after rendering the badge).

### Behavioral Spot-Checks

| Behavior                                                                                              | Command                                                              | Result                                                                                                                                                | Status      |
|-------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------|-------------|
| `bash -n` on all modified files                                                                       | `bash -n core.sh utils.sh modes.sh parallel.sh reconftw.cfg`         | "ALL_PARSE_OK"                                                                                                                                       | PASS        |
| `shellcheck -s bash --severity=error` on all modified files                                           | `shellcheck -s bash --severity=error <files>`                        | exit 0                                                                                                                                              | PASS        |
| Source reconftw.cfg → confirm 5 default values                                                        | `bash -c 'source reconftw.cfg && echo ...'`                          | `DNS_BRUTE_TIMEOUT=6h, DNS_RESOLVE_TIMEOUT=4h, PARALLEL_JOB_TIMEOUT_SECONDS=0, PARALLEL_KILL_GRACE_SECONDS=10, MIN_DISK_SPACE_GB=2`                  | PASS        |
| Disk-full abort path                                                                                  | `/tmp/disk_smoke.sh` with `MIN_DISK_SPACE_GB=99999999`               | `Test 1 (low req) rc=0`, `Test 2 rc=1`, stderr `[FAIL] disk_full: aborting (Disk space LOW: required 99999999GB, available 20GB at ...)`             | PASS        |
| SC1 SIGINT preserves sentinel (CR-01 inversion of prior reproduction)                                 | `/tmp/sc1_final.sh`                                                  | BEFORE: `.inprogress_sub_brute .sub_passive`. AFTER SIGINT: `.inprogress_sub_brute .sub_passive`. "RESULT: SC1_OK — sentinel SURVIVED SIGINT"        | PASS        |
| Clean exit sweeps sentinel (D-02 happy path)                                                          | `/tmp/clean_recheck.sh`                                              | BEFORE: `.inprogress_sub_brute .sub_passive`. AFTER `_RECON_CLEAN_EXIT=true; exit 0`: `.sub_passive` only. "RESULT: CLEAN_OK"                        | PASS        |
| FORCE_RESCAN clears both checkpoints and sentinels                                                    | `/tmp/force_rescan_smoke.sh`                                         | "RESULT: FORCE_RESCAN_OK" — directory empty after the dual rm                                                                                       | PASS        |
| Resume banner format (D-04)                                                                           | `/tmp/resume_banner.sh`                                              | `WARN  resume: 2 functions re-running after interruption (sub_brute,sub_crt)`                                                                       | PASS        |
| CR-02: timeout-kill fires under `--quiet` (OUTPUT_VERBOSITY=0)                                        | `/tmp/quiet_timeout.sh` with `PARALLEL_JOB_TIMEOUT_SECONDS=2 sleep 30` job | ELAPSED=5s (job killed within timeout + grace, was 30s+ pre-fix). Status files written → consumed by emit; FAIL badge rendered with `reason: timeout`. | PASS        |
| CR-03: inner tool process dies alongside wrapper                                                       | `/tmp/inner_kill.sh` with backgrounded `sleep 30` inside wrapper      | INNER_PID's `sleep 30` confirmed dead via `kill -0` non-zero. "RESULT: CR-03_OK"                                                                     | PASS        |
| bats unit tests                                                                                        | `bats tests/unit/`                                                   | 246 pass, 0 fail                                                                                                                                     | PASS        |
| bats security tests                                                                                    | `bats tests/security/`                                               | 34 pass, 0 fail                                                                                                                                      | PASS        |

### Probe Execution

| Probe | Command | Result | Status |
| ----- | ------- | ------ | ------ |
| N/A   | —       | No probes declared in PLAN/SUMMARY; no `scripts/*/tests/probe-*.sh` convention found in this repository for Phase 1. | SKIPPED |

### Requirements Coverage

| Requirement | Source Plan(s)   | Description                                                                                                                                | Status      | Evidence                                                                                                                                                                                                  |
|-------------|------------------|------------------------------------------------------------------------------------------------------------------------------------------|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| RESIL-01    | 01-01, 01-04     | User can resume an interrupted recon and skip functions that finished cleanly while re-running functions that were killed mid-execution    | SATISFIED   | Sentinel lifecycle from 01-01 + clean-exit-flag gating from 01-04. SC1 reproduction smoke confirms `.inprogress_sub_brute` survives SIGINT; checkpoint guard re-runs only the crashed function.        |
| RESIL-02    | 01-02            | A recon run aborts with a clear error rather than producing truncated output when filesystem fills mid-scan                                | SATISFIED   | `_check_disk_mid_run` boundary calls in start_func and end_func; `_abort_disk_full` emits stderr error + JSONL `reason=disk_full` + exit 1. Empirical smoke confirms rc=1.                              |
| RESIL-03    | 01-03, 01-05     | User can bound individual job time inside parallel_funcs via PARALLEL_JOB_TIMEOUT_SECONDS, with stuck jobs terminated by kill -TERM        | SATISFIED   | Timeout knob + `_timeout_kill_job` from 01-03; gate decoupling + `_kill_tree` from 01-05. Smokes confirm kill under --quiet AND inner tool process termination.                                       |
| PERF-02     | 01-03            | DNS brute/resolve operations have non-zero default timeouts (DNS_BRUTE_TIMEOUT=6h, DNS_RESOLVE_TIMEOUT=4h)                                | SATISFIED   | reconftw.cfg:394-395 ship with the required defaults; `_run_dns_with_heartbeat` honors them via `timeout/gtimeout -k 10s`.                                                                              |

All 4 requirement IDs declared across plan frontmatter are accounted for. No orphaned requirements detected — REQUIREMENTS.md Traceability table maps exactly RESIL-01, RESIL-02, RESIL-03, PERF-02 to Phase 1, and all four are now SATISFIED.

### Anti-Patterns Found

| File                | Line | Pattern                                                                                  | Severity | Impact                                                                                                                                  |
|---------------------|------|----------------------------------------------------------------------------------------|----------|----------------------------------------------------------------------------------------------------------------------------------------|
| (no debt markers found in modified files)                                                                                                                                                                                                                                                                                  |
| modules/core.sh     | 1421 | Stale comment `# Plan 01-01 EXIT trap clears .inprogress_*` (post-CR-01, EXIT trap is gated)                 | INFO     | Documentation drift surfaced by 01-REVIEW.md WR-02. The actual behavior is correct (disk-full path leaves sentinels for resume); only the inline phrasing is now imprecise. Not a blocker; carry as Phase 5 DOCS-01 candidate. |
| modules/utils.sh    | 455  | Stale comment `# Hard-abort the run on disk-full mid-run detection (D-09). EXIT trap (Plan 01-01) clears .inprogress_* on the way out.` | INFO     | Same drift class as above — the disk-full path now intentionally leaves sentinels so the next run shows the resume banner. Update comment in DOCS-01.                                                       |
| modules/core.sh     | 1485 | Unguarded `touch "$called_fn_dir/.${fn}"` (pre-existing CR-04 from prior review, not addressed by 01-04/01-05)                | INFO     | Inherits from before this phase; surfaced by 01-REVIEW.md WR-01. The new `.inprogress_*` rm at :1483 is correctly guarded, but the adjacent checkpoint touch at :1485 is not. Same pattern in `end_subfunc` at :1572. Phase 5 DOCS-01 candidate. |

No `TBD`/`FIXME`/`XXX` debt markers in any phase-modified file. The grep matches for `mktemp ...XXXXXX` are template placeholders, not debt markers.

### Human Verification Required

#### 1. End-to-end resume on real Ctrl+C interruption

**Test:** Run `./reconftw.sh -d <safe-domain> -r --parallel` against a target known to take >30 seconds in `sub_brute`. Wait for `sub_brute` to start, then press Ctrl+C. Immediately re-run with `PRESERVE=true` (default).
**Expected:** Post-CR-01 fix, the EXIT trap no longer wipes the sentinel because `_RECON_CLEAN_EXIT` remains false on the SIGINT path. The next run should print exactly one WARN banner: `resume: 1 functions re-running after interruption (sub_brute)`. Then `sub_brute` re-executes via the existing checkpoint guard; completed prior functions retain their `.<fn>` checkpoints.
**Why human:** Requires a real recon run with real SIGINT — not safely automatable in this verification context. The code path was confirmed by behavioral smoke (Spot-Check `/tmp/sc1_final.sh`); the user-facing wall-clock test is the human leg.

#### 2. Timeout-kill under --quiet on a real long-running tool (e.g., puredns)

**Test:** Set `PARALLEL_JOB_TIMEOUT_SECONDS=600` in `reconftw.cfg`, run `./reconftw.sh --quiet -d <target> -r` against a target known to take >10 minutes in some parallel-funcs child (e.g., `sub_brute` with a 2GB wordlist).
**Expected:** Post-CR-02 fix, the heartbeat loop runs under `--quiet` (OUTPUT_VERBOSITY=0) because the timeout-enforcement gate is decoupled from the verbosity gate. The stuck function should be killed at the 600s mark with FAIL + `reason: timeout`. The batch continues to subsequent functions.
**Why human:** Behavioral confirmation against a real external tool requires a 10+ minute run. Code-path correctness was confirmed by synthetic smoke (`/tmp/quiet_timeout.sh` — killed in 5s under OUTPUT_VERBOSITY=0).

#### 3. Process-tree kill on a real tool with descendants (e.g., puredns + massdns)

**Test:** With `PARALLEL_JOB_TIMEOUT_SECONDS=10` and `OUTPUT_VERBOSITY=1`, run a recon that triggers `puredns bruteforce` (which forks `massdns`) inside a parallel batch. Monitor `ps` during and after the 10s timeout fires.
**Expected:** Post-CR-03 fix, both the wrapper subshell AND the underlying `puredns` AND `massdns` processes should be terminated within `PARALLEL_KILL_GRACE_SECONDS` because `_kill_tree` walks `pgrep -P` descendants children-first.
**Why human:** Requires monitoring a real parallel batch with `ps` while a timeout fires on a real external tool. Synthetic two-level subshell smoke (`/tmp/inner_kill.sh`) confirms recursion works; real-tool process-table confirmation needs human eyes on `ps`.

### Gaps Summary

**None remaining.** All four success criteria are now VERIFIED:

- **SC1 (RESIL-01, .inprogress_<fn> indicator on interruption + re-run only the interrupted function):** PARTIAL → VERIFIED. Plan 01-04 introduced the `_RECON_CLEAN_EXIT` flag, gated `_cleanup_inprogress` on it, and flipped the flag at end()'s last statement. SIGINT/SIGTERM via `cleanup_on_exit` leaves the flag false → EXIT trap returns early → sentinels survive. Clean traversals through end() set the flag true → EXIT trap sweeps. Empirical SIGINT smoke confirms sentinel survival; empirical clean-exit smoke confirms sentinel sweep. The misleading comment at modules/core.sh:1431-1434 was rewritten; D-02 in 01-CONTEXT.md was reconciled with implemented semantics.

- **SC2 (RESIL-02, disk-full mid-run abort):** Remains VERIFIED. No changes since initial verification; helpers and call sites all in place and behaviorally correct.

- **SC3 (RESIL-03, PARALLEL_JOB_TIMEOUT_SECONDS=600 terminates child via kill -TERM):** PARTIAL → VERIFIED. Plan 01-05 closed both compound defects. (a) CR-02: decoupled the heartbeat-loop verbosity gate from the timeout-enforcement gate via hoisted `_to`/`_verbose_progress`/`_loop_active` booleans; the loop now enters on `_loop_active && (_verbose_progress || _to > 0)` and the timeout-enforcement check inside the loop body is unconditional. Two-loop symmetry preserved (batch-flush and final-wait both refactored identically). (b) CR-03: new `_kill_tree` helper walks `pgrep -P` descendants children-first; `_timeout_kill_job` body now calls `_kill_tree $pid TERM/KILL` instead of bare `kill` against the wrapper PID. Process-group kill via pgid was rejected because `set +m` is explicitly in effect; the recursive walk is portable (Linux procps + macOS BSD pgrep both support `-P`) and degrades gracefully if `pgrep` is missing. Empirical `--quiet` smoke confirms kill fires; inner-sleep smoke confirms descendants die.

- **SC4 (PERF-02, DNS_BRUTE_TIMEOUT=6h / DNS_RESOLVE_TIMEOUT=4h defaults):** Remains VERIFIED. No changes since initial verification.

The three remaining items in the post-fix code review (WR-01 unguarded `touch` at end_func/end_subfunc; WR-02 stale comments at modules/core.sh:1421 and modules/utils.sh:455 referencing the pre-CR-01 trap behavior; WR-03 hypothetical double-kill race in `_kill_tree`) are pre-existing or low-severity warnings, not Phase 1 blockers. They are Phase 5 DOCS-01 / DOCS-02 candidates.

---

_Verified: 2026-05-13T13:30:00Z_
_Verifier: Claude (gsd-verifier)_
