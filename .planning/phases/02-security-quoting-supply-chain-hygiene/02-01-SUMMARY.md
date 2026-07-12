---
phase: 02-security-quoting-supply-chain-hygiene
plan: "01"
subsystem: security
tags: [bash, eval-injection, safe_count, count_lines, lib/common.sh, bats]

# Dependency graph
requires: []
provides:
  - "safe_count() eval injection vector fully deleted from lib/common.sh"
  - "3 bats tests exercising the eval pipeline-string form removed"
  - "5 doc files updated to reference count_lines/count_lines_stdin instead of safe_count"
affects:
  - "02-02 (sendToNotify quoting — adjacent SEC changes in same phase)"
  - "Phase 4 test coverage (count_lines already has independent coverage)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Delete-over-deprecate: zero-caller functions are removed entirely, not stubbed"
    - "count_lines()/count_lines_stdin() as canonical file-line-count helpers (no eval)"

key-files:
  created: []
  modified:
    - "lib/common.sh"
    - "tests/unit/test_common.bats"
    - "tests/integration/test_full_flow.bats"
    - "CHANGELOG.md"
    - "CLAUDE.md"
    - ".planning/codebase/CONVENTIONS.md"
    - ".planning/codebase/STRUCTURE.md"
    - ".planning/codebase/ARCHITECTURE.md"

key-decisions:
  - "D-01: Delete safe_count() entirely (17-line block) rather than leaving a zero-caller stub — matches CLAUDE.md 'if unused, delete it completely' policy"
  - "D-02: Delete 3 bats tests that exercise the eval branch rather than porting to count_lines — count_lines already has independent test coverage"
  - "D-03: Update 5 specific doc files only; planning artifacts (REQUIREMENTS/ROADMAP/PROJECT/CONCERNS) retain historical references per explicit D-03 exclusion"

patterns-established:
  - "Delete-over-deprecate: zero-caller surface areas are removed entirely"
  - "Replacement helpers count_lines/count_lines_stdin are the canonical pattern for line counting"

requirements-completed: [SEC-01]

# Metrics
duration: 8min
completed: "2026-05-13"
---

# Phase 2 Plan 01: safe_count() Eval Injection Vector Removal Summary

**Deleted safe_count() eval fallback (SEC-01) from lib/common.sh entirely — 17-line block gone, 3 bats tests removed, 5 doc files updated to reference count_lines/count_lines_stdin**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-13T12:14:00Z
- **Completed:** 2026-05-13T12:22:26Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Removed `safe_count()` function (lines 748-764) from `lib/common.sh` including the 4-line Usage comment block and the function body containing `eval "$1"` at the legacy fallback branch — zero callers remain, surface is gone
- Deleted the 2-test `# safe_count tests` section from `tests/unit/test_common.bats` (including section banner) and 1-test block from `tests/integration/test_full_flow.bats`; replacement helpers `count_lines`/`count_lines_stdin` already have independent test coverage in `test_common.bats`
- Updated 5 doc files to drop or replace `safe_count` references with `count_lines`/`count_lines_stdin` — CONVENTIONS.md now documents the canonical helper pattern for future contributors

## Task Commits

Each task was committed atomically:

1. **Task 1: Delete safe_count() from lib/common.sh + its 3 bats tests** - `46aed84` (fix)
2. **Task 2: Update 5 doc files to drop safe_count references** - `0e896c1` (docs)

## Files Created/Modified

- `lib/common.sh` - Removed 17-line safe_count() block (Usage comment + function body with eval fallback); Pipeline Helpers section divider and count_lines/count_lines_stdin helpers preserved
- `tests/unit/test_common.bats` - Removed 14-line safe_count tests section (banner + 2 @test blocks); surrounding sections intact
- `tests/integration/test_full_flow.bats` - Removed 12-line safe_count integration @test block; sibling tests unaffected
- `CHANGELOG.md` - Dropped `/safe_count()` from centralized helpers bullet (line 203)
- `CLAUDE.md` - Removed `, safe_count` from Component Responsibilities table (line 283)
- `.planning/codebase/CONVENTIONS.md` - Replaced safe_count Error Handling example block with count_lines/count_lines_stdin canonical form (lines 162-166)
- `.planning/codebase/STRUCTURE.md` - Dropped `, safe_count` from common.sh comment (line 18)
- `.planning/codebase/ARCHITECTURE.md` - Dropped `, safe_count` from shared file/counter utilities row (line 63)

## Decisions Made

- D-01: Deleted safe_count() entirely rather than removing only the else branch — zero live callers in modules/*.sh or lib/*.sh confirmed; full deletion is cleaner than a zero-caller stub and matches CLAUDE.md "if unused, delete it completely" policy
- D-02: Deleted 3 bats tests rather than porting to count_lines form — tests exercise the eval pipeline-string form being removed, and count_lines already has independent coverage elsewhere in test_common.bats
- D-03: Updated only the 5 specified doc files; .planning/PROJECT.md safe_count Active bullet intentionally left unchanged — transition step's responsibility per D-03 exclusion

## Deviations from Plan

None - plan executed exactly as written. The D-03 acceptance criteria check `grep -rn 'safe_count' . --include='*.md' --exclude-dir=node_modules --exclude-dir=.git | grep -v '/.planning/phases/02-'` still returns non-zero because REQUIREMENTS.md, ROADMAP.md, PROJECT.md, and CONCERNS.md contain intentional historical references that D-03 explicitly excludes from editing. All 5 target doc files have 0 safe_count hits.

## Issues Encountered

None. The worktree-path-safety issue (accidental edits to main repo path instead of worktree path) was caught before committing and corrected by applying edits to the correct worktree path. Main repo files were reverted via `git checkout --`.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- SEC-01 is closed: the eval injection vector at lib/common.sh:760 no longer exists because the entire function has been deleted
- count_lines() and count_lines_stdin() remain callable and are the canonical helpers for line counting
- Plan 02-02 (sendToNotify quoting + mantra path fix) can proceed independently

---
*Phase: 02-security-quoting-supply-chain-hygiene*
*Completed: 2026-05-13*
