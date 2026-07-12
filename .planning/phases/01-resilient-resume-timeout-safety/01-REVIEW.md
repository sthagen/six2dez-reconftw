---
phase: 01-resilient-resume-timeout-safety
reviewed: 2026-05-13T14:30:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - lib/parallel.sh
  - modules/core.sh
  - modules/modes.sh
  - modules/utils.sh
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 01: Code Review Report (Re-review post 01-04 / 01-05)

**Reviewed:** 2026-05-13T14:30:00Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Re-review after gap closure. Plans 01-04 and 01-05 landed the three critical fixes from the prior
review (CR-01 EXIT-trap gating, CR-02 timeout-under-quiet, CR-03 process-tree kill). All three
fixes look structurally correct and pass through the workflows I traced. The remaining findings
are:

1. **WR-01 (carried over):** CR-04 from the prior review — the unguarded
   `touch "$called_fn_dir/.${fn}"` in `end_func` (modules/core.sh:1485) — was NOT addressed by
   either 01-04 or 01-05 and is still present. Same unguarded touch in `end_subfunc`
   (modules/core.sh:1572). Pre-existing defect, surfaced in the prior review, still open.

2. **WR-02 (new doc drift introduced by CR-01):** Two comments in the codebase claim the EXIT
   trap "clears .inprogress_*" — modules/core.sh:1421 and modules/utils.sh:455. Post-CR-01,
   the EXIT trap is gated on `_RECON_CLEAN_EXIT=true`. On `_abort_disk_full`'s `exit 1` path,
   the flag is `false`, so `_cleanup_inprogress` returns early without clearing anything. The
   actual behavior is correct (sentinels survive disk-full abort → next run resumes), but the
   inline documentation now misrepresents the mechanism. A maintainer reading these comments
   will be misled when reasoning about the trap chain.

3. **WR-03 (new — recursive sweep race in `_kill_tree`):** `_kill_tree` discovers all children
   of `$parent` via `pgrep -P "$parent"` BEFORE sending the signal to the parent. If a child
   has already exited between `pgrep` and the recursive `kill`, the recursion is harmless
   (kill on dead PID returns error, swallowed). But if `_kill_tree` is called twice for the
   same wrapper PID (which CAN happen across heartbeat iterations — WR-03 from the prior
   review remains unresolved per 01-05 SUMMARY referring to it as deferred), the second call
   will re-walk a now-partially-dead tree and re-signal whichever children are now zombies
   (no-op) plus race against the kernel's reaping. The user-visible impact is duplicate
   `.status_<fn>` / `.status_reason_<fn>` writes and duplicate `log_json` lines. Low severity
   but verifiable.

No new BLOCKERs. The three CR fixes from 01-04 and 01-05 are landed correctly.

## Warnings

### WR-01: Unguarded `touch "$called_fn_dir/.${fn}"` in `end_func` and `end_subfunc` (pre-existing CR-04, not addressed)

**File:** `modules/core.sh:1485`, `modules/core.sh:1572`
**Issue:**
The CR-04 finding from the prior review remains unaddressed. The fix at modules/core.sh:1483
correctly guards the new `.inprogress_<fn>` rm with `[[ -n "${called_fn_dir:-}" ]]`, but the
adjacent checkpoint write at line 1485 is still bare:

```bash
if [[ -n "${called_fn_dir:-}" ]]; then
    rm -f "$called_fn_dir/.inprogress_${fn}" 2>/dev/null || true
fi
touch "$called_fn_dir/.${fn}"   # <-- still unguarded
```

If `called_fn_dir` is empty (custom workflow, alternative entrypoint, future test runner that
doesn't call `start()`), the touch expands to `touch /.${fn}` which is either a permission-denied
error (non-root) or silently creates files at filesystem root (root). The prior review flagged
this for line 1483; the rm was moved into the guard but the touch was not. Same pre-existing
defect at `end_subfunc` line 1572: `touch "$called_fn_dir/.${2}"`.

The prior review's CR-04 was apparently scoped out of plans 01-04 and 01-05 (which focused
narrowly on CR-01, CR-02, CR-03). Carry forward as a follow-up.

**Fix:**

```bash
# modules/core.sh, around end_func line 1482-1485:
if [[ -n "${called_fn_dir:-}" ]]; then
    rm -f "$called_fn_dir/.inprogress_${fn}" 2>/dev/null || true
    touch "$called_fn_dir/.${fn}" 2>/dev/null || true
fi
```

And mirror in `end_subfunc`:

```bash
# modules/core.sh, around end_subfunc line 1572:
function end_subfunc() {
    if [[ -n "${called_fn_dir:-}" ]]; then
        touch "$called_fn_dir/.${2}" 2>/dev/null || true
    fi
    end_sub=$(date +%s)
    ...
```

---

### WR-02: Stale comments claim EXIT trap clears `.inprogress_*` — post-CR-01 it does not

**File:** `modules/core.sh:1420-1421`, `modules/utils.sh:455`
**Issue:**
The CR-01 fix gated `_cleanup_inprogress` on `_RECON_CLEAN_EXIT`. Two surviving comments still
describe the pre-CR-01 unconditional-sweep behavior:

```bash
# modules/core.sh:1419-1422
function start_func() {
    # Mid-run disk-full guard (D-07/D-09): abort BEFORE any state write so the
    # Plan 01-01 EXIT trap clears .inprogress_* with no orphan for this function.
    _check_disk_mid_run || _abort_disk_full
```

```bash
# modules/utils.sh:455
# Hard-abort the run on disk-full mid-run detection (D-09). EXIT trap (Plan 01-01) clears .inprogress_* on the way out.
function _abort_disk_full() {
```

Post-CR-01, `_abort_disk_full`'s `exit 1` triggers the EXIT trap, but `_cleanup_inprogress`
guards on `_RECON_CLEAN_EXIT=true` (set ONLY by `end()`'s last statement). `_abort_disk_full`
does not set the flag, so the trap returns 0 without sweeping. The actual behavior is correct
for resume semantics (sentinels survive abort → next run shows the resume banner), but the
comments now describe the OLD mechanism. The same drift already broke the prior review's
analysis path because the start_func comment originally said "EXIT trap clears it on graceful
exit" before being rewritten in plan 01-04 for the touch-the-sentinel block at lines 1431-1436.
The comment at line 1421 (above the disk-guard) and the one in utils.sh were missed.

Compare to the corrected comment at modules/core.sh:1431-1436 which DOES describe the gated
behavior accurately. The two stale comments should be brought into alignment with that one.

**Fix:**

```bash
# modules/core.sh:1419-1422 — adjust comment to reflect gated semantics:
function start_func() {
    # Mid-run disk-full guard (D-07/D-09): abort BEFORE any state write so there
    # is no .inprogress_<fn> orphan for this function. _abort_disk_full's exit 1
    # leaves _RECON_CLEAN_EXIT=false so the EXIT trap's _cleanup_inprogress does
    # NOT sweep — pre-existing sentinels from other in-flight functions survive
    # and drive the next run's resume banner (CR-01 fix; see modes.sh end()).
    _check_disk_mid_run || _abort_disk_full
```

```bash
# modules/utils.sh:455 — adjust comment to reflect gated semantics:
# Hard-abort the run on disk-full mid-run detection (D-09). exit 1 leaves
# _RECON_CLEAN_EXIT=false so the EXIT trap PRESERVES .inprogress_* sentinels —
# the next run shows the resume banner and re-enters interrupted functions
# (CR-01 fix; see modes.sh end() for the clean-exit flag flip).
function _abort_disk_full() {
```

This is a documentation-only change; no behavior change required.

---

### WR-03: `_timeout_kill_job` re-fires across heartbeat iterations — duplicate status writes and log lines

**File:** `lib/parallel.sh:520-524`, `lib/parallel.sh:641-645`, `lib/parallel.sh:77-105`
**Issue:**
The CR-03 fix did NOT include WR-03 from the prior review (which was a separate "track signaled
PIDs" recommendation). Within the heartbeat loop's `for idx in "${!batch_pids[@]}"` block, the
timeout check fires on every outer-while iteration:

```bash
if kill -0 "${batch_pids[$idx]}" 2>/dev/null; then
    alive=1
    job_dur=$((now - batch_starts[$idx]))
    if (( _to > 0 )) && (( job_dur > _to )); then
        _timeout_kill_job "${batch_pids[$idx]}" "${batch_funcs[$idx]}" "$job_dur"
    fi
```

`_timeout_kill_job` internally sleeps up to `grace` seconds polling `kill -0`. When it returns:
- If the wrapper PID is reaped, next `kill -0` from outer loop returns false → idx skipped.
- If the wrapper PID is in zombie state (parent hasn't waited yet), `kill -0` STILL returns
  success on most kernels (esp. Linux). The next outer iteration re-fires `_timeout_kill_job`,
  which re-walks the tree (now mostly dead), re-writes `.status_${func_name}=FAIL`,
  re-writes `.status_reason_${func_name}=timeout`, and re-emits an ERROR `log_json` line.
- The second call's `kill -KILL` after grace is also a no-op (already dead).

Behavior is correct but wasteful (10s redundant grace sleep, duplicate persisted status, double
log entries). On a slow kernel with multiple timed-out jobs, this also blocks the outer
heartbeat from checking the OTHER still-alive jobs for their timeouts during the second-call's
grace sleep.

**Fix:**
Track signaled PIDs in a local associative array, scoped to the heartbeat loop:

```bash
# Add near the local declarations at lib/parallel.sh:509 / :630:
local -A _timed_out_pids=()

# In the alive-check block:
if kill -0 "${batch_pids[$idx]}" 2>/dev/null; then
    alive=1
    job_dur=$((now - batch_starts[$idx]))
    if (( _to > 0 )) && (( job_dur > _to )) \
        && [[ -z "${_timed_out_pids[${batch_pids[$idx]}]:-}" ]]; then
        _timeout_kill_job "${batch_pids[$idx]}" "${batch_funcs[$idx]}" "$job_dur"
        _timed_out_pids[${batch_pids[$idx]}]=1
    fi
    ...
```

Mirror the same change in the second heartbeat loop at lines 641-645. This was the WR-03
recommendation from the prior review; 01-05 SUMMARY (line 117-118) calls out CR-02 + CR-03
explicitly as the only fixes in scope and does not claim WR-03 was addressed.

---

## Info

### IN-01: `start_subfunc` does not write `.inprogress_<fn>` — sub-function resume coverage gap (carried from prior WR-07)

**File:** `modules/core.sh:1558-1569`
**Issue:**
The sentinel lifecycle applies only to `start_func`/`end_func`, not to
`start_subfunc`/`end_subfunc`. `sub_passive`, `sub_crt`, `sub_active`, `sub_brute`, etc.
(sub-functions wrapped by `start_subfunc`) participate in the checkpoint guard system (they
write `.<fn>` and `.status_<fn>`) but do NOT write `.inprogress_<fn>`. A SIGINT during a
sub-function leaves no marker for the resume banner to surface. The parent (`subdomains_full`)
IS protected, so the user gets correct re-run on re-invocation, but the resume-banner WARN
won't name the affected sub-functions specifically.

Pre-existing. Documented in the prior review as WR-07; 01-04/01-05 did not extend the sentinel
pattern to sub-functions. Recommend either:
- Mirror the inprogress touch/rm in `start_subfunc`/`end_subfunc`, OR
- Add a header comment to `start_subfunc` explicitly stating sub-functions rely on `.<fn>`
  only and are not surfaced in the resume banner.

---

### IN-02: `_kill_tree` recursion has no depth bound — bash stack risk on pathological process trees

**File:** `lib/parallel.sh:55-66`
**Issue:**
```bash
function _kill_tree() {
    local parent="$1" sig="${2:-TERM}"
    local child
    if command -v pgrep >/dev/null 2>&1; then
        for child in $(pgrep -P "$parent" 2>/dev/null); do
            _kill_tree "$child" "$sig"
        done
    fi
    kill "-$sig" "$parent" 2>/dev/null || true
}
```

Unbounded recursion via `_kill_tree "$child"`. In practice, parallel wrapper subshells in
reconftw spawn at most 2-3 levels deep (subshell → tool → tool's children for piped tools like
`subfinder | anew`), so this is theoretical. But on a misbehaving tool that fork-bombs (or in
a deeply-nested axiom tool chain), the recursion depth equals the tree depth. Bash has a
default function-call stack limit (FUNCNEST, typically unset/unlimited but kernel stack ≈ 8MB
caps it at ~5000-10000 frames). Acceptable for current code.

Optional hardening: pass an explicit depth limit. Not required for the v1 fix.

```bash
function _kill_tree() {
    local parent="$1" sig="${2:-TERM}" depth="${3:-0}"
    local max_depth="${PARALLEL_KILL_MAX_DEPTH:-16}"
    (( depth >= max_depth )) && { kill "-$sig" "$parent" 2>/dev/null || true; return; }
    ...
    _kill_tree "$child" "$sig" "$((depth + 1))"
    ...
}
```

---

### IN-03: Resume banner uses `ls -1` over a glob — pre-existing IN-01

**File:** `modules/modes.sh:169`
**Issue:**
```bash
mapfile -t _leftover < <(ls -1 "${called_fn_dir}"/.inprogress_* 2>/dev/null)
```

`ls -1` over a non-matching glob is a fork + stderr-noise pattern. A pure-bash nullglob loop
would be portable and faster, and matches how the rest of reconftw enumerates files. Pre-existing
from the prior review's IN-01; not addressed by 01-04 (which touched only `_RECON_CLEAN_EXIT`
init and `_cleanup_inprogress` body) or 01-05 (scoped to CR-02/CR-03 in lib/parallel.sh).

```bash
local -a _leftover=()
shopt -s nullglob
_leftover=("${called_fn_dir}"/.inprogress_*)
shopt -u nullglob
```

This is style, not a defect.

---

## Verified-correct Fixes

For traceability, these are the prior-review CRs that I confirmed landed correctly in 01-04 / 01-05:

- **CR-01 (EXIT trap defeats `.inprogress_<fn>` resume on SIGINT/SIGTERM)** — closed by
  `_RECON_CLEAN_EXIT` flag introduced at modules/modes.sh:16 (init in `start()`),
  modules/modes.sh:517 (set-true as final statement of `end()`), and
  `_cleanup_inprogress` gating at modules/utils.sh:153-157
  (`[[ "${_RECON_CLEAN_EXIT:-false}" == "true" ]] || return 0`). Traced through all mode
  flows (`-r`, `-s`, `-p`, `-a`, `-w`, `-n`, `-z`, `-c`, monitor, report-only, multi); each
  workflow that calls `start()` also calls `end()`, which sets the flag true. Workflows that
  bypass `end()` (SIGINT via cleanup_on_exit, _abort_disk_full's exit 1, unhandled error)
  leave the flag false and sentinels survive. The "-l list" loop correctly resets the flag
  per-iteration in each `start()` call.

- **CR-02 (PARALLEL_JOB_TIMEOUT_SECONDS silently disabled in --quiet)** — closed by splitting
  the heartbeat-loop gate at lib/parallel.sh:500-508 and lib/parallel.sh:621-629. The new
  `_loop_active` enters the loop whenever `hb > 0`, and the `_to > 0` OR `_verbose_progress`
  condition determines whether to actually keep iterating. The timeout check at lines 522-524
  and 643-645 fires regardless of verbosity. Verified that with OUTPUT_VERBOSITY=0 and
  PARALLEL_JOB_TIMEOUT_SECONDS=600, the loop runs and `_timeout_kill_job` is invoked.

- **CR-03 (_timeout_kill_job only killed wrapper subshell)** — closed by the new `_kill_tree`
  helper at lib/parallel.sh:55-66 and the two call sites at lines 87 and 93. `_kill_tree`
  walks `pgrep -P` recursively, kills children before parent, and degrades gracefully if pgrep
  is missing (`command -v pgrep` guard, fall-through to wrapper-only kill matches pre-patch
  behavior). The kill-poll-kill sequence at lines 87-93 properly TERM-graces-KILLs the entire
  subtree. `pgrep -P` confirmed available on macOS BSD (system test).

The 246/246 unit + 34/34 security bats baselines from 01-04 and 01-05 SUMMARYs hold; no test
files have been added covering the new fixes (Phase 4 / TEST-01 explicitly defers this per
01-CONTEXT.md §Claude's Discretion).

---

_Reviewed: 2026-05-13T14:30:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
