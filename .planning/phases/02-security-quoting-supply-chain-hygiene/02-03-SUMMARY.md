---
phase: 02-security-quoting-supply-chain-hygiene
plan: "03"
subsystem: security
tags: [axiom, bash, supply-chain, sha256, tools-lock, word-splitting]

requires:
  - phase: 01-resilient-resume-timeout-safety
    provides: stable function lifecycle (start_func/end_func) used in all modules

provides:
  - Global AXIOM_EXTRA_ARGS_ARR array parsed once in reconftw.sh; 36 call sites migrated
  - Optional SHA256 verification of rustup and uv installer downloads
  - tools.lock pinning 5 stability-critical Go tools (nuclei, httpx, ffuf, puredns, subfinder)

affects:
  - 04-test-coverage-reinforcement  # tests should cover AXIOM_EXTRA_ARGS_ARR tokenisation (deferred to TEST-03)
  - any future contributor adding axiom-scan calls  # must use "${AXIOM_EXTRA_ARGS_ARR[@]}"

tech-stack:
  added: [tools.lock (plain-text Go tool lock manifest)]
  patterns:
    - "Global AXIOM_EXTRA_ARGS_ARR pattern: parse once in reconftw.sh, expand with \"${AXIOM_EXTRA_ARGS_ARR[@]}\" at every axiom-scan call site"
    - "Env-var-driven SHA256 verification: RUSTUP_INSTALLER_SHA256 / UV_INSTALLER_SHA256 mirror GETJSWORDS_SHA256 / AXIOM_CONFIG_SHA256 precedent"
    - "tools.lock manifest: binary=module@version, blank/comment-line tolerant, read into pinned_tools assoc array in install_tools()"

key-files:
  created:
    - tools.lock  # 5 pinned Go tool entries for nuclei/httpx/ffuf/puredns/subfinder
  modified:
    - reconftw.sh  # AXIOM_EXTRA_ARGS_ARR global parse (early + post-config)
    - modules/subdomains.sh  # 21 axiom-scan call sites migrated to AXIOM_EXTRA_ARGS_ARR
    - modules/web.sh  # 15 call sites + webprobe_full local block removed
    - install.sh  # install_rust_uv() SHA256 gates; install_tools() tools.lock consumer; doc comment

key-decisions:
  - "D-07: AXIOM_EXTRA_ARGS_ARR parsed twice — early (before --source-only) for unit test smoke tests, and again after config load for production use; config parse always overwrites env-only value"
  - "D-09: webprobe_full local axiom_extra_args=() block fully removed; guard if [[ ${#AXIOM_EXTRA_ARGS_ARR[@]} -gt 0 ]] kept for defensive symmetry"
  - "D-11: SHA256 verification is opt-in via env vars; unset env = pre-change HTTPS-trust behaviour; return 1 on mismatch aborts install_rust_uv but not overall install.sh (ERR trap is log-and-continue)"
  - "D-12/D-13: Only 5 stability-critical tools pinned in tools.lock; ~50 unpinned tools stay at @latest per commit 71653984 intent"

patterns-established:
  - "Array expansion pattern: \"${AXIOM_EXTRA_ARGS_ARR[@]}\" for all axiom-scan extra-args injection"
  - "tools.lock format: <binary>=<module>@<version> with # comments; read via while IFS='=' read"

requirements-completed: [SEC-03, SEC-04]

duration: 35min
completed: 2026-05-13
---

# Phase 2 Plan 3: AXIOM Array Refactor + SHA256 Gates + tools.lock Summary

**Global AXIOM_EXTRA_ARGS_ARR array replaces 36 word-split call sites; opt-in SHA256 verification for rustup/uv installers; tools.lock pins 5 critical Go tools to reproducible versions**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-05-13T12:30:00Z
- **Completed:** 2026-05-13T13:05:00Z
- **Tasks:** 3
- **Files modified:** 5 (reconftw.sh, modules/subdomains.sh, modules/web.sh, install.sh, tools.lock)

## Accomplishments

- Eliminated all 36 bare/quoted `$AXIOM_EXTRA_ARGS` / `"$AXIOM_EXTRA_ARGS"` references across modules/subdomains.sh (21 sites) and modules/web.sh (15 sites); tokenisation is now deterministic via a single global `AXIOM_EXTRA_ARGS_ARR=()` array
- Removed the per-function `local -a axiom_extra_args=()` duplicate-parse block from `webprobe_full()`, eliminating IFS side-effect risk and the invisible dual-tokenisation path
- Wired optional SHA256 integrity verification for both rustup and uv installer downloads in `install_rust_uv()`; mismatch aborts with `msg_err` + `return 1`, matching T-02-03-04 mitigation
- Created `tools.lock` with 5 pinned entries; `install_tools()` reads the manifest before the Go install loop and uses pinned versions where available, making those 5 tools reproducibly installable

## Task Commits

Each task was committed atomically:

1. **Task 1: AXIOM_EXTRA_ARGS global array + 36 call site migration** - `1f2db13a` (refactor)
2. **Task 2: verify_sha256 wired into install_rust_uv()** - `e5aa81c7` (feat)
3. **Task 3: tools.lock + install_tools() consumer** - `833ce946` (feat)

## Files Created/Modified

- `/Users/six2dez/Tools/reconftw/reconftw.sh` - Two AXIOM_EXTRA_ARGS_ARR parse blocks: early (before --source-only for unit tests) and post-config (production canonical)
- `/Users/six2dez/Tools/reconftw/modules/subdomains.sh` - 21 axiom-scan call sites: all $AXIOM_EXTRA_ARGS / "$AXIOM_EXTRA_ARGS" → "${AXIOM_EXTRA_ARGS_ARR[@]}"
- `/Users/six2dez/Tools/reconftw/modules/web.sh` - 15 axiom-scan call sites migrated + webprobe_full local block deleted (local -a axiom_extra_args=(), if/IFS/read/fi block, expansion guard updated to global)
- `/Users/six2dez/Tools/reconftw/install.sh` - install_rust_uv() gated on RUSTUP_INSTALLER_SHA256/UV_INSTALLER_SHA256; install_tools() reads tools.lock into pinned_tools assoc array; doc comment block extended
- `/Users/six2dez/Tools/reconftw/tools.lock` - New file: 5 pinned entries (nuclei@v3.8.0, httpx@v1.9.0, ffuf@v2.1.0, puredns@v2.1.1, subfinder@v2.14.0)

## Decisions Made

- **Two-parse pattern for reconftw.sh (D-07):** The early parse (before --source-only) serves unit tests that use --source-only to skip config loading. The post-config parse overwrites it with the config-sourced AXIOM_EXTRA_ARGS value. This satisfies D-10b smoke test (`echo "${#AXIOM_EXTRA_ARGS_ARR[@]}"` → 4) without restructuring the --source-only gate.
- **Keep array-length guard in webprobe_full (D-09):** `if [[ ${#AXIOM_EXTRA_ARGS_ARR[@]} -gt 0 ]]; then axiom_cmd+=(...) fi` kept for defensive symmetry; dropping it would also be correct (no-op append) but fewer diff lines aids review.
- **Versions from go module proxy (D-12):** Resolved via `go list -m -json @latest` for each module; recorded the actual latest stable tag at execution time (v3.8.0, v1.9.0, v2.1.0, v2.1.1, v2.14.0).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Early AXIOM_EXTRA_ARGS_ARR parse added before --source-only gate**
- **Found during:** Task 1 (smoke test verification)
- **Issue:** Plan's D-10b smoke test expects `bash -c 'AXIOM_EXTRA_ARGS="..." source reconftw.sh --source-only; echo "${#AXIOM_EXTRA_ARGS_ARR[@]}"'` to output 4. The `--source-only` check at line 123 exits before the post-config parse block, so the array was always empty in --source-only mode.
- **Fix:** Added a second AXIOM_EXTRA_ARGS_ARR parse immediately before the `--source-only` check. The post-config parse (canonical, production path) still runs and overwrites this early value with the config-sourced variable. Both smoke tests (4 tokens, 0 empty) now pass.
- **Files modified:** reconftw.sh
- **Verification:** `bash -c 'AXIOM_EXTRA_ARGS="--rate-limit 100 --threads 50" source reconftw.sh --source-only; echo "${#AXIOM_EXTRA_ARGS_ARR[@]}"'` → 4; `unset AXIOM_EXTRA_ARGS; source ...; echo "${#AXIOM_EXTRA_ARGS_ARR[@]}"` → 0
- **Committed in:** 1f2db13a (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug in smoke test path)
**Impact on plan:** Fix required to satisfy D-10b acceptance criterion. No scope change; the two-parse approach maintains the D-07 production guarantee.

## Issues Encountered

None — all three tasks executed cleanly. shellcheck --severity=error exits 0 on all four modified scripts.

## User Setup Required

None — no external service configuration required. The SHA256 env vars (RUSTUP_INSTALLER_SHA256, UV_INSTALLER_SHA256) are opt-in; not setting them preserves pre-change behaviour.

## Next Phase Readiness

- Phase 2 Plan 3 complete; SEC-03 and SEC-04 requirements satisfied
- tools.lock should be updated whenever any of the 5 pinned tools ships a significant release (run `go install @latest`, record tag)
- Phase 4 TEST-03 should add bats tests asserting AXIOM_EXTRA_ARGS_ARR tokenisation (4 tokens, empty array, single token)

---
*Phase: 02-security-quoting-supply-chain-hygiene*
*Completed: 2026-05-13*
