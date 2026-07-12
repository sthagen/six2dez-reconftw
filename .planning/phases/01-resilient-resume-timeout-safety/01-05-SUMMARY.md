---
phase: 01-resilient-resume-timeout-safety
plan: 05
subsystem: infra
tags: [parallel, timeout, signals, sigterm, sigkill, kill-tree, pgrep, bash, heartbeat, quiet-mode, ci]

# Dependency graph
requires:
  - phase: 01-resilient-resume-timeout-safety
    provides: "PARALLEL_JOB_TIMEOUT_SECONDS knob + _timeout_kill_job helper (from Plan 01-03); the two heartbeat loops with verbosity-coupled gate that this plan decouples"
provides:
  - "Decoupled timeout-enforcement gate in lib/parallel.sh: loop runs when `_loop_active && (_verbose_progress || _to > 0)` so PARALLEL_JOB_TIMEOUT_SECONDS fires under --quiet (OUTPUT_VERBOSITY=0), the documented CI scenario at reconftw.cfg:317 (closes CR-02)"
  - "Hoisted `_to`/`_verbose_progress`/`_loop_active` locals declared once per batch instead of per-iteration (IN-02 micro-fix folded in)"
  - "Inline WR-05 documentation note acknowledging that PARALLEL_HEARTBEAT_SECONDS=0 disables timeout enforcement; Phase 5 DOCS-01 candidate"
  - "New `_kill_tree` helper in lib/parallel.sh: recursive `pgrep -P` walk that signals children-first-then-parent so the entire process tree under the wrapper PID is terminated (closes CR-03)"
  - "`_timeout_kill_job` body now calls `_kill_tree $pid TERM` / `_kill_tree $pid KILL` instead of bare `kill` against the wrapper PID — the actual external tool (puredns, dnsx, ffuf, axiom-scan, etc.) terminates, not just the wrapper subshell"
  - "Graceful `command -v pgrep` degradation: if pgrep is missing on the host the walk falls back to wrapper-only kill (pre-patch behavior), so the run does not fail"
  - "Two-loop symmetry preserved per Plan 01-03's pattern note: batch-flush and final-wait heartbeat loops have identical structure post-patch"
affects: [01-verification (SC3 transitions PARTIAL → VERIFIED), 04-test-coverage (TEST-01 will assert timeout-kill path under --quiet AND inner-tool-tree-kill), 05-config-docs (DOCS-01 followup: WR-05 PARALLEL_HEARTBEAT_SECONDS=0 corner case; canonical `function name() {` form for sibling helpers)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Decoupled-gate pattern: hoist conditional locals once per batch then enter the loop on `loop_active && (UI_arm || enforcement_arm)` so UI and enforcement concerns are orthogonal"
    - "`_kill_tree` pattern: recursive `pgrep -P` walk with `command -v pgrep` graceful-degradation guard — reusable model for any future supervised-process kill in bash (alongside the TERM-then-KILL grace pattern from Plan 01-03)"
    - "Children-first-then-parent recursion ordering: standard Unix tree-kill idiom; protects against a parent re-spawning children on signal"

key-files:
  created: []
  modified:
    - "lib/parallel.sh — decoupled heartbeat gate at the two heartbeat-loop entry points (was :469, :579; now :467-481 and :583-597); new `_kill_tree` helper at :44-66 (between `_throttle_jobs` and `_timeout_kill_job`); `_timeout_kill_job` body refactored to call `_kill_tree $pid TERM` / `_kill_tree $pid KILL` (was bare `kill -TERM/-KILL $pid` against wrapper-only PID)"

key-decisions:
  - "Decouple via three hoisted booleans (`_to`, `_verbose_progress`, `_loop_active`) rather than splitting into two separate `if` blocks — preserves the existing loop body shape, makes the new combined gate easy to read, and folds in IN-02's micro-optimization (hoist `_to` out of the per-iteration scope) as a clean co-fix"
  - "Recursive `pgrep -P` walk in `_kill_tree`, NOT a process-group kill (`kill -- -<pgid>`). Process-group kill rejected because `start()` at `modules/modes.sh:16` explicitly disables job control via `set +m`. Flipping `set -m` for one corner case is intrusive across the codebase. Documented inside the `_kill_tree` docstring AND in this SUMMARY"
  - "Children-first-then-parent ordering: standard Unix idiom; the parent's own kill happens last so any deeper descendants reaped first. The `command -v pgrep` guard adds defense-in-depth for hosts that lack pgrep (extremely rare on reconftw's supported platforms — Linux procps and macOS BSD pgrep both have `-P <ppid>`)"
  - "`_kill_tree` uses canonical `function name() {` form per CONVENTIONS.md §Function Naming. Sibling helpers in `lib/parallel.sh` that omit the keyword predate the rule and remain a Phase 5 DOCS-01 followup, not a precedent for new code"
  - "Inside the loop body the timeout-enforcement check drops the `[[ \"$_to\" =~ ^[0-9]+$ ]]` regex check (already validated outside the loop in the hoisted `_to` assignment) — minor cleanup that does not change behavior but makes the inner check single-purpose"
  - "Heartbeat snapshots (`_parallel_snapshot` call) wrapped in an explicit `if [[ \"$_verbose_progress\" == \"true\" ]]` block — UI behavior is unchanged at OUTPUT_VERBOSITY=0 (no heartbeat noise); only the timeout-enforcement path runs unconditionally"

patterns-established:
  - "Decoupled UI-vs-enforcement gate pattern: when a single while-loop serves both UI updates and a correctness mechanism, the entry condition should be `enforcement_active OR UI_wanted`; the UI emission inside the loop body gets its own `UI_wanted` guard. Future supervised loops in lib/parallel.sh should follow this shape"
  - "`_kill_tree` is the canonical helper for kill-the-tool-not-just-the-wrapper in bash subshell contexts; should be reused by any future code that supervises external processes inside parallel_funcs wrappers"
  - "Two-loop symmetry discipline (established by Plan 01-03) is enforced via grep-counted acceptance criteria — both heartbeat loops have the same four hoisted-local declarations, the same compound gate, and the same verbosity-wrapped snapshot call"

requirements-completed: [RESIL-03]

# Metrics
duration: 13min
completed: 2026-05-13
---

# Phase 01 Plan 05: CR-02 + CR-03 Gap Closure — Decouple Timeout Gate and Kill the Whole Process Tree Summary

**`PARALLEL_JOB_TIMEOUT_SECONDS` now fires under `--quiet` (CR-02 fix) AND the entire process tree under the wrapper PID is terminated on timeout — not just the wrapper subshell (CR-03 fix). Both gaps from 01-VERIFICATION.md SC3 closed in one plan because both fixes live in the same change site.**

## Performance

- **Duration:** 13 min
- **Started:** 2026-05-13T10:44:35Z (worktree agent spawn)
- **Completed:** 2026-05-13T10:57:26Z
- **Tasks:** 2 (both `type="auto"`)
- **Files modified:** 1 (`lib/parallel.sh`)

## Accomplishments

- **CR-02 closed:** Two heartbeat loops at `lib/parallel.sh:467-510` (batch-flush) and `:583-630` (final-wait) decoupled the verbosity gate from the timeout-enforcement gate. The loop runs when `_loop_active && (_verbose_progress || _to > 0)`; the timeout-enforcement check inside the loop body is unconditional. Setting `PARALLEL_JOB_TIMEOUT_SECONDS=600` under `--quiet` (OUTPUT_VERBOSITY=0) now terminates any parallel_funcs child that exceeds 600s — the documented CI scenario at `reconftw.cfg:317` works as designed.
- **CR-03 closed:** New `_kill_tree` helper at `lib/parallel.sh:44-66` walks the process tree via `pgrep -P` and signals children-first-then-parent. `_timeout_kill_job` body now calls `_kill_tree $pid TERM` / `_kill_tree $pid KILL` instead of bare `kill` against the wrapper PID. The actual external tool (puredns, dnsx, ffuf, axiom-scan, etc.) terminates — not just the wrapper subshell. Verified via inner-sleep + multi-level-subshell behavior smokes.
- **IN-02 folded in:** `_to` and the other gate booleans are declared once per batch (outside the inner per-iteration loop) instead of being re-declared on every heartbeat iteration. Trivial micro-optimization, but makes the code clearer about scope.
- **Two-loop symmetry preserved:** batch-flush and final-wait heartbeats have identical post-patch shape (verified by grep-counted acceptance criteria returning exactly 2 for every key pattern). The discipline established by Plan 01-03 holds.
- **macOS compatibility:** `pgrep -P <ppid>` is supported by BSD `pgrep` shipped with macOS (`/usr/bin/pgrep`, universal binary) — confirmed on the executor host (Darwin 25.5.0). The `command -v pgrep` guard provides defense-in-depth for hosts that lack pgrep.
- **No new bats tests added:** Phase 4 / TEST-01 explicitly covers parallel_funcs timeout-kill coverage per CONTEXT.md §Claude's Discretion. The existing 246/246 unit baseline holds.

## Task Commits

Each task was committed atomically:

1. **Task 1: Decouple timeout-enforcement gate from verbosity gate in both heartbeat loops** — `d9a5a01a` (fix)
2. **Task 2: Add `_kill_tree` helper and refactor `_timeout_kill_job` to walk the process tree** — `3ad3bdf0` (fix)

Plan metadata (this SUMMARY) commit follows separately per execute-plan.md.

## Files Created/Modified

- `lib/parallel.sh` — Three edit sites in one file:
  1. Batch-flush heartbeat at `:467-510` (was `:467-506`): hoisted `_to` / `_verbose_progress` / `_loop_active` locals; new compound gate `_loop_active && (_verbose_progress || _to > 0)`; unconditional timeout-enforcement inside loop body; explicit `_verbose_progress` guard around `_parallel_snapshot` call; CR-02 explanatory comment and WR-05 inline note.
  2. Final-wait heartbeat at `:583-630` (was `:577-616`): identical refactor — two-loop symmetry preserved character-for-character.
  3. New `_kill_tree` helper at `:44-66` (inserted between `_throttle_jobs` at `:33-42` and the existing comment block above `_timeout_kill_job` at `:68`). `_timeout_kill_job` body at `:78-105` updated: `kill -TERM "$pid"` → `_kill_tree "$pid" TERM`; `kill -KILL "$pid"` → `_kill_tree "$pid" KILL`. Persistence writes, `kill -0` poll, and `log_json` call all UNCHANGED.

## Decisions Made

- **Pgid approach rejected** in favor of `pgrep -P` recursive walk. Reason: `start()` at `modules/modes.sh:16` explicitly disables job control (`set +m 2>/dev/null || true`), so the wrapper subshell does not get its own pgid; flipping `set -m` for one corner case would propagate intrusive side effects across the codebase. The `pgrep -P` walk is portable, side-effect-free, and has been validated on macOS BSD and Linux procps. Documented inside `_kill_tree`'s docstring AND here in the SUMMARY's Decisions Made section per the planner's request.
- **Decoupled gate via hoisted booleans**, not via two separate `if` blocks: preserves the existing loop-body shape, makes the new combined gate easy to read, and folds in IN-02's hot-loop micro-optimization (hoist `_to` out of per-iteration scope) as a clean co-fix.
- **Children-first-then-parent recursion ordering** in `_kill_tree`: standard Unix tree-kill idiom; protects against a parent re-spawning children on signal. The caller's TERM-then-KILL grace pattern (from Plan 01-03) handles the parent's own re-spawn risk.
- **`command -v pgrep` graceful-degradation guard** added even though pgrep is universally available on reconftw's supported platforms — defense in depth is cheap, and a missing-pgrep host falls back to pre-patch behavior (wrapper-only kill) rather than failing the entire run.
- **Did not modify `_timeout_kill_job`'s function signature** (`<pid> <func_name> <duration_sec>`) or the `kill -0` poll guard. Callers see the same surface; only the kill mechanism is replaced behind the helper boundary.
- **WR-05 corner case acknowledged but not resolved** in this plan. The `PARALLEL_HEARTBEAT_SECONDS=0` case still disables timeout enforcement (because the entire loop is gated on `hb > 0`). Added inline `NB: PARALLEL_HEARTBEAT_SECONDS=0 disables the loop entirely, which also disables timeout enforcement. WR-05 documented this; resolve in Phase 5 DOCS-01 if it surfaces in practice.` near the `_loop_active` declaration. The planner's original advisory framed this as a documentation concern, not a blocking gap.

## Deviations from Plan

None — plan executed exactly as written. All `must_haves.truths`, `acceptance_criteria`, and `success_criteria` verified by grep-counted patterns AND behavior smokes (`/tmp/quiet_timeout.sh`, `/tmp/default_disabled.sh`, `/tmp/inner_kill.sh`, `/tmp/multi_level_kill.sh`, `/tmp/two_loop_symmetry.sh`).

Auto-fixes applied during execution: none (no bugs, no missing critical functionality, no blocking issues encountered).

## Issues Encountered

- A few acceptance-criteria grep patterns from the plan used backslash-escapes that needed adjustment for execution: the plan-supplied pattern `'_timeout_kill_job "${batch_pids\[\$idx\]}" "${batch_funcs\[\$idx\]}" "$job_dur"'` was treated as a regex by grep and the bracket-escaping confused the match; used `grep -F` (fixed-string mode) for the call-site count, which returned the expected 2 occurrences. Same issue Plan 01-03's SUMMARY flagged. The actual file content matches the plan's explicit specification — the patterns just need fixed-string mode to verify cleanly.
- One acceptance-criterion `awk '... { p=NR ... c=NR ... }' END{...}'` ordering check needed to use the raw function-body line numbers (NR inside the `awk` range, not file-level line numbers) — the original plan pattern returned ORDER_OK as expected. No adjustment needed.

## User Setup Required

None — the change is internal to `lib/parallel.sh` and inherits the existing `PARALLEL_JOB_TIMEOUT_SECONDS=0` (disabled) default from Plan 01-03. Opt-in tuning happens by editing `reconftw.cfg` or exporting the env var, just as before. CI users who already set `PARALLEL_JOB_TIMEOUT_SECONDS=600` per the cfg comment now get the enforcement they expect under `--quiet`.

## Next Phase Readiness

- **SC3 gaps closed:** Both compound defects from `01-VERIFICATION.md` (CR-02 + CR-03) are now fixed. The next verifier run should transition SC3 from PARTIAL → VERIFIED. The headline guarantee — "PARALLEL_JOB_TIMEOUT_SECONDS=600 terminates any single `parallel_funcs` child exceeding 10 minutes via kill -TERM" — now holds under `--quiet` AND signals the entire process tree (not just the wrapper).
- **Behavioral smokes serve as the next verifier's checks:**
  - `/tmp/quiet_timeout.sh`: CR-02 reproduction — `PARALLEL_JOB_TIMEOUT_SECONDS=2 OUTPUT_VERBOSITY=0`, slow_func sleeps 30. Pre-patch: runs 30s+. Post-patch: killed in ~5s. ✓
  - `/tmp/default_disabled.sh`: backwards-compat — `PARALLEL_JOB_TIMEOUT_SECONDS=0` (default), normal_func sleeps 3. Runs to natural completion. ✓
  - `/tmp/inner_kill.sh`: CR-03 reproduction — backgrounded `sleep 30` inner child. Pre-patch: orphaned to PID 1 and runs to completion. Post-patch: dead within ~5s. ✓
  - `/tmp/multi_level_kill.sh`: multi-level recursion — extra `( sleep 30 ) &` subshell. Post-patch: both the subshell AND its sleep child are dead. ✓
  - `/tmp/two_loop_symmetry.sh`: final-wait loop also enforces timeout under quiet mode — 3-function batch with `PARALLEL_MAX_JOBS=2` exercises the final-wait path; slow 3rd function killed by the final-wait loop's modified gate. ✓
- **Phase 4 / TEST-01 readiness:** the timeout-kill path now has two behavioral surfaces to assert — (a) FAIL + reason=timeout persistence under `--quiet`, and (b) inner-tool-tree termination via `_kill_tree`. Both are deterministic and test-friendly via the smokes above.
- **Phase 5 / DOCS-01 followup candidates:**
  - `_kill_tree` pattern is the established model for supervised-process kills in `lib/parallel.sh`. Document it alongside the TERM-then-KILL grace pattern from Plan 01-03.
  - WR-05 corner case (`PARALLEL_HEARTBEAT_SECONDS=0` disables timeout enforcement) — inline `NB:` comment present; surface in DOCS-01 if it bites a user in practice.
  - Canonical `function name() {` form for sibling helpers in `lib/parallel.sh` (`_throttle_jobs`, `_parallel_live_break`, etc.) that predate the rule — flagged by Plan 01-03 already; this plan continued the same in-file note discipline.
- **No blockers for downstream phases.** Plan 01-04 (separate worktree, parallel wave 3) handles CR-01 (resume-sentinel survival under SIGINT) and is independent of this plan.

## Self-Check: PASSED

- FOUND: lib/parallel.sh
- FOUND: .planning/phases/01-resilient-resume-timeout-safety/01-05-SUMMARY.md (this file)
- FOUND: d9a5a01a (Task 1 commit — gate decoupling)
- FOUND: 3ad3bdf0 (Task 2 commit — `_kill_tree` helper + `_timeout_kill_job` refactor)

All claimed files exist; all claimed commits are in git history. `bash -n` and `shellcheck -s bash --severity=error` both exit 0 on `lib/parallel.sh`. All grep-counted acceptance criteria pass (compound gate removed × 0, hoisted locals × 2, new compound gate × 2, `_parallel_snapshot` verbosity-wrapped × 2, CR-02 comment × 4, WR-05 note × 2, `_kill_tree` declaration × 1, `pgrep -P` walk × 1, `command -v pgrep` guard × 1, children-first ordering ORDER_OK, position POS_OK, `_kill_tree` TERM/KILL calls × 1+1, bare `kill -TERM/KILL "$pid"` removed × 0, `kill -0` poll preserved × 1, persistence writes preserved × 1+1, `log_json` preserved × 1, CR-03 comment × 1, call sites × 2). Behavior smokes confirm CR-02 + CR-03 fixes hold; 246/246 bats unit tests pass.

---
*Phase: 01-resilient-resume-timeout-safety*
*Completed: 2026-05-13*
