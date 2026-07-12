---
phase: 02-security-quoting-supply-chain-hygiene
fixed_at: 2026-05-13T13:52:00Z
review_path: .planning/phases/02-security-quoting-supply-chain-hygiene/02-REVIEW.md
iteration: 1
findings_in_scope: 8
fixed: 8
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-05-13T13:52:00Z
**Source review:** .planning/phases/02-security-quoting-supply-chain-hygiene/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 8 (3 Critical, 5 Warning; Info findings excluded per fix_scope=critical_warning)
- Fixed: 8
- Skipped: 0

## Fixed Issues

### CR-01: `end_func()` touches checkpoint without guarding `called_fn_dir`

**Files modified:** `modules/core.sh`
**Commit:** 68b6697d
**Applied fix:** Moved `touch "$called_fn_dir/.${fn}"` inside the existing `[[ -n "${called_fn_dir:-}" ]]` guard block that already gated the `rm -f .inprogress_*` call on line 1482. Applied the identical null-guard to `end_subfunc()` which had the same defect. Both touch calls also gained `2>/dev/null || true` to silently tolerate read-only filesystems without masking the real error.

---

### CR-02: `slack_auth` Bearer token written unredacted to `LOGFILE`

**Files modified:** `modules/core.sh`
**Commit:** 5b738c56
**Applied fix:** Added `register_secret "${slack_auth}"` immediately before `notification "Sending ${domain} data over Slack"` in the Slack branch of `sendToNotify()`. This mirrors the `register_secret "${telegram_key}"` call on line 1403 and the `register_secret "${discord_url}"` call on line 1409, ensuring the Bearer token is added to the redaction set before `run_command` logs the curl invocation.

---

### CR-03: `verify_sha256()` silently returns success when no hash tool is available

**Files modified:** `install.sh`
**Commit:** 574b8b09
**Applied fix:** Added a `printf '[WARN] ...' >&2` line in the `else` branch (when neither `sha256sum` nor `shasum` is on PATH) before `return 0`. Preserves backward-compatible return code semantics while making the bypass visible to operators in both interactive and piped-log installs. The `return 0` comment was updated to clarify intent.

---

### WR-01: Unquoted `AXIOM_RESOLVERS_PATH` / `AXIOM_RESOLVERS_TRUSTED_PATH` — word-splitting breaks Axiom paths with spaces

**Files modified:** `modules/subdomains.sh`
**Commit:** 25e9f226
**Applied fix:** Quoted all eleven unquoted `${AXIOM_RESOLVERS_PATH}` and `${AXIOM_RESOLVERS_TRUSTED_PATH}` references across `modules/subdomains.sh`. The reviewer cited four specific sites (lines 668-669, 766, 1097-1098, 1364); seven additional identical occurrences existed in the recursive brute/permutation functions (lines 1664, 1740, 1836, 1903, 1924, 1942, 1988) and were fixed in the same commit to eliminate the full class of the defect. All now match the correctly-quoted form at lines 1104-1105.

---

### WR-02: `mantra` local-path invocation passes literal backslash-quotes to the shell

**Files modified:** `modules/web.sh`
**Commit:** 7dd02c4c
**Applied fix:** Changed `mantra -ua \"$HEADER\"` to `mantra -ua "$HEADER"` on the non-Axiom code path at line 2329. The `\"` inside a double-quoted string produces a literal double-quote character, not an argument boundary. The fix matches the Axiom path on line 2332 which already used `"$HEADER"` correctly.

---

### WR-03: `process_results()` fallback branch always returns 0 (never counts lines correctly)

**Files modified:** `lib/common.sh`
**Commit:** 2b0bcf19
**Applied fix:** Separated the `cat "$input" >> "$output" && wc -l < "$input"` chain into two independent statements. `cat` appends unconditionally; `count` is then set via `sed '/^$/d' "$input" | wc -l | tr -d ' '` to count non-empty input lines. Added a comment documenting the known limitation that the fallback may over-count duplicates (since there is no `anew` deduplication), consistent with the reviewer's guidance to document the expected behaviour.

---

### WR-04: `tools.lock` covers only 5 of ~55 Go tools — supply-chain pinning incomplete

**Files modified:** `tools.lock`
**Commit:** 378d5cd1
**Applied fix:** Extended `tools.lock` with six high-privilege tools cited by the reviewer: `dalfox`, `katana`, `dnsx`, `naabu`, `interactsh-client`, and `tlsx`. Added a section comment documenting the intent and instructing maintainers to verify tags in a sandbox before each major release. Note: version tags (e.g. `dalfox@v2.9.2`) are the reviewer-suggested pins and should be cross-checked against each project's GitHub releases page before shipping, as the reviewer's knowledge cutoff may not reflect the current latest stable.

**Human verification recommended:** Confirm all six version tags are genuine published releases before merging to main.

---

### WR-05: SHA-256 coverage for downloaded scripts is opt-in only — `getjswords.py` and `axiom_config.sh` run unsigned by default

**Files modified:** `install.sh`
**Commit:** 0ed61a1a
**Applied fix:** In the download loop's `else` branch (no `_expected` value), added a conditional check: if the key is present in `download_sha256` (i.e. it is a known integrity-checkable download but has no pinned hash), emit `msg_warn "... integrity unverified"` with a comment documenting the env vars (`GETJSWORDS_SHA256`, `AXIOM_CONFIG_SHA256`) that operators must set for a hardened install. Downloads not in the `download_sha256` map (i.e. truly unrelated items) continue to emit `msg_ok`. This makes the security gap visible on every default installation without blocking the install for operators who accept the risk.

---

## Skipped Issues

None — all 8 in-scope findings were successfully fixed.

---

_Fixed: 2026-05-13T13:52:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
