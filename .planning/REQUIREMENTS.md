# Requirements: reconFTW

**Defined:** 2026-05-13
**Core Value:** Run one command, get a complete recon picture of a target — passive, active, and vulnerability layers — with resumable checkpoints, structured output, and zero-touch tool orchestration.

## v1 Requirements

Brownfield audit-driven milestone. Each requirement remediates a finding from `.planning/codebase/CONCERNS.md` or fills a known gap. Existing reconFTW capabilities are tracked under PROJECT.md `Validated` and are not re-listed here.

### Resilience

- [ ] **RESIL-01**: User can resume an interrupted recon and skip functions that finished cleanly while re-running functions that were killed mid-execution — via `.inprogress_<func>` sentinel written at `start_func`, renamed to `.<func>` at `end_func`, surfacing partial state on next invocation
- [ ] **RESIL-02**: A recon run aborts with a clear error (rather than producing truncated output) when the working filesystem fills mid-scan — via periodic `df` checks inside long subdomain/DNS loops and a `trap` on `ENOSPC` write failures
- [ ] **RESIL-03**: User can bound individual job time inside `parallel_funcs` via a `PARALLEL_JOB_TIMEOUT_SECONDS` setting, with stuck jobs terminated by `kill -TERM` so a hung tool no longer stalls an entire batch

### Security Hardening

- [ ] **SEC-01**: `safe_count()` no longer falls back to `eval` — all remaining callers in `lib/` and `modules/` write output to a temp file first, and the `else` branch at `lib/common.sh:760` is removed
- [ ] **SEC-02**: `sendToNotify()` quotes every variable it passes to `curl` — `$discord_url`, `${slack_channel}`, and the filename argument `${1}` are all `"$var"`-quoted at `modules/core.sh:1410-1414`
- [ ] **SEC-03**: `AXIOM_EXTRA_ARGS` is consumed via a bash array (`AXIOM_EXTRA_ARGS_ARR=()`) across `modules/subdomains.sh` and `modules/web.sh`, with intentional tokenization made explicit instead of relying on word-splitting an unquoted variable
- [ ] **SEC-04**: Installer verifies the integrity of `rustup` and `uv` bootstrappers via `verify_sha256()` against pinned hashes, and stability-critical Go tools (`nuclei`, `httpx`, `ffuf`, `puredns`, `subfinder`) re-introduce pinned versions captured in a `tools.lock`-style manifest

### Performance

- [ ] **PERF-01**: User can cap per-tool thread counts via `FFUF_THREADS_MAX`, `HTTPX_THREADS_MAX`, `HTTPX_UNCOMMONPORTS_THREADS_MAX`, `KATANA_THREADS_MAX`, `DALFOX_THREADS_MAX`, `DNSTAKE_THREADS_MAX` so multi-core hosts no longer scale linearly into target-overwhelming concurrency
- [ ] **PERF-02**: DNS brute/resolve operations have non-zero default timeouts (`DNS_BRUTE_TIMEOUT=6h`, `DNS_RESOLVE_TIMEOUT=4h`) so a hung resolver does not indefinitely stall a run

### Test Coverage

- [ ] **TEST-01**: Unit tests cover `parallel_funcs` barrier synchronization, heartbeat polling cadence, and the failure-counter increment path so regressions in parallel execution surface in CI
- [ ] **TEST-02**: A mocked end-to-end integration test exercises the `subdomains.sh` → `web.sh` → `vulns.sh` handoff so format-contract regressions (e.g., `webs.txt` shape, scope filter output) fail before manual testing
- [ ] **TEST-03**: Integration tests cover the axiom failover path: `axiom_disable_runtime` invocation on launch failure, partial-fleet fallback to local mode, and `AXIOM_AUTO_FIX_HOSTKEY` repair

### Documentation

- [ ] **DOCS-01**: `reconftw.cfg` documents every previously-hidden tunable — `PARALLEL_MAX_JOBS`, `ALLOW_TRANSFER`, `RAISE_ULIMIT`, `ULIMIT_TARGET`, and `AXIOM_EXTRA_ARGS` word-splitting semantics — as commented-out reference entries
- [ ] **DOCS-02**: Disk-space defaults align — either `reconftw.cfg:39` lifts `MIN_DISK_SPACE_GB` to `5` to match `modules/modes.sh:23`, or `modes.sh` drops the `:-5` fallback so the config value is authoritative

### Bug Fixes

- [ ] **FIX-01**: `modules/web.sh:2340` axiom-exec install path is `github.com/brosck/mantra@latest` (lowercase), matching the local install path fixed in commit `f64383c2`
- [ ] **FIX-02**: Scope-check unification — `is_in_scope_host()` (Python-backed, `lib/validation.sh`) and `domain_match_regex()` (ERE, `lib/common.sh`) agree on edge cases (trailing dots, wildcards, empty input, IDN), verified by a cross-check test in `tests/unit/`

## v2 Requirements

Acknowledged backlog. Tracked but not in current roadmap.

### Architecture

- **ARCH-01**: Split `modules/web.sh` (2965 lines) into `modules/web_analysis.sh` and `modules/web_detection.sh` to improve reviewability and isolated testing
- **ARCH-02**: Centralize secret handling so tokens can always be passed via files (e.g., `-tf` flag) instead of CLI args visible in `ps aux`

### Scaling

- **SCALE-01**: Add memory-aware permutation throttling so `gotator`/`regulator` adjust input size based on available RAM
- **SCALE-02**: Resolver-file health gate — abort `puredns` if fewer than N working resolvers are reachable (instead of silently degrading)

### Observability

- **OBS-01**: Surface venv health (missing imports, broken Python virtualenvs) in `tools_installed`/`check_optional_api_keys` startup summary so silent skips no longer hide failures
- **OBS-02**: Emit structured JSONL events at every module boundary by default (currently opt-in via `STRUCTURED_LOGGING=true`)

## Out of Scope

Explicit exclusions. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Active exploitation / payload delivery | reconFTW maps attack surface and flags candidate vulns; weaponized exploitation belongs in user-driven tooling |
| GUI / web dashboard | CLI-first by design; report HTML is read-only output, not an interactive UI |
| Real-time streaming results | Output is file-based and post-run; live dashboards require a fundamentally different architecture |
| Multi-user collaboration | Single-operator CLI tool; team workflows handled by external systems (Faraday, custom aggregators) |
| Cloud SaaS hosting | Self-hosted CLI by design; Axiom is opt-in distributed execution, not managed hosting |
| Re-implementing wrapped tools | reconFTW orchestrates existing best-of-breed tools (subfinder, nuclei, httpx, ...) rather than competing with them |
| Removing `bash -lc` execution of `AXIOM_POST_START` | Config value is intentionally executable; documenting the contract is the chosen path, not removing the capability |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| RESIL-01 | Phase 1 | Pending |
| RESIL-02 | Phase 1 | Pending |
| RESIL-03 | Phase 1 | Pending |
| SEC-01 | Phase 2 | Pending |
| SEC-02 | Phase 2 | Pending |
| SEC-03 | Phase 2 | Pending |
| SEC-04 | Phase 2 | Pending |
| PERF-01 | Phase 3 | Pending |
| PERF-02 | Phase 1 | Pending |
| TEST-01 | Phase 4 | Pending |
| TEST-02 | Phase 4 | Pending |
| TEST-03 | Phase 4 | Pending |
| DOCS-01 | Phase 5 | Pending |
| DOCS-02 | Phase 5 | Pending |
| FIX-01 | Phase 2 | Pending |
| FIX-02 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 16 total
- Mapped to phases: 16 ✓
- Unmapped: 0

---
*Requirements defined: 2026-05-13*
*Last updated: 2026-05-13 after roadmap creation (traceability populated)*
