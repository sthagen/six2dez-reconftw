---
phase: 02-security-quoting-supply-chain-hygiene
plan: "02"
subsystem: security
tags: [bash, quoting, curl, word-splitting, shellcheck, axiom, supply-chain, fix]

requires:
  - phase: 02-security-quoting-supply-chain-hygiene
    plan: "03"
    provides: AXIOM_EXTRA_ARGS_ARR array form at modules/web.sh:2332 (depends_on contract)

provides:
  - sendToNotify() in modules/core.sh fully-quoted: all $1, $NOTIFY_CONFIG, $discord_url, $slack_channel, $slack_auth double-quoted
  - Telegram URL interpolation quoted: "https://api.telegram.org/bot${telegram_key}/sendDocument"
  - All -F form pairs in quoted-pair form: -F "key=value", -F "key=@${1}"
  - modules/web.sh axiom-exec mantra install path lowercase: github.com/brosck/mantra@latest
  - Local (install.sh) and remote (modules/web.sh) mantra install paths now agree

affects:
  - any future contributor adding a notify backend to sendToNotify() — must follow the now-canonical quoted pattern (enforced by pre-commit shellcheck)
  - axiom-exec mantra install runs succeed instead of 404ing on case-sensitive GitHub path

tech-stack:
  added: []
  patterns:
    - "Full-function shellcheck-clean quoting pass: every variable expansion in curl-based functions uses double-quoted braced form"
    - "Quoted -F form pair pattern: -F \"key=value\" and -F \"key=@${var}\" prevent word-splitting on filenames with spaces"

key-files:
  created: []
  modified:
    - modules/core.sh  # sendToNotify() body fully-quoted (lines ~1387-1417)
    - modules/web.sh   # 1-char Brosck→brosck fix at line 2331 (axiom-exec mantra install)

key-decisions:
  - "D-04: Full-function pass (not just the 3 named vars from ROADMAP) so no unquoted neighbour survives as a copy-paste regression vector"
  - "D-05: shellcheck --severity=error exits 0; no file-level disable directives added; pre-commit hook catches future regressions"
  - "D-06: 1-char B→b fix aligns web.sh axiom-exec with install.sh:gotools commit f64383c2; local and remote paths now consistent"

duration: 2min
completed: 2026-05-13
---

# Phase 2 Plan 2: sendToNotify Full Quoting Pass + Mantra Path Fix Summary

**sendToNotify() in modules/core.sh fully-quoted against word-splitting; axiom-exec mantra module path fixed from Brosck to brosck to match GitHub's case-sensitive resolution**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-05-13T12:49:19Z
- **Completed:** 2026-05-13T12:52:15Z
- **Tasks:** 2
- **Files modified:** 2 (modules/core.sh, modules/web.sh)

## Accomplishments

- Applied full-function quoting pass to `sendToNotify()` (modules/core.sh lines 1387-1417): all 14 variable expansion sites now use `"${var}"` form; all 3 `-F` form pairs now use quoted-pair form (`-F "key=@${1}"`, `-F "file1=@${1}"`, `-F "channels=${slack_channel}"`); Telegram URL now double-quoted around the full `https://...` argument
- Eliminated word-splitting attack surfaces: a filename with spaces in `${1}` no longer splits into multiple curl form-fields; `$NOTIFY_CONFIG` path with spaces now works in grep/sed invocations; `$discord_url` with whitespace no longer breaks the curl call
- Preserved function declaration form `function sendToNotify {` (no parentheses), single-quoted `payload_json` JSON literal, and all `2>>"$LOGFILE" >/dev/null` redirections verbatim
- Fixed 1-character case typo in modules/web.sh:2331: `github.com/Brosck/mantra@latest` → `github.com/brosck/mantra@latest` — GitHub module paths are case-sensitive; the old value 404'd on axiom nodes, silently producing empty mantra output
- Local and remote mantra install paths now agree: install.sh:gotools `["mantra"]="github.com/brosck/mantra"` (commit f64383c2) matches the axiom-exec form

## Task Commits

Each task was committed atomically:

1. **Task 1: Full-function quoting pass on sendToNotify()** - `e7a066c9` (fix)
2. **Task 2: One-character mantra path fix at modules/web.sh:2331** - `5de0a72b` (fix)

## Files Created/Modified

- `/Users/six2dez/Tools/reconftw/modules/core.sh` — sendToNotify() body: 13 lines changed (all variable expansions double-quoted, all -F form pairs in quoted-pair form, Telegram URL quoted, function declaration preserved)
- `/Users/six2dez/Tools/reconftw/modules/web.sh` — 1-char fix at line 2331: Brosck→brosck in axiom-exec mantra install path; no regression of AXIOM_EXTRA_ARGS_ARR form on adjacent line 2332

## Decisions Made

- **Full-function pass (D-04):** ROADMAP named 3 specific vars but CONTEXT.md D-04 explicitly requires fixing the whole function body so unquoted neighbours don't become copy-paste regression vectors. The full pass was applied as specified.
- **Telegram URL quoting:** The bare `https://api.telegram.org/bot${telegram_key}/sendDocument` was the last unquoted site in the function; wrapping it in double quotes closes the defence-in-depth gap.
- **register_secret normalisation:** `register_secret "$telegram_key"` and `register_secret "$discord_url"` normalised to braced form `"${telegram_key}"` / `"${discord_url}"` for stylistic consistency — functionally equivalent, no behaviour change.
- **No parentheses on declaration:** `function sendToNotify {` preserved exactly as required by must_haves.truths.

## Deviations from Plan

None — plan executed exactly as written. Both tasks applied cleanly on top of Plan 02-03's modules/web.sh edits (AXIOM_EXTRA_ARGS_ARR at line 2332 confirmed present before Task 2 proceeded).

## Verification Results

All acceptance criteria passed:

- `bash -n modules/core.sh modules/web.sh` → exit 0
- `grep -nE '\$1[^"}]|\$NOTIFY_CONFIG[^"}]|\$discord_url[^"}]|\$slack_channel[^"}]|\$slack_auth[^"}]' modules/core.sh | awk -F: '$1>=1385 && $1<=1420' | wc -l` → `0`
- `grep -c 'Brosck' modules/web.sh` → `0`
- `grep -c 'github.com/brosck/mantra@latest' modules/web.sh` → `1`
- `shellcheck -s bash --severity=error modules/core.sh modules/web.sh` → exit 0
- `grep -E 'brosck/mantra' install.sh modules/web.sh | wc -l` → `2` (local + remote agree)
- Adjacent axiom-scan line confirmed: `"${AXIOM_EXTRA_ARGS_ARR[@]}"` present (Plan 02-03 dependency satisfied)
- SC2086/SC2068/SC2027 count in lines 1385-1420 → `0`

## Known Stubs

None.

## Threat Flags

No new security-relevant surface introduced. Both changes reduce attack surface (quoting removes word-split vectors; case fix removes a silent-failure 404 path).

## Self-Check: PASSED

- modules/core.sh exists and contains fully-quoted sendToNotify() body
- modules/web.sh exists and contains lowercase brosck/mantra at line 2331
- Task 1 commit e7a066c9 exists in git log
- Task 2 commit 5de0a72b exists in git log
