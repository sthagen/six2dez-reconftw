# Roadmap: reconFTW (Audit Hardening Milestone)

## Overview

This milestone closes the 2026-03 audit gaps captured in `.planning/codebase/CONCERNS.md`. Five phases drive 16 v1 requirements across resilience, security, performance, test coverage, and documentation. The sequencing places resilience and security fixes first (foundation), then performance caps and scope coherence (behavioural correctness), then test coverage that asserts the new behaviour, then documentation alignment. Each phase groups work by concern and shared code-touch surface so a single PR/plan modifies one logical area, minimising merge churn.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Resilient Resume & Timeout Safety** — `.inprogress` sentinel, disk-full mid-run detection, parallel job timeouts, DNS timeout defaults *(completed 2026-05-13)*
- [ ] **Phase 2: Security Quoting & Supply-Chain Hygiene** — Eval removal, curl quoting, `AXIOM_EXTRA_ARGS` array refactor, installer SHA256, mantra path fix
- [ ] **Phase 3: Concurrency Caps & Scope Unification** — Per-tool thread caps, `is_in_scope_host` vs `domain_match_regex` reconciliation with cross-check tests
- [ ] **Phase 4: Test Coverage Reinforcement** — `parallel_funcs` batch behaviour, mocked end-to-end pipeline, axiom failover
- [ ] **Phase 5: Configuration & Documentation Alignment** — Surface hidden tunables in `reconftw.cfg`, resolve disk-space default mismatch

## Phase Details

### Phase 1: Resilient Resume & Timeout Safety
**Goal**: Long-running scans survive interruptions, disk pressure, and stuck tools without silently producing truncated output or wasting hours of re-work on resume.
**Depends on**: Nothing (first phase)
**Requirements**: RESIL-01, RESIL-02, RESIL-03, PERF-02
**Success Criteria** (what must be TRUE):
  1. Interrupting a recon mid-`sub_brute` and re-running with `PRESERVE=true` produces a clear `.inprogress_sub_brute` indicator and re-executes only that function — completed functions retain `.<func>` checkpoints and are skipped
  2. A scan that exhausts disk space mid-run aborts with a clear `ENOSPC` error message rather than producing zero-byte or truncated output files
  3. Setting `PARALLEL_JOB_TIMEOUT_SECONDS=600` in `reconftw.cfg` terminates any single `parallel_funcs` child exceeding 10 minutes via `kill -TERM`, allowing the batch to continue
  4. Fresh installs of `reconftw.cfg` ship with non-zero `DNS_BRUTE_TIMEOUT=6h` and `DNS_RESOLVE_TIMEOUT=4h` defaults, and a stuck DNS run aborts with a logged timeout rather than blocking indefinitely
**Plans**: TBD

Plans:
- [x] 01-01: `.inprogress` sentinel lifecycle in `start_func`/`end_func` with resume detection (RESIL-01)
- [x] 01-02: Disk-full mid-run guard — periodic `df` check + `ENOSPC` trap (RESIL-02)
- [x] 01-03: `PARALLEL_JOB_TIMEOUT_SECONDS` enforcement in `lib/parallel.sh` plus DNS timeout defaults in `reconftw.cfg` (RESIL-03, PERF-02)
- [x] 01-04: Gap closure — `_RECON_CLEAN_EXIT` flag gates `_cleanup_inprogress` so SIGINT/SIGTERM preserves `.inprogress_<fn>` sentinels (RESIL-01 / CR-01)
- [x] 01-05: Gap closure — decouple timeout enforcement from `--quiet` verbosity gate AND switch `_timeout_kill_job` to process-tree kill via `pgrep -P` walk (RESIL-03 / CR-02, CR-03)

### Phase 2: Security Quoting & Supply-Chain Hygiene
**Goal**: Eliminate the remaining `eval` injection vector, lock down unquoted notification curl calls, make `AXIOM_EXTRA_ARGS` tokenisation explicit, and integrity-check installer bootstrappers.
**Depends on**: Phase 1
**Requirements**: SEC-01, SEC-02, SEC-03, SEC-04, FIX-01
**Success Criteria** (what must be TRUE):
  1. `grep -n "eval " lib/common.sh modules/*.sh` returns no `eval` calls under `safe_count()` and all callers pass file paths — the `else` branch at `lib/common.sh:760` is gone
  2. `sendToNotify()` in `modules/core.sh` quotes every variable passed to `curl` (`"$discord_url"`, `"${slack_channel}"`, `"${1}"`); shellcheck reports no new findings against `modules/core.sh:1399-1414`
  3. `AXIOM_EXTRA_ARGS` is consumed as `AXIOM_EXTRA_ARGS_ARR=()` across `modules/subdomains.sh` and `modules/web.sh`; a value containing intentional whitespace tokens (e.g., `--rate-limit 100`) tokenises correctly and an accidentally-quoted single-token value does not split
  4. `install.sh` calls `verify_sha256()` against pinned hashes for `rustup-init.sh` and `uv/install.sh`; aborts with a clear error on mismatch; a `tools.lock` (or equivalent manifest) pins versions for `nuclei`, `httpx`, `ffuf`, `puredns`, `subfinder`
  5. Running `axiom-exec mantra` against a remote node installs `github.com/brosck/mantra@latest` (lowercase) and the binary runs — the previous 404 / module-not-found on case-sensitive GitHub paths is gone
**Plans**: TBD

Plans:
- [x] 02-01: `safe_count()` eval removal + caller migration to file-path form (SEC-01)
- [x] 02-02: `sendToNotify()` quoting refactor + `modules/web.sh:2340` mantra path fix (SEC-02, FIX-01)
- [x] 02-03: `AXIOM_EXTRA_ARGS_ARR` array refactor + installer SHA256 verification + tools manifest (SEC-03, SEC-04)

### Phase 3: Concurrency Caps & Scope Unification
**Goal**: Bound multi-core thread scaling so large hosts don't overwhelm targets, and reconcile the two scope-checking implementations so output is consistent across code paths.
**Depends on**: Phase 2
**Requirements**: PERF-01, FIX-02
**Success Criteria** (what must be TRUE):
  1. On a 64-core machine the computed values of `FFUF_THREADS`, `HTTPX_THREADS`, `HTTPX_UNCOMMONPORTS_THREADS`, `KATANA_THREADS`, `DALFOX_THREADS`, `DNSTAKE_THREADS` never exceed their respective `*_THREADS_MAX` caps from `reconftw.cfg`
  2. The thread-cap variables (`FFUF_THREADS_MAX`, etc.) appear as commented-out reference entries in `reconftw.cfg` so users can tune them without reading source code
  3. `is_in_scope_host()` and `domain_match_regex()` agree on edge cases — trailing dots, wildcards, empty input, IDN — verified by a cross-check test in `tests/unit/` that feeds the same corpus through both functions and asserts identical accept/reject decisions
**Plans**: TBD

Plans:
- [ ] 03-01: Per-tool thread-count caps with `*_THREADS_MAX` config knobs and `min()` enforcement (PERF-01)
- [ ] 03-02: Scope-check unification — pick canonical implementation + cross-check bats test (FIX-02)

### Phase 4: Test Coverage Reinforcement
**Goal**: Lock in the resilience and parallel changes from Phase 1 with regression tests, and add coverage for the two highest-priority untested areas (end-to-end module handoff and axiom failover).
**Depends on**: Phase 3
**Requirements**: TEST-01, TEST-02, TEST-03
**Success Criteria** (what must be TRUE):
  1. `bats tests/unit/test_parallel.bats` covers barrier sync, heartbeat polling cadence, the failure-counter increment path, and the new `PARALLEL_JOB_TIMEOUT_SECONDS` kill path — at least 4 new `@test` blocks, all green in `make unit-fast`
  2. A new bats integration test (e.g., `tests/integration/test_pipeline_handoff.bats`) exercises `subdomains.sh` → `web.sh` → `vulns.sh` against mocked tool outputs and asserts the `webs.txt` shape and scope-filter output remain stable
  3. A new bats test covers the axiom failover path: `axiom_disable_runtime` invocation on launch failure, partial-fleet fallback to local mode, and `AXIOM_AUTO_FIX_HOSTKEY` repair logic — running locally without an axiom fleet
  4. `make test` (or the equivalent CI target) reports the new test files in its summary and CI passes on the `dev` branch with the additions
**Plans**: TBD

Plans:
- [ ] 04-01: `parallel_funcs` unit tests — barrier, heartbeat, failure counter, timeout kill path (TEST-01)
- [ ] 04-02: Mocked end-to-end pipeline integration test + axiom failover test (TEST-02, TEST-03)

### Phase 5: Configuration & Documentation Alignment
**Goal**: Surface every previously-undocumented config knob in `reconftw.cfg` and resolve the disk-space default mismatch so the config file is authoritative.
**Depends on**: Phase 4
**Requirements**: DOCS-01, DOCS-02
**Success Criteria** (what must be TRUE):
  1. `reconftw.cfg` contains commented-out reference entries for `PARALLEL_MAX_JOBS`, `ALLOW_TRANSFER`, `RAISE_ULIMIT`, `ULIMIT_TARGET`, and `AXIOM_EXTRA_ARGS` semantics; a user grepping `reconftw.cfg` for any of these names finds documentation rather than empty results
  2. `MIN_DISK_SPACE_GB` has a single source of truth — either `reconftw.cfg:39` lifts to `5` to match `modes.sh`, or `modes.sh:23` drops the `:-5` fallback; the value reported by `check_disk_space()` matches the value documented in `reconftw.cfg`
  3. Running `shellcheck reconftw.cfg` and `bats tests/unit/test_config.bats` (or equivalent) passes with no new findings tied to the documentation additions
**Plans**: TBD

Plans:
- [ ] 05-01: Surface hidden tunables + resolve disk-space mismatch in `reconftw.cfg` and `modes.sh` (DOCS-01, DOCS-02)

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Resilient Resume & Timeout Safety | 5/5 | Complete | 2026-05-13 |
| 2. Security Quoting & Supply-Chain Hygiene | 0/3 | Not started | - |
| 3. Concurrency Caps & Scope Unification | 0/2 | Not started | - |
| 4. Test Coverage Reinforcement | 0/2 | Not started | - |
| 5. Configuration & Documentation Alignment | 0/1 | Not started | - |

## Coverage

**v1 requirements:** 16 total, 16 mapped (100%)

| Requirement | Phase |
|-------------|-------|
| RESIL-01 | Phase 1 |
| RESIL-02 | Phase 1 |
| RESIL-03 | Phase 1 |
| PERF-02 | Phase 1 |
| SEC-01 | Phase 2 |
| SEC-02 | Phase 2 |
| SEC-03 | Phase 2 |
| SEC-04 | Phase 2 |
| FIX-01 | Phase 2 |
| PERF-01 | Phase 3 |
| FIX-02 | Phase 3 |
| TEST-01 | Phase 4 |
| TEST-02 | Phase 4 |
| TEST-03 | Phase 4 |
| DOCS-01 | Phase 5 |
| DOCS-02 | Phase 5 |

---
*Roadmap created: 2026-05-13*
