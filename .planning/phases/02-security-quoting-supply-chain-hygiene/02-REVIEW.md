---
phase: 02-security-quoting-supply-chain-hygiene
reviewed: 2026-05-13T00:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - lib/common.sh
  - tests/unit/test_common.bats
  - tests/integration/test_full_flow.bats
  - CHANGELOG.md
  - CLAUDE.md
  - modules/core.sh
  - modules/web.sh
  - tools.lock
  - reconftw.sh
  - modules/subdomains.sh
  - install.sh
findings:
  critical: 3
  warning: 5
  info: 3
  total: 11
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-05-13
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

This review covers the phase-02 security changes: removal of the `safe_count()` eval vector, quoting pass on `sendToNotify()` in `modules/core.sh`, the `AXIOM_EXTRA_ARGS_ARR` array refactor across `modules/subdomains.sh` and `modules/web.sh`, SHA-256 install gates and `tools.lock` manifest in `install.sh`, and a casing fix for the brosck/mantra module path.

The eval deletion and the array refactor are correct. The `tools.lock` mechanism works. Several bugs and security gaps remain, however:

- `end_func()` in `modules/core.sh` touches `$called_fn_dir/.${fn}` without guarding for an unset `called_fn_dir`, which crashes the framework if the global is absent.
- `sendToNotify()` never calls `register_secret` for `slack_auth`, leaving the Bearer token unredacted in `LOGFILE` on every Slack upload.
- `install.sh` silently skips SHA-256 verification when neither `sha256sum` nor `shasum` is on `PATH`, prints `return 0` even for a corrupted file — this negates the supply-chain gate on exotic systems.
- Multiple `AXIOM_RESOLVERS_PATH` / `AXIOM_RESOLVERS_TRUSTED_PATH` references in `modules/subdomains.sh` remain unquoted, breaking Axiom execution if either path contains whitespace.
- `mantra` on the local (non-Axiom) path passes `\"$HEADER\"` with literal backslash-escaped quotes to the shell, causing the user-agent argument to be passed with stray quote characters.
- `process_results()` fallback (no `anew`) is logically incorrect and always returns 0.
- `tools.lock` pins only 5 of the ~55 Go tools, leaving the majority still at `@latest`.

---

## Critical Issues

### CR-01: `end_func()` touches checkpoint without guarding `called_fn_dir`

**File:** `modules/core.sh:1485`
**Issue:** Lines 1482-1484 correctly gate the `rm -f .inprogress_*` step behind `[[ -n "${called_fn_dir:-}" ]]`, but line 1485 calls `touch "$called_fn_dir/.${fn}"` unconditionally. When `called_fn_dir` is empty or unset (unit-test context, early `--source-only` load, or any invocation where `start()` has not run yet), this expands to `touch "/.${fn}"`, attempting to write a dotfile in the filesystem root. On a read-only root or when running as non-root this silently fails; the checkpoint is never created and every function will re-execute forever. On a writable root it pollutes `/`.

`end_subfunc()` at line 1572 has the identical defect.

**Fix:**
```bash
# end_func line 1485 — guard matches the rm block above it
if [[ -n "${called_fn_dir:-}" ]]; then
    touch "$called_fn_dir/.${fn}" 2>/dev/null || true
fi
```
Apply the same guard to `end_subfunc` line 1572.

---

### CR-02: `slack_auth` Bearer token written unredacted to `LOGFILE`

**File:** `modules/core.sh:1412-1414`
**Issue:** `sendToNotify()` calls `register_secret` for both `telegram_key` (line 1403) and `discord_url` (line 1409), correctly preventing those values from appearing in the log. However, the Slack branch (lines 1412-1414) passes `slack_auth` directly in the `curl` command's `-H "Authorization: Bearer ${slack_auth}"` header **without** a preceding `register_secret "${slack_auth}"` call. The `run_command` wrapper logs the full command string to `LOGFILE` when `SHOW_COMMANDS=true`, and `_trace_redact_stream` only redacts values that appear in `REDACT_VARS` (which includes `slack_auth` by name) — but `redact_secrets()` resolves vars via `${!var}` **at log-write time**, so if `slack_auth` was set as a local inside `sendToNotify` (which it isn't here — it's a global config var), the indirection would miss it. More critically, `run_tool()` in `lib/common.sh` line 641 echoes the raw command to `LOGFILE` **before** `redact_secrets` is applied to xtrace output, meaning the Bearer token lands verbatim when `LOGFILE` captures from `run_command`'s `echo` call.

**Fix:**
```bash
if [[ -n "${slack_channel}" ]] && [[ -n "${slack_auth}" ]]; then
    register_secret "${slack_auth}"    # <-- add this line
    notification "Sending ${domain} data over Slack" info
    run_command curl -F "file=@${1}" ...
fi
```

---

### CR-03: `verify_sha256()` silently returns success when no hash tool is available

**File:** `install.sh:93-98`
**Issue:** When neither `sha256sum` nor `shasum` is in `PATH`, `verify_sha256()` unconditionally returns 0 (success). The caller in `install_rust_uv()` interprets this as "hash verified" and proceeds to execute the downloaded installer script. An attacker who can strip those tools from `PATH` (e.g., via a compromised Docker base layer or environment manipulation before `install.sh` runs) gets code execution from an unverified download without any error or warning.

```bash
# install.sh lines 97-98 — the silent pass-through
else
    return 0  # no hashing tool available; skip (don't block install)
fi
```

**Fix:** Return a distinct code (2) when no hashing tool is found, and treat it as a warning (not success) in callers. At minimum, print a warning so the operator knows verification was bypassed:
```bash
else
    printf '[WARN] verify_sha256: no sha256sum or shasum found; skipping integrity check for %s\n' "$file" >&2
    return 0  # preserve backward compat but warn loudly
fi
```
The callers should be updated to treat this differently from a positive match:
```bash
if verify_sha256 "$_tmpfile" "$_expected"; then
    msg_ok "[!] rustup installer sha256 verified"
    sh "$_tmpfile" ...
else
    # Could be mismatch OR no tool available — log distinguishes them
    msg_err "[!] rustup installer verification failed; refusing to execute"
    ...
fi
```

---

## Warnings

### WR-01: Unquoted `AXIOM_RESOLVERS_PATH` / `AXIOM_RESOLVERS_TRUSTED_PATH` — word-splitting breaks Axiom paths with spaces

**File:** `modules/subdomains.sh:668-669, 766, 1097-1098, 1364`
**Issue:** Several `axiom-scan` call sites pass these two path variables unquoted. Lines 1104-1105 quote them correctly (`"${AXIOM_RESOLVERS_PATH}"`), proving the intended fix style, but lines 668-669, 766, 1097-1098, and 1364 still use bare `${AXIOM_RESOLVERS_PATH}`. If either variable contains a space or glob character (common on macOS user home directories like `/Users/My Name/...`), the argument splits into multiple tokens, breaking the `-r` or `--resolvers-trusted` flags.

**Fix:** Apply consistent quoting everywhere:
```bash
# line 667-669 — before
run_command axiom-scan .tmp/subs_no_resolved.txt -m puredns-resolve \
    -r ${AXIOM_RESOLVERS_PATH} \
    --resolvers-trusted ${AXIOM_RESOLVERS_TRUSTED_PATH} \

# after
run_command axiom-scan .tmp/subs_no_resolved.txt -m puredns-resolve \
    -r "${AXIOM_RESOLVERS_PATH}" \
    --resolvers-trusted "${AXIOM_RESOLVERS_TRUSTED_PATH}" \
```
Apply the same to lines 766, 1097-1098, and 1364.

---

### WR-02: `mantra` local-path invocation passes literal backslash-quotes to the shell

**File:** `modules/web.sh:2329`
**Issue:** The local (non-Axiom) mantra call uses `\"$HEADER\"` with backslash-escaped double-quotes inside a double-quoted string:
```bash
cat js/js_livelinks.txt | mantra -ua \"$HEADER\" -s | anew -q js/js_secrets.txt ...
```
In bash, inside a double-quoted string `\"` is just a literal double-quote character — so if `HEADER` contains e.g. `User-Agent: reconFTW`, the shell actually passes the argument as `"User-Agent: reconFTW"` (with literal quote characters) to mantra, not as a clean unquoted string. The Axiom path on line 2332 does this correctly (`-ua "$HEADER"`). This means the user-agent header value sent in local mode differs from the Axiom mode and may cause mantra to reject the argument or pass a malformed header.

**Fix:**
```bash
# line 2329 — change \"$HEADER\" to "$HEADER"
cat js/js_livelinks.txt | mantra -ua "$HEADER" -s | anew -q js/js_secrets.txt 2>>"$LOGFILE" >/dev/null || true
```

---

### WR-03: `process_results()` fallback branch always returns 0 (never counts lines correctly)

**File:** `lib/common.sh:763`
**Issue:** The fallback branch (when `anew` is unavailable) is:
```bash
count=$(cat "$input" >> "$output" && wc -l < "$input" | tr -d ' ')
```
`cat "$input" >> "$output"` appends and succeeds (exits 0); the `&&` then runs `wc -l < "$input"`. However, the entire expression is evaluated as a single command substitution pipeline where `cat ... && wc -l` — the `&&` inside `$()` chains the two subshell commands. When `cat` succeeds, `wc -l` runs, but its stdout is the command substitution result, which is correct. The real bug: there is no deduplication in the fallback path, so `count` reflects all lines from the input file (including duplicates already in output), not the number of newly added lines. Callers that use the returned count to emit "N new lines" will report inflated counts when `anew` is absent.

**Fix:** Either explicitly deduplicate in the fallback or document the limitation:
```bash
else
    # Fallback: no dedup — append all and count input lines (may overcount duplicates)
    cat "$input" >> "$output" 2>/dev/null
    count=$(sed '/^$/d' "$input" | wc -l | tr -d ' ')
fi
```

---

### WR-04: `tools.lock` covers only 5 of ~55 Go tools — supply-chain pinning incomplete

**File:** `tools.lock`
**Issue:** The lock file introduced in this phase pins `nuclei`, `httpx`, `ffuf`, `puredns`, and `subfinder`. The remaining ~50 Go tools declared in `install.sh`'s `gotools` associative array still fall through to `@latest`. Tools like `dalfox`, `katana`, `trufflehog`, `interactsh-client`, and `tlsx` run with broad network and filesystem access during scans; a compromised `@latest` release of any of them constitutes a supply-chain vector. The lock mechanism is correct and the parsing logic works, but its security value is limited to those 5 entries.

**Fix:** Extend `tools.lock` to pin high-privilege tools at minimum. A pragmatic priority list (tools with network/filesystem write access during active scans):
```
dalfox=github.com/hahwul/dalfox/v2@v2.9.2
katana=github.com/projectdiscovery/katana/cmd/katana@v1.1.2
dnsx=github.com/projectdiscovery/dnsx/cmd/dnsx@v1.2.1
naabu=github.com/projectdiscovery/naabu/v2/cmd/naabu@v2.3.3
interactsh-client=github.com/projectdiscovery/interactsh/cmd/interactsh-client@v1.2.2
tlsx=github.com/projectdiscovery/tlsx/cmd/tlsx@v1.1.7
```

---

### WR-05: SHA-256 coverage for downloaded scripts is opt-in only — `getjswords.py` and `axiom_config.sh` run unsigned by default

**File:** `install.sh:1306-1308`
**Issue:** The `download_sha256` map for `getjswords.py` and `axiom_config.sh` uses `${GETJSWORDS_SHA256:-}` and `${AXIOM_CONFIG_SHA256:-}`, both defaulting to empty string. The surrounding logic skips verification entirely when the variable is empty (line 1330: `if [[ -n "$_expected" ]]`). In practice, no operator will set these env vars without explicit documentation, so `getjswords.py` (fetched from `m4ll0k/Bug-Bounty-Toolz@master`) and `axiom_config.sh` (from a gist) are executed with no integrity check on every default installation. `axiom_config.sh` is `chmod +x` and runs arbitrary code from a GitHub gist controlled by the project author — a compromised gist account is a direct RCE vector.

**Fix:** Hardcode a known-good SHA-256 for each of these in `tools.lock` or directly in `download_sha256`. If the gist or script changes legitimately, bump the hash explicitly and record it in the CHANGELOG. At minimum, document that operators **must** set these vars for a hardened install.

---

## Info

### IN-01: `AXIOM_EXTRA_ARGS_ARR` is parsed twice before config load in `reconftw.sh`

**File:** `reconftw.sh:121-131, 526-536`
**Issue:** `AXIOM_EXTRA_ARGS_ARR` is initialized twice: once at line 125 (before config is sourced, described as "for --source-only callers") and again at line 529 (after config). The first initialization is harmless but confusing — the comment says the second parse is the "canonical production parse" that overwrites the first. In a `--source-only` context, both parses produce the same result from the same env var. The duplication adds maintenance risk: if the parsing logic ever diverges between the two blocks, bugs appear only in one context.

**Fix:** Factor the parse logic into a helper function called from both sites, or delete the pre-config initialization and rely only on the post-config parse with a note that `--source-only` tests must set `AXIOM_EXTRA_ARGS` before sourcing.

---

### IN-02: `run_with_heartbeat_shell` executes a user-controlled shell string via `/bin/bash -lc`

**File:** `lib/common.sh:745`
**Issue:** `run_with_heartbeat_shell` passes its second argument directly as a shell command string to `/bin/bash -lc`. All current call sites in `modules/web.sh` construct this string from config variables (`katana_headless_flags`, `KATANA_THREADS`, `LOGFILE`, etc.). If any of these variables contain shell metacharacters (semicolons, backticks, `$()`), they will be interpreted as commands. This is an existing structural issue, not a regression in this phase, but deserves tracking as the pattern is fragile under adversarial config values.

**Fix:** Replace shell-string construction with explicit array passing where possible (use `run_with_heartbeat` instead of `run_with_heartbeat_shell`). For complex redirections that require shell expansion, validate that no variable embedded in the string is user-controlled or sanitize them with `printf '%q'`.

---

### IN-03: `test_common.bats` has no test for `process_results()` fallback path

**File:** `tests/unit/test_common.bats:257-266`
**Issue:** The `process_results` test at line 257 skips entirely if `anew` is not installed (`skip "anew not installed"`), meaning the fallback code path (lines 762-763 in `lib/common.sh`) is never tested by the suite. The fallback has a logic error (WR-03 above) that could have been caught by a test that temporarily moves `anew` out of `PATH`.

**Fix:**
```bash
@test "process_results fallback counts all input lines when anew unavailable" {
    local old_path="$PATH"
    # Shadow anew with a non-existent path
    PATH="/nonexistent:$PATH"
    printf "a\nb\nc\n" > input.txt
    touch output.txt
    result=$(process_results input.txt output.txt)
    PATH="$old_path"
    [ "$result" -eq 3 ]
    [ "$(wc -l < output.txt | tr -d ' ')" -eq 3 ]
}
```

---

_Reviewed: 2026-05-13_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
