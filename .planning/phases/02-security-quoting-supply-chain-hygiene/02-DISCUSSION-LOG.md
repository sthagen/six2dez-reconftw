# Phase 2: Security Quoting & Supply-Chain Hygiene - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-13
**Phase:** 02-security-quoting-supply-chain-hygiene
**Areas discussed:** safe_count() removal scope, sendToNotify() quoting depth, AXIOM_EXTRA_ARGS_ARR refactor pattern

---

## Initial gray-area selection

| Option | Description | Selected |
|--------|-------------|----------|
| safe_count() removal scope | Zero live callers in the codebase. Options: remove only the else+TODO branch (literal success criterion), OR delete safe_count() entirely as dead code (count_lines/count_lines_stdin already cover its use cases). Affects whether we leave a stub or fully clean up. | ✓ |
| sendToNotify() quoting depth | Success criterion names $discord_url, ${slack_channel}, ${1}. But the full block at modules/core.sh:1399-1414 has additional unquoted Telegram vars (${telegram_chat_id}, ${telegram_key}, the URL interpolation). Audit the whole function or only the named variables? | ✓ |
| AXIOM_EXTRA_ARGS_ARR refactor pattern | Parse once globally (reconftw.sh post-config) vs per-function local arrays like webprobe_full at web.sh:144-200. Also: how to handle the 13 sites that currently use the WRONG "$AXIOM_EXTRA_ARGS" single-token quoting vs 25 sites with bare $AXIOM_EXTRA_ARGS word-splitting. | ✓ |
| Installer SHA256 + tools.lock strategy | For rustup/uv: hard-pin hashes (breaks weekly on upstream releases) vs env-var-driven (matches existing GETJSWORDS_SHA256 pattern but inactive by default) vs hybrid. For tools.lock: pin only the 5 named tools (nuclei/httpx/ffuf/puredns/subfinder) vs pin all ~50; bash assoc array in install.sh vs separate manifest file; version tag (@v3.3.4) vs commit SHA. | |

**User's choice:** Selected three areas (safe_count removal, sendToNotify quoting, AXIOM_EXTRA_ARGS_ARR refactor); skipped SHA256/tools.lock area; raised UX/UI output improvement as a fourth interest area (Spanish: "tambien me gustaria explorar la posibilidad de mejorar el output de la herramienta, que fuese mas ux/ui friendly si es que eso es posible").

**Notes:** UX/UI improvement was redirected as scope creep — Phase 2 is security/supply-chain hardening, not UI work. The 2026-03 audit already shipped the current UI overhaul. Logged as deferred idea for the roadmap backlog. SEC-04 (SHA256 + tools.lock) was not selected; CONTEXT.md locks in the env-var-driven default that matches the existing precedent.

---

## safe_count() removal scope

### Question 1: How thoroughly should we clean up safe_count()?

| Option | Description | Selected |
|--------|-------------|----------|
| Delete safe_count() entirely (Recommended) | Remove the whole function + Usage comment block at lib/common.sh:748-764. Zero callers in codebase, count_lines/count_lines_stdin already cover the use cases. Cleanest fix; matches CLAUDE.md 'if unused, delete it completely' policy. Success criterion phrasing — 'eval branch is gone' — is still satisfied. | ✓ |
| Remove only the else-branch + TODO | Literal interpretation of success criterion: keep safe_count() with the file-path branch, drop lines 757-760 (else + eval + TODO comment). Leaves a function with zero callers as a future trap (new code could re-introduce eval-prone patterns). | |
| Replace with deprecation stub | Keep safe_count() as a thin wrapper that calls count_lines() for backwards compat with any hypothetical third-party consumer. Probably overkill since this is a bash project, not a library, and no plugin.sh files reference safe_count. | |

**User's choice:** Delete safe_count() entirely.
**Notes:** Confirmed via `grep -rn 'safe_count' . --include='*.sh'` that no live callers exist in any modules/*.sh or lib/*.sh.

### Question 2: How should we handle the 3 bats tests and 5 doc references to safe_count?

| Option | Description | Selected |
|--------|-------------|----------|
| Delete tests + update docs (Recommended) | Remove the 3 bats tests for safe_count (they test legacy eval behavior we're killing). Update CHANGELOG/CLAUDE.md/CONVENTIONS.md/STRUCTURE.md/ARCHITECTURE.md to replace 'safe_count' references with 'count_lines'. Complete removal with no dangling references. | ✓ |
| Delete tests, leave docs for codebase remap | Drop the bats tests but skip the doc updates — docs will get refreshed by a future /gsd-map-codebase or /gsd-docs-update pass. Smaller diff for this phase; downside is docs will be stale until that runs. | |
| Convert tests to count_lines tests | Rather than delete tests outright, rewrite them to exercise count_lines() since that's now the canonical helper. Net coverage stays roughly the same. | |

**User's choice:** Delete tests + update docs.
**Notes:** The 3 tests at tests/unit/test_common.bats:254-267 and tests/integration/test_full_flow.bats:245-256 specifically exercise the eval branch (pipeline-string form), so they can't be ported as-is — only deletion or rewrite. Existing count_lines coverage elsewhere makes rewrite redundant.

---

## sendToNotify() quoting depth

### Question 1: How wide should the quoting fix go in sendToNotify()?

| Option | Description | Selected |
|--------|-------------|----------|
| Full function quoting + shellcheck-clean (Recommended) | Quote every expansion in the whole sendToNotify() function (groups 1, 2, 3). Run shellcheck against modules/core.sh and address any other quoting findings opened up by the changes. This matches success criterion #2's 'shellcheck reports no new findings against modules/core.sh:1399-1414' literally. | ✓ |
| Quote curl arg surface only (1+2) | Fix every variable that ends up as a curl argument (the file=@${1}, channels=${slack_channel}, chat_id, etc) but leave the NOTIFY_CONFIG sed/grep scaffolding alone. Smaller diff, addresses the actual injection vectors (curl args), doesn't touch the config-read plumbing. | |
| Minimum to pass criterion (1 only) | Quote ONLY $discord_url, ${slack_channel}, ${1} as literally named. Smallest patch. Downside: surrounding unquoted patterns survive, and a future contributor copy-pasting the still-unquoted -F form lines re-introduces the same class of bug. | |

**User's choice:** Full function quoting + shellcheck-clean.
**Notes:** Includes NOTIFY_CONFIG scaffolding ($NOTIFY_CONFIG bare in grep/sed lines), -F curl-form args (@${1}, channels=, chat_id=, document=, file=), and the named variables ($discord_url, ${slack_channel}, ${1}).

### Question 2: How should shellcheck noise be handled inside sendToNotify() during the quoting pass?

| Option | Description | Selected |
|--------|-------------|----------|
| Quote first, suppress only what's truly intentional (Recommended) | Quote every flagged expansion. If shellcheck flags something we deliberately leave word-split (none expected in sendToNotify, but e.g. inside transfer() if it gets touched), add an inline `# shellcheck disable=SC2086` with a one-line reason comment. Keeps the project's pre-commit shellcheck gate green without blanket suppressions. | ✓ |
| Quote-only, no suppressions added | Just quote everything. If shellcheck still complains anywhere in modules/core.sh:1399-1414, treat it as a real bug and fix it. No new disable comments. | |
| Quote sendToNotify only, file-level suppression for the rest | Keep changes inside sendToNotify(). If shellcheck flags other parts of modules/core.sh as collateral, suppress at file scope rather than inline (project convention frowns on this per CONVENTIONS.md). | |

**User's choice:** Quote first, suppress only what's truly intentional.
**Notes:** Inline disables only, never file-level, per CONVENTIONS.md. One-line explanation comment required on any disable line.

---

## AXIOM_EXTRA_ARGS_ARR refactor pattern

### Question 1: Where should AXIOM_EXTRA_ARGS be parsed into an array?

| Option | Description | Selected |
|--------|-------------|----------|
| Parse once globally in reconftw.sh after config sourcing (Recommended) | Add `read -r -a AXIOM_EXTRA_ARGS_ARR <<< "${AXIOM_EXTRA_ARGS:-}"` in reconftw.sh:~503 right after secrets.cfg is sourced. All 38 call sites then use `"${AXIOM_EXTRA_ARGS_ARR[@]}"`. Single source of truth, parse cost paid once, matches the success criterion name literally. Backwards-compatible with existing `AXIOM_EXTRA_ARGS="..."` config values. | ✓ |
| Per-function local arrays (webprobe_full pattern) | Replicate the local `axiom_extra_args=()` + IFS read pattern at every call site (or in helper functions inside each module). Closer to existing precedent at web.sh:144-153 but multiplies the parse logic 38× and risks each function diverging on edge cases. | |
| Hybrid: global default + optional local override | Provide global `AXIOM_EXTRA_ARGS_ARR` but allow per-function local overrides for sites that need tool-specific args. Most flexible but no current call site needs this — YAGNI risk. | |

**User's choice:** Parse once globally in reconftw.sh after config sourcing.
**Notes:** Position is post-secrets.cfg and pre-CLI-override-reapply, around line 503.

### Question 2: How should the existing webprobe_full local-array pattern be handled during migration?

| Option | Description | Selected |
|--------|-------------|----------|
| Remove local pattern, use global array (Recommended) | Delete the local `axiom_extra_args=()` + IFS read at modules/web.sh:144-155. Replace `"${axiom_extra_args[@]}"` at line 200 with `"${AXIOM_EXTRA_ARGS_ARR[@]}"`. One uniform pattern across all 38 sites. The local block is no longer needed once parsing moves global. | ✓ |
| Keep webprobe_full local, migrate the other 37 | Leave webprobe_full as-is (it works correctly already). Only touch the 37 broken/inconsistent sites. Smaller diff but leaves codebase with two patterns side-by-side, which is the current state's problem. | |
| Convert all to use a helper function `axiom_args` that expands the array | Define `axiom_args() { printf '%s\n' "${AXIOM_EXTRA_ARGS_ARR[@]}"; }` or similar, and use command substitution at call sites. Hides the array detail but adds an indirection layer for no real gain. | |

**User's choice:** Remove local pattern, use global array.

### Question 3: How should the migration sweep verify correctness across all 38 call sites?

| Option | Description | Selected |
|--------|-------------|----------|
| Tokenisation smoke test + shellcheck (Recommended) | After the sweep, run a smoke test: set `AXIOM_EXTRA_ARGS="--rate-limit 100 --threads 50"` and dry-run a single axiom-scan-bearing function (e.g., sub_passive). Assert the expanded argv has 4 tokens, not 1. Plus shellcheck the two modules. Phase 4 will add the proper bats test (TEST-03 covers axiom). | ✓ |
| Grep-based regex audit only | Post-sweep, `grep -nE 'AXIOM_EXTRA_ARGS(?!_ARR)' modules/{subdomains,web}.sh` should return zero hits. Fast but only verifies the pattern — doesn't prove tokenisation actually works at runtime. | |
| Full unit test in this phase | Write a bats test in tests/unit/test_axiom_args.bats that asserts both empty and multi-token cases. Out of phase scope per Phase 1's deferred section (tests live in Phase 4), but tempting since the surface is small. | |

**User's choice:** Tokenisation smoke test + shellcheck.
**Notes:** Combines a runtime tokenisation check with grep-based pattern verification. Proper bats coverage deferred to Phase 4 (TEST-03 axiom failover).

---

## Wrap-up

### Question: Where do we go from here?

| Option | Description | Selected |
|--------|-------------|----------|
| I'm ready for context (Recommended) | Lock in the decisions captured above and write CONTEXT.md. SEC-04 lands with env-var-driven SHA256 (RUSTUP_INSTALLER_SHA256, UV_INSTALLER_SHA256) + tools.lock as a separate manifest file pinning the 5 critical Go tools (nuclei/httpx/ffuf/puredns/subfinder) using @version tags. | ✓ |
| Discuss SEC-04 / tools.lock strategy | Open the installer SHA256 + tools.lock area we skipped — hard-pin vs env-var hashes, manifest format, version vs commit SHA pinning, 5 tools vs all 50. | |
| Explore another gray area | There may be additional ambiguity I haven't surfaced (e.g., commit/PR granularity across the 3 plans, plan boundary tweaks, how to handle the doc-refresh burden for CLAUDE.md/CONVENTIONS.md). | |

**User's choice:** I'm ready for context.

---

## Claude's Discretion

- Exact placement of the global `AXIOM_EXTRA_ARGS_ARR` parse line in `reconftw.sh` (anywhere between secrets.cfg source and `case $opt_mode` dispatch).
- `tools.lock` file format details (comment syntax, blank-line tolerance, optional trailing comments).
- Whether D-03 doc updates land in the same commit as the `safe_count` delete or split into a follow-up commit.
- Whether shellcheck verification runs via the pre-commit hook (already configured) or as an explicit executor step.
- SEC-04 / tools.lock strategy detail: user did not actively select this area, so CONTEXT.md locks in env-var-driven SHA pinning and a 5-tool plain-text `tools.lock` matching the existing `GETJSWORDS_SHA256` / `AXIOM_CONFIG_SHA256` precedent.

## Deferred Ideas

- **UX/UI output improvement** — raised by user but redirected as scope creep (Phase 2 is security/supply-chain, not UI). 2026-03 audit already shipped the current UI overhaul. Note for the roadmap backlog post-v1.0.
- **Pin every Go tool, not just 5** — explicitly excluded per commit `71653984` history; revisit only if a future stability incident justifies maintenance burden.
- **Bats tests for the new array refactor / SHA path** — coverage belongs in Phase 4 (TEST-03 axiom failover).
- **`AXIOM_POST_START` documentation as executable** — separate concern, fold into Phase 5 (DOCS-01) if desired.
- **`GH_TOKEN` ps-aux exposure** — REQUIREMENTS.md v2 backlog (ARCH-02), out of scope for v1.
- **Hard-pin rustup/uv hashes** — revisitable later by replacing D-11; underlying `verify_sha256` supports both modes.
