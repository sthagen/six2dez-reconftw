---
phase: 01-resilient-resume-timeout-safety
plan: 01
subsystem: infra
tags: [bash, lifecycle, resume, checkpoints, traps, signals, resilience]

# Dependency graph
requires:
  - phase: codebase-mapping
    provides: existing start_func/end_func lifecycle wrappers, cleanup_on_exit pattern, called_fn_dir checkpoint convention
provides:
  - .inprogress_<fn> sentinel touched at start_func, removed at end_func before the .<fn> checkpoint
  - silent EXIT-only trap (_cleanup_inprogress) that clears stale sentinels on graceful exit
  - FORCE_RESCAN block now explicitly wipes .inprogress_* orphans
  - resume banner ("WARN  resume: N functions re-running after interruption (...)") plus structured log event with reason=inprogress_leftover
affects: [01-02-disk-full-guard, 01-03-parallel-timeout, 04-test-coverage]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "EXIT/INT/TERM trap separation: EXIT is silent and side-effect-only; INT/TERM keeps the loud cleanup_on_exit banner + forced exit 130"
    - "sentinel lifecycle (start touch / end remove-before-checkpoint) where the .<fn> file remains the source of truth and the .inprogress_<fn> file is a surface indicator only"

key-files:
  created: []
  modified:
    - modules/core.sh
    - modules/modes.sh
    - modules/utils.sh

key-decisions:
  - "Kept cleanup_on_exit (INT/TERM) untouched; added a separate silent EXIT-only trap calling a new _cleanup_inprogress helper so successful exits never print 'Interrupted. Cleaning up...' or force exit 130"
  - "EXIT trap placed on the line IMMEDIATELY after the INT/TERM trap (single inline doc comment trailing the trap call, not above) to satisfy the awk-getline adjacency acceptance criterion"
  - "Resume detection guarded with both [[ -n ${called_fn_dir:-} ]] AND [[ FORCE_RESCAN != true ]] so the block never scans filesystem root and never fires after a --force wipe"

patterns-established:
  - "Trap composition: when an existing handler is load-bearing for a specific signal set, add new signal handlers via SEPARATE trap calls rather than chaining into the existing handler"
  - "Sentinel ordering: rm sentinel BEFORE touch checkpoint — a crash between the two operations leaves .<fn> absent, so the existing checkpoint guard re-runs the function naturally on next invocation"

requirements-completed: [RESIL-01]

# Metrics
duration: 9m
completed: 2026-05-13
---

# Phase 01 Plan 01: Resilient Resume Sentinel Lifecycle Summary

**`.inprogress_<fn>` sentinel lifecycle in start_func/end_func, silent EXIT-only trap (_cleanup_inprogress) that does not disrupt the existing INT/TERM cleanup banner, and one-shot resume banner in start() when a prior crash left orphan sentinels — closes RESIL-01.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-05-13T11:04:34Z (first task commit)
- **Completed:** 2026-05-13T11:13:00Z (approx, second task commit)
- **Tasks:** 2 (both `type="auto"`)
- **Files modified:** 3 (`modules/core.sh`, `modules/modes.sh`, `modules/utils.sh`)

## Accomplishments

- `start_func` now touches `${called_fn_dir}/.inprogress_<fn>` immediately after the per-function start-timestamp setup; `end_func` removes it BEFORE the existing `touch "$called_fn_dir/.${fn}"` so the success checkpoint stays the single source of truth for "function completed".
- New `_cleanup_inprogress()` helper in `modules/utils.sh` (sibling to `cleanup_on_exit`, registered on `EXIT` only) silently sweeps any `.inprogress_*` files on every shell exit. It does NOT call `exit`, `kill`, or print any banner — graceful exits stay quiet and preserve the natural `$?`.
- `cleanup_on_exit` body is untouched; its loud "Interrupted. Cleaning up..." banner and forced `exit 130` remain the user-facing signal for actual SIGINT/SIGTERM. This avoided the BLOCKER regression where binding `cleanup_on_exit` to EXIT would have broken every successful CI run.
- FORCE_RESCAN block in `start()` gained an explicit `rm -f "$called_fn_dir"/.inprogress_*` so a `--force` run never inherits a fake resume condition (defensive against shell dotglob settings).
- New resume banner in `start()` between the existing FORCE_RESCAN warning and the MONITOR_MODE block emits exactly one WARN line — `WARN  resume: N functions re-running after interruption (fn_a, fn_b)` — and one JSONL event with `reason=inprogress_leftover` when crash-leftover sentinels are detected. Guarded against unset `called_fn_dir` (prevents scanning filesystem root) and skipped under FORCE_RESCAN (Step C already wiped orphans).

## Task Commits

Each task was committed atomically:

1. **Task 1: Sentinel touch in start_func + sentinel remove in end_func** — `a72e27e6` (feat)
2. **Task 2: Separate EXIT-only trap + orphan cleanup + resume banner in start()** — `199f198a` (feat)

## Files Created/Modified

- `modules/core.sh` — added `.inprogress_<fn>` touch in `start_func` (after the per-function start-timestamp setup, before the first `log_json` call) and the matching `rm -f .inprogress_<fn>` in `end_func` immediately before the existing `touch "$called_fn_dir/.${fn}"`. Both ops guarded with `[[ -n "${called_fn_dir:-}" ]]` and `2>/dev/null || true`.
- `modules/utils.sh` — added `_cleanup_inprogress` as a sibling helper to `cleanup_on_exit`. Single line body: `[[ -n "${called_fn_dir:-}" ]] && rm -f "${called_fn_dir}"/.inprogress_* 2>/dev/null; return 0`. `cleanup_on_exit` itself NOT modified.
- `modules/modes.sh` — three insertions in `start()`: (1) `rm -f "$called_fn_dir"/.inprogress_*` inside the existing FORCE_RESCAN block, (2) `trap '_cleanup_inprogress' EXIT` immediately after the unchanged `trap 'cleanup_on_exit' INT TERM`, (3) resume-banner detection block between the FORCE_RESCAN warning and the MONITOR_MODE branch.

## Decisions Made

- **Option 2 from PATTERNS.md (separate EXIT-only trap, NOT chaining `_cleanup_inprogress` into `cleanup_on_exit`)** was the only safe composition: chaining would have either inherited cleanup_on_exit's `Interrupted. Cleaning up...` banner + forced exit 130 on every successful run, or required mutating cleanup_on_exit's body — both regressions. Plan explicitly mandated this approach; the implementation followed it without deviation.
- **EXIT trap on a single line with a trailing inline comment** (`trap '_cleanup_inprogress' EXIT  # silent EXIT-only sentinel sweep (D-02)`) rather than a multi-line comment block above the trap. This was driven by the AC requirement "EXIT trap line sits IMMEDIATELY AFTER the INT/TERM trap line" (awk-getline check) — a leading comment block would have caused the getline check to return 0. First attempt put the comment above, which failed the AC; corrected by moving the doc into a trailing comment.
- **Banner detection runs AFTER the FORCE_RESCAN warning** rather than before, so a `--force` run sees only the rescan warning and never the resume banner (FORCE_RESCAN block already wiped any leftovers earlier in `start()`).

## Deviations from Plan

None - plan executed exactly as written.

(One in-flight correction: the EXIT trap was initially separated from the INT/TERM trap by a 3-line doc comment, failing the awk-getline adjacency AC. Corrected within the same task by moving the doc to a trailing inline comment on the trap line itself. Not a deviation — the AC was always the immediate-adjacency check; the first edit just didn't satisfy it. Verified via the AC awk grep returning 1.)

## Issues Encountered

- **Smoke-test harness pollution:** Inside the agent's existing zsh subshell, sourcing `reconftw.sh --source-only` inherited a `readonly status` binding from a prior load, causing `end_func "done" test_fn` to fail with `read-only variable: status`. Resolved by running smokes in a fresh `bash -c` invocation that gets a clean environment. Pre-existing harness quirk, not caused by this plan.
- **No other issues.** All bats unit tests (246/246) and security tests (34/34) still pass with the changes in place.

## User Setup Required

None - no external service configuration required. Behavior is enabled by default; no new CLI flag or config knob added by this plan.

## Next Phase Readiness

- Sentinel lifecycle is the foundation for Plan 01-02 (disk-full guard, which aborts via `exit 1` and relies on the EXIT trap clearing sentinels so subsequent runs do not see a fake resume) and Plan 01-03 (timeout kill, which persists `.status_<fn>=FAIL` + `.status_reason_<fn>=timeout` using the same sentinel-adjacent storage pattern).
- No blockers.
- Phase 4 (TEST-01) is the explicit home for sentinel-lifecycle regression coverage; per CONTEXT.md "tests for the new code paths" are deferred there by design.

## Verification

- `bash -n modules/core.sh modules/modes.sh modules/utils.sh` exits 0.
- `shellcheck -s bash --severity=error modules/core.sh modules/modes.sh modules/utils.sh` exits 0 (no new error-level findings vs. baseline).
- All Task 1 acceptance criteria (`touch` and `rm` grep counts, ordering, existing-line preservation) confirmed via grep.
- All Task 2 acceptance criteria (`_cleanup_inprogress` declaration form, no chaining from `cleanup_on_exit`, INT/TERM trap unchanged, EXIT trap immediately adjacent, FORCE_RESCAN orphan-clear ordering, banner guards, WARN/log_json strings) confirmed via grep + awk.
- Behavior smokes:
  - Graceful-exit safety: `start_func` + `end_func` + clean `exit 0` → `$?=0`, no "Interrupted..." banner, `.inprogress_*` files cleared by the EXIT trap.
  - Resume banner: pre-existing `.inprogress_sub_brute` + a fresh `start()`-like invocation prints exactly `WARN  resume: 1 functions re-running after interruption (sub_brute)` and preserves `.sub_other` (success checkpoint not wiped).
  - FORCE_RESCAN suppression: with `FORCE_RESCAN=true`, only the rescan banner appears, no resume banner, both `.inprogress_*` and `.sub_other` files are removed.
- 246/246 bats unit tests still pass; 34/34 bats security tests still pass — no regressions.

## Self-Check: PASSED

Files verified to exist:
- FOUND: `modules/core.sh` (modified)
- FOUND: `modules/modes.sh` (modified)
- FOUND: `modules/utils.sh` (modified)
- FOUND: `.planning/phases/01-resilient-resume-timeout-safety/01-01-SUMMARY.md` (this file, being written)

Commits verified on `worktree-agent-a69e9d800f0a6150a`:
- FOUND: `a72e27e6` — feat(01-01): add .inprogress_<fn> sentinel lifecycle in start_func/end_func
- FOUND: `199f198a` — feat(01-01): add EXIT-only sentinel trap + resume banner in start()

---
*Phase: 01-resilient-resume-timeout-safety*
*Completed: 2026-05-13*
