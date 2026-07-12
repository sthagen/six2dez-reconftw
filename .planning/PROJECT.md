# reconFTW

## What This Is

reconFTW is a comprehensive bash-based reconnaissance automation framework used by bug bounty hunters, penetration testers, and security researchers. It orchestrates 70+ external security tools (Go, Python, Rust) across subdomain enumeration, web probing, OSINT, and vulnerability scanning, producing structured per-target output trees with optional Axiom distributed execution, AI reporting, monitor/incremental mode, and Slack/Telegram/Discord notifications.

## Core Value

Run one command, get a complete recon picture of a target — passive, active, and vulnerability layers — with resumable checkpoints, structured output, and zero-touch tool orchestration.

## Requirements

### Validated

<!-- Shipped capabilities verified in the existing codebase. -->

- ✓ **Multi-mode entry** — `recon`, `passive`, `subs`, `web`, `osint`, `vulns`, `all`, `zen`, `monitor`, `deep` modes via getopt CLI (`reconftw.sh`)
- ✓ **Subdomain enumeration** — Passive sources, brute force, permutations, takeover detection, zone transfer, scope filtering (`modules/subdomains.sh`)
- ✓ **Web analysis pipeline** — Probing, screenshots, fuzzing, JS analysis, nuclei templates, WAF detection, source-map extraction (`modules/web.sh`)
- ✓ **Vulnerability scanning** — XSS (dalfox), SQLi (sqlmap/ghauri), SSRF, LFI, SSTI, CRLF, smuggling, nuclei DAST (`modules/vulns.sh`)
- ✓ **OSINT collection** — Domain info, emails, GitHub leaks, GitHub Actions audit, cloud bucket enumeration, dorking (`modules/osint.sh`)
- ✓ **Axiom distributed mode** — Fleet provisioning, transparent dispatch via `axiom-scan`, axiom→local failover wrapper (`modules/axiom.sh`)
- ✓ **Parallel execution** — `parallel_funcs` job manager with throttling, heartbeat, configurable log modes (`lib/parallel.sh`)
- ✓ **Checkpoint resumability** — Per-function `.called_fn/.funcname` sentinels skip completed work on resume
- ✓ **Output verbosity controls** — `OUTPUT_VERBOSITY` 0/1/2, `--quiet`/`--verbose`, `PARALLEL_LOG_MODE` summary|tail|full
- ✓ **Structured reporting** — JSON/HTML/CSV reports, AI report (opt-in), Faraday export, hotlist risk-scoring, incremental diff
- ✓ **Notifications** — `notify` integration for Slack/Telegram/Discord with secret redaction
- ✓ **Input safety** — `lib/validation.sh` sanitizers reject shell metacharacters in all user-supplied domains/IPs/list entries
- ✓ **Config layering** — `reconftw.cfg` defaults + `secrets.cfg` overlay + `$CUSTOM_CONFIG` + CLI overrides re-applied post-config
- ✓ **Cross-platform** — Linux (Debian/Ubuntu/RHEL/Arch) and macOS (auto re-exec under Homebrew Bash 4+)
- ✓ **Docker support** — `Docker/Dockerfile` Ubuntu 24.04 base with full toolchain
- ✓ **Test suite** — 351 bats tests (246 unit + 71 integration + 34 security) across 35 files
- ✓ **CI integration** — GitHub Actions: shellcheck, unit-fast, integration-smoke per push; weekly integration-full
- ✓ **Pre-commit hygiene** — shellcheck + shfmt + semgrep enforced via hooks
- ✓ **Comprehensive audit (2026-03)** — CLI override pattern unified, XSS in HTML report fixed, dead code removed, scope filter sed-escape, parallel-safe timing, transfer() opt-in gate
- ✓ **UI overhaul** — Dot-fill status format, silent `start_func`, single-line dependency summaries, parallel group rebalancing
- ✓ **Resilience: interrupted-run recovery** — `.inprogress_*` sentinel at `start_func`, rename to checkpoint at `end_func`, gated `_RECON_CLEAN_EXIT` clean-exit semantics so SIGINT/SIGTERM preserves the indicator (Phase 1 / RESIL-01 / 2026-05-13)
- ✓ **Resilience: mid-run disk-full detection** — Boundary-only `df` check at `start_func`/`end_func` + `_abort_disk_full` with structured ENOSPC error (Phase 1 / RESIL-02 / 2026-05-13)
- ✓ **Resilience: per-job timeout in `parallel_funcs`** — `PARALLEL_JOB_TIMEOUT_SECONDS` enforcement decoupled from verbosity gate; `_kill_tree` walks `pgrep -P` children-first so the underlying tool dies, not just the wrapper (Phase 1 / RESIL-03 / 2026-05-13)
- ✓ **Perf: DNS timeout defaults** — `DNS_BRUTE_TIMEOUT=6h`, `DNS_RESOLVE_TIMEOUT=4h` defaults shipped in `reconftw.cfg`; `_run_dns_with_heartbeat` honors them (Phase 1 / PERF-02 / 2026-05-13)
- ✓ **Security: `safe_count()` eval vector removed** — `safe_count()` helper deleted from `lib/common.sh` (17-line block including `eval` branch); 3 bats tests dropped; 5 doc files updated; `count_lines()`/`count_lines_stdin()` are now the canonical line-count helpers (Phase 2 / SEC-01 / 2026-05-13)
- ✓ **Security: notification curl quoting hardened** — `sendToNotify()` in `modules/core.sh` fully-quoted (every `$1`, `$NOTIFY_CONFIG`, `$discord_url`, `$slack_channel`, `$slack_auth`, telegram URL, `-F` pair); `shellcheck --severity=error` clean (Phase 2 / SEC-02 / 2026-05-13)
- ✓ **Security: `AXIOM_EXTRA_ARGS` array refactor** — Global `AXIOM_EXTRA_ARGS_ARR` parsed once in `reconftw.sh` (early + post-config); 21 sites in `modules/subdomains.sh` + 17 sites in `modules/web.sh` migrated to `"${AXIOM_EXTRA_ARGS_ARR[@]}"`; explicit tokenisation, no word-splitting (Phase 2 / SEC-03 / 2026-05-13)
- ✓ **Security: installer SHA256 verification + tools.lock** — `verify_sha256()` gates rustup/uv bootstrappers (opt-in via `RUSTUP_INSTALLER_SHA256` / `UV_INSTALLER_SHA256` env vars); `tools.lock` manifest pins 11 stability-critical Go tools (nuclei, httpx, ffuf, puredns, subfinder + dalfox, katana, dnsx, naabu, interactsh-client, tlsx); `install_tools()` reads it before each `go install` (Phase 2 / SEC-04 / 2026-05-13)
- ✓ **Fix: axiom-exec mantra path case** — `Brosck/mantra` → `brosck/mantra` at `modules/web.sh:2331`; local `install.sh:gotools` and remote `modules/web.sh:axiom-exec` paths now agree on lowercase (Phase 2 / FIX-01 / 2026-05-13)

### Active

<!-- Audit-surfaced improvements being driven through the next milestone. -->

- [ ] **Perf: thread-count upper bounds** — Add `FFUF_THREADS_MAX`, `HTTPX_THREADS_MAX`, `DALFOX_THREADS_MAX` caps so multi-core scaling does not overwhelm targets or hit FD limits
- [ ] **Test coverage: `parallel_funcs` batch behaviour** — Tests for barrier sync, heartbeat polling, failure counter propagation
- [ ] **Test coverage: end-to-end module pipelines** — Mocked integration between subdomains → web → vulns to catch handoff regressions
- [ ] **Test coverage: axiom failover path** — `axiom_disable_runtime` invocation, partial-fleet fallback, host-key auto-repair
- [ ] **Docs: surface undocumented config knobs** — `PARALLEL_MAX_JOBS`, `ALLOW_TRANSFER`, `RAISE_ULIMIT`, `ULIMIT_TARGET`, `AXIOM_EXTRA_ARGS` semantics added to `reconftw.cfg` comments
- [ ] **Docs: disk-space default alignment** — Resolve `MIN_DISK_SPACE_GB=2` (cfg) vs `:-5` (modes.sh) mismatch
- [ ] **Scope-check unification** — Reconcile `is_in_scope_host()` (Python-backed) vs `domain_match_regex()` (ERE) so a subdomain accepted by one path is accepted by the other; cross-check tests

### Out of Scope

<!-- Explicit boundaries to prevent scope creep. -->

- **Active exploitation / payload delivery** — reconFTW maps attack surface and flags candidate vulns; weaponized exploitation belongs in user-driven tooling
- **GUI / web dashboard** — CLI-first by design; report HTML is read-only output, not an interactive UI
- **Real-time streaming results** — Output is file-based and post-run; live dashboards would require a fundamentally different architecture
- **Multi-user collaboration** — Single-operator CLI tool; team workflows handled by external systems (Faraday, custom report aggregation)
- **Cloud SaaS hosting** — Self-hosted CLI by design; Axiom is opt-in distributed execution, not managed hosting
- **Replacing individual tools** — Wraps existing best-of-breed tools rather than re-implementing subfinder/nuclei/httpx/etc.

## Context

**Project lineage** — Long-running open-source fork maintained by six2dez at `github.com/six2dez/reconftw`, used widely in bug bounty / pentesting communities. Active issue tracker, PR flow, weekly integration tests.

**Recent trajectory:**
- 2026-03: Comprehensive audit — CLI override unification, dead-code removal (`parallel_run`, `parallel_vulns_full`, `parallel_subdomains_full`), security hardening (XSS in HTML report, scope filter sed-escape, transfer() opt-in gate), parallel-safe timing in `start_func`/`end_func`, pushd/popd → subshell migration
- UI overhaul — Dot-fill status format, single-line dependency summaries, parallel group rebalancing (zonetransfer + favicon parallel), removal of redundant `resolvers_update_quick_*` calls
- 2026-05: Codebase mapped via `/gsd-map-codebase` (`.planning/codebase/*`)

**Existing intel** — `.planning/codebase/ARCHITECTURE.md`, `STACK.md`, `STRUCTURE.md`, `CONVENTIONS.md`, `TESTING.md`, `CONCERNS.md`, `INTEGRATIONS.md` are the authoritative source for system behaviour. The CONCERNS.md inventory is the primary driver for the Active requirements above.

**Technical environment** — Bash 4.3+ (macOS auto re-execs under Homebrew bash), Go ≥ 1.21, Python ≥ 3.7, `uv` package manager, optional Rust/Cargo for `smugglex`. ~5GB disk, ~1GB RAM minimum. bats-core for testing, shellcheck + shfmt + semgrep for hygiene.

## Constraints

- **Tech stack**: Bash 4.3+ — Required for `wait -n`, `mapfile`, associative arrays. macOS users must have Homebrew bash; auto re-exec is best-effort.
- **External tools**: 70+ runtime dependencies — Most install via `go install @latest` (no version pinning), which is convenient but a known supply-chain risk.
- **Single process**: All modules sourced into one shell — No subshell isolation between modules; all state shared via globals. Workflow functions must save/restore globals they override (see `passive()` pattern).
- **Resume semantics**: Checkpoint files are touch-once at `end_func` — Interrupted functions re-run from scratch on next invocation; partial outputs are not detected.
- **Single-operator**: Designed for one user per target run — No locking, no multi-user state, no concurrent runs against the same target dir.
- **Output stability**: `Recon/<domain>/` tree is a public contract — Subdirectory names and filenames are consumed by downstream pipelines, scripts, and parsers; renames are breaking changes.
- **macOS compatibility**: GNU coreutils + GNU sed + GNU getopt required — System BSD versions are not supported.
- **CI budget**: Integration-full is weekly cron — Unit + smoke are per-push; adding heavy integration tests must respect this split.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Brownfield GSD initialization | Codebase is mature, mapped, and actively maintained — questioning-driven greenfield setup would discard known context | ✓ Good |
| CONCERNS.md drives Active requirements | Audit inventory already classifies severity and provides remediation guidance — using it as the backlog avoids re-deriving the same list | — Pending |
| Audit-mode milestone first (not features) | The 2026-03 audit surfaced concrete reliability/security gaps that block confident feature work | — Pending |
| Skip domain research | Bash recon tooling is the maintainer's own domain; codebase already documents stack/architecture; further research would not change requirements | — Pending |
| Coarse granularity / parallel execution | Few, broader phases align with single-maintainer cadence; parallel plans inside a phase reduce calendar time | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-13 after Phase 2 (Security Quoting & Supply-Chain Hygiene) completion*
