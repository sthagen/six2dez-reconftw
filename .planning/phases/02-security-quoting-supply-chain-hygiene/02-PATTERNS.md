# Phase 2: Security Quoting & Supply-Chain Hygiene - Pattern Map

**Mapped:** 2026-05-13
**Files analyzed:** 11 file/region scopes (across 3 plans 02-01 / 02-02 / 02-03)
**Analogs found:** 11 / 11

## File Classification

| File / Region | Plan | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|------|-----------|----------------|---------------|
| `lib/common.sh:748-764` | 02-01 | delete | utility / counter | `lib/common.sh:122-140` (`count_lines`/`count_lines_stdin`) | exact-role |
| `tests/unit/test_common.bats:253-266` | 02-01 | delete (tests) | bats `@test` blocks | `tests/unit/test_common.bats:253-255` (header banner pattern) | exact |
| `tests/integration/test_full_flow.bats:245-256` | 02-01 | delete (tests) | bats `@test` block | `tests/integration/test_full_flow.bats:234-243` (sibling `@test` style) | exact |
| `CHANGELOG.md:203`, `CLAUDE.md:283`, `.planning/codebase/CONVENTIONS.md:162-164`, `.planning/codebase/STRUCTURE.md:18`, `.planning/codebase/ARCHITECTURE.md:63` | 02-01 | update-in-place (docs) | text-substitution | (n/a — markdown) | n/a |
| `modules/core.sh:1387-1417` (`sendToNotify`) | 02-02 | refactor (quote pass) | curl multi-form POST | `modules/core.sh:1380` (`transfer()` curl line — fully-quoted) | exact |
| `modules/web.sh:2340` (1-char path fix) | 02-02 | update-in-place | string literal | commit `f64383c2` `install.sh:325` `gotools["mantra"]` lowercase | exact |
| `reconftw.sh:~503-512` (insert global `AXIOM_EXTRA_ARGS_ARR` parse) | 02-03 | insert (global state) | `read -r -a` from string | `modules/web.sh:150-155` (existing IFS-juggling `read -r -a` block) + `modules/vulns.sh:258` (simpler `read -r -a`) | exact |
| `modules/subdomains.sh` (21 sites) | 02-03 | refactor (var → array) | axiom-scan invocations | `modules/subdomains.sh:1300, 2227` (`"${webinfo_files[@]}"`, `"${cloud_enum_cmd[@]}"`) | role-match |
| `modules/web.sh` (17 sites + delete local block) | 02-03 | refactor + delete-local-block | axiom-scan invocations | `modules/web.sh:179-202` (existing `axiom_cmd=(...)` + `axiom_extra_args[@]` append pattern) | exact |
| `install.sh:159-188` (`install_rust_uv` SHA wiring) | 02-03 | refactor (insert verify) | `mktemp` → `curl -o` → `verify_sha256` → `sh "$_tmpfile"` | `install.sh:1240-1289` (`download_sha256` map + env-var-driven `verify_sha256` precedent) | exact |
| `tools.lock` (new, repo root) | 02-03 | new-file (manifest) | key=value text | No existing analog — spec is verbatim from CONTEXT.md D-12 | none-fallback-to-spec |
| `install.sh:489-521` (Go install loop reads `tools.lock`) | 02-03 | refactor (consume manifest) | `awk`/`while read` over text file | `install.sh:1258-1290` (`for key in "${!downloads[@]}"; do … "${download_sha256[$key]:-}"; do`) | role-match |

## Pattern Assignments

---

### `lib/common.sh:748-764` — DELETE `safe_count()` (Plan 02-01 / D-01)

**Analog:** `lib/common.sh:122-140` — the canonical `count_lines()` + `count_lines_stdin()` replacement helpers that must remain after deletion.

**Existing function header / pattern to preserve next to the deletion** (`lib/common.sh:122-140`):

```bash
# Count non-empty lines in a file safely
# Usage: count_lines filename
# Returns: line count (0 if file doesn't exist or is empty)
count_lines() {
    local file="$1"
    if [[ -s "$file" ]]; then
        sed '/^$/d' "$file" | wc -l | tr -d ' '
    else
        echo 0
    fi
}

# Count lines from stdin, with fallback to 0 on failure
# Usage: result=$(command | count_lines_stdin)
count_lines_stdin() {
    local count
    count=$(sed '/^$/d' | wc -l | tr -d ' ') || count=0
    echo "${count:-0}"
}
```

**Block to DELETE verbatim** (`lib/common.sh:748-764`):

```bash
# Count non-empty lines in a file safely
# Usage: NUMOFLINES=$(safe_count "file_path")
#        NUMOFLINES=$(safe_count "command | pipeline")  # legacy: still supported via eval
# Always returns a valid number (0 on failure)
safe_count() {
    local result
    if [[ -f "$1" ]]; then
        # Safe path: count lines in file directly, no eval
        result=$(sed '/^$/d' "$1" 2>/dev/null | wc -l | tr -d ' ') || result=0
    else
        # Legacy fallback for callers passing pipeline strings
        # TODO: migrate remaining callers to pass file paths
        result=$(eval "$1" 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ') || result=0
    fi
    [[ "$result" =~ ^[0-9]+$ ]] || result=0
    echo "$result"
}
```

**Quirks to respect:**
- The blank line at line 747 (separator between `run_with_heartbeat_shell` end at 746 and the `safe_count` doc-comment start at 748) and the section header `###############################################################################` block at line 766 (`# Pipeline Helpers`) must remain intact. Delete only lines 748-764; the next sibling section divider keeps its position.
- Zero live callers in `modules/*.sh` or `lib/*.sh` (verified via `grep -rn 'safe_count' . --include='*.sh'`). Only the 3 bats tests below reference it.
- File-level source guard `[[ -n "$_COMMON_SH_LOADED" ]] && return 0` (line 6) is untouched.

---

### `tests/unit/test_common.bats:253-266` — DELETE 2 `@test` blocks + section header (Plan 02-01 / D-02)

**Analog:** the surrounding `@test` blocks at `tests/unit/test_common.bats:240-251` (`run_tool` tests) and `:272+` (`process_results` tests). Both follow the same `@test "name" { ... }` pattern with a section banner above each cluster.

**Section banner pattern above each cluster** (already present at `:253-255`):

```bash
###############################################################################
# safe_count tests
###############################################################################
```

**Block to DELETE verbatim** (`tests/unit/test_common.bats:253-266`):

```bash
###############################################################################
# safe_count tests
###############################################################################

@test "safe_count returns valid number" {
    printf "line1\nline2\n" > test.txt
    result=$(safe_count "cat test.txt")
    [ "$result" -eq 2 ]
}

@test "safe_count returns 0 on failure" {
    result=$(safe_count "cat nonexistent_file_xyz.txt")
    [ "$result" -eq 0 ]
}
```

**Quirks to respect:**
- Delete the 14-line block as one chunk: the section divider `###` lines AND the two `@test` blocks AND the trailing blank line before line 267 (`process_results tests` banner). Do NOT leave a dangling section header.
- Both deleted tests pass pipeline-strings (`"cat test.txt"`, `"cat nonexistent_file_xyz.txt"`) — they exercised the eval branch specifically. There is nothing to port to `count_lines`; that helper is already covered by sibling tests in this file.
- Maintain spacing/blank-line consistency: 1 blank line between `@test` blocks; 1 blank line before each `###...###` banner.

---

### `tests/integration/test_full_flow.bats:245-256` — DELETE 1 `@test` block (Plan 02-01 / D-02)

**Analog:** sibling `@test` blocks `:234-243` (`notification skip works`) and `:257-263` (`parallel_funcs handles empty list`) — same `source_reconftw; source "$SCRIPTPATH/lib/common.sh"` setup pattern.

**Block to DELETE verbatim** (`tests/integration/test_full_flow.bats:245-256`):

```bash
@test "full flow: safe_count handles missing files" {
    source_reconftw
    
    # shellcheck source=/dev/null
    source "$SCRIPTPATH/lib/common.sh"
    
    # Test with non-existent file
    local count
    count=$(safe_count "/nonexistent/file.txt")
    [ "$count" -eq 0 ]
}
```

**Quirks to respect:**
- Delete the entire 12-line block (the `@test` plus the blank line that follows at line 256). Sibling tests above and below remain.
- This test uses the file-path form (not pipeline-string), so it would superficially port to `count_lines`. Decision per CONTEXT.md D-02 is **delete, do not port** — `count_lines` is already covered by `test_common.bats`.

---

### Doc reference updates (Plan 02-01 / D-03)

**5 files, each a 1-line substitution.** No analog needed; mechanical text replacement.

| File | Line | Current | Replace with |
|------|------|---------|--------------|
| `CHANGELOG.md` | 203 | ``  - `count_lines()`/`safe_count()` `` | ``  - `count_lines()` `` |
| `CLAUDE.md` | 283 | `... `count_lines`, `safe_count`, incident tracking ...` | `... `count_lines`, incident tracking ...` |
| `.planning/codebase/CONVENTIONS.md` | 162-164 | The "**`safe_count()`** in `lib/common.sh` — always returns a valid integer:" example block referencing `safe_count` | Replace with a `count_lines` example, or drop entirely. CONVENTIONS.md is regenerated periodically — minimal touch: just retitle to `count_lines` and change the snippet to `NUMOFLINES=$(count_lines "subdomains/subdomains.txt")` with no legacy/eval mention. |
| `.planning/codebase/STRUCTURE.md` | 18 | `│   ├── common.sh            # File/dir helpers, incident tracking, count_lines, safe_count` | `│   ├── common.sh            # File/dir helpers, incident tracking, count_lines` |
| `.planning/codebase/ARCHITECTURE.md` | 63 | `| Shared file/counter utilities | `ensure_dirs`, `ensure_webs_all`, `safe_backup`, `count_lines`, `safe_count`, incident tracking | `lib/common.sh` |` | `| Shared file/counter utilities | `ensure_dirs`, `ensure_webs_all`, `safe_backup`, `count_lines`, incident tracking | `lib/common.sh` |` |

**Quirks to respect:**
- `.planning/PROJECT.md:46` Active bullet for SEC-01 is moved to Validated by the transition step — **do NOT edit here**.
- Planner-level call (per CONTEXT.md Claude's Discretion): bundle these 5 edits in the same commit as the `safe_count` delete (`Plan 02-01`), OR split into a follow-up commit. Either is acceptable.

---

### `modules/core.sh:1387-1417` — `sendToNotify` full-function quoting pass (Plan 02-02 / D-04)

**Analog (canonical fully-quoted curl pattern):** `modules/core.sh:1380` (`transfer()` function — the same file, ~7 lines above `sendToNotify`). Already uses `--data-binary "@/tmp/$file_name"` with the `@` form quoted as `"@..."`.

**Existing fully-quoted pattern in `transfer()`** (`modules/core.sh:1380`):

```bash
run_command tar -czvf "/tmp/$file_name" "$file" >/dev/null 2>&1 && \
    run_command curl -s "https://bashupload.com/${file_name}.tgz" \
                --data-binary "@/tmp/$file_name" | grep wget
```

**Current `sendToNotify` body** (`modules/core.sh:1387-1417`) — **every bare/under-quoted expansion to fix**:

```bash
function sendToNotify {
    if [[ -z $1 ]]; then
        _print_status WARN "No file provided to send"
    else
        if [[ -z $NOTIFY_CONFIG ]]; then
            NOTIFY_CONFIG=~/.config/notify/provider-config.yaml
        fi
        if [[ -n "$(find "${1}" -prune -size +8000000c)" ]]; then
            _print_msg WARN "${1} is larger than 8MB, sending over external service"
            transfer "${1}" | notify -silent
            return 0
        fi
        if grep -q '^ telegram\|^telegram\|^    telegram' $NOTIFY_CONFIG; then
            notification "Sending ${domain} data over Telegram" info
            telegram_chat_id=$(sed -n '/^telegram:/,/^[^ ]/p' ${NOTIFY_CONFIG} | sed -n 's/^[ ]*telegram_chat_id:[ ]*"\([^"]*\)".*/\1/p')
            telegram_key=$(sed -n '/^telegram:/,/^[^ ]/p' ${NOTIFY_CONFIG} | sed -n 's/^[ ]*telegram_api_key:[ ]*"\([^"]*\)".*/\1/p')
            register_secret "$telegram_key"
            run_command curl -F "chat_id=${telegram_chat_id}" -F "document=@${1}" https://api.telegram.org/bot${telegram_key}/sendDocument 2>>"$LOGFILE" >/dev/null
        fi
        if grep -q '^ discord\|^discord\|^    discord' $NOTIFY_CONFIG; then
            notification "Sending ${domain} data over Discord" info
            discord_url=$(sed -n '/^discord:/,/^[^ ]/p' ${NOTIFY_CONFIG} | sed -n 's/^[ ]*discord_webhook_url:[ ]*"\([^"]*\)".*/\1/p')
            register_secret "$discord_url"
            run_command curl -v -i -H "Accept: application/json" -H "Content-Type: multipart/form-data" -X POST -F 'payload_json={"username": "test", "content": "hello"}' -F file1=@${1} $discord_url 2>>"$LOGFILE" >/dev/null
        fi
        if [[ -n $slack_channel ]] && [[ -n $slack_auth ]]; then
            notification "Sending ${domain} data over Slack" info
            run_command curl -F file=@${1} -F "initial_comment=reconftw zip file" -F channels=${slack_channel} -H "Authorization: Bearer ${slack_auth}" https://slack.com/api/files.upload 2>>"$LOGFILE" >/dev/null
        fi
    fi
}
```

**Target shape after the quoting pass** (every variable expansion quoted; matches the `transfer()` analog idiom):

```bash
function sendToNotify {
    if [[ -z "${1}" ]]; then
        _print_status WARN "No file provided to send"
    else
        if [[ -z "${NOTIFY_CONFIG}" ]]; then
            NOTIFY_CONFIG=~/.config/notify/provider-config.yaml
        fi
        if [[ -n "$(find "${1}" -prune -size +8000000c)" ]]; then
            _print_msg WARN "${1} is larger than 8MB, sending over external service"
            transfer "${1}" | notify -silent
            return 0
        fi
        if grep -q '^ telegram\|^telegram\|^    telegram' "${NOTIFY_CONFIG}"; then
            notification "Sending ${domain} data over Telegram" info
            telegram_chat_id=$(sed -n '/^telegram:/,/^[^ ]/p' "${NOTIFY_CONFIG}" | sed -n 's/^[ ]*telegram_chat_id:[ ]*"\([^"]*\)".*/\1/p')
            telegram_key=$(sed -n '/^telegram:/,/^[^ ]/p' "${NOTIFY_CONFIG}" | sed -n 's/^[ ]*telegram_api_key:[ ]*"\([^"]*\)".*/\1/p')
            register_secret "${telegram_key}"
            run_command curl -F "chat_id=${telegram_chat_id}" -F "document=@${1}" "https://api.telegram.org/bot${telegram_key}/sendDocument" 2>>"$LOGFILE" >/dev/null
        fi
        if grep -q '^ discord\|^discord\|^    discord' "${NOTIFY_CONFIG}"; then
            notification "Sending ${domain} data over Discord" info
            discord_url=$(sed -n '/^discord:/,/^[^ ]/p' "${NOTIFY_CONFIG}" | sed -n 's/^[ ]*discord_webhook_url:[ ]*"\([^"]*\)".*/\1/p')
            register_secret "${discord_url}"
            run_command curl -v -i -H "Accept: application/json" -H "Content-Type: multipart/form-data" -X POST -F 'payload_json={"username": "test", "content": "hello"}' -F "file1=@${1}" "${discord_url}" 2>>"$LOGFILE" >/dev/null
        fi
        if [[ -n "${slack_channel}" ]] && [[ -n "${slack_auth}" ]]; then
            notification "Sending ${domain} data over Slack" info
            run_command curl -F "file=@${1}" -F "initial_comment=reconftw zip file" -F "channels=${slack_channel}" -H "Authorization: Bearer ${slack_auth}" https://slack.com/api/files.upload 2>>"$LOGFILE" >/dev/null
        fi
    fi
}
```

**Per-line change inventory** (executor checklist):
1. Line 1388: `[[ -z $1 ]]` → `[[ -z "${1}" ]]`
2. Line 1391: `[[ -z $NOTIFY_CONFIG ]]` → `[[ -z "${NOTIFY_CONFIG}" ]]`
3. Line 1399: `grep -q '...' $NOTIFY_CONFIG` → `grep -q '...' "${NOTIFY_CONFIG}"`
4. Lines 1401-1402: `${NOTIFY_CONFIG}` already braced; wrap in double quotes → `"${NOTIFY_CONFIG}"` (twice).
5. Line 1404: `https://api.telegram.org/bot${telegram_key}/sendDocument` is the trailing bare URL — quote the whole URL: `"https://api.telegram.org/bot${telegram_key}/sendDocument"`. The `-F` form pairs are already quoted with `${1}` braced and protected.
6. Line 1406: `grep -q '...' $NOTIFY_CONFIG` → `"${NOTIFY_CONFIG}"`.
7. Line 1408: `${NOTIFY_CONFIG}` → `"${NOTIFY_CONFIG}"`.
8. Line 1410: bare `-F file1=@${1}` → `-F "file1=@${1}"`; bare `$discord_url` → `"${discord_url}"`.
9. Line 1412: `[[ -n $slack_channel ]] && [[ -n $slack_auth ]]` → `[[ -n "${slack_channel}" ]] && [[ -n "${slack_auth}" ]]`.
10. Line 1414: bare `-F file=@${1}` → `-F "file=@${1}"`; bare `-F channels=${slack_channel}` → `-F "channels=${slack_channel}"`.
11. Line 1403 / 1409: `register_secret "$telegram_key"` and `register_secret "$discord_url"` are already correctly quoted — leave as-is (or normalize to `"${telegram_key}"` / `"${discord_url}"` for stylistic consistency).

**Quirks to respect (D-05 shellcheck-clean policy):**
- After the pass, `shellcheck modules/core.sh` must produce no new SC2086 / SC2068 / SC2027 findings in lines `:1387-1420`.
- If any intentional word-split survives (none expected), use an inline `# shellcheck disable=SCXXXX` on the line above with a one-line explanation comment. **NEVER file-level** (CONVENTIONS.md:277).
- Function declaration `function sendToNotify {` uses the parentheses-less form — preserve verbatim (it's the only function in `modules/core.sh` using this exact form; do not "normalize" it to `function sendToNotify()` as part of the quoting pass).

---

### `modules/web.sh:2340` — `Brosck` → `brosck` 1-char fix (Plan 02-02 / FIX-01 / D-06)

**Analog:** commit `f64383c2644d1daa8e3c8a59ed4ce68e63c4b5b5` — the precedent local-install fix to `install.sh:325` (`gotools["mantra"]`).

**Precedent diff** (`install.sh` from commit `f64383c2`):

```diff
-    ["mantra"]="github.com/Brosck/mantra"
+    ["mantra"]="github.com/brosck/mantra"
```

**Currently confirmed lowercase in `install.sh:330`** (already merged):

```bash
    ["mantra"]="github.com/brosck/mantra"
```

**Block to FIX in `modules/web.sh:2336-2342`** (1-character change at line 2340):

```bash
            if [[ -s "js/js_livelinks.txt" ]]; then
                if [[ $AXIOM != true ]]; then
                    cat js/js_livelinks.txt | mantra -ua \"$HEADER\" -s | anew -q js/js_secrets.txt 2>>"$LOGFILE" >/dev/null || true
                else
                    axiom-exec "go install github.com/Brosck/mantra@latest" 2>>"$LOGFILE" >/dev/null   # ← change Brosck to brosck
                    run_command axiom-scan js/js_livelinks.txt -m mantra -ua "$HEADER" -s -o js/js_secrets.txt "$AXIOM_EXTRA_ARGS" &>/dev/null
                fi
```

**Target (post-fix):**

```bash
                    axiom-exec "go install github.com/brosck/mantra@latest" 2>>"$LOGFILE" >/dev/null
```

**Quirks to respect:**
- Line 2341 (`"$AXIOM_EXTRA_ARGS"`) is fixed separately by D-08 in the same plan (02-03). Plan 02-02's mantra fix touches only the `B`→`b` on line 2340.
- Single-commit-per-logical-change: per CONTEXT.md the mantra fix is bundled with the sendToNotify pass in Plan 02-02. Whether to keep it as one commit or split is a planner call — established repo pattern is single logical change per commit; both fixes are part of "Plan 02-02 hardening pass" so one commit is the canonical outcome.

---

### `reconftw.sh:~503-512` — INSERT global `AXIOM_EXTRA_ARGS_ARR` parse (Plan 02-03 / D-07)

**Analog:** `modules/web.sh:150-155` (existing `webprobe_full` local-pattern, to be removed by D-09) AND `modules/vulns.sh:258` (simpler one-line `read -r -a` precedent).

**Existing IFS-juggling pattern at `modules/web.sh:150-155`** (the pattern to mirror at global scope):

```bash
        if [[ $AXIOM == true ]] && [[ -n "${AXIOM_EXTRA_ARGS:-}" ]]; then
            local _ifs="$IFS"
            IFS=' '
            read -r -a axiom_extra_args <<<"$AXIOM_EXTRA_ARGS"
            IFS="$_ifs"
        fi
```

**Simpler precedent at `modules/vulns.sh:258`** (single-line `read -r -a` from string):

```bash
    read -r -a params <<<"$query"
```

**Existing target region in `reconftw.sh:497-513`** (where the insert lands):

```bash
. "${SCRIPTPATH}"/reconftw.cfg || {
    _print_error "Error importing reconftw.cfg"
    exit 1
}

# Source optional secrets file (gitignored, for API keys and tokens)
[[ -f "${SCRIPTPATH}/secrets.cfg" ]] && . "${SCRIPTPATH}/secrets.cfg"

if [[ -s $CUSTOM_CONFIG ]]; then
    # shellcheck source=/home/six2dez/Tools/reconftw/custom_config.cfg
    . "${CUSTOM_CONFIG}" || {
        _print_error "Error importing custom config"
        exit 1
    }
fi

# Re-apply CLI overrides after config load (config defaults should not clobber CLI flags)
```

**Insert this block** (canonical placement: after `CUSTOM_CONFIG` source completes on line 511, before the `CLI_*` re-apply on line 513 — anywhere between `secrets.cfg` source at 503 and the dispatch case at ~590 works per CONTEXT.md Claude's Discretion):

```bash
# Global parse of AXIOM_EXTRA_ARGS once after config load — single source of truth.
# Consumed via "${AXIOM_EXTRA_ARGS_ARR[@]}" in modules/subdomains.sh and modules/web.sh.
# Empty/unset env → empty array → expands to nothing at the call sites.
declare -a AXIOM_EXTRA_ARGS_ARR=()
if [[ -n "${AXIOM_EXTRA_ARGS:-}" ]]; then
    read -r -a AXIOM_EXTRA_ARGS_ARR <<<"${AXIOM_EXTRA_ARGS}"
fi
```

**Quirks to respect:**
- `reconftw.sh` ships `IFS=$'\n\t'` (top of file, per CONVENTIONS.md:11). `read -r -a` with `<<<` here-string respects the current `IFS`. **Either** restore IFS to `' '` for the parse like `modules/web.sh:151-154` does, **OR** rely on the fact that `<<<"$VAR"` word-splits on any `IFS` character (including `\n` and `\t`) which still produces the expected token list for space-separated values like `"--rate-limit 100 --threads 50"`. The simpler form (without IFS juggling) is acceptable because: (a) the top-level `IFS=$'\n\t'` is set but the `<<<` here-string still tokenises on whitespace including spaces, (b) the global parse runs **once** and is read-only thereafter, (c) `modules/vulns.sh:258` and lib/parallel.sh use the simple form. Recommend planner default to the IFS-aware form (mirroring `modules/web.sh:150-155`) for safety in case a future config value uses tabs.

  Defensive variant (recommended):

  ```bash
  declare -a AXIOM_EXTRA_ARGS_ARR=()
  if [[ -n "${AXIOM_EXTRA_ARGS:-}" ]]; then
      _axiom_ifs_saved="$IFS"
      IFS=' '
      read -r -a AXIOM_EXTRA_ARGS_ARR <<<"${AXIOM_EXTRA_ARGS}"
      IFS="$_axiom_ifs_saved"
      unset _axiom_ifs_saved
  fi
  ```

- `set -u` is NOT used by reconftw (CONVENTIONS.md:11 lists `set +e`; CONVENTIONS.md:11 — no `set -u`). Expanding `"${AXIOM_EXTRA_ARGS_ARR[@]}"` when the array is empty is safe and expands to zero arguments.
- `AXIOM_EXTRA_ARGS_ARR` is `UPPER_SNAKE_CASE` matching `AXIOM_EXTRA_ARGS`, `AXIOM`, `AXIOM_FLEET_COUNT` (CONVENTIONS.md:60-63).
- Insertion lives BEFORE the `CLI_*` re-apply block intentionally — if a future CLI flag wants to override `AXIOM_EXTRA_ARGS`, the array would need to be re-parsed after the override. None today; revisit if added.

---

### `modules/subdomains.sh` (21 sites) — migrate `$AXIOM_EXTRA_ARGS` / `"$AXIOM_EXTRA_ARGS"` to `"${AXIOM_EXTRA_ARGS_ARR[@]}"` (Plan 02-03 / D-08)

**Analog (array-expansion-in-axiom-scan-call surrounding context):** `modules/web.sh:179-202` (`axiom_cmd=(...)` + `axiom_extra_args[@]` append pattern — the cleanest existing example). Same module-style array+append usage that mirrors the target post-migration shape.

**Existing same-module array expansion** (`modules/subdomains.sh:1300`, `:2227` — array-in-pipe and `run_command` array):

```bash
                    if ! cat "${webinfo_files[@]}" 2>>"$LOGFILE" \
```

```bash
            run_command "${cloud_enum_cmd[@]}" >>"$LOGFILE" 2>>"$LOGFILE" || cloud_enum_rc=$?
```

**Surrounding context for one site (typical pattern in 21-site list)** — `modules/subdomains.sh:665-674`:

```bash
            # Resolve subdomains using axiom-scan
            if [[ -s ".tmp/subs_no_resolved.txt" ]]; then
                run_command axiom-scan .tmp/subs_no_resolved.txt -m puredns-resolve \
                    -r ${AXIOM_RESOLVERS_PATH} \
                    --resolvers-trusted ${AXIOM_RESOLVERS_TRUSTED_PATH} \
                    --wildcard-tests "$PUREDNS_WILDCARDTEST_LIMIT" \
                    --wildcard-batch "$PUREDNS_WILDCARDBATCH_LIMIT" \
                    -o .tmp/subdomains_tmp.txt $AXIOM_EXTRA_ARGS \
                    2>>"$LOGFILE" >/dev/null
            fi
```

**Target shape (per-site mechanical substitution):**

```bash
                run_command axiom-scan .tmp/subs_no_resolved.txt -m puredns-resolve \
                    -r ${AXIOM_RESOLVERS_PATH} \
                    --resolvers-trusted ${AXIOM_RESOLVERS_TRUSTED_PATH} \
                    --wildcard-tests "$PUREDNS_WILDCARDTEST_LIMIT" \
                    --wildcard-batch "$PUREDNS_WILDCARDBATCH_LIMIT" \
                    -o .tmp/subdomains_tmp.txt "${AXIOM_EXTRA_ARGS_ARR[@]}" \
                    2>>"$LOGFILE" >/dev/null
```

**Authoritative 21-site checklist** (from `grep -nE 'AXIOM_EXTRA_ARGS' modules/subdomains.sh` — 20 axiom-scan call sites + 1 to verify is not a comment):

| Line | Current form | Replace with |
|------|--------------|--------------|
| 672 | `$AXIOM_EXTRA_ARGS \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 737 | `$AXIOM_EXTRA_ARGS 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 745 | `$AXIOM_EXTRA_ARGS 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 768 | `$AXIOM_EXTRA_ARGS \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 962 | `"$AXIOM_EXTRA_ARGS" \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 1100 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 1107 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 1233 | `$AXIOM_EXTRA_ARGS 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 1366 | `$AXIOM_EXTRA_ARGS \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 1570 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 1587 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 1666 | `$AXIOM_EXTRA_ARGS \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 1742 | `$AXIOM_EXTRA_ARGS \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 1825 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 1838 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 1905 | `$AXIOM_EXTRA_ARGS \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 1926 | `$AXIOM_EXTRA_ARGS \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 1944 | `$AXIOM_EXTRA_ARGS \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 1990 | `$AXIOM_EXTRA_ARGS \` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" \` |
| 2068 | `$AXIOM_EXTRA_ARGS 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 2197 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |

**Note: CONTEXT.md lists 20 lines for subdomains.sh ("plus any duplicates revealed by grep"). The fresh grep above shows line 2197 as a 21st site that the CONTEXT.md author flagged with "plus any duplicates"** — executor MUST include line 2197.

**Quirks to respect:**
- Line continuations (`\`) and trailing redirections (`2>>"$LOGFILE" >/dev/null`) on the same physical line must be preserved exactly — the substitution is the token only, not the surrounding whitespace or continuation.
- Of the 21 sites, ~11 use bare `$AXIOM_EXTRA_ARGS` (word-split intent) and ~10 use `"$AXIOM_EXTRA_ARGS"` (single-token bug). Both become the same `"${AXIOM_EXTRA_ARGS_ARR[@]}"` per CONTEXT.md D-08.
- After substitution: run `grep -nE 'AXIOM_EXTRA_ARGS([^_]|$)' modules/subdomains.sh` — must return 0 hits except for the new `AXIOM_EXTRA_ARGS_ARR` references (D-10a verification).

---

### `modules/web.sh` (17 sites) — same migration as subdomains (Plan 02-03 / D-08)

**Analog:** same pattern as `modules/subdomains.sh` migration. The clean axiom-call-without-locals invocation analog **after** D-09 removes the local block exists already at `modules/subdomains.sh:1825` post-migration: `run_command axiom-scan ... "${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null`.

**Authoritative 17-site checklist** (from `grep -nE 'AXIOM_EXTRA_ARGS' modules/web.sh` — excludes the 4 mentions in lines 144-155 / 199-200 which are handled by D-09):

| Line | Current form | Replace with |
|------|--------------|--------------|
| 340 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 431 | `$AXIOM_EXTRA_ARGS 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 506 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 786 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 1008 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 1152 | `"$AXIOM_EXTRA_ARGS"` (no trailing redirect on same line) | `"${AXIOM_EXTRA_ARGS_ARR[@]}"` |
| 1537 | `"$AXIOM_EXTRA_ARGS"` (run_with_heartbeat trailing) | `"${AXIOM_EXTRA_ARGS_ARR[@]}"` |
| 1988 | `"$AXIOM_EXTRA_ARGS"` (run_with_heartbeat) | `"${AXIOM_EXTRA_ARGS_ARR[@]}"` |
| 1990 | `"$AXIOM_EXTRA_ARGS"` (run_with_heartbeat) | `"${AXIOM_EXTRA_ARGS_ARR[@]}"` |
| 2257 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 2280 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 2341 | `"$AXIOM_EXTRA_ARGS" &>/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" &>/dev/null` |
| 2479 | `"$AXIOM_EXTRA_ARGS" 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 2925 | `$AXIOM_EXTRA_ARGS 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |
| 2927 | `$AXIOM_EXTRA_ARGS 2>>"$LOGFILE" >/dev/null` | `"${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` |

**Note: CONTEXT.md lists "17 sites in web.sh"; the fresh grep above shows 15 axiom-scan call-site lines + 2 occurrences inside the `webprobe_full` local block at lines 150 and 153. The 2 webprobe_full occurrences are removed entirely by D-09, and a new `"${AXIOM_EXTRA_ARGS_ARR[@]}"` replaces the `"${axiom_extra_args[@]}"` expansion at line 200. So the executor reconciliation is: 15 call-site substitutions + 1 substitution at line 200 (the array-expansion in the `axiom_cmd` append) + entire block-delete at 150-155 = the "17 sites" from CONTEXT.md. Cross-check at executor-time.**

**Quirks to respect:**
- Lines 1152, 1537, 1988, 1990 do NOT have a trailing `2>>"$LOGFILE"` on the same line — they end with `"$AXIOM_EXTRA_ARGS"` at line end (or follow `run_with_heartbeat "label"` argv form). Substitute the token only.
- Line 2341 uses `&>/dev/null` (bash combined-redirect), not `2>>"$LOGFILE" >/dev/null` — preserve verbatim.
- After substitution: run `grep -nE 'AXIOM_EXTRA_ARGS([^_]|$)' modules/web.sh` — must return 0 hits (D-10a).

---

### `modules/web.sh:144-155, 199-202` — REMOVE local `axiom_extra_args=()` block + replace expansion (Plan 02-03 / D-09)

**Analog (the clean post-removal shape):** any `run_command axiom-scan ... "${AXIOM_EXTRA_ARGS_ARR[@]}" 2>>"$LOGFILE" >/dev/null` site after migration (e.g., the post-D-08 `modules/subdomains.sh:1825`).

**Currently the most complex axiom-call wrapper in the codebase** (the block to dismantle, `modules/web.sh:144-202`):

```bash
        local probe_out=".tmp/web_full_info_probe.txt"
        local common_json_tmp=".tmp/web_full_info_common_current.txt"
        local uncommon_json_tmp=".tmp/web_full_info_uncommon_current.txt"
        local -a axiom_extra_args=()                                            # ← DELETE this line

        : >"$probe_out" 2>/dev/null || true
        : >"$common_json_tmp" 2>/dev/null || true
        : >"$uncommon_json_tmp" 2>/dev/null || true

        if [[ $AXIOM == true ]] && [[ -n "${AXIOM_EXTRA_ARGS:-}" ]]; then       # ← DELETE block (151-155)
            local _ifs="$IFS"
            IFS=' '
            read -r -a axiom_extra_args <<<"$AXIOM_EXTRA_ARGS"
            IFS="$_ifs"
        fi                                                                       # ← end DELETE block

        if [[ $AXIOM != true ]]; then
            local -a httpx_cmd=(
                ...
            )
            run_command "${httpx_cmd[@]}" <subdomains/subdomains.txt 2>>"$LOGFILE" >/dev/null
        else
            local -a axiom_cmd=(
                axiom-scan
                subdomains/subdomains.txt
                -m httpx
                ...
                -o "$probe_out"
            )
            if [[ ${#axiom_extra_args[@]} -gt 0 ]]; then                         # ← REPLACE 199-201
                axiom_cmd+=("${axiom_extra_args[@]}")
            fi
            run_command "${axiom_cmd[@]}" 2>>"$LOGFILE" >/dev/null
        fi
```

**Target shape (post-D-09):**

```bash
        local probe_out=".tmp/web_full_info_probe.txt"
        local common_json_tmp=".tmp/web_full_info_common_current.txt"
        local uncommon_json_tmp=".tmp/web_full_info_uncommon_current.txt"

        : >"$probe_out" 2>/dev/null || true
        : >"$common_json_tmp" 2>/dev/null || true
        : >"$uncommon_json_tmp" 2>/dev/null || true

        if [[ $AXIOM != true ]]; then
            local -a httpx_cmd=(
                ...
            )
            run_command "${httpx_cmd[@]}" <subdomains/subdomains.txt 2>>"$LOGFILE" >/dev/null
        else
            local -a axiom_cmd=(
                axiom-scan
                subdomains/subdomains.txt
                -m httpx
                ...
                -o "$probe_out"
            )
            if [[ ${#AXIOM_EXTRA_ARGS_ARR[@]} -gt 0 ]]; then
                axiom_cmd+=("${AXIOM_EXTRA_ARGS_ARR[@]}")
            fi
            run_command "${axiom_cmd[@]}" 2>>"$LOGFILE" >/dev/null
        fi
```

**Per-line change inventory** (executor checklist):
1. Line 144: DELETE `        local -a axiom_extra_args=()`
2. Lines 150-155 inclusive: DELETE the 6-line `if/then/read/fi` block.
3. Line 199: REPLACE `if [[ ${#axiom_extra_args[@]} -gt 0 ]]; then` → `if [[ ${#AXIOM_EXTRA_ARGS_ARR[@]} -gt 0 ]]; then`
4. Line 200: REPLACE `axiom_cmd+=("${axiom_extra_args[@]}")` → `axiom_cmd+=("${AXIOM_EXTRA_ARGS_ARR[@]}")`

**Quirks to respect:**
- The append pattern (`axiom_cmd+=(...)`) is preserved because it's the cleanest way to conditionally extend an argv array when the source array might be empty. Bash 4.3+ behaviour means `axiom_cmd+=("${AXIOM_EXTRA_ARGS_ARR[@]}")` with an empty source array is a no-op — the `if [[ ${#...[@]} -gt 0 ]]` guard is now redundant but harmless. Planner may choose to drop the guard for simplicity (recommended) OR keep it for defensive symmetry with the rest of the function. **Recommendation: drop the guard**, reducing the post-D-09 block to one less line.
- After dismantling: `local -a` declarations remaining in this function (`httpx_cmd`, `axiom_cmd`) are untouched; only the `axiom_extra_args` local goes away.
- The block lives inside `webprobe_full()` (declared circa line 80) — this is a function-local refactor; nothing else in `webprobe_full` needs touching.

---

### `install.sh:159-188` (`install_rust_uv`) — WIRE `verify_sha256` calls (Plan 02-03 / SEC-04 / D-11)

**Analog (canonical env-var-driven SHA pin):** `install.sh:1240-1289` — the `download_sha256` associative-array pattern with `${VAR:-}` defaults.

**Canonical precedent at `install.sh:1240-1290`:**

```bash
    declare -A downloads=(
        ["notify_provider_config"]="..."
        ["getjswords"]="..."
        ...
    )

    # Map of optional pinned checksums (env-var driven). Add more entries here
    # to extend integrity checks. Empty string means "no verification".
    declare -A download_sha256=(
        ["getjswords"]="${GETJSWORDS_SHA256:-}"
        ["axiom_config"]="${AXIOM_CONFIG_SHA256:-}"
    )

    local dl_step=0
    local total_dl=${#downloads[@]}
    for key in "${!downloads[@]}"; do
        ((++dl_step))
        url="${downloads[$key]% *}"
        destination="${downloads[$key]#* }"

        # Skip download if provider-config.yaml already exists
        if [[ $key == "notify_provider_config" && -f $destination ]]; then
            msg_warn "[$dl_step/$total_dl] $key skipped (already exists)"
            continue
        fi

        # Ensure destination directory exists
        mkdir -p "$(dirname "$destination")" 2>/dev/null || true

        if with_spinner "[$dl_step/$total_dl] Fetching $key" retry 3 3 q_to 120 wget -q -O "$destination" "$url"; then
            # Optional integrity check (active only when a SHA is pinned).
            local _expected="${download_sha256[$key]:-}"
            if [[ -n "$_expected" ]]; then
                if verify_sha256 "$destination" "$_expected"; then
                    msg_ok "[$dl_step/$total_dl] $key fetched (sha256 verified)"
                else
                    msg_err "[$dl_step/$total_dl] $key sha256 mismatch for $url; refusing to install"
                    rm -f "$destination"
                    continue
                fi
            else
                msg_ok "[$dl_step/$total_dl] $key fetched"
            fi
        else
            msg_err "[$dl_step/$total_dl] Failed to download $key from $url"
            continue
        fi
    done
```

**`verify_sha256` helper signature** (`install.sh:82-102` — already defined, already used by D-11's analog):

```bash
verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual=""

    [[ -n "$expected" ]] || return 0   # nothing to verify
    [[ -s "$file" ]] || return 1

    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | awk '{print $1}')
    else
        return 0  # no hashing tool available; skip (don't block install)
    fi

    [[ -n "$actual" && "$actual" == "$expected" ]]
}
```

**Current `install_rust_uv()` body** (`install.sh:159-188`):

```bash
install_rust_uv() {
    local _tmpfile
    # Install rustup via downloaded script (verify before executing)
    _tmpfile=$(mktemp "${TMPDIR:-/tmp}/rustup_install.XXXXXX")
    if curl -sSf https://sh.rustup.rs -o "$_tmpfile" 2>/dev/null; then
        sh "$_tmpfile" -y >/dev/null 2>&1
    else
        msg_warn "[!] Failed to download rustup installer"
    fi
    rm -f "$_tmpfile"

    # shellcheck source=/dev/null
    source "${HOME}/.cargo/env" 2>/dev/null || true
    cargo install smugglex &>/dev/null

    # Install uv via downloaded script (verify before executing)
    _tmpfile=$(mktemp "${TMPDIR:-/tmp}/uv_install.XXXXXX")
    if curl -LsSf https://astral.sh/uv/install.sh -o "$_tmpfile" 2>/dev/null; then
        sh "$_tmpfile" &>/dev/null
    else
        msg_warn "[!] Failed to download uv installer"
    fi
    rm -f "$_tmpfile"

    # shellcheck source=/dev/null
    source "${HOME}/.local/bin/env" 2>/dev/null || export PATH="${HOME}/.local/bin:$PATH"
    uv tool update-shell &>/dev/null || true
    # Install shodan CLI via uv
    uv tool install shodan --force &>/dev/null || uv tool upgrade shodan &>/dev/null || true
}
```

**Target shape (post-D-11):**

```bash
install_rust_uv() {
    local _tmpfile
    local _expected
    # Install rustup via downloaded script (verify before executing)
    _tmpfile=$(mktemp "${TMPDIR:-/tmp}/rustup_install.XXXXXX")
    if curl -sSf https://sh.rustup.rs -o "$_tmpfile" 2>/dev/null; then
        _expected="${RUSTUP_INSTALLER_SHA256:-}"
        if [[ -n "$_expected" ]]; then
            if verify_sha256 "$_tmpfile" "$_expected"; then
                msg_ok "[!] rustup installer sha256 verified"
                sh "$_tmpfile" -y >/dev/null 2>&1
            else
                msg_err "[!] rustup installer sha256 mismatch; refusing to execute"
                rm -f "$_tmpfile"
                return 1
            fi
        else
            sh "$_tmpfile" -y >/dev/null 2>&1
        fi
    else
        msg_warn "[!] Failed to download rustup installer"
    fi
    rm -f "$_tmpfile"

    # shellcheck source=/dev/null
    source "${HOME}/.cargo/env" 2>/dev/null || true
    cargo install smugglex &>/dev/null

    # Install uv via downloaded script (verify before executing)
    _tmpfile=$(mktemp "${TMPDIR:-/tmp}/uv_install.XXXXXX")
    if curl -LsSf https://astral.sh/uv/install.sh -o "$_tmpfile" 2>/dev/null; then
        _expected="${UV_INSTALLER_SHA256:-}"
        if [[ -n "$_expected" ]]; then
            if verify_sha256 "$_tmpfile" "$_expected"; then
                msg_ok "[!] uv installer sha256 verified"
                sh "$_tmpfile" &>/dev/null
            else
                msg_err "[!] uv installer sha256 mismatch; refusing to execute"
                rm -f "$_tmpfile"
                return 1
            fi
        else
            sh "$_tmpfile" &>/dev/null
        fi
    else
        msg_warn "[!] Failed to download uv installer"
    fi
    rm -f "$_tmpfile"

    # shellcheck source=/dev/null
    source "${HOME}/.local/bin/env" 2>/dev/null || export PATH="${HOME}/.local/bin:$PATH"
    uv tool update-shell &>/dev/null || true
    # Install shodan CLI via uv
    uv tool install shodan --force &>/dev/null || uv tool upgrade shodan &>/dev/null || true
}
```

**Documentation block to update at `install.sh:1228-1239`** (extend the GETJSWORDS / AXIOM_CONFIG example):

```bash
    # You can pin any entry by exporting an expected SHA-256 before running
    # install.sh:
    #     export GETJSWORDS_SHA256=<64 hex chars>
    #     export AXIOM_CONFIG_SHA256=<64 hex chars>
    #     export RUSTUP_INSTALLER_SHA256=<64 hex chars>   # rustup-init.sh from https://sh.rustup.rs
    #     export UV_INSTALLER_SHA256=<64 hex chars>       # uv installer from https://astral.sh/uv/install.sh
    # If set, each download is verified with `verify_sha256` and the install
    # aborts on mismatch. If unset the previous upstream-trusting behaviour is
    # preserved for backwards compatibility.
```

**Quirks to respect:**
- `verify_sha256` returns 0 when no hash tool is available (`install.sh:98`: `return 0  # no hashing tool available; skip (don't block install)`). This is intentional skip-don't-block semantics — preserves install on systems without `sha256sum`/`shasum`. The new env-var path inherits this behaviour automatically.
- `verify_sha256` returns 0 when `$expected` is empty (`install.sh:90`: `[[ -n "$expected" ]] || return 0`). The wrapping `if [[ -n "$_expected" ]]; then` is for the OK-msg path only; you could simplify by always calling `verify_sha256` and treating success as "either matched or skipped". Recommended structure (above) keeps the OK message explicit when verification was active, matching the `download_sha256` analog.
- `local _expected` must be declared once at the top of the function (after `local _tmpfile`) — bash will complain about re-`local` declarations only with `set -u`, which isn't enabled, but stylistic consistency matters.
- The `return 1` on mismatch ABORTS `install_rust_uv` but does NOT abort `install.sh` overall, because `install.sh` line 191 sets `trap … ERR` to log-and-continue. Per CONTEXT.md D-11 "aborts with a clear error message before executing it" — this means abort the bootstrapping, NOT the whole install. The `return 1` from `install_rust_uv` propagates up and the calling `install_apt`/`install_yum`/etc. will continue with other tools.
- `msg_ok` / `msg_warn` / `msg_err` are already-defined UI helpers (`install.sh:193+` "Minimal UI helpers (classic style)").

---

### `tools.lock` (new file, repo root) — Go-tool version pins (Plan 02-03 / D-12)

**Analog:** No existing manifest in the repo (verified: no `*.lock`, `requirements.txt`, `package.json` at repo root). Format spec is verbatim from CONTEXT.md D-12.

**File path:** `/Users/six2dez/Tools/reconftw/tools.lock`

**Format (CONTEXT.md D-12 verbatim):**

```text
# tools.lock — pinned Go tool versions for stability-critical tools.
# Format: <binary>=<go-module>@<version>
# - Comment lines start with '#'
# - Blank lines tolerated
# - Tools not listed here fall through to `go install <module>@latest` in install.sh
# - Update by running `go install <module>@latest` once and recording the resolved tag

nuclei=github.com/projectdiscovery/nuclei/v3/cmd/nuclei@v3.3.4
httpx=github.com/projectdiscovery/httpx/cmd/httpx@v1.6.10
ffuf=github.com/ffuf/ffuf/v2@v2.1.0
puredns=github.com/d3mondev/puredns/v2@v2.1.1
subfinder=github.com/projectdiscovery/subfinder/v2/cmd/subfinder@v2.6.7
```

**Quirks to respect:**
- **Version tags above are illustrative.** Per CONTEXT.md D-12 "Versions chosen by the planner via `go install ...@latest` once, recording the resolved tag." Executor must resolve actual `@latest` tags at execution time (e.g., `go list -m -versions github.com/projectdiscovery/nuclei/v3/cmd/nuclei` or watch `go install -v` output).
- Module paths MUST match the corresponding `gotools[name]` value in `install.sh:300-328` exactly — `nuclei` → `github.com/projectdiscovery/nuclei/v3/cmd/nuclei`, `httpx` → `github.com/projectdiscovery/httpx/cmd/httpx`, `ffuf` → `github.com/ffuf/ffuf/v2`, `puredns` → `github.com/d3mondev/puredns/v2`, `subfinder` → `github.com/projectdiscovery/subfinder/v2/cmd/subfinder`.
- Scope cap (D-13): exactly 5 entries. Do NOT add additional tools. Commit `71653984` explicitly removed wholesale pinning.
- File ends with a trailing newline (standard text file).
- Plain-text format chosen for `awk`/`sed` consumption and human-friendliness. Trailing whitespace per line is acceptable but discouraged (executor should `sed 's/[[:space:]]*$//'` if needed).

---

### `install.sh:489-521` — Read `tools.lock` before iterating (Plan 02-03 / D-12)

**Analog:** `install.sh:1258-1290` (the `download_sha256` map iteration — env-var-driven branch + fallback default).

**Existing Go install loop** (`install.sh:489-521`):

```bash
# Function to install Go tools
function install_tools() {
    header "Installing Golang tools (${#gotools[@]})"

    # Force module-mode resolution so vendored or GOPATH-mode environments
    # don't break go install for tools whose modules use SIV (e.g. /v2, /v3).
    export GOFLAGS="-mod=mod"
    export GO111MODULE="on"

    local go_step=0
    local failed_tools=()
    local total_go=${#gotools[@]}
    local go_ok=0 go_skip=0 go_fail=0
    for gotool in "${!gotools[@]}"; do
        ((++go_step))
        # Always run go install so already-present binaries also get updated.
        # argv form (not bash -lc) so arr values are data, not shell syntax.
        if q go install -v "${gotools[$gotool]}@latest"; then
            ((++go_ok))
            msg_ok "[$go_step/$total_go] ${gotool} installed"
        else
            # If the binary is already present, the upgrade failed but the tool still works.
            # Treat this as a warning rather than a hard failure.
            if command -v "$gotool" >/dev/null 2>&1; then
                ((++go_skip))
                msg_warn "[$go_step/$total_go] ${gotool} upgrade failed (existing binary kept)"
            else
                failed_tools+=("$gotool")
                ((++go_fail))
                double_check=true
                msg_err "[$go_step/$total_go] ${gotool} failed"
            fi
        fi
    done
```

**Target shape (post-D-12):**

```bash
# Function to install Go tools
function install_tools() {
    header "Installing Golang tools (${#gotools[@]})"

    # Force module-mode resolution so vendored or GOPATH-mode environments
    # don't break go install for tools whose modules use SIV (e.g. /v2, /v3).
    export GOFLAGS="-mod=mod"
    export GO111MODULE="on"

    # Load optional tool pins from ./tools.lock (D-12 / SEC-04).
    # Each line: <binary>=<module>@<version>. Comments (#) and blank lines ignored.
    # If a tool listed here is also in $gotools, the lock entry wins; otherwise
    # `go install @latest` is used. Errors loading tools.lock are non-fatal.
    declare -A pinned_tools=()
    local _lockfile="${SCRIPTPATH:-$(pwd)}/tools.lock"
    if [[ -f "$_lockfile" ]]; then
        while IFS='=' read -r _key _val; do
            # Strip surrounding whitespace; skip blanks/comments
            _key="${_key#"${_key%%[![:space:]]*}"}"   # ltrim
            _key="${_key%"${_key##*[![:space:]]}"}"   # rtrim
            [[ -z "$_key" || "$_key" == \#* ]] && continue
            _val="${_val#"${_val%%[![:space:]]*}"}"
            _val="${_val%"${_val##*[![:space:]]}"}"
            [[ -z "$_val" ]] && continue
            pinned_tools["$_key"]="$_val"
        done < "$_lockfile"
        msg_ok "Loaded ${#pinned_tools[@]} pin(s) from tools.lock"
    fi

    local go_step=0
    local failed_tools=()
    local total_go=${#gotools[@]}
    local go_ok=0 go_skip=0 go_fail=0
    for gotool in "${!gotools[@]}"; do
        ((++go_step))
        # Pinned version wins; otherwise fall through to @latest.
        local _module_at_version
        if [[ -n "${pinned_tools[$gotool]:-}" ]]; then
            _module_at_version="${pinned_tools[$gotool]}"
        else
            _module_at_version="${gotools[$gotool]}@latest"
        fi
        if q go install -v "$_module_at_version"; then
            ((++go_ok))
            msg_ok "[$go_step/$total_go] ${gotool} installed"
        else
            # If the binary is already present, the upgrade failed but the tool still works.
            # Treat this as a warning rather than a hard failure.
            if command -v "$gotool" >/dev/null 2>&1; then
                ((++go_skip))
                msg_warn "[$go_step/$total_go] ${gotool} upgrade failed (existing binary kept)"
            else
                failed_tools+=("$gotool")
                ((++go_fail))
                double_check=true
                msg_err "[$go_step/$total_go] ${gotool} failed"
            fi
        fi
    done
```

**Quirks to respect:**
- The lockfile path uses `SCRIPTPATH:-$(pwd)` because `install.sh` is normally invoked from the repo root but `SCRIPTPATH` may not be set in standalone install invocations. CONTEXT.md D-12 specifies "plain-text `tools.lock` file in the repo root" — `SCRIPTPATH` resolution in `install.sh` predates this work; verify path resolution at execution time.
- The `pinned_tools["$_key"]="$_val"` already INCLUDES the `@version` suffix from the lock value (per CONTEXT.md format: `nuclei=github.com/.../nuclei@v3.3.4`). So `_module_at_version="${pinned_tools[$gotool]}"` directly contains the full `<module>@<version>` string — do NOT append `@latest`.
- The fallback for unpinned tools concatenates `@latest` exactly as the pre-D-12 loop did: `"${gotools[$gotool]}@latest"`.
- Whitespace stripping uses Bash parameter-expansion idioms (no `sed`/`tr` dependency) — `_key="${_key#"${_key%%[![:space:]]*}"}"` etc. is the canonical pure-Bash ltrim/rtrim.
- Comment / blank line handling: `[[ -z "$_key" || "$_key" == \#* ]] && continue` covers `# comment`, empty lines, and whitespace-only lines.
- If `tools.lock` has a malformed line (missing `=` separator), `_val` is empty after the `read -r`, and the `[[ -z "$_val" ]] && continue` skips it. Graceful failure mode.
- Manifest scope cap is enforced by the file itself (5 entries) — install.sh does not enforce a cap; it iterates `gotools` keys (50+) and looks up each in `pinned_tools`. So if `tools.lock` grows beyond 5 entries (against D-13), all entries still apply. The cap is policy, not mechanism.

---

## Shared Patterns

### UPPER_SNAKE_CASE globals
**Source:** `.planning/codebase/CONVENTIONS.md:60-63`
**Apply to:** `AXIOM_EXTRA_ARGS_ARR` (D-07)
**Existing siblings to slot alongside:** `AXIOM`, `AXIOM_EXTRA_ARGS`, `AXIOM_FLEET_COUNT`, `OUTPUT_VERBOSITY`, `PARALLEL_MODE` — all defined globally and read from any module without local shadowing.

### `function name()` declaration form
**Source:** `.planning/codebase/CONVENTIONS.md:43-49`
**Apply to:** any new function added by Plan 02-03 (none currently planned; `verify_sha256` and `install_rust_uv` already exist and use the `name() { ... }` form, which is the established install.sh style — preserve it).

### Inline shellcheck disables only
**Source:** `.planning/codebase/CONVENTIONS.md:277`
**Apply to:** D-05 (`sendToNotify` quoting pass)
**Pattern:**

```bash
# shellcheck disable=SC2086  # word-split intentional for ARGS list
some_cmd $ARGS
```

NEVER file-level. Place the disable comment on the line ABOVE the offending expansion with a one-line explanation.

### `read -r -a` from a here-string idiom
**Source:** `modules/web.sh:150-155`, `modules/vulns.sh:258`, `modules/web.sh:740`, `modules/web.sh:754`, `modules/web.sh:810`
**Apply to:** D-07 (global `AXIOM_EXTRA_ARGS_ARR` parse)
**Canonical excerpt** (`modules/web.sh:150-155`):

```bash
if [[ -n "${AXIOM_EXTRA_ARGS:-}" ]]; then
    local _ifs="$IFS"
    IFS=' '
    read -r -a axiom_extra_args <<<"$AXIOM_EXTRA_ARGS"
    IFS="$_ifs"
fi
```

The global version (D-07) replaces `local _ifs` with `_axiom_ifs_saved` to make scope clear at top-level.

### Env-var-driven optional verification
**Source:** `install.sh:1240-1289` (`download_sha256` map pattern)
**Apply to:** D-11 (`RUSTUP_INSTALLER_SHA256`, `UV_INSTALLER_SHA256`)
**Semantics:** Empty env var = skip (don't block install). Set env var = verify, abort on mismatch. Behaviour-preserving for existing users; opt-in pinning for security-conscious users / CI.

### Single-commit-per-logical-change
**Source:** `.planning/PROJECT.md` §"Recent trajectory"; Phase 1 execution log
**Apply to:** Plans 02-01, 02-02, 02-03
**Application:**
- Plan 02-01 = 1 commit (`safe_count` removal + bats deletes + doc updates), OR 2 commits (code + docs). Either is acceptable per CONTEXT.md Claude's Discretion.
- Plan 02-02 = 1 commit (sendToNotify quoting + mantra path fix — both in `modules/`, both Plan 02-02 hardening).
- Plan 02-03 = 3 commits (global parse + 38-site migration, install_rust_uv SHA wiring + comment block update, tools.lock manifest + install.sh consumer) — OR 1 large commit; planner judgment. Recommend 3 commits for review-ability since the array refactor touches 2 files + reconftw.sh, and tools.lock + install.sh consumer is logically separate from rustup/uv SHA wiring.

### `_print_status`, `msg_ok`, `msg_warn`, `msg_err` UI helpers
**Source:** `lib/common.sh:213-249` (`print_task` / `_print_status`); `install.sh` "Minimal UI helpers (classic style)" block circa line 193
**Apply to:** D-04 (`sendToNotify` keeps `_print_status` / `_print_msg`), D-11 (`install_rust_uv` keeps `msg_ok` / `msg_warn` / `msg_err`)
**Note:** `modules/core.sh` uses `_print_status` / `_print_msg`; `install.sh` uses `msg_ok` / `msg_warn` / `msg_err`. Do NOT cross-pollinate — each file's UI vocabulary is established.

## No Analog Found

| File | Role | Reason | Mitigation |
|------|------|--------|------------|
| `tools.lock` (new file) | new-file manifest | No existing `*.lock` or `requirements.txt`-style manifest in the repo. The closest pattern is the `download_sha256` associative-array declared in-line in `install.sh:1251-1254`, but it lives inside a function rather than as a separate file. | Follow CONTEXT.md D-12 spec verbatim. Plain-text key=value, `#` comments, blank lines tolerated. |

## Metadata

**Analog search scope:** `lib/common.sh`, `modules/core.sh`, `modules/web.sh`, `modules/subdomains.sh`, `modules/vulns.sh`, `modules/axiom.sh`, `modules/modes.sh`, `modules/utils.sh`, `lib/parallel.sh`, `lib/ui.sh`, `lib/validation.sh`, `reconftw.sh`, `install.sh`, `tests/unit/test_common.bats`, `tests/integration/test_full_flow.bats`, `CHANGELOG.md`, `CLAUDE.md`, `.planning/codebase/*`
**Files scanned:** 19 source files + 5 doc files
**Pattern extraction date:** 2026-05-13
**Tooling required by executor:** `shellcheck` (pre-commit hook), `shfmt` (pre-commit hook), `bats-core` (test deletion verification), `go` (for resolving `@latest` tags during tools.lock authoring)
