---
phase: 02-security-quoting-supply-chain-hygiene
verified: 2026-05-13T14:30:00Z
status: human_needed
score: 4/5 must-haves verified
overrides_applied: 0
human_verification:
  - test: "Axiom remote mantra install"
    expected: "axiom-exec 'go install github.com/brosck/mantra@latest' completes without 404; the mantra binary is available on the remote node; axiom-scan with -m mantra produces output"
    why_human: "Cannot start an Axiom fleet or issue axiom-exec commands programmatically in the verifier environment. The codebase fix (B->b) is verified, but the live runtime outcome requires an actual Axiom node."
---

# Phase 2: Security Quoting & Supply-Chain Hygiene Verification Report

**Phase Goal:** Eliminate the remaining `eval` injection vector, lock down unquoted notification curl calls, make `AXIOM_EXTRA_ARGS` tokenisation explicit, and integrity-check installer bootstrappers.
**Verified:** 2026-05-13T14:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `grep -n "eval " lib/common.sh modules/*.sh` returns no eval calls under safe_count() — the else branch at lib/common.sh:760 is gone | ✓ VERIFIED | `safe_count()` function entirely deleted from lib/common.sh (17-line block including eval branch). `grep -n "safe_count" lib/common.sh modules/*.sh` returns 0 hits. `grep -n "eval " lib/common.sh modules/*.sh` returns 0 hits. Bash syntax check passes. |
| 2 | sendToNotify() in modules/core.sh quotes every variable passed to curl ($discord_url, ${slack_channel}, ${1}); shellcheck reports no new findings against modules/core.sh:1399-1414 | ✓ VERIFIED | All 14 variable expansion sites in sendToNotify() use "${var}" form (lines 1387-1418 verified). `grep -nE '\$1[^"}]\|...' modules/core.sh | awk -F: '$1>=1387 && $1<=1418'` returns 0 hits. -F form pairs use quoted-pair form. Telegram URL is quoted. `shellcheck --severity=warning modules/core.sh` produces 0 SC2086/SC2068/SC2027 findings in that range. CR-02 (register_secret for slack_auth) also fixed at line 1413. |
| 3 | AXIOM_EXTRA_ARGS is consumed as AXIOM_EXTRA_ARGS_ARR=() across modules/subdomains.sh and modules/web.sh; intentional whitespace tokens tokenise correctly; single-token value does not split | ✓ VERIFIED | Global array parsed in reconftw.sh (lines 121-131 early parse, 526-535 post-config parse). 21 sites in subdomains.sh and 17 sites in web.sh use `"${AXIOM_EXTRA_ARGS_ARR[@]}"`. `grep -nE 'AXIOM_EXTRA_ARGS([^_]|$)' modules/subdomains.sh modules/web.sh` returns 0 hits. Tokenisation smoke: `--rate-limit 100 --threads 50` → 4 tokens. Single-token `--flag` → 1 token (no split). Empty env → 0 tokens. webprobe_full local-array block removed. |
| 4 | install.sh calls verify_sha256() against pinned hashes for rustup-init.sh and uv/install.sh; aborts with clear error on mismatch; tools.lock pins versions for nuclei, httpx, ffuf, puredns, subfinder | ✓ VERIFIED | install_rust_uv() reads RUSTUP_INSTALLER_SHA256 and UV_INSTALLER_SHA256 env vars; calls `verify_sha256 "$_tmpfile" "$_expected"` for both; `return 1` on mismatch with `msg_err "refusing to execute"`. tools.lock exists with 11 entries (5 required + 6 high-privilege additions from WR-04). All 5 required tools (nuclei, httpx, ffuf, puredns, subfinder) present. install_tools() reads tools.lock into pinned_tools associative array before the for-gotool loop. CR-03 fixed: verify_sha256 prints WARN when no hash tool found instead of silent return 0. |
| 5 | Running axiom-exec mantra against a remote node installs github.com/brosck/mantra@latest (lowercase) and the binary runs | ? UNCERTAIN (HUMAN) | Codebase fix confirmed: `grep -n "Brosck" modules/web.sh` returns 0 hits; `grep -c "github.com/brosck/mantra@latest" modules/web.sh` returns 1 (line 2331). Local install.sh and remote web.sh now agree on lowercase brosck. Live axiom runtime cannot be tested programmatically. |

**Score:** 4/5 must-haves verified (SC-5 requires human testing)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/common.sh` | safe_count() removed; count_lines/count_lines_stdin preserved | ✓ VERIFIED | 17-line block deleted including eval branch. count_lines() at line 125 and count_lines_stdin() at line 136 intact and callable. Bash syntax clean. |
| `tests/unit/test_common.bats` | safe_count test section removed | ✓ VERIFIED | `grep -n "safe_count" tests/unit/test_common.bats` returns 0 hits. |
| `tests/integration/test_full_flow.bats` | safe_count integration test removed | ✓ VERIFIED | `grep -n "safe_count" tests/integration/test_full_flow.bats` returns 0 hits. |
| `CHANGELOG.md`, `CLAUDE.md`, `.planning/codebase/CONVENTIONS.md`, `.planning/codebase/STRUCTURE.md`, `.planning/codebase/ARCHITECTURE.md` | safe_count references dropped | ✓ VERIFIED | `grep -c "safe_count"` returns 0 for all 5 files. |
| `modules/core.sh` | sendToNotify() fully-quoted; CR-01 and CR-02 fixes applied | ✓ VERIFIED | All variables double-quoted. register_secret called for telegram_key, discord_url, and slack_auth. end_func/end_subfunc guarded by `[[ -n "${called_fn_dir:-}" ]]`. |
| `modules/web.sh` | brosck/mantra lowercase at axiom-exec line; AXIOM_EXTRA_ARGS_ARR at 15+ sites; WR-02 mantra local-path fix | ✓ VERIFIED | `grep -n "Brosck" modules/web.sh` = 0. `grep -cP "AXIOM_EXTRA_ARGS_ARR\[@\]"` = 17. Local mantra path uses `"$HEADER"` without backslash-escaped quotes (line 2329). |
| `modules/subdomains.sh` | AXIOM_EXTRA_ARGS_ARR at 21 sites; WR-01 AXIOM_RESOLVERS_PATH quoting | ✓ VERIFIED | `grep -cP "AXIOM_EXTRA_ARGS_ARR\[@\]"` = 21. All AXIOM_RESOLVERS_PATH and AXIOM_RESOLVERS_TRUSTED_PATH references use `"${...}"` form (11 sites). |
| `reconftw.sh` | Global AXIOM_EXTRA_ARGS_ARR parse; early parse + post-config parse | ✓ VERIFIED | declare -a at line 125 (early) and line 529 (post-config). Both IFS-safe IFS-save/restore read -r -a blocks present. |
| `install.sh` | verify_sha256 gated in install_rust_uv(); pinned_tools via tools.lock; CR-03 WARN on no hash tool; WR-05 integrity warn | ✓ VERIFIED | verify_sha256 called at lines 168 and 193. pinned_tools assoc array at line 527. printf WARN in verify_sha256 else branch at line 98. msg_warn for integrity-unverified downloads at line 1344. |
| `tools.lock` | 5 required tools pinned with correct module paths and version tags | ✓ VERIFIED | File exists at repo root. `grep -cE '^[a-z][a-z_-]*=github\.com'` = 11 (5 required + 6 WR-04 additions). All 5 required (nuclei, httpx, ffuf, puredns, subfinder) match gotools module paths exactly. `bash -n install.sh` exits 0. |
| `lib/common.sh` (process_results) | WR-03 fallback path fixed | ✓ VERIFIED | cat and wc -l separated into two independent statements (lines 765-766). Comment documents deduplication limitation. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| modules/subdomains.sh axiom-scan sites | reconftw.sh AXIOM_EXTRA_ARGS_ARR | `"${AXIOM_EXTRA_ARGS_ARR[@]}"` expansion | ✓ WIRED | 21 sites migrated; legacy `AXIOM_EXTRA_ARGS` references: 0 |
| modules/web.sh axiom-scan sites | reconftw.sh AXIOM_EXTRA_ARGS_ARR | `"${AXIOM_EXTRA_ARGS_ARR[@]}"` expansion | ✓ WIRED | 17 sites migrated (15 call sites + 2 in webprobe_full axiom_cmd); legacy references: 0 |
| install.sh install_rust_uv() | verify_sha256() at :82-102 | env-var RUSTUP_INSTALLER_SHA256 / UV_INSTALLER_SHA256 | ✓ WIRED | Both blocks call `verify_sha256 "$_tmpfile" "$_expected"` with abort on mismatch |
| install.sh install_tools() | tools.lock at repo root | while-IFS-read into pinned_tools assoc array | ✓ WIRED | lockfile path: `${SCRIPTPATH:-$(pwd)}/tools.lock`; 11 entries parsed |
| modules/web.sh axiom-exec mantra | github.com/brosck/mantra@latest | axiom-exec remote go install command | ✓ WIRED (code) / ? UNVERIFIABLE (runtime) | Codebase fix confirmed; live Axiom fleet required for runtime verification |

### Data-Flow Trace (Level 4)

Not applicable — this phase produces no data-rendering components. All artifacts are security hardening patches to control flow, quoting, and installer logic.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| count_lines callable after lib/common.sh source | `bash -c 'source lib/common.sh; type count_lines count_lines_stdin >/dev/null && echo OK'` | `OK` | ✓ PASS |
| AXIOM_EXTRA_ARGS_ARR tokenises 4 tokens | `bash -c 'AXIOM_EXTRA_ARGS="--rate-limit 100 --threads 50" source reconftw.sh --source-only; echo "${#AXIOM_EXTRA_ARGS_ARR[@]}"'` | `4` | ✓ PASS |
| AXIOM_EXTRA_ARGS_ARR empty when unset | `bash -c 'unset AXIOM_EXTRA_ARGS; source reconftw.sh --source-only; echo "${#AXIOM_EXTRA_ARGS_ARR[@]}"'` | `0` | ✓ PASS |
| Single-token does not split | `bash -c 'AXIOM_EXTRA_ARGS="--flag" source reconftw.sh --source-only; echo "${#AXIOM_EXTRA_ARGS_ARR[@]}"'` | `1` | ✓ PASS |
| tools.lock parses to 11 entries | `bash -c 'declare -A p=(); while IFS="=" read -r k v; do k="${k#...}"; [[ -z "$k" || "$k" == \#* ]] && continue; p["$k"]="$v"; done < tools.lock; echo "${#p[@]}"'` | `11` | ✓ PASS |
| verify_sha256 warns when no hash tool | Confirmed at install.sh:98: `printf '[WARN] verify_sha256: no sha256sum or shasum found...' >&2` | Present | ✓ PASS |
| bash syntax on all modified files | `bash -n lib/common.sh modules/core.sh modules/web.sh modules/subdomains.sh reconftw.sh install.sh` | All exit 0 | ✓ PASS |
| shellcheck --severity=error on all modified files | `shellcheck -s bash --severity=error modules/core.sh modules/web.sh modules/subdomains.sh reconftw.sh install.sh lib/common.sh` | 0 findings | ✓ PASS |

### Probe Execution

No probes declared in PLAN frontmatter. No conventional `scripts/*/tests/probe-*.sh` files found for this phase.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SEC-01 | 02-01 | safe_count() no longer falls back to eval | ✓ SATISFIED | safe_count() deleted entirely from lib/common.sh; 0 eval calls in lib/ or modules/ |
| SEC-02 | 02-02 | sendToNotify() quotes every curl variable | ✓ SATISFIED | All 14 expansion sites quoted; shellcheck clean; slack_auth registered before curl |
| SEC-03 | 02-03 | AXIOM_EXTRA_ARGS consumed via bash array | ✓ SATISFIED | 36 sites migrated across subdomains.sh (21) and web.sh (15+); tokenisation verified |
| SEC-04 | 02-03 | verify_sha256 for bootstrappers + tools.lock | ✓ SATISFIED | SHA256 gates in install_rust_uv(); tools.lock with 11 pinned entries; mismatch aborts |
| FIX-01 | 02-02 | modules/web.sh:2340 mantra path lowercase | ✓ SATISFIED (code) | `grep -c 'Brosck' modules/web.sh` = 0; brosck/mantra@latest at line 2331 |

No orphaned requirements detected. All 5 Phase 2 requirements (SEC-01, SEC-02, SEC-03, SEC-04, FIX-01) are claimed by plans and have implementation evidence.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| install.sh | 164, 189 | `XXXXXX` in mktemp template | ℹ️ Info | False positive — this is the required mktemp randomness suffix, not a TBD marker |

No TBD, FIXME, or XXX markers found in any phase-modified file. No stubs or placeholder returns detected. No unresolved debt markers.

### Human Verification Required

#### 1. Axiom Remote Mantra Install (SC-5)

**Test:** On a system with a configured Axiom fleet, run:
```bash
# Trigger the mantra axiom-exec path
axiom-exec "go install github.com/brosck/mantra@latest" && echo "install OK"
# Then run a scan that exercises the mantra axiom-scan path
echo "https://example.com" > /tmp/test_js.txt
axiom-scan /tmp/test_js.txt -m mantra -o /tmp/test_secrets.txt
```
**Expected:** `axiom-exec` completes without a 404 or "module not found" error; the mantra binary is available on each fleet node; the axiom-scan run completes and produces a (possibly empty) output file at `/tmp/test_secrets.txt`.

**Why human:** The verifier cannot start or connect to an Axiom fleet. The codebase change (B→b in the module path string at modules/web.sh:2331) is fully verified by static analysis — the live execution outcome requires an actual fleet environment.

### Gaps Summary

No gaps blocking phase goal achievement. All four programmatically-verifiable success criteria are fully met:

- SC-1: eval injection vector eliminated
- SC-2: sendToNotify() fully-quoted, review fixes applied
- SC-3: AXIOM_EXTRA_ARGS_ARR correctly tokenises in all verified scenarios
- SC-4: SHA256 gates and tools.lock wired and functional

SC-5 requires live Axiom fleet testing. The code change is correct and consistent with the local install path.

---

_Verified: 2026-05-13T14:30:00Z_
_Verifier: Claude (gsd-verifier)_
