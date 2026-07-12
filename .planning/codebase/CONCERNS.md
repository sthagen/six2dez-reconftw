# Codebase Concerns

**Analysis Date:** 2026-05-13

---

## Security Concerns

### eval in safe_count() Legacy Fallback

**What happens:** `safe_count()` has a documented TODO fallback that runs `eval "$1"` when `$1` is not a file path.
**Files:** `lib/common.sh:760`
**Risk:** Any caller that passes a pipeline string instead of a file path triggers the `eval` branch. If that string is ever derived from external data (tool output, domain names), it becomes an injection vector.
**Current mitigation:** The `if [[ -f "$1" ]]` guard means the file path is the hot path. The eval branch is only hit for legacy callers.
**Fix approach:** Complete the `TODO: migrate remaining callers to pass file paths` at `lib/common.sh:759`. After migration, remove the `else` branch entirely.

---

### bash -lc with Config-Controlled Strings

**What happens:** `run_with_heartbeat_shell()` passes its second argument to `/bin/bash -lc "$shell_cmd"`. The axiom `AXIOM_POST_START` config variable is also executed via `bash -lc "$AXIOM_POST_START"`.
**Files:** `lib/common.sh:745`, `modules/axiom.sh:166`, `modules/core.sh:1663`, `modules/core.sh:1673`
**Risk:** `AXIOM_POST_START` comes verbatim from `reconftw.cfg`. A malicious or accidentally corrupted config value is executed as a shell command. The `run_with_heartbeat_shell` call path is also reachable with user-supplied data if a caller builds the string from tool output.
**Current mitigation:** None — these are treated as trusted config values.
**Recommendation:** Document clearly in `reconftw.cfg` that `AXIOM_POST_START` is executed as a shell command. Consider validating it against an allowlist of safe paths.

---

### Unquoted AXIOM_EXTRA_ARGS — Inconsistent Quoting

**What happens:** `AXIOM_EXTRA_ARGS` is quoted as `"$AXIOM_EXTRA_ARGS"` in some axiom-scan calls but left unquoted (bare `$AXIOM_EXTRA_ARGS`) in many others.
**Files:** `modules/subdomains.sh:672`, `modules/subdomains.sh:737`, `modules/subdomains.sh:745`, `modules/subdomains.sh:768`, `modules/subdomains.sh:1233`, `modules/subdomains.sh:1366`, `modules/subdomains.sh:1666`, `modules/subdomains.sh:1742`, `modules/subdomains.sh:1905`, `modules/subdomains.sh:1926`, `modules/subdomains.sh:1944`, `modules/subdomains.sh:1990`, `modules/subdomains.sh:2068`, `modules/web.sh`
**Risk:** Word splitting on an unquoted `$AXIOM_EXTRA_ARGS` is intentional (it must expand to multiple tokens), but this pattern is indistinguishable from accidental unquoting. A future maintainer may introduce a value with spaces that breaks argument parsing. The inconsistency (some sites quote it, some don't) makes the intent unclear.
**Fix approach:** Use a Bash array `AXIOM_EXTRA_ARGS_ARR=() ; [[ -n "$AXIOM_EXTRA_ARGS" ]] && read -ra AXIOM_EXTRA_ARGS_ARR <<< "$AXIOM_EXTRA_ARGS"` and expand as `"${AXIOM_EXTRA_ARGS_ARR[@]}"`.

---

### Axiom Mantra Module Path Stale in Axiom Branch

**What happens:** The local install path was fixed to lowercase `brosck/mantra` in commit `f64383c2`, but the axiom-exec remote install path still uses the old `Brosck/mantra` capitalization.
**Files:** `modules/web.sh:2340`
**Risk:** When running in Axiom mode the remote `go install` will fail with a 404/module-not-found error because GitHub path matching is case-sensitive for module paths. The fallback `axiom-scan` at line 2341 will then run with no module installed.
**Fix approach:** Change `github.com/Brosck/mantra@latest` to `github.com/brosck/mantra@latest` at `modules/web.sh:2340`.

---

### GitHub Token File Passed Directly on Command Line

**What happens:** `GITHUB_TOKENS` (the path to a token file) is passed as `-t "$GITHUB_TOKENS"` to tools like `github-subdomains`, `gitdorks_go`, and `github-endpoints`. The token is also extracted inline as `GH_TOKEN=$(head -n 1 "$GITHUB_TOKENS")` and passed via `--token "$GH_TOKEN"`.
**Files:** `modules/osint.sh:44`, `modules/osint.sh:49`, `modules/osint.sh:79-86`, `modules/osint.sh:275-281`, `modules/subdomains.sh:521-523`, `modules/web.sh:1902`
**Risk:** `GH_TOKEN` appearing as a CLI argument is visible in `ps aux` output for the duration of the subprocess. The token is registered via `register_secret()` for log redaction, which is correct, but the process list exposure is separate from log redaction.
**Current mitigation:** `register_secret "$GH_TOKEN"` is called before use (`modules/osint.sh:80`, `modules/osint.sh:277`). The `REDACT_VARS` array covers `GH_TOKEN` and `GITHUB_TOKEN`.
**Recommendation:** Where tools support a file path instead of a bare token (e.g., `-tf` flag in gitdorks_go), prefer the file form. Document the ps exposure in security notes.

---

### Notification Credentials Stored Plaintext in notify.conf

**What happens:** The Docker image `COPY`s `Docker/notify.conf` to `/root/.config/notify/provider-config.yaml`. Telegram API keys, Discord webhook URLs, and Slack tokens are read from this YAML file at runtime by `sendToNotify()`.
**Files:** `Docker/Dockerfile:122`, `modules/core.sh:1399-1414`, `reconftw.cfg:92`
**Risk:** If the Docker image is committed with a populated `notify.conf`, credentials are baked into the image layer. Credentials are only protected by `register_secret()` in log output — they are not encrypted at rest.
**Current mitigation:** `register_secret()` redacts values in logs. The `reconftw.cfg` comment says to use environment variables. The `secrets.cfg` auto-source pattern provides a gitignored override.
**Recommendation:** Add a `Docker/.gitignore` that ignores `notify.conf`. Document that `notify.conf` must not contain real tokens when building the image. Consider supporting env-var overrides in `sendToNotify()` analogous to the API key pattern in `reconftw.cfg:97-105`.

---

### transfer() Uploads to External bashupload.com

**What happens:** `transfer()` uploads files to `https://bashupload.com`. It is gated by `ALLOW_TRANSFER=true` (default: false, opt-in required).
**Files:** `modules/core.sh:1359-1386`
**Risk:** When `ALLOW_TRANSFER=true` and `SENDZIPNOTIFY=true`, scan results (potentially containing sensitive internal data) are uploaded to a third-party service with no authentication. Data retention and privacy policies of bashupload.com are external to this project.
**Current mitigation:** Hard opt-in via `ALLOW_TRANSFER=true` in config. Disabled by default.
**Recommendation:** Add a warning in `reconftw.cfg` that `ALLOW_TRANSFER=true` sends data to an unauthenticated external service. Document this explicitly in the README.

---

### Installer Downloads and Executes Unverified Scripts

**What happens:** `install_rust_uv()` downloads `https://sh.rustup.rs` and `https://astral.sh/uv/install.sh` to tempfiles and executes them with `sh "$_tmpfile"`. The `verify_sha256()` helper exists but is not called on these scripts.
**Files:** `install.sh:162-181`
**Risk:** If the download is intercepted (MITM, DNS hijack, CDN compromise), the executed script could contain arbitrary code. The commit `71653984` ("remove pinned versions") removed version pinning from Go tools; all 50+ Go tools now install `@latest` with no integrity check.
**Current mitigation:** Downloads are over HTTPS. `verify_sha256()` is defined but only used optionally (returns 0 if no hash tool available, `install.sh:98`).
**Recommendation:** Call `verify_sha256()` with known-good hashes for the rustup and uv bootstrappers. At minimum, document that users should verify hashes manually. Consider a lockfile or pinned versions for critical tools.

---

### sendToNotify Unquoted Variables in curl Calls

**What happens:** `$discord_url` is unquoted in the `curl` call, and `${1}` (filename) is unquoted in multiple places.
**Files:** `modules/core.sh:1410`, `modules/core.sh:1414`
**Risk:** If the Discord URL or filename contains spaces, word splitting will break the curl call or inject extra arguments. A filename with shell metacharacters could cause unexpected behavior.
**Fix approach:** Quote all variables: `"$discord_url"`, `"${1}"`, `"${slack_channel}"`.

---

## Performance Concerns

### Thread Counts Scaled by CPU Core Count Without Upper Bound

**What happens:** `FFUF_THREADS`, `HTTPX_THREADS`, `HTTPX_UNCOMMONPORTS_THREADS`, `KATANA_THREADS`, `DALFOX_THREADS`, `DNSTAKE_THREADS` are all computed as multiples of `AVAILABLE_CORES` with no maximum cap.
**Files:** `reconftw.cfg:349-355`
**Risk:** On a 64-core machine, `DALFOX_THREADS=$((64 * 15))` = 960 threads. This can overwhelm the target, trigger WAF bans, or exhaust the scanning host's file descriptor limits. `DNSTAKE_THREADS` at 10x already carries a comment noting it was reduced.
**Current mitigation:** `PORTSCAN_ACTIVE_OPTIONS` has `--max-retries 2`. Adaptive rate limiting (`ADAPTIVE_RATE_LIMIT=false` by default) can compensate but is opt-in.
**Fix approach:** Add `FFUF_THREADS_MAX`, `HTTPX_THREADS_MAX` caps in `reconftw.cfg`. Apply `min(computed, max_cap)` in the thread assignment logic.

---

### PUREDNS_WILDCARDBATCH_LIMIT at 1.5 Million

**What happens:** `PUREDNS_WILDCARDBATCH_LIMIT=1500000` controls how many unique subdomains puredns processes per wildcard batch.
**Files:** `reconftw.cfg:360`
**Risk:** Very large targets with aggressive permutation wordlists can generate millions of candidates. Processing 1.5M entries per batch is memory-intensive and can exhaust RAM on small VPS instances (the installer warns at <1GB but `MIN_DISK_SPACE_GB` is set to 2GB, not accounting for RAM).
**Recommendation:** Document in `reconftw.cfg` the approximate memory usage at this limit. Consider lowering for the `low` performance profile.

---

### DNS_BRUTE_TIMEOUT and DNS_RESOLVE_TIMEOUT Default to 0 (Disabled)

**What happens:** Both hard-timeout guards default to `0` (disabled). Long DNS brute-force runs against large wordlists can run indefinitely.
**Files:** `reconftw.cfg:387-388`
**Risk:** An interrupted (Ctrl-C) long DNS job leaves partial output files, and the checkpoint mechanism (`called_fn_dir/.funcname`) is not created on incomplete runs, so the function re-runs on next invocation with `DIFF=false`. This wastes time rather than resuming.
**Recommendation:** Set sensible defaults (e.g., `DNS_BRUTE_TIMEOUT=6h`, `DNS_RESOLVE_TIMEOUT=4h`). Document these in the performance tuning section.

---

### Python Venv Dependencies Not Validated at Startup

**What happens:** `GETJSWORDS_VENV` (default: `$SCRIPTPATH/.venv`) is tested with a Python import check at call time inside `jschecks()`. CMSeeK and JSA use hardcoded venv paths. Missing or stale venvs silently skip the step.
**Files:** `modules/web.sh:2354-2382`, `modules/web.sh:1793`, `modules/web.sh:2017`
**Risk:** If a venv is partially broken (e.g., `jsbeautifier` installed but `requests` missing), the skip is silent at verbosity < 2. Users get no output from those tools without knowing why.
**Recommendation:** Add venv health checks to `check_optional_api_keys` / `tools_installed` summary output so venv failures surface in the startup health check.

---

## Tech Debt

### TODO: Migrate safe_count Callers to File Paths

**Issue:** Documented incomplete migration leaving an `eval` fallback alive.
**Files:** `lib/common.sh:759-760`
**Impact:** The `eval` branch is a latent injection vector that grows riskier as more callers are added.
**Fix approach:** Audit all `safe_count` call sites with `grep -rn "safe_count"` and convert pipeline-passing callers to write output to a temp file first.

---

### All Go Tools Install @latest Without Version Pinning

**Issue:** Commit `71653984` ("remove pinned versions") removed all pinned Go tool versions. All ~50 tools in the `gotools` associative array now install `@latest`.
**Files:** `install.sh:292-355`, `install.sh:505`
**Impact:** A breaking upstream change in any tool (API change, renamed flag, removed feature) will silently break the corresponding module. There is no lockfile or checksum verification. CI cannot reproduce the exact tool set from a month ago.
**Fix approach:** Re-introduce pinned versions for stability-critical tools (nuclei, httpx, ffuf, puredns, subfinder). Use a `tools.lock` file pattern or a `go.sum`-style manifest.

---

### Large Monolithic Module Files

**Issue:** Core modules exceed 2000 lines, making code review, testing, and targeted edits difficult.
**Files:** `modules/web.sh` (2965 lines), `modules/subdomains.sh` (2406 lines), `modules/core.sh` (2340 lines), `modules/modes.sh` (1649 lines)
**Impact:** Grep-and-patch workflows are error-prone at this scale. Bats unit tests in `tests/unit/` cannot easily isolate individual functions without extracting them via `awk`/`sed` (see MEMORY.md note on fragile `grep -A N` extraction).
**Fix approach:** No immediate action required, but consider splitting `web.sh` into `web_analysis.sh` and `web_detection.sh` as a first step.

---

### PARALLEL_MAX_JOBS Default Not Documented in reconftw.cfg

**Issue:** `PARALLEL_MAX_JOBS=4` is the default set in `lib/parallel.sh:14` but not exposed in `reconftw.cfg`. Users cannot easily tune it via config without knowing the internal default.
**Files:** `lib/parallel.sh:14`, `reconftw.cfg:302-325`
**Impact:** Advanced users tuning parallelism miss this lever.
**Fix approach:** Add `# PARALLEL_MAX_JOBS=4  # Maximum concurrent jobs across all parallel_funcs batches` to `reconftw.cfg`.

---

### mantra Module Path Stale in axiom-exec Branch

**Issue:** See Security section above. The local tool module path was fixed but the remote `axiom-exec` install path retains the old case.
**Files:** `modules/web.sh:2340`
**Fix approach:** One-line change: `github.com/Brosck/mantra@latest` → `github.com/brosck/mantra@latest`.

---

### fray GitHub Repo No Longer Available

**Issue:** `fray` was moved from GitHub (`dalisecurity/fray`) to PyPI only. The installer has a special case for it (`install.sh:534-537`), but the `pipxtools` map still lists the old GitHub path (`dalisecurity/fray`) for display purposes.
**Files:** `install.sh:375`, `install.sh:534-537`
**Impact:** Low — the installer correctly uses `tool_url="fray"` (PyPI name) for fray. But the map entry is misleading to contributors reading the code.
**Fix approach:** Remove the `dalisecurity/fray` value from the `pipxtools` map entry since it's no longer used.

---

## Known Bugs / Reliability Issues

### Checkpoint Files Not Created on Interrupted Runs

**What happens:** `end_func()` calls `touch "$called_fn_dir/.${fn}"` to mark a function complete. If a function is interrupted (SIGINT, SIGKILL, tool crash), the checkpoint file is never written.
**Files:** `modules/core.sh:1465`
**Trigger:** Ctrl-C during a long sub-function, OOM kill of a child process, disk-full mid-run.
**Impact:** On re-run with `PRESERVE=true` the function re-executes from the beginning. For expensive functions like `sub_brute` or DNS resolution, this means hours of repeated work.
**Workaround:** `PRESERVE=false` (default) clears all checkpoints on re-run. For large scans where `PRESERVE=true` is set, interrupted functions always restart.
**Recommendation:** Write an `.inprogress_${fn}` sentinel at `start_func` time and rename it to the checkpoint at `end_func` time. On resume, detect `.inprogress_*` files as incomplete.

---

### Disk-Full Detection Is Pre-Flight Only, Not Mid-Run

**What happens:** `check_disk_space()` is called once at the start of each recon mode (`modes.sh:24`). If disk fills during a long permutation or DNS brute run, tools fail silently or write corrupt partial output.
**Files:** `modules/modes.sh:23-27`, `modules/utils.sh:419-436`
**Risk:** Partial output files without disk-full markers can cause subsequent pipeline steps to produce incorrect results (e.g., counting "0 new subdomains" when the actual output was truncated).
**Recommendation:** Periodically check disk space in long-running loops (e.g., before each subdomain resolution batch). Add a trap handler that detects `ENOSPC` write failures.

---

### Checkpoint Race Condition in Parallel Mode

**What happens:** When `parallel_funcs` runs multiple functions concurrently, each function writes its own `called_fn_dir/.funcname` and `.status_funcname` files. There is no file locking on these writes.
**Files:** `modules/core.sh:1465`, `modules/core.sh:1505-1509`, `lib/parallel.sh:397-403`
**Risk:** On NFS or certain local filesystems, concurrent `touch` + `printf` to adjacent files in the same directory can produce race conditions. More practically, if two parallel functions share a common status file name (which they don't today, but could after future refactoring), writes would clobber each other.
**Current mitigation:** Each function writes a uniquely named file (`.$funcname`), so collisions require naming conflicts. The `2>/dev/null || true` error suppression means write failures are silent.
**Recommendation:** Add a warning if `called_fn_dir` is on a network filesystem.

---

### Disk Space Config Default Mismatch

**What happens:** `MIN_DISK_SPACE_GB=2` in `reconftw.cfg:39`, but `modes.sh:23` overrides it with `${MIN_DISK_SPACE_GB:-5}` (5 GB default). The installer warns below 5 GB too. The config comment says `2` but the effective default is `5`.
**Files:** `reconftw.cfg:39`, `modules/modes.sh:23`
**Impact:** Users who read `reconftw.cfg` and see `2` may believe 2 GB is the threshold, but the modes initialization applies 5 GB unless the config value is explicitly set. Misleading documentation.
**Fix approach:** Align `reconftw.cfg:39` to `MIN_DISK_SPACE_GB=5` to match the modes.sh default, or remove the `:-5` fallback in `modes.sh` so the config value is authoritative.

---

## Fragile Areas

### Axiom Fleet Failure Modes

**What happens:** Axiom fleet operations rely on `axiom-ls`, `axiom-select`, `axiom-fleet2`, and `axiom-exec` all succeeding. Partial fleet launches (e.g., N-1 of N nodes provisioned) disable Axiom runtime and fall back to local mode without re-attempting.
**Files:** `modules/axiom.sh:122-180`
**Why fragile:** Cloud provider rate limits, SSH key distribution delays, and network timeouts all cause `axiom_launch` to return failure and invoke `axiom_disable_runtime`. There is no retry for partial fleet launches.
**Safe modification:** Always test Axiom changes with a 1-node fleet first. The `AXIOM_AUTO_FIX_HOSTKEY` mechanism (`modules/axiom.sh:227-249`) is useful but only handles the SSH host-key case, not provisioning failures.

---

### parallel_funcs Batch Flushing

**What happens:** `parallel_funcs` fills a batch to `max_jobs` then waits for all jobs in that batch to complete before starting new ones. This is a barrier synchronization, not a sliding window.
**Files:** `lib/parallel.sh:350-570`
**Why fragile:** If one function in a batch hangs (e.g., a tool that doesn't respect timeouts), the entire batch stalls. The heartbeat loop (`lib/parallel.sh:434-474`) polls alive PIDs every `PARALLEL_HEARTBEAT_SECONDS` but provides no kill mechanism for stuck jobs.
**Recommendation:** Add `PARALLEL_JOB_TIMEOUT_SECONDS` config that kills individual jobs exceeding the limit with `kill -TERM`.

---

### is_in_scope_host vs grep -E DOMAIN_MATCH_REGEX Inconsistency

**What happens:** Two scope-checking mechanisms exist in parallel: the Python-backed `is_in_scope_host()` / `filter_in_scope_hosts()` in `lib/validation.sh`, and the ERE-based `DOMAIN_MATCH_REGEX` from `domain_match_regex()` in `lib/common.sh`. Different code paths use different mechanisms.
**Files:** `lib/validation.sh:192-199`, `lib/common.sh:821-826`, `modules/subdomains.sh:194`, `modules/subdomains.sh:472`
**Risk:** The two implementations must agree on edge cases (trailing dots, wildcards, empty input). A discrepancy means a subdomain accepted by one path is rejected by the other, causing inconsistent output between runs with different code paths.
**Recommendation:** Add a test that cross-checks both mechanisms with the same corpus. Consider deprecating one in favor of the other.

---

### wait -n Requires Bash 4.3+

**What happens:** `_throttle_jobs()` uses `wait -n` to harvest background job slots.
**Files:** `lib/parallel.sh:40`
**Risk:** macOS ships Bash 3.2. The scripts re-exec with Homebrew Bash 4+ at the top of both `reconftw.sh` and `install.sh`, but this mitigation only works if Homebrew Bash is installed. On a macOS system without Homebrew (e.g., CI Docker), `wait -n` silently fails with `|| break`, which exits the throttle loop early and spawns unbounded jobs.
**Current mitigation:** `wait -n 2>/dev/null || break` — the break exits the while loop, bypassing the throttle entirely (no error, just unthrottled spawning).
**Recommendation:** Document the Homebrew Bash requirement for macOS prominently. Add a Bash version assertion before any `wait -n` call.

---

## Scaling Limits

### Resolver File Size Not Validated Before puredns Runs

**What happens:** `puredns` quality degrades sharply if the resolvers file has fewer than ~100 working resolvers. The resolver download is a soft dependency (failure emits a warning but does not abort).
**Files:** `reconftw.cfg:401-402`, `modules/modes.sh:44-46` (health check)
**Current capacity:** `PUREDNS_PUBLIC_LIMIT=5000` QPS, `PUREDNS_TRUSTED_LIMIT=400` QPS.
**Limit:** If the resolvers file has stale entries from the trickest/resolvers list, effective throughput drops. The health check (`modules/modes.sh` startup) warns if resolvers file is missing but does not count valid entries.
**Scaling path:** Enable `generate_resolvers=true` with `dnsvalidator` on VPS deployments. Document the tradeoff in `reconftw.cfg`.

---

### No Per-Target Memory Limit for Permutation Generation

**What happens:** `PERMUTATIONS_LIMIT=2147483648` (2 GB) caps permutation wordlist size before gotator runs. However, gotator and regulator load the wordlist into memory; on very large inputs the 2 GB file size limit does not directly bound RAM usage.
**Files:** `reconftw.cfg:386`
**Scaling path:** Set `PERMUTATIONS_LIMIT` to a lower value (e.g., 500 MB) on instances with less than 8 GB RAM.

---

## Dependencies at Risk

### subwiz (hadriansecurity/subwiz) — Research Tool Maturity

**Risk:** `subwiz` is an ML-based subdomain prediction tool from a security research team. Research tools often have unstable APIs, are abandoned, or break with Python updates. The tool is installed via `uv` from GitHub.
**Files:** `install.sh:370`, `modules/subdomains.sh`
**Impact:** If the GitHub repo is archived or the Python dependency tree breaks, the `subwiz` function silently skips.
**Migration plan:** Monitor upstream activity. The skip behavior on missing tool (`command -v subwiz`) means failure is non-blocking.

---

### fray (PyPI) — External Service Dependency

**Risk:** `fray` payload lists may be fetched from external sources at runtime. The PyPI-only distribution means there is no GitHub source to audit for changes.
**Files:** `install.sh:534-537`, `modules/vulns.sh:1115-1159`
**Impact:** Payload updates could introduce unexpected request patterns. The `FRAY_DELAY=0.5` and `FRAY_MAX_PAYLOADS=20` defaults limit blast radius.

---

### trufflehog — Install via go install @latest

**Risk:** trufflehog is installed via `go install` in the repos section (`install.sh:703`), not via the `gotools` map, so it has a different install path and no version pinning.
**Files:** `install.sh:703`
**Impact:** Breaking changes in trufflehog's CLI between versions can silently break the `github_leaks` function.

---

## Test Coverage Gaps

### No Tests for parallel_funcs Batch Barrier Behavior

**What's not tested:** Whether `parallel_funcs` correctly waits for all jobs in a batch, whether the heartbeat loop polls correctly, and whether job failure propagates the `failed` counter.
**Files:** `lib/parallel.sh:350-570`
**Risk:** Parallel execution bugs (jobs skipped, output interleaved incorrectly, stuck batches) go undetected.
**Priority:** High — parallel mode is default (`PARALLEL_MODE=true`).

---

### No Tests for Disk-Full Handling

**What's not tested:** Tool behavior when `df` reports 0 GB available mid-run, or when `write()` returns `ENOSPC`.
**Files:** `modules/utils.sh:419-436`, `modules/modes.sh:23-27`
**Risk:** Corrupt partial output files from truncated writes could cause false-negative security findings.
**Priority:** Medium.

---

### No Tests for axiom Failure/Fallback Path

**What's not tested:** `axiom_disable_runtime` invocation, fallback to local mode on fleet launch failure, `AXIOM_AUTO_FIX_HOSTKEY` repair logic.
**Files:** `modules/axiom.sh`
**Risk:** Axiom fallback failures are only discovered in production with a live fleet.
**Priority:** Medium — Axiom is optional, but cloud mode is a primary use case.

---

### No Integration Tests for End-to-End Module Pipelines

**What's not tested:** The pipeline from `subdomains.sh` through `web.sh` through `vulns.sh` with real (or mocked) tool output. All existing tests in `tests/unit/` test individual helper functions in isolation.
**Files:** `tests/unit/` (226+ unit tests), `tests/security/` (12 security tests)
**Risk:** Regressions in inter-module data handoff (e.g., webs.txt format changes, scope filter behavior) are undetected until manual testing.
**Priority:** High for new feature development.

---

## Documentation Gaps

### AXIOM_EXTRA_ARGS Not Documented in reconftw.cfg

`reconftw.cfg:418` sets `AXIOM_EXTRA_ARGS=""` with a single example comment. The variable is used in 20+ axiom-scan calls but there is no explanation of which axiom-scan flags are safe to pass here, or that word splitting is intentional.

### ALLOW_TRANSFER Not Present in reconftw.cfg

The `ALLOW_TRANSFER` flag is checked in `modules/core.sh:1362` and mentioned in MEMORY.md, but does not appear in `reconftw.cfg` as a commented-out option. Users must discover it by reading source code.
**Files:** `modules/core.sh:1362`, `reconftw.cfg`

### PARALLEL_MAX_JOBS Not Exposed in reconftw.cfg

See Tech Debt section above. The default of 4 is set only in `lib/parallel.sh:14`.

### RAISE_ULIMIT / ULIMIT_TARGET Not in reconftw.cfg

`RAISE_ULIMIT=true` and `ULIMIT_TARGET=65535` are referenced in `modules/modes.sh:30-32` but not exposed as config options in `reconftw.cfg`.

---

*Concerns audit: 2026-05-13*
