---
phase: 01-resilient-resume-timeout-safety
plan: 02
subsystem: infra
tags: [bash, disk-full, ENOSPC, lifecycle, abort, resilience, df]

# Dependency graph
requires:
  - phase: 01-resilient-resume-timeout-safety
    provides: .inprogress_<fn> sentinel lifecycle + silent EXIT-only trap (_cleanup_inprogress) from Plan 01-01 — the EXIT trap clears .inprogress_* on the way out when _abort_disk_full triggers exit 1, ensuring no fake resume condition next run
provides:
  - _check_disk_mid_run (thin wrapper around check_disk_space using MIN_DISK_SPACE_GB / ${dir:-.})
  - _abort_disk_full (hard-aborts via _print_error + log_json reason=disk_full + exit 1)
  - start_func and end_func now invoke _check_disk_mid_run || _abort_disk_full at the documented boundaries (top-of-start, post-checkpoint tail-of-end)
  - Boundary-only ENOSPC detection (~1ms × ~100 boundaries per scan; no background watcher, no per-redirect traps)
affects: [04-test-coverage (TEST-01 disk-full scenario tests), 05-config-docs (DOCS-02 MIN_DISK_SPACE_GB reconciliation will reuse the single-source threshold this plan installed)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-source-of-truth threshold reuse — the pre-flight check at modes.sh:23 and the new mid-run check both read MIN_DISK_SPACE_GB; no separate mid-run knob"
    - "Boundary-only ENOSPC detection at start_func entry + end_func tail — no run_command stderr scanning, no per-redirect failure traps (D-10 locked)"
    - "Hard-abort-then-trap-clears pattern: _abort_disk_full exits 1, the Plan 01-01 EXIT trap (_cleanup_inprogress) clears .inprogress_* automatically; no double-cleanup logic needed"
    - "Asymmetric anchor placement — start_func disk check sits as the FIRST executable statement (abort before any state write), end_func disk check sits as the LAST executable statement (abort after .<fn> and .status_<fn> are durably written)"

key-files:
  created: []
  modified:
    - modules/utils.sh
    - modules/core.sh
    - tests/unit/test_verbosity.bats

key-decisions:
  - "Used the existing _print_error + log_json + exit 1 idiom for _abort_disk_full (no new helper, no new badge, no new schema) — reuses the always-visible stderr error path from lib/common.sh:528 and the canonical log_json shape from modules/core.sh"
  - "Inserted the disk check at start_func as the VERY FIRST executable statement (before any LOGFILE write, timestamp setup, or sentinel touch) so an abort produces no orphan .inprogress_<fn> for the aborting function; completed prior functions retain their .<fn> success checkpoints — clean, deterministic state for the next run"
  - "Inserted the disk check at end_func as the VERY LAST executable statement (after log_json SUCCESS + ui_log_jsonl) so the just-finished function's .<fn> + .status_<fn> are durably written before the abort, preserving the success record while protecting the NEXT function from running with no headroom"
  - "Used a 2-line doc comment on each call site instead of an inline comment — the asymmetric placement rationale (why first-in-start, why last-in-end) is non-obvious and merits an explanatory comment for future maintainers"
  - "Test harness fix for tests/unit/test_verbosity.bats — added _check_disk_mid_run / _abort_disk_full stubs next to existing log_json / getElapsedTime stubs. The test sed-extracts start_func in isolation and the new helpers from utils.sh are not sourced; without stubs they would resolve as 'command not found' and pollute stderr"

patterns-established:
  - "Sibling-helper insertion: new private helpers (_check_disk_mid_run, _abort_disk_full) sit immediately after check_disk_space (their semantic analog) and before the next visual section (progress_bar) — preserves grouping discipline in the file"
  - "Asymmetric lifecycle guards: a guard at start_func's FIRST executable statement protects the function from running with no headroom; the same guard at end_func's LAST executable statement (post-checkpoint) protects the NEXT function. Two placements, same helper, complementary roles"
  - "Hard-abort via exit 1 + EXIT trap composition: the abort site emits structured + human error, exits 1, and lets a separately-registered EXIT trap handle stale-state cleanup — no duplicated cleanup code at the abort site"

requirements-completed: [RESIL-02]

# Metrics
duration: 12min
completed: 2026-05-13
---

# Phase 01 Plan 02: Boundary-Only Mid-Run Disk-Full Guard Summary

**Boundary-only mid-run ENOSPC abort: start_func / end_func now invoke _check_disk_mid_run || _abort_disk_full so a scan that exhausts disk space mid-run halts with a clear `disk_full: aborting (...)` error and structured `reason=disk_full` log entry instead of producing zero-byte or truncated outputs — closes RESIL-02.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-13T09:23:04Z (first plan action)
- **Completed:** 2026-05-13T09:35:26Z (after task 2 commit + verification)
- **Tasks:** 2 (both `type="auto"`)
- **Files modified:** 3 (`modules/utils.sh`, `modules/core.sh`, `tests/unit/test_verbosity.bats`)

## Accomplishments

- Two new private helpers in `modules/utils.sh` immediately after `check_disk_space`:
  - `_check_disk_mid_run` — thin wrapper that calls `check_disk_space "${MIN_DISK_SPACE_GB:-5}" "${dir:-.}"` and returns its exit code. The `:-5` default mirrors the pre-flight default at `modules/modes.sh:23` (D-08 single source of truth), and `${dir:-.}` handles invocations where `dir` is unset (e.g., test harnesses).
  - `_abort_disk_full` — emits `_print_error "disk_full: aborting (${DISK_SPACE_INFO:-...})"`, calls `log_json "ERROR" "${FUNCNAME[1]:-main}" "Disk space exhausted" "reason=disk_full" "info=..."`, then `exit 1`. `FUNCNAME[1]` resolves to the CALLER (start_func or end_func), not `_abort_disk_full` itself, so the structured log accurately identifies which boundary fired the abort.
- Two call sites in `modules/core.sh`, both using the canonical short-circuit pattern `_check_disk_mid_run || _abort_disk_full`:
  - **start_func** (`modules/core.sh:1419`): the disk check is the VERY FIRST executable statement, before `local current_date`, the LOGFILE write, the per-function timestamp setup, AND the Plan 01-01 `.inprogress_<fn>` touch. A disk-full abort at start_func entry therefore writes NO state for the aborting function — clean, deterministic for next-run resume.
  - **end_func** (`modules/core.sh:1444`): the disk check is the VERY LAST executable statement, after `log_json "SUCCESS"`, `ui_log_jsonl`, and the existing `:` no-op. The just-finished function's `.<fn>` success checkpoint and `.status_<fn>` / `.status_reason_<fn>` files are all durably written before the abort can trip — completed work is preserved on disk.
- Test-harness fix: `tests/unit/test_verbosity.bats` setup now stubs `_check_disk_mid_run` / `_abort_disk_full` next to the existing `log_json` / `getElapsedTime` stubs. The test sed-extracts `start_func` from `core.sh` in isolation; without these stubs, the new function calls fall to "command not found" and pollute stderr, breaking the verbosity assertions. The fix is a 2-line stub addition, no behavioral change.

## Task Commits

Each task was committed atomically:

1. **Task 1: Define _check_disk_mid_run + _abort_disk_full in modules/utils.sh** — `2a2013d3` (feat)
2. **Task 2: Wire _check_disk_mid_run into start_func + end_func boundaries** — `f205abf4` (feat, includes test-harness stub fix)

## Files Created/Modified

- `modules/utils.sh` — added 13 lines between `check_disk_space` (closing brace at :442) and `progress_bar` (comment at :458): two `function name()` declarations with single-line doc comments, mirroring the sibling style of `check_disk_space`. No global introduced — `DISK_SPACE_INFO` (already populated by `check_disk_space`) carries the human-readable context through to `_print_error` and `log_json`.
- `modules/core.sh` — added 8 lines total across two boundaries:
  - `start_func` body, between the opening `{` and `local current_date`: 3 lines of doc comment + 1 line of guard. Reasoning for the placement is in-file (asymmetric anchor non-obvious without context).
  - `end_func` body, between the `ui_log_jsonl` block and the trailing `:` no-op: 3 lines of doc comment + 1 line of guard. Same in-file reasoning.
- `tests/unit/test_verbosity.bats` — added 3 lines (2 stubs + 1 comment) in `setup()` next to the existing `getElapsedTime` / `record_func_timing` / `log_json` stubs.

## Decisions Made

- **Followed the plan as written.** Both helpers were placed at the documented anchors, with the documented short-circuit chain (`_check_disk_mid_run || _abort_disk_full`), with the documented `function name()` declaration style, with the documented `${MIN_DISK_SPACE_GB:-5}` fallback for the single-source-of-truth threshold (D-08), and with the documented `FUNCNAME[1]` reference for caller-context in the log_json call. No deviations to the spec.
- **Added 2-line explanatory doc comment** at each `start_func` / `end_func` call site. The plan called for the helper line plus inline reasoning (which a single-line trailing comment cannot easily express); the chosen 3-line `# ... \n# ...` doc + 1-line guard format reads cleanly and survives future re-formatters. The plan did not forbid this, and the in-file rationale ("why first-in-start" / "why last-in-end") is genuinely non-obvious for future maintainers.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed test harness regression in tests/unit/test_verbosity.bats**
- **Found during:** Task 2 verification (running `bats tests/unit/`)
- **Issue:** The test sed-extracts `start_func` from `modules/core.sh` and runs it in isolation (without sourcing `modules/utils.sh`). After Task 2, `start_func` calls `_check_disk_mid_run || _abort_disk_full` as its first statement; in the isolated harness, both helpers are undefined, both calls fail with "command not found", both errors land in stderr → `[[ "$output" == "" ]]` assertion fails (test "start_func silent at verbosity 1").
- **Fix:** Added two-line stub in `setup()` immediately after the existing `getElapsedTime` / `log_json` stubs: `_check_disk_mid_run() { return 0; }` and `_abort_disk_full() { return 0; }`. Stubs match the pattern already established for sibling utility helpers, no other test mechanics changed.
- **Files modified:** tests/unit/test_verbosity.bats
- **Verification:** `bats tests/unit/test_verbosity.bats` 12/12 pass; full suite `bats tests/unit/` 246/246 pass; `bats tests/security/` 34/34 pass.
- **Committed in:** f205abf4 (Task 2 commit — bundled because the test break and its fix have a strict dependency on the Task 2 source change; splitting into a separate commit would leave the suite red between commits)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Single auto-fix preserved test-suite integrity. The fix is mechanical (stub injection) and matches the file's existing pattern. No scope creep, no plan-spec violation.

## Issues Encountered

- **Test harness pollution from sed-extraction:** `tests/unit/test_verbosity.bats` uses `sed -n '/^function start_func()/,/^}/p' core.sh` to source `start_func` in isolation. This pattern survives small additions inside `start_func`'s body but breaks when the body adds calls to helpers defined in OTHER files. Documented as Rule 1 deviation above; future plans that add cross-file dependencies to `start_func` / `end_func` should expect the same test-harness coupling and stub accordingly.
- **No other issues.** Plan executed as written, all acceptance criteria verified, all smoke tests pass.

## User Setup Required

None — no external service configuration required. The disk-full guard is enabled by default via the same `MIN_DISK_SPACE_GB` value already used by the pre-flight check (effective default 5GB at `modes.sh:23`). No new CLI flag, no new config knob, no behavioral change to existing successful runs.

## Next Phase Readiness

- RESIL-02 closed: the v1 success criterion ("A scan that exhausts disk space mid-run aborts with a clear ENOSPC error message rather than producing zero-byte or truncated output files") is verified via behavior smokes — a `MIN_DISK_SPACE_GB=99999999` injection causes `start_func` to exit 1 with `_print_error "disk_full: aborting (...)"` on stderr and a `reason=disk_full` JSONL log entry, with no orphan `.inprogress_<fn>` for the aborting function.
- Phase 4 (TEST-01) gains a clean target: the guard pattern (`_check_disk_mid_run || _abort_disk_full`), the FUNCNAME[1]-driven log payload, the asymmetric anchor placement, and the EXIT-trap composition with Plan 01-01 are all behaviors that should have dedicated regression coverage.
- Phase 5 (DOCS-02) is unaffected by this plan — neither `reconftw.cfg:39` (where `MIN_DISK_SPACE_GB=2` lives) nor `modules/modes.sh:23` (where the `:-5` fallback lives) were modified in Phase 1; the 2-vs-5 reconciliation remains scoped to Phase 5 as planned.
- No blockers for downstream phases.

## Verification

- `bash -n modules/utils.sh modules/core.sh` exits 0.
- `shellcheck -s bash --severity=error modules/utils.sh modules/core.sh` exits 0 (no new error-level findings vs. baseline).
- `shfmt -d -i 4 -bn -ci modules/utils.sh modules/core.sh` reports zero diff in the new code blocks (pre-existing baseline diffs in unrelated parts of both files are unchanged).
- All Task 1 acceptance criteria confirmed via grep:
  - `^function _check_disk_mid_run`: 1 match
  - `^function _abort_disk_full`: 1 match
  - `check_disk_space "${MIN_DISK_SPACE_GB:-5}"`: 1 match (inside `_check_disk_mid_run`)
  - `reason=disk_full`: 1 match (inside `_abort_disk_full` log_json call)
  - Visual ordering: `check_disk_space` → `_check_disk_mid_run` → `_abort_disk_full` → `progress_bar` (preserved)
- All Task 2 acceptance criteria confirmed via grep + awk:
  - `_check_disk_mid_run || _abort_disk_full` count: 2 (one each in start_func and end_func)
  - In `start_func`: the guard line comes BEFORE `local current_date` AND BEFORE `touch "$called_fn_dir/.inprogress_${1}"`
  - In `end_func`: the guard line comes AFTER `log_json "SUCCESS" ...` AND BEFORE the closing `}`
  - Plan 01-01 sentinel ops (`touch .inprogress_${1}` in start_func, `rm -f .inprogress_${fn}` in end_func) still present, unchanged
  - Existing `touch "$called_fn_dir/.${fn}"` at end_func still present
- Behavior smokes (all passed):
  - **Smoke 1 (start_func abort):** With `MIN_DISK_SPACE_GB=99999999`, `start_func test_fn "desc"` exits 1, stderr contains `[FAIL] disk_full: aborting (Disk space LOW: required 99999999GB, available 20GB at /tmp/...)`, LOGFILE JSONL has `ERROR start_func Disk space exhausted reason=disk_full info=...`, and `.inprogress_test_fn` is NOT created (disk check ran before sentinel touch).
  - **Smoke 2 (normal path):** With `MIN_DISK_SPACE_GB=0`, `start_func test_fn2 "desc"` exits 0 and `.inprogress_test_fn2` IS created (sentinel touch reached).
  - **Smoke 3 (EXIT-trap composition):** With a pre-seeded `.inprogress_sub_brute` (simulating a leftover) and `MIN_DISK_SPACE_GB=99999999`, running `start_func test_new_fn` inside a subshell with `trap '_cleanup_inprogress' EXIT` (matching the Plan 01-01 registration) — the abort triggers exit 1, the EXIT trap fires, the pre-seeded `.inprogress_sub_brute` IS cleared (no fake resume next run), and `.inprogress_test_new_fn` is NOT created.
- All 246 bats unit tests pass; all 34 bats security tests pass; no regressions.

## Self-Check: PASSED

Files verified to exist:
- FOUND: `modules/utils.sh` (modified — 13 lines added)
- FOUND: `modules/core.sh` (modified — 8 lines added across two boundaries)
- FOUND: `tests/unit/test_verbosity.bats` (modified — 3 lines added for stubs)
- FOUND: `.planning/phases/01-resilient-resume-timeout-safety/01-02-SUMMARY.md` (this file, being written)

Commits verified on `worktree-agent-a9aa70e0a74b2b729`:
- FOUND: `2a2013d3` — feat(01-02): add _check_disk_mid_run + _abort_disk_full helpers in utils.sh
- FOUND: `f205abf4` — feat(01-02): wire _check_disk_mid_run into start_func + end_func boundaries

---
*Phase: 01-resilient-resume-timeout-safety*
*Completed: 2026-05-13*
