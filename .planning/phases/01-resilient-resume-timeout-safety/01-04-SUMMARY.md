---
phase: 01-resilient-resume-timeout-safety
plan: 04
subsystem: infra
tags: [bash, lifecycle, resume, checkpoints, traps, signals, resilience, gap-closure]

# Dependency graph
requires:
  - phase: 01-01
    provides: .inprogress_<fn> sentinel lifecycle, _cleanup_inprogress helper, separate EXIT-only trap, resume banner
provides:
  - _RECON_CLEAN_EXIT flag pattern for gated-trap cleanup
  - SC1 indicator-preserves-SIGINT behavior (closes CR-01 / Gap A)
  - D-02 wording reconciled with implemented semantics
affects: [04-test-coverage]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Clean-exit-gated trap cleanup: an EXIT trap whose body is gated on a flag set ONLY by the canonical wrap-up function. Signal handlers (INT/TERM via cleanup_on_exit) and internal aborts (_abort_disk_full's exit 1) bypass end() and leave the flag at false, preserving sentinel state for the next run's resume."

key-files:
  created:
    - .planning/phases/01-resilient-resume-timeout-safety/01-04-SUMMARY.md
  modified:
    - modules/modes.sh
    - modules/utils.sh
    - modules/core.sh
    - .planning/phases/01-resilient-resume-timeout-safety/01-CONTEXT.md

key-decisions:
  - "Chose clean-exit-flag (_RECON_CLEAN_EXIT) over 'drop EXIT trap entirely': preserves the original D-02 graceful-exit intent (clean run leaves a tidy directory) AND honors SC1 (Ctrl+C preserves the indicator). Reviewer's CR-01 explicitly recommended the gated approach."
  - "Single anchor inside end() rather than per-workflow flag-flips. Every workflow function in modes.sh (recon, passive, all, vulns, osint, subs_menu, webs_menu, zen_menu, monitor_mode) calls end() per the project's lifecycle contract, so one flip there covers all clean-traversal paths without multiplying the maintenance burden."
  - "cleanup_on_exit body left untouched — the loud 'Interrupted. Cleaning up...' banner and exit 130 remain the user-facing interruption signal. The fix lives entirely in the EXIT trap's body, not the INT/TERM handler."
  - "D-02 reworded in-place (not appended/deprecated). The decision ID and intent are stable; only the implementation-mechanism phrasing changed. Future verifiers reading the locked decision see the gated-trap semantics directly."

patterns-established:
  - "Gated EXIT trap with clean-exit flag: a useful general pattern for any 'sweep on clean exit only' bookkeeping in a shell project that also installs an INT/TERM handler that calls exit. Without the gate the EXIT trap fires for both paths and the signal-handler-preserves-state guarantee breaks."

requirements-completed: []
gap_closure: true
closes_gaps: [CR-01]

# Metrics
duration: ~5 min (from PLAN_START_EPOCH 1778669108 to last commit)
completed: 2026-05-13
---

# Phase 01 Plan 04: CR-01 Clean-Exit Gate for `.inprogress_<fn>` Sentinels — Summary

**Closes Gap A from 01-VERIFICATION.md by introducing a `_RECON_CLEAN_EXIT` flag that gates `_cleanup_inprogress`. SIGINT/SIGTERM via `cleanup_on_exit`'s `exit 130` now preserves `.inprogress_<fn>` sentinels through the EXIT trap chain, so the next run's WARN resume banner fires correctly. SC1 transitions PARTIAL → VERIFIED on next verifier run.**

## Performance

- **Duration:** ~5 minutes (3 tasks, ~1.7 min per task)
- **Started:** 2026-05-13T10:45:08Z (PLAN_START_EPOCH 1778669108)
- **Completed:** 2026-05-13T10:51:05Z (last commit `17ae1e17`)
- **Tasks:** 3 (all `type="auto"`)
- **Files modified:** 4 (`modules/modes.sh`, `modules/utils.sh`, `modules/core.sh`, `.planning/phases/01-resilient-resume-timeout-safety/01-CONTEXT.md`)

## Accomplishments

- **Task 1** initialises `_RECON_CLEAN_EXIT=false` at the top of `start()` (between `global_start=$(date +%s)` at :15 and `set +m 2>/dev/null || true` at :17) and gates `_cleanup_inprogress`'s body on `${_RECON_CLEAN_EXIT:-false} == "true"`. Early-return 0 on the non-clean path preserves the existing contract that the EXIT trap never propagates a non-zero `$?` to the shell exit code. `cleanup_on_exit` body and both trap install lines (`trap 'cleanup_on_exit' INT TERM` at :122, `trap '_cleanup_inprogress' EXIT` at :123) untouched.
- **Task 2** sets `_RECON_CLEAN_EXIT=true` as the last executable statement of `end()` (immediately before its closing `}` at modes.sh :518). A 6-line comment block above the assignment documents the clean-exit-only intent and the asymmetric placement rationale (no leaks into `cleanup_on_exit`, no leaks into `_abort_disk_full`, no per-workflow duplicates). Workflow-coverage spot check confirmed `end` is called by 10 workflow functions (recon, passive, all, vulns, osint, subs_menu, webs_menu, zen_menu, monitor_mode, plus an additional menu path), so the single anchor inside `end()` is sufficient.
- **Task 3** rewrites the misleading 4-line comment block at `modules/core.sh:1431-1434` (was: "EXIT trap clears it on graceful exit" — flagged by 01-VERIFICATION.md anti-pattern table line 137) into a 6-line block that documents the clean-exit-flag gating explicitly. Also rewords the body of D-02 in `01-CONTEXT.md` so the locked decision matches the implemented semantics — decision ID and intent preserved, only the implementation-mechanism phrasing changed from "trap on EXIT INT TERM" to "clean-exit-gated trap cleanup" anchored on `_RECON_CLEAN_EXIT`. D-01 and D-03..D-17 unchanged.

## Task Commits

Each task committed atomically:

1. **Task 1: Init flag + gate `_cleanup_inprogress`** — `5fbbbf1d` (fix)
2. **Task 2: Flip flag at end of `end()`** — `79967d71` (fix)
3. **Task 3: Reconcile core.sh comment + D-02 wording** — `17ae1e17` (docs)

## Files Created/Modified

- `modules/modes.sh` — 2 insertions: (1) `_RECON_CLEAN_EXIT=false` at the top of `start()` between `global_start=$(date +%s)` and `set +m 2>/dev/null || true`; (2) 6-line comment block + `_RECON_CLEAN_EXIT=true` as the last executable statement of `end()`.
- `modules/utils.sh` — body of `_cleanup_inprogress` (4-line function) rewritten: now gates on `${_RECON_CLEAN_EXIT:-false} == "true"` with early `return 0` on the non-clean path. Comment block above the function (5 lines, was 1 line) documents the CR-01 fix. `cleanup_on_exit` body, signature, and trap install untouched.
- `modules/core.sh` — comment block at `:1431-1434` (4 lines) rewritten to 6 lines. The header `# Resume sentinel (RESIL-01 / D-01)` is preserved; the misleading "EXIT trap clears it on graceful exit" sentence is replaced with explicit clean-exit-flag semantics referencing `_RECON_CLEAN_EXIT`, `cleanup_on_exit`, and CR-01 / SC1. The sentinel touch logic at :1437-1439 is unchanged.
- `.planning/phases/01-resilient-resume-timeout-safety/01-CONTEXT.md` — body of D-02 (single bullet under §Decisions) rewritten in-place. The `- **D-02:**` header is preserved; the body changes from "trap on EXIT INT TERM" to "clean-exit-gated trap cleanup" anchored on `_RECON_CLEAN_EXIT`. Decision count integrity verified: D-01 through D-17 each appear exactly once.

## Behavioral Smokes (Pass/Fail Evidence)

All three smokes run inside subshells that source `./reconftw.sh --source-only` (which loads libs and modules without executing the recon flow). Sets `called_fn_dir` to a `mktemp -d` directory and `_RECON_CLEAN_EXIT=false` to match `start()`'s initial state. `set -u` is intentionally NOT used because `lib/common.sh`'s source-guard `[[ -n "$_COMMON_SH_LOADED" ]]` would trip it.

| Smoke                                                     | Script                       | Expected                                                                     | Result        |
| --------------------------------------------------------- | ---------------------------- | ---------------------------------------------------------------------------- | ------------- |
| SC1 inverted: SIGINT preserves `.inprogress_sub_brute`    | `/tmp/sc1_recheck.sh`        | Both `.inprogress_sub_brute` AND `.sub_passive` survive `kill -INT $$`        | `SC1_OK`      |
| Task 1 default: flag=false → sentinel NOT swept on exit 0 | `/tmp/task1_default_check.sh`| `.inprogress_sub_brute` remains after `exit 0` with flag at default `false`  | `TASK1_DEFAULT_OK` |
| Task 2 clean: flag=true → sentinel swept on exit 0        | `/tmp/clean_recheck.sh`      | `.inprogress_sub_brute` removed by EXIT trap when subshell sets flag=true     | `CLEAN_OK`    |
| Health-check happy path                                   | `./reconftw.sh --health-check` | exit 0, no "Interrupted..." printed, no leftover `.inprogress_*` files     | exit 0        |
| bats unit baseline                                        | `bats tests/unit/`           | 246 PASS                                                                     | 246/246 PASS  |
| bats security baseline                                    | `bats tests/security/`       | 34 PASS                                                                      | 34/34 PASS    |

The smokes are the source of truth for "did the fix land correctly." Per CONTEXT.md §Claude's Discretion, no new bats tests are added in this phase — Phase 4 (TEST-01) owns coverage for the `.inprogress_*` lifecycle and related paths.

## Deviations from Plan

**None — plan executed exactly as written.**

Edge note: the planner's acceptance-criterion awk script for the "ORDER_OK" check on the `_RECON_CLEAN_EXIT=false` line position (`g<f && f<s`) scans the entire file, so the `g` (global_start) capture is overwritten by later occurrences of `global_start=$(date +%s)` in other workflow functions (`passive()`, `all()`, etc.). Re-running the same awk scoped to the `start()` block (`awk '/^function start\(\) \{/,/^}/'`) returns `ORDER_OK` (g=3, f=4, s=5 within the block). This is an acceptance-script scoping issue, not an implementation defect — the actual ordering inside `start()` at lines 15-17 is correct. Documented here for the verifier.

## Authentication Gates

None.

## Threat Flags

None — this plan modifies a single shell variable, a function body's early-return, a comment block, and a documentation paragraph. No new attack surface, network endpoints, auth paths, file-access patterns, or trust boundaries are introduced. The `_RECON_CLEAN_EXIT` flag is process-local (no environment export), is set/read only by `start()`, `end()`, and `_cleanup_inprogress`, and runs inside the same single-operator-per-target invariant that already underpins the trap-based resume design.

## Known Stubs

None — no UI components, no data-rendering stubs, no placeholder text introduced.

## TDD Gate Compliance

Not applicable — this plan's `type` is `execute` (not `tdd`), and the phase's CONTEXT.md §Claude's Discretion explicitly defers test coverage for the `.inprogress_*` lifecycle to Phase 4 (TEST-01). The bats baseline (246/246 unit + 34/34 security) is the regression check; behavioral smokes are the source of truth for the fix landing correctly.

## Notes for Downstream Consumers

- **Gap A (CR-01) closed.** Next verifier run should transition SC1 (`.inprogress_<fn>` indicator on SIGINT/SIGTERM) from PARTIAL → VERIFIED. The orthogonal SC3 gaps (CR-02 `--quiet` mode timeout disablement; CR-03 wrapper-PID-only kill) are NOT addressed by this plan — they are covered by plan 01-05.
- **`_RECON_CLEAN_EXIT` flag pattern is a Phase 5 documentation candidate.** The pattern is reusable for any future "sweep on clean exit only" bookkeeping where an INT/TERM handler that calls `exit` would otherwise defeat an EXIT trap's intent. Worth documenting in `.planning/codebase/CONVENTIONS.md` or `.planning/codebase/PATTERNS.md` at the Phase 5 alignment step.
- **`01-CONTEXT.md` D-02 was rewritten in-place.** Downstream consumers (researchers, planners, future verifiers) read the updated body and see the gated-trap semantics directly. The decision intent ("graceful exits leave NO `.inprogress_*` files") is preserved; only the implementation-mechanism phrasing changed. No traceability link updates needed elsewhere — `01-CONTEXT.md` is the canonical source for the phase's locked decisions.
- **The behavioral smoke `/tmp/sc1_recheck.sh` is the next verifier's check** for the SC1 indicator-survives-SIGINT property. It is equivalent to the verifier's original `/tmp/sc1_v3.sh` reproduction but inverted: instead of expecting `.inprogress_sub_brute` to be wiped, it expects it to survive.

## Self-Check: PASSED

Created files exist:
- `.planning/phases/01-resilient-resume-timeout-safety/01-04-SUMMARY.md` — this file (created by current Write call)

Commits exist (will be confirmed by post-write commit; expected hashes in this branch):
- `5fbbbf1d`: fix(01-04): gate _cleanup_inprogress on _RECON_CLEAN_EXIT (CR-01)
- `79967d71`: fix(01-04): flip _RECON_CLEAN_EXIT=true as last statement of end() (CR-01)
- `17ae1e17`: docs(01-04): reconcile core.sh comment and D-02 with gated-trap semantics

Acceptance criteria status:
- Task 1: All checks PASS (flag init present, gate body correct, no leaks into cleanup_on_exit, traps unchanged, SC1 smoke OK, default-flag smoke OK, bash -n / shellcheck clean)
- Task 2: All checks PASS (single flag-flip in end(), placed before closing brace, comment references CR-01/clean traversal/D-02, no leaks into cleanup_on_exit or _abort_disk_full, clean smoke OK, SC1 smoke still OK, 246/246 bats unit PASS)
- Task 3: All checks PASS (misleading sentence removed from core.sh, new wording references _RECON_CLEAN_EXIT and CR-01, D-02 reworded with clean-exit-gated trap cleanup phrasing, D-01..D-17 each present once, bash -n / shellcheck clean, --health-check exits 0)

Phase-level success criteria (from <success_criteria>):
- [x] All 3 tasks executed
- [x] Each task committed individually (5fbbbf1d, 79967d71, 17ae1e17)
- [x] SUMMARY.md created in plan directory (this file) — committed in next step
- [x] All acceptance criteria pass (SC1 smoke shows .inprogress_sub_brute survives SIGINT — `SC1_OK`)
- [x] No modifications to shared orchestrator artifacts (STATE.md, ROADMAP.md untouched)
