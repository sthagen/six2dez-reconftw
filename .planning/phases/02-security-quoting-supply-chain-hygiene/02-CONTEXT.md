# Phase 2: Security Quoting & Supply-Chain Hygiene - Context

**Gathered:** 2026-05-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Close five security/supply-chain audit gaps grouped into three plans:

- **02-01** — Remove the `eval` injection vector under `safe_count()` (SEC-01)
- **02-02** — Quote every variable in `sendToNotify()` curl calls + 1-char `mantra` axiom-exec path fix (SEC-02, FIX-01)
- **02-03** — Refactor `AXIOM_EXTRA_ARGS` to an explicit Bash array + `verify_sha256` on installer bootstrappers + `tools.lock` manifest for stability-critical Go tools (SEC-03, SEC-04)

In scope: `lib/common.sh` (safe_count delete), `modules/core.sh:1399-1414` (sendToNotify quoting), `modules/web.sh:2340` (mantra path), `modules/subdomains.sh` + `modules/web.sh` (38 AXIOM_EXTRA_ARGS call sites), `reconftw.sh` (global AXIOM_EXTRA_ARGS_ARR parse), `install.sh` (rustup/uv SHA256 + tools.lock manifest), and the associated bats test and doc updates triggered by `safe_count` removal.

Out of scope (other phases): per-tool thread caps and scope-check unification (Phase 3 / PERF-01, FIX-02); the `parallel_funcs`/axiom failover bats tests for the new array refactor (Phase 4 / TEST-01, TEST-03); `PARALLEL_MAX_JOBS` / `ALLOW_TRANSFER` / `RAISE_ULIMIT` config exposure and `MIN_DISK_SPACE_GB` 2-vs-5 reconciliation (Phase 5 / DOCS-01, DOCS-02). UX/UI output overhaul beyond what already shipped is a new capability for a future milestone.

</domain>

<decisions>
## Implementation Decisions

### `safe_count()` Removal (Plan 02-01, SEC-01)

- **D-01:** **Delete `safe_count()` entirely** from `lib/common.sh:748-764` (function definition + Usage comment block). Zero live callers in any `modules/*.sh` or `lib/*.sh` file confirmed via `grep -rn 'safe_count' . --include='*.sh'` (only the definition itself plus 3 bats tests show up). `count_lines()` (file path, `lib/common.sh:125`) and `count_lines_stdin()` (`lib/common.sh:136`) already cover every legitimate use case. This is a fuller cleanup than the literal success criterion ("else branch is gone") but matches CLAUDE.md's "if certain something is unused, delete it completely" policy and removes the latent injection-vector surface entirely rather than leaving a zero-caller function as a future trap.
- **D-02:** **Delete the 3 bats tests that exercise the eval branch** at `tests/unit/test_common.bats:254-267` (2 tests) and `tests/integration/test_full_flow.bats:245-256` (1 test). These tests call `safe_count "cat test.txt"` (pipeline-string form), which exercises the very eval branch we're removing — they cannot be ported as-is. Rewriting them as `count_lines` tests adds no new coverage because `count_lines` is already tested elsewhere in `test_common.bats`. Plain deletion is the correct outcome.
- **D-03:** **Update 5 doc/intel files that mention `safe_count`** to reference `count_lines` instead, or drop the reference if no replacement is needed. Files: `CHANGELOG.md:203`, `CLAUDE.md:283`, `.planning/codebase/CONVENTIONS.md:162-164`, `.planning/codebase/STRUCTURE.md:18`, `.planning/codebase/ARCHITECTURE.md:63`. The `.planning/PROJECT.md:46` Active bullet for SEC-01 will be moved to Validated by the transition step, not edited as part of the phase work.

### `sendToNotify()` Quoting + `mantra` Path Fix (Plan 02-02, SEC-02 + FIX-01)

- **D-04:** **Quote every variable expansion in the full `sendToNotify()` body** (`modules/core.sh:~1390-1416`), not just the three names listed in the success criterion. Concretely: `"$discord_url"`, `"${slack_channel}"`, `"${1}"` (named in criterion); `"@${1}"` in every `-F` curl-form expression; `"-F channels=${slack_channel}"`, `"-F chat_id=${telegram_chat_id}"`, `"-F document=@${1}"`, `"-F file1=@${1}"`, `"-F file=@${1}"`; the four bare `$NOTIFY_CONFIG` expansions in the surrounding `grep -q ... $NOTIFY_CONFIG` and `sed -n ... ${NOTIFY_CONFIG}` lines; and the URL interpolation `https://api.telegram.org/bot${telegram_key}/sendDocument` (inside an existing double-quoted curl arg, so already safe — but the planner should double-check). Full-function pass means a future contributor who copy-pastes any line in this block does not re-introduce the same class of bug from an unquoted neighbour.
- **D-05:** **Shellcheck-clean policy**: after the quoting pass, `shellcheck modules/core.sh` should produce no new SC2086 / SC2068 / SC2027 findings inside `:1390-1420`. If a flagged expansion is genuinely intentional (none expected in this block), use an inline `# shellcheck disable=SCXXXX` with a one-line explanation comment on the line ABOVE. Project convention (`.planning/codebase/CONVENTIONS.md:277`) is inline suppressions only, never file-level.
- **D-06:** **`mantra` axiom-exec path fix (FIX-01)**: 1-character change at `modules/web.sh:2340` — `github.com/Brosck/mantra@latest` → `github.com/brosck/mantra@latest` to match the local install path corrected in commit `f64383c2`. GitHub module path matching is case-sensitive; the current value 404s on the remote axiom node. Bundled in Plan 02-02 because it's a single-line edit in adjacent code-touch territory (notification + remote install). No commit boundary games — single commit per logical change is fine.

### `AXIOM_EXTRA_ARGS_ARR` Array Refactor (Plan 02-03, SEC-03)

- **D-07:** **Parse once globally in `reconftw.sh`** immediately after `secrets.cfg` is sourced (right around line 503, before the `CLI_*` re-apply block). The parse is `read -r -a AXIOM_EXTRA_ARGS_ARR <<< "${AXIOM_EXTRA_ARGS:-}"`. Single source of truth, parse cost paid exactly once per invocation, intentionally exposed as `AXIOM_EXTRA_ARGS_ARR` (matches the success criterion name verbatim) so users who set `AXIOM_EXTRA_ARGS="--rate-limit 100"` in `reconftw.cfg` get the correct multi-token expansion at every site. Backwards-compatible with existing string-form config values. If the var is unset/empty, the array is empty and `"${AXIOM_EXTRA_ARGS_ARR[@]}"` expands to nothing (bash 4.3+ behaviour without `set -u`, which reconftw never enables — confirmed by `.planning/codebase/CONVENTIONS.md:5-13`).
- **D-08:** **Migrate all 38 call sites to `"${AXIOM_EXTRA_ARGS_ARR[@]}"`** uniformly. Breakdown for the planner's grep audit:
  - `modules/subdomains.sh`: 21 sites (lines 672, 737, 745, 768, 962, 1100, 1107, 1233, 1366, 1570, 1587, 1666, 1742, 1825, 1838, 1905, 1926, 1944, 1990, 2068, plus any duplicates revealed by `grep -nE 'AXIOM_EXTRA_ARGS' modules/subdomains.sh`)
  - `modules/web.sh`: 17 sites (lines 340, 431, 506, 786, 1008, 1152, 1537, 1988, 1990, 2257, 2280, 2341, 2479, 2925, 2927, plus the local-pattern block at 144-200 to be removed per D-09).

  Of the 38 sites today, ~25 use bare `$AXIOM_EXTRA_ARGS` (word-split, works but silent intent) and ~13 use `"$AXIOM_EXTRA_ARGS"` (wrong — single-token; actively breaks `--rate-limit 100`-style values). Both patterns become `"${AXIOM_EXTRA_ARGS_ARR[@]}"`.
- **D-09:** **Remove the local `axiom_extra_args=()` pattern from `webprobe_full`** at `modules/web.sh:144-155` (the `local -a axiom_extra_args=()` declaration + IFS-juggling `read -r -a` block) and replace `"${axiom_extra_args[@]}"` at line 200 with `"${AXIOM_EXTRA_ARGS_ARR[@]}"`. One uniform pattern across the codebase; the local block is redundant once the global parse runs at startup.
- **D-10:** **Verification sweep after migration**: (a) `grep -nE 'AXIOM_EXTRA_ARGS([^_]|$)' modules/{subdomains,web}.sh` must return zero hits except for the new `AXIOM_EXTRA_ARGS_ARR` references and any doc comments. (b) A one-shot tokenisation smoke test: in a sandboxed shell, set `AXIOM_EXTRA_ARGS="--rate-limit 100 --threads 50"`, source `reconftw.sh --source-only`, and inspect `"${AXIOM_EXTRA_ARGS_ARR[@]}"` — assert it expands to 4 tokens, not 1. (c) `shellcheck modules/subdomains.sh modules/web.sh` returns no new findings. The proper bats coverage lives in Phase 4 (TEST-03 axiom failover) per Phase 1's deferred-section precedent; do NOT add a new bats test in this phase.

### Installer SHA256 + `tools.lock` (Plan 02-03, SEC-04)

User did not select this gray area for discussion — pattern is locked from the existing precedent at `install.sh:1251-1289`.

- **D-11:** **`verify_sha256()` for rustup and uv bootstrappers**: extend `install_rust_uv()` at `install.sh:159-188` to follow the existing env-var-driven pinning pattern. Add `RUSTUP_INSTALLER_SHA256` and `UV_INSTALLER_SHA256` env vars (default unset). When set, the script must verify the downloaded tempfile against the pinned hash via `verify_sha256` (already defined at `install.sh:85-102`) and abort with a clear error message before executing it. When unset, behaviour is unchanged — backwards-compatible. Hard-pinning would break on every upstream release (rustup ~weekly, uv ~monthly); env-var-driven means CI/security-conscious users can pin without forcing the maintainer into an upstream-release-tracking treadmill. Document the env vars in the install.sh comment block at `:1228-1239` alongside the existing `GETJSWORDS_SHA256` example.
- **D-12:** **`tools.lock` manifest** pinning the 5 stability-critical Go tools (`nuclei`, `httpx`, `ffuf`, `puredns`, `subfinder`) per the success criterion. Format: a plain-text `tools.lock` file in the repo root, one entry per line as `<binary>=<module>@<version>`, e.g. `nuclei=github.com/projectdiscovery/nuclei/v3/cmd/nuclei@v3.3.4`. The Go install loop at `install.sh:501-518` consults `tools.lock` first; if the entry exists, `go install -v "$module_at_version"` runs with the pinned version. If absent, fall through to the existing `@latest` behaviour (so the other 50+ tools are unaffected). Plain text means easy to grep, easy for `dependabot`-style automation to update, and no Bash associative-array duplication of the existing `gotools` map. Versions chosen by the planner via `go install ...@latest` once, recording the resolved tag.
- **D-13:** **Scope cap**: do NOT pin every Go tool. Commit `71653984` ("remove pinned versions") explicitly removed wholesale pinning because the maintenance burden was disproportionate to the value for tools that change rarely (e.g., `anew`, `unfurl`, `qsreplace`). Pinning only the 5 named tools matches the success criterion and keeps the maintenance surface small.

### Claude's Discretion

- The exact ordering of the global `AXIOM_EXTRA_ARGS_ARR` parse line vs the `CLI_*` re-apply block in `reconftw.sh` is a planner-level choice — anywhere between `secrets.cfg` sourcing (~line 503) and the dispatch case (~line 590) works, as long as it's BEFORE any module function runs. Plan 02-03's preferred placement is "immediately after secrets.cfg source" because that keeps array-parse state co-located with the var's canonical setter site.
- The `tools.lock` file format detail (e.g., comment-line syntax `#`, blank-line tolerance, optional trailing comments) is up to the planner. Whatever format is chosen, it must round-trip cleanly through `awk`/`sed` parsing in `install.sh` and survive contributors editing it by hand.
- Whether the doc updates in D-03 are bundled in the same commit as the `safe_count` delete or split into a follow-up commit is a planner-level call. Single-commit-per-logical-change is the established pattern.
- Whether shellcheck is run as a pre-commit hook (already configured in `.pre-commit-config.yaml` per `.planning/codebase/CONVENTIONS.md`) or as an explicit step in the executor's verification is the planner's call. The existing pre-commit gate is the canonical enforcer.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §"Phase 2: Security Quoting & Supply-Chain Hygiene" — phase goal, 5 success criteria, 3 plans
- `.planning/REQUIREMENTS.md` §"Security Hardening" (SEC-01, SEC-02, SEC-03, SEC-04) and §"Bug Fixes" (FIX-01) — the five v1 requirements this phase delivers

### Codebase intel (driving the changes)
- `.planning/codebase/CONCERNS.md` §"eval in safe_count() Legacy Fallback" — drives SEC-01 / Plan 02-01
- `.planning/codebase/CONCERNS.md` §"sendToNotify Unquoted Variables in curl Calls" — drives SEC-02 / Plan 02-02
- `.planning/codebase/CONCERNS.md` §"Unquoted AXIOM_EXTRA_ARGS — Inconsistent Quoting" — drives SEC-03 / Plan 02-03
- `.planning/codebase/CONCERNS.md` §"Installer Downloads and Executes Unverified Scripts" and §"All Go Tools Install @latest Without Version Pinning" — drives SEC-04 / Plan 02-03
- `.planning/codebase/CONCERNS.md` §"Axiom Mantra Module Path Stale in Axiom Branch" — drives FIX-01 / Plan 02-02

### Architectural and conventions (must align with)
- `.planning/codebase/CONVENTIONS.md` §"Source Guard Pattern" and §"Variable Naming" — confirms `UPPER_SNAKE_CASE` globals; `AXIOM_EXTRA_ARGS_ARR` matches the existing convention
- `.planning/codebase/CONVENTIONS.md` §"Comments" — inline `# shellcheck disable=` policy for the sendToNotify pass
- `.planning/codebase/ARCHITECTURE.md` §"Component Responsibilities" — `lib/common.sh` shared utilities listing (to be updated when `safe_count` is removed)
- `.planning/codebase/STACK.md` — supply-chain context for the 50+ Go tools and the rustup/uv bootstrap dependency

### Existing reusable code
- `install.sh:82-102` (`verify_sha256()`) — already-defined SHA-256 helper to wire into `install_rust_uv()`
- `install.sh:1251-1289` (`download_sha256` map + verify loop) — the env-var-driven pinning precedent for D-11
- `lib/common.sh:122-140` (`count_lines`, `count_lines_stdin`) — canonical replacement helpers for `safe_count` per D-01
- `modules/web.sh:144-200` (existing `axiom_extra_args` local pattern in `webprobe_full`) — the pattern to remove per D-09 and replace with the global D-07

### Project constraints
- `.planning/PROJECT.md` §Constraints — "external tools: 70+ runtime dependencies … no version pinning, a known supply-chain risk" — the constraint SEC-04 partially addresses
- `CLAUDE.md` §Conventions — `function name()` declaration form, `_snake_case` private helpers, global UPPER_SNAKE_CASE config vars

### Prior-phase precedent
- `.planning/phases/01-resilient-resume-timeout-safety/01-CONTEXT.md` — tests in Phase 4 (not the implementation phase) precedent, shellcheck/JSONL conventions, opt-in default knob pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`count_lines()` at `lib/common.sh:125`** — canonical file-line-count helper, already used by 11 call sites in `modules/core.sh` and `modules/modes.sh`. Replaces every legitimate `safe_count` use case (D-01).
- **`count_lines_stdin()` at `lib/common.sh:136`** — covers the pipeline-input case that the `safe_count` else branch used to handle, but safely (no `eval`).
- **`verify_sha256()` at `install.sh:85-102`** — already returns 0 on match, 1 on mismatch, and 0 on missing hash tool (intentional skip-don't-block semantics). Compatible with both GNU `sha256sum` and macOS `shasum -a 256`. D-11 wires it into `install_rust_uv()` with new env vars.
- **`download_sha256` associative-array pattern at `install.sh:1251-1289`** — the env-var-driven hash override precedent (`GETJSWORDS_SHA256`, `AXIOM_CONFIG_SHA256`). D-11 follows the same pattern for rustup/uv.
- **`gotools` associative-array at `install.sh:293-355`** — the existing Go-tool install table. D-12 reads `tools.lock` first, falls back to this table's `@latest` install for unpinned entries.
- **`bblue/bgreen/byellow/reset` colour vars + `_print_msg`/`_print_error` helpers** — already wired through `lib/ui.sh`. The smoke-test output in D-10 uses these so verbose mode still shows the verification result; no UI work needed.

### Established Patterns

- **`UPPER_SNAKE_CASE` globals** (CONVENTIONS.md §"Variable Naming") — `AXIOM_EXTRA_ARGS_ARR` slots in alongside `AXIOM`, `AXIOM_EXTRA_ARGS`, `AXIOM_FLEET_COUNT`. No special-case naming.
- **Env-var-driven optional verification** — existing pinning is opt-in via env var, defaults to "skip don't block". D-11 follows this. Hard-pinning breaks the install loop on every upstream release without giving users a way to override.
- **`local -a array_name=()` + `read -r -a` from a heredoc/here-string** is the canonical Bash array-from-string pattern (CONVENTIONS.md does not call it out explicitly, but `web.sh:144-153` and `lib/parallel.sh` use it). The global D-07 parse uses the same idiom.
- **Inline `# shellcheck disable=` with explanation** (CONVENTIONS.md §"Comments") — never file-level. D-05 honors this for any intentional word-split that survives the sendToNotify pass (none expected).
- **Single-commit-per-logical-change** (PROJECT.md §"Recent trajectory" + Phase 1 execution log) — D-06 bundles the 1-char mantra fix with the sendToNotify quoting because they live in the same plan (02-02). D-03 doc updates can be one commit or split per planner judgment.

### Integration Points

- **`reconftw.sh:~500-578`** — config sourcing block. D-07 inserts the global `AXIOM_EXTRA_ARGS_ARR` parse after `secrets.cfg` source, BEFORE the `CLI_*` re-apply block, so the array is initialised before any module function (which all run after the `case $opt_mode` dispatch downstream).
- **`install.sh:159-188` (`install_rust_uv`)** — D-11 wires `verify_sha256` calls into the rustup and uv download blocks. The existing tempfile pattern (`mktemp` → `curl -o` → `sh "$_tmpfile"`) stays; verification is inserted between download and execution.
- **`install.sh:489-525` (`install_tools` loop)** — D-12 reads `tools.lock` once before the loop, then per iteration checks if the current `gotool` is in the pinned map. The existing `go install -v "${gotools[$gotool]}@latest"` becomes `go install -v "$pinned_or_latest"`.
- **Pre-commit hooks** (`.pre-commit-config.yaml`) — shellcheck + shfmt already run on every commit. The sendToNotify and AXIOM refactor passes go through this gate automatically; no new hook config needed.
- **No axiom-module impact** — the array refactor is fully contained in `reconftw.sh` (parse) + `modules/subdomains.sh` + `modules/web.sh` (consumers). `modules/axiom.sh` itself does not read `AXIOM_EXTRA_ARGS` directly; it provides `axiom-scan` infrastructure that consumers pass args to.

</code_context>

<specifics>
## Specific Ideas

- **Deletion over deprecation**: the user chose to fully delete `safe_count()`, bats tests, and doc references rather than leave a deprecated stub. Planner should NOT propose a back-compat wrapper or a deprecation warning — there are zero callers and zero plugins depending on it. Clean delete is the agreed outcome (D-01/D-02/D-03).
- **Full-function quoting over minimum-criterion**: the user explicitly chose to quote every expansion in `sendToNotify()`, not only the names listed in the success criterion. Planner should NOT scope the diff down to the named vars to keep the patch small — the agreed standard is a shellcheck-clean function body (D-04/D-05).
- **One global `AXIOM_EXTRA_ARGS_ARR` over per-function locals**: the user explicitly rejected the per-function local-array pattern (including the existing one at `webprobe_full`). Planner should NOT preserve `axiom_extra_args=()` in `webprobe_full` as an exception — removing it is the explicit agreement (D-09). All 38 sites use the global.
- **Env-var-driven SHA pinning over hard-pin**: although the user did not actively discuss SEC-04, the in-context default chosen here (D-11) matches the existing `GETJSWORDS_SHA256` / `AXIOM_CONFIG_SHA256` precedent. Planner should NOT switch to hard-pinned hashes without surfacing it as a question first.
- **5-tool `tools.lock` over wholesale re-pinning**: D-13 explicitly caps SEC-04 scope at the 5 tools named in the success criterion. Planner should NOT re-introduce pinning for every Go tool — commit `71653984` removed it for a reason.

</specifics>

<deferred>
## Deferred Ideas

- **UX/UI output overhaul** — user expressed interest in further UX/UI improvements to tool output. The 2026-03 audit already shipped the current UI overhaul (dot-fill status format, single-line summaries, parallel group rebalancing, OUTPUT_VERBOSITY gating). Any further UI work is a new capability that belongs in its own milestone, not in Phase 2's security/supply-chain remediation. Carry forward to roadmap backlog for consideration after the v1.0 audit-hardening milestone closes.
- **Pin every Go tool, not just 5** — explicitly rejected per D-13 / commit `71653984` history. Revisit if a future stability incident on a non-pinned tool justifies the maintenance burden.
- **Bats coverage for the new AXIOM_EXTRA_ARGS_ARR parse and the rustup/uv SHA path** — Phase 4 (TEST-03 axiom failover) is the canonical place for axiom-touching test work. Phase 2 ships behaviour, Phase 4 ships coverage. Planner should NOT add bats tests in this phase even though the surface is small.
- **Documenting `AXIOM_POST_START` as executable in `reconftw.cfg`** (separate concern surfaced by CONCERNS.md §"bash -lc with Config-Controlled Strings") — not in v1 requirements. Could be folded into Phase 5 (DOCS-01) doc-surfacing work.
- **`GH_TOKEN` ps-aux exposure mitigation** (CONCERNS.md §"GitHub Token File Passed Directly on Command Line") — listed in REQUIREMENTS.md v2 backlog as ARCH-02. Out of scope for v1.
- **Hard-pin rustup/uv hashes (vs env-var-driven)** — the planner-locked D-11 chose env-var-driven. If a security incident or CI policy later requires hard-pinning, revisit by replacing D-11; the underlying `verify_sha256` helper supports both modes.

</deferred>

---

*Phase: 2-Security Quoting & Supply-Chain Hygiene*
*Context gathered: 2026-05-13*
