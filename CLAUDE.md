<!-- GSD:project-start source:PROJECT.md -->
## Project

**reconFTW**

reconFTW is a comprehensive bash-based reconnaissance automation framework used by bug bounty hunters, penetration testers, and security researchers. It orchestrates 70+ external security tools (Go, Python, Rust) across subdomain enumeration, web probing, OSINT, and vulnerability scanning, producing structured per-target output trees with optional Axiom distributed execution, AI reporting, monitor/incremental mode, and Slack/Telegram/Discord notifications.

**Core Value:** Run one command, get a complete recon picture of a target — passive, active, and vulnerability layers — with resumable checkpoints, structured output, and zero-touch tool orchestration.

### Constraints

- **Tech stack**: Bash 4.3+ — Required for `wait -n`, `mapfile`, associative arrays. macOS users must have Homebrew bash; auto re-exec is best-effort.
- **External tools**: 70+ runtime dependencies — Most install via `go install @latest` (no version pinning), which is convenient but a known supply-chain risk.
- **Single process**: All modules sourced into one shell — No subshell isolation between modules; all state shared via globals. Workflow functions must save/restore globals they override (see `passive()` pattern).
- **Resume semantics**: Checkpoint files are touch-once at `end_func` — Interrupted functions re-run from scratch on next invocation; partial outputs are not detected.
- **Single-operator**: Designed for one user per target run — No locking, no multi-user state, no concurrent runs against the same target dir.
- **Output stability**: `Recon/<domain>/` tree is a public contract — Subdirectory names and filenames are consumed by downstream pipelines, scripts, and parsers; renames are breaking changes.
- **macOS compatibility**: GNU coreutils + GNU sed + GNU getopt required — System BSD versions are not supported.
- **CI budget**: Integration-full is weekly cron — Unit + smoke are per-push; adding heavy integration tests must respect this split.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- Bash 4+ - All core framework logic (`reconftw.sh`, `modules/*.sh`, `lib/*.sh`, `install.sh`)
- Python 3.7+ - Python-backed tools (each runs in isolated `uv venv`): `dorks_hunter`, `CMSeeK`, `EmailHarvester`, `Spoofy`, `SSTImap`, `gato`, `regulator`, `reconftw_ai`, `getjswords.py`
- Go (latest, min ~1.21) - Primary binary language for ~55 security tools installed via `go install @latest`
## Runtime
- Linux (Debian/Ubuntu/RHEL/Arch) or macOS (Apple Silicon / Intel)
- Docker: Ubuntu 24.04 base image (`Docker/Dockerfile`)
- ARM64/aarch64, ARMv6l/v7l, and x86_64 all supported for Go binary installs
- `getopt` (GNU getopt required on macOS via `brew install gnu-getopt`)
- `nproc` / `sysctl -n hw.ncpu` for CPU core auto-detection
- `timeout` / `gtimeout` (macOS Homebrew `coreutils`)
- `gnu-sed` (macOS requires `brew install gnu-sed`)
- `gnu-coreutils` (macOS requires `brew install coreutils`)
- Go tools: `go install` (`GOPATH=$HOME/go`, `GOROOT=/usr/local/go`)
- Python tools: `uv tool install` from GitHub (most) or PyPI (`fray`)
- Python repo venvs: `uv venv venv && uv pip install -r requirements.txt`
- Lockfile: None (always installs `@latest`)
## Frameworks
- No framework — pure Bash with sourced module files
- Module loading order: `lib/validation.sh` → `lib/common.sh` → `lib/ui.sh` → `lib/parallel.sh` → `modules/utils.sh` → `modules/core.sh` → `modules/osint.sh` → `modules/subdomains.sh` → `modules/web.sh` → `modules/vulns.sh` → `modules/axiom.sh` → `modules/modes.sh`
- bats-core (Bash Automated Testing System)
- GNU make (`Makefile`) — test, lint, format targets
- shellcheck (error-level) — `make lint`, pre-commit hook
- shfmt (4-space indent, `-bn`, `-ci`) — `make fmt`, pre-commit hook
- pre-commit hooks defined in `.pre-commit-config.yaml`
- semgrep: `.github/workflows/semgrep.yml` (CI only)
## Key Dependencies
### Go Tools (installed via `go install @latest`)
- `subfinder` (projectdiscovery/subfinder) — passive multi-source subdomain discovery
- `github-subdomains` (gwen001/github-subdomains) — GitHub-based subdomain search
- `gitlab-subdomains` (gwen001/gitlab-subdomains) — GitLab-based subdomain search
- `dnstake` (pwnesia/dnstake) — subdomain takeover detection
- `puredns` (d3mondev/puredns) — mass DNS resolution with wildcard filtering
- `dnsx` (projectdiscovery/dnsx) — DNS toolkit
- `massdns` (blechschmidt/massdns) — via repo clone + build
- `dsieve` (trickest/dsieve) — subdomain filtering
- `enumerepo` (trickest/enumerepo) — GitHub org repo enumeration
- `gotator` (Josue87/gotator) — subdomain permutations
- `analyticsrelationships` (Josue87/analyticsrelationships) — Google Analytics pivoting
- `roboxtractor` (Josue87/roboxtractor) — robots.txt extractor
- `crt` (cemulus/crt) — crt.sh search
- `asnmap` (projectdiscovery/asnmap) — ASN-to-CIDR mapping
- `mapcidr` (projectdiscovery/mapcidr) — CIDR manipulation
- `smap` (s0md3v/smap) — passive Shodan-powered port scan
- `tlsx` (projectdiscovery/tlsx) — TLS certificate harvesting
- `hakip2host` (hakluke/hakip2host) — reverse IP lookup
- `cdncheck` (projectdiscovery/cdncheck) — CDN/WAF IP classification
- `hakoriginfinder` (hakluke/hakoriginfinder) — origin IP discovery behind CDN
- `inscope` (tomnomnom/hacks/inscope) — scope filtering
- `csprecon` (edoardottt/csprecon) — CSP-based subdomain discovery
- `favirecon` (edoardottt/favirecon) — favicon-based tech recon
- `httpx` (projectdiscovery/httpx) — multi-probe HTTP toolkit
- `katana` (projectdiscovery/katana) — web crawler
- `ffuf` (ffuf/ffuf) — web fuzzer
- `subjs` (lc/subjs) — JavaScript URL extractor
- `Gxss` (KathanP19/Gxss) — reflected XSS param finder
- `jsluice` (BishopFox/jsluice) — JS secret/URL extractor
- `sourcemapper` (denandz/sourcemapper) — JS source map extractor
- `mantra` (brosck/mantra) — JS/secret scanner
- `urlfinder` (projectdiscovery/urlfinder) — URL discovery
- `xnLinkFinder` (xnl-h4ck3r/xnLinkFinder) — via uv
- `nmapurls` (sdcampbell/nmapurls) — URL extraction from Nmap XML
- `naabu` (projectdiscovery/naabu) — fast port scanner
- `VhostFinder` (wdahlenburg/VhostFinder) — virtual host discovery
- `shortscan` (bitquark/shortscan) — IIS short filename scanner
- `nuclei` (projectdiscovery/nuclei) — template-based scanner
- `dalfox` (hahwul/dalfox) — XSS scanner
- `crlfuzz` (dwisiswant0/crlfuzz) — CRLF injection scanner
- `Web-Cache-Vulnerability-Scanner` (Hackmanit) — web cache poisoning
- `TInjA` (Hackmanit/TInjA) — SSTI scanner
- `toxicache` (xhzeem/toxicache) — web cache poisoning
- `second-order` (mhmdiaa/second-order) — broken link/second-order injection
- `s3scanner` (sa7mon/s3scanner) — S3/GCS/Azure Blob misconfiguration
- `misconfig-mapper` (intigriti/misconfig-mapper) — third-party misconfiguration
- `sj` (BishopFox/sj) — Swagger/OpenAPI analysis
- `grpcurl` (fullstorydev/grpcurl) — gRPC reflection scanner
- `nerva` (praetorian-inc/nerva) — service fingerprinting
- `brutus` (praetorian-inc/brutus) — credential spraying
- `julius` (praetorian-inc/julius) — LLM endpoint probe
- `titus` (praetorian-inc/titus) — secrets engine
- `notify` (projectdiscovery/notify) — multi-channel notifications
- `interactsh-client` (projectdiscovery/interactsh) — OOB callback server
- `gf` (tomnomnom/gf) — URL pattern grep
- `anew` (tomnomnom/anew) — append new lines only
- `unfurl` (tomnomnom/unfurl) — URL parser
- `qsreplace` (tomnomnom/qsreplace) — querystring replacer
- `gitdorks_go` (damit5/gitdorks_go) — GitHub dork search
- `github-endpoints` (gwen001/github-endpoints) — GitHub endpoint discovery
- `cent` (xm1k3/cent) — nuclei template manager
- `trufflehog` (trufflesecurity/trufflehog) — secrets scanner (via `go install`)
- `brutespray` (x90skysn3k/brutespray) — service credential spraying
### Python Tools (installed via `uv tool install`)
- `dnsvalidator` (vortexau/dnsvalidator) — DNS resolver validation
- `interlace` (pry0cc/interlace) — parallel command runner
- `wafw00f` (EnableSecurity/wafw00f) — WAF fingerprinting
- `commix` (commixproject/commix) — command injection scanner
- `waymore` (xnl-h4ck3r/waymore) — passive URL collection
- `urless` (xnl-h4ck3r/urless) — URL deduplication
- `ghauri` (r0oth3x49/ghauri) — SQLi scanner (optional)
- `xnLinkFinder` (xnl-h4ck3r/xnLinkFinder) — deep link finder
- `xnldorker` (xnl-h4ck3r/xnldorker) — Google dorker
- `porch-pirate` (MandConsultingGroup/porch-pirate) — Postman API leaks
- `p1radup` (iambouali/p1radup) — URL deduplication
- `subwiz` (hadriansecurity/subwiz) — ML-based subdomain prediction
- `arjun` (s0md3v/Arjun) — parameter discovery
- `gqlspection` (doyensec/GQLSpection) — GraphQL deep introspection
- `postleaksNg` (six2dez/postleaksNG) — Postman public leak search
- `cewler` (roys/cewler) — web wordlist generator
- `fray` (dalisecurity/fray) — WAF-aware payload testing (PyPI)
### Repo-Clone Tools (Python venvs, run via `venv/bin/python3`)
- `dorks_hunter` (six2dez/dorks_hunter) — Google dork automation
- `CMSeeK` (Tuhinshubhra/CMSeeK) — CMS fingerprinting
- `cloud_enum` (initstring/cloud_enum) — AWS/GCP/Azure bucket enumeration
- `EmailHarvester` (maldevel/EmailHarvester) — email harvesting
- `SwaggerSpy` (UndeadSec/SwaggerSpy) — Swagger endpoint leak detection
- `LeakSearch` (JoelGMSec/LeakSearch) — credential leak search
- `Spoofy` (MattKeeley/Spoofy) — email spoofing check
- `msftrecon` (Arcanum-Sec/msftrecon) — Microsoft tenant recon
- `Scopify` (Arcanum-Sec/Scopify) — scope management
- `regulator` (cramppet/regulator) — regex-based subdomain permutations
- `SSTImap` (vladko312/SSTImap) — SSTI scanner (alternative engine)
- `gato` (praetorian-inc/gato) — GitHub Actions audit
### Repo-Clone Tools (Go build)
- `ghleaks` (dinosn/ghleaks) — GitHub-wide secret search
- `nomore403` (devploit/nomore403) — 403 bypass
- `ffufPostprocessing` (Damian89/ffufPostprocessing) — ffuf result analysis
- `JSA` (w9w/JSA) — JS analysis
- `ultimate-nmap-parser` (shifty0g/ultimate-nmap-parser) — Nmap XML parser
### System-Level Tools (apt/brew/yum)
- `nmap` — active port scanning
- `massdns` — DNS resolver (also cloned + built from source)
- `jq` — JSON processing throughout all modules
- `exiftool` (perl-Image-ExifTool) — metadata extraction
- `whois` — domain registration lookup
- `sqlmap` — SQL injection (system or via repo clone)
- `testssl.sh` (testssl/testssl.sh) — TLS/SSL misconfiguration testing
- `medusa` — credential brute-force (system install)
- `shodan` CLI — installed via `uv tool install shodan`
### Rust Tools
- `smugglex` (Cargo) — HTTP request smuggling detection
- Rustup installed from `https://sh.rustup.rs`
## Configuration
- `reconftw.cfg` — sourced after CLI parsing; all feature flags, rate limits, timeouts, wordlist paths, API keys, thread counts
- `secrets.cfg` (gitignored, auto-sourced) — API keys and tokens separated from main config
- `secrets.cfg.example` — template showing all supported secret vars
- Feature flags: `OSINT=true`, `SUBDOMAINS_GENERAL=true`, `VULNS_GENERAL=false`, etc.
- Rate limits: `HTTPX_RATELIMIT=150`, `NUCLEI_RATELIMIT=150`, `FFUF_RATELIMIT=0`
- Thread counts: auto-scaled via `AVAILABLE_CORES=$(nproc)` with multipliers per tool
- Timeouts: per-tool in seconds or minutes (`CMSSCAN_TIMEOUT=3600`, `SUBFINDER_ENUM_TIMEOUT=180`)
- Wordlist paths: `fuzz_wordlist`, `lfi_wordlist`, `subs_wordlist` etc. under `${WORDLISTS_DIR}`
- Output: `EXPORT_FORMAT`, `AI_REPORT_TYPE`, `ASSET_STORE`
- GNU `getopt` long options, parsed in `reconftw.sh` while/case loop
- All CLI overrides use `CLI_*` pattern and are re-applied after `reconftw.cfg` is sourced
- Full list from `getopt` call: `domain`, `list`, `recon`, `subdomains`, `passive`, `all`, `web`, `osint`, `zen`, `deep`, `help`, `vps`, `vps-count`, `ai`, `check-tools`, `health-check`, `quick-rescan`, `incremental`, `adaptive-rate`, `dry-run`, `parallel`, `no-parallel`, `monitor`, `monitor-interval`, `monitor-cycles`, `refresh-cache`, `gen-resolvers`, `force`, `export`, `report-only`, `no-report`, `parallel-log`, `quiet`, `verbose`, `no-color`, `log-format`, `show-cache`, `banner`, `no-banner`, `legal`
- `SHODAN_API_KEY`, `WHOISXML_API`, `PDCP_API_KEY`, `XSS_SERVER`, `COLLAB_SERVER` — preferred over config file
- `GOROOT`, `GOPATH`, `PATH` — extended by `reconftw.cfg` for Go and Rust binaries
- `LOGFILE` — per-target log path
- `config/reconftw_full.cfg` — full-scan preset
- `config/reconftw_quick.cfg` — quick-scan preset
- `config/reconftw_stealth.cfg` — low-noise preset
## Build
- Default: `go1.23.6` (fetches latest from `https://go.dev/VERSION?m=text`)
- Installed to `/usr/local/go`; set `install_golang=false` in config to skip
- Minimum: Python 3.7 (enforced in `install_yum()`)
- Virtual environments per tool via `uv venv`
- Root venv at `.venv/` for `getjswords.py` and similar helpers
## Platform Requirements
- Bash ≥ 4.3 (for `wait -n` used in `lib/parallel.sh`)
- Go ≥ 1.21 (tools use SIV module paths like `/v2`, `/v3`)
- Python ≥ 3.7
- `uv` package manager
- Rust / Cargo (for `smugglex`)
- GNU coreutils, getopt, sed (macOS only via Homebrew)
- ~5GB free disk space for Go cache, tools, and repos
- ~1GB RAM minimum (Go compilation)
- Base image: `ubuntu:24.04`
- Build arg `INSTALL_AXIOM=true` (default) installs axiom fleet tooling
- Ports 85-90 exposed (for headless browser tooling)
- Runs as root (required for raw socket operations by some tools)
- Health check: `./reconftw.sh --health-check`
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Shell Settings
## Source Guard Pattern
- `lib/common.sh`: `[[ -n "$_COMMON_SH_LOADED" ]] && return 0`
- `lib/parallel.sh`: `[[ -n "$_PARALLEL_SH_LOADED" ]] && return 0`
- `lib/ui.sh`: `[[ -n "${_UI_SH_LOADED:-}" ]] && return 0`
## Function Naming
- Public module functions: `snake_case` prefixed with module context (`sub_passive`, `sub_crt`, `geo_info`)
- Private helpers: `_snake_case` prefix (`_print_status`, `_print_error`, `_print_module_start`, `_parallel_emit_job_output`)
- UI layer: `ui_` prefix (`ui_init`, `ui_header`, `ui_summary`, `ui_batch_end`)
- Lifecycle wrappers: `start_func` / `end_func` (call these at top/bottom of every recon function)
- Validation functions: `validate_*` / `sanitize_*` (defined in `lib/validation.sh` and `modules/utils.sh`)
## Variable Naming
- Config flags: `SUBPASSIVE`, `SUBCRT`, `PARALLEL_MODE`, `OUTPUT_VERBOSITY`
- Runtime state: `LOGFILE`, `SCRIPTPATH`, `DIFF`, `DRY_RUN`, `AXIOM`
- Error codes: `E_SUCCESS=0`, `E_INVALID_DOMAIN=20`, `E_INVALID_IP=21` (readonly, defined in `lib/validation.sh`)
## CLI Flag Pattern
## Output / UI Conventions
- `OUTPUT_VERBOSITY=0` (quiet): only errors/FAIL printed
- `OUTPUT_VERBOSITY=1` (normal, default): OK/WARN/FAIL/SKIP status lines
- `OUTPUT_VERBOSITY=2` (verbose): all of the above + INFO messages + start_func messages
## Function Lifecycle (start_func / end_func)
- `start_func name desc` — logs to LOGFILE, sets per-function start timestamp, emits INFO at verbosity >= 2
- `end_func message name [status]` — touches checkpoint file, calculates elapsed time, calls `_print_status`
- `skip_notification reason` — emits SKIP/CACHE badge; reasons: `"disabled"`, `"mode"`, `"processed"`, `"processed-visible"`, `"noinput"`
## File Checkpointing (Resumability)
- `end_func` creates the checkpoint: `touch "$called_fn_dir/.${fn}"`
- DIFF mode (`DIFF=true`) bypasses checkpoint — forces re-execution
- Helper `should_run()` in `lib/common.sh` provides a cleaner gate: `if should_run "FLAG_VAR"; then`
## Error Handling
- `E_SUCCESS=0`, `E_GENERAL=1`, `E_MISSING_DEP=2`, `E_INVALID_INPUT=3`
## Validation Functions
| Function | Purpose |
|----------|---------|
| `validate_domain()` | RFC domain check + injection character rejection |
| `validate_ipv4()` | Octet range validation |
| `validate_integer()` | Numeric range check |
| `validate_boolean()` | Accepts `true`/`false` only (not `1`/`0`/`yes`/`no`) |
| `validate_file_readable()` | Exists + readable + is-a-file |
| `sanitize_interlace_input()` | Removes shell metacharacters from input files (canonical in `lib/validation.sh`) |
| `sanitize_domain()` | Strips URL components, lowercases, rejects injection (in `modules/utils.sh`) |
| `is_in_scope_host()` | Anchored hostname scope check (prevents substring false positives) |
| `filter_in_scope_urls()` | Python3-based URL scope check (scheme, userinfo, host) |
## Path and CWD Conventions
## Parallel Execution
## Import / Sourcing Order
## Logging
- All tool output redirected to `$LOGFILE`: `command ... 2>>"$LOGFILE" >/dev/null`
- Structured JSON logging via `log_json level func message [key=val]` (optional, `STRUCTURED_LOGGING=true`)
- `redact_secrets()` scrubs `REDACT_VARS` and `REGISTERED_SECRETS` from log lines
- `register_secret "$value"` must be called before logging any secret value
## Comments
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
```text
```
## Component Responsibilities
| Component | Responsibility | File |
|-----------|----------------|------|
| Entry point & CLI parser | getopt argument parsing, config sourcing, mode dispatch | `reconftw.sh` |
| Mode orchestration | `start`/`end`, workflow functions (`recon`, `passive`, `all`, `vulns`, `osint`, `subs_menu`, `webs_menu`, `zen_menu`, `monitor_mode`) | `modules/modes.sh` |
| Function lifecycle | `start_func`/`end_func`, checkpointing, logging, notifications, reporting, plugins, health check | `modules/core.sh` |
| Subdomain enumeration | All `sub_*` functions, `subtakeover`, `zonetransfer`, `s3buckets`, `geo_info` | `modules/subdomains.sh` |
| Web analysis | `webprobe_full`, `screenshot`, `nuclei_check`, `fuzz`, `jschecks`, `urlchecks`, `waf_checks`, and 20+ others | `modules/web.sh` |
| Vulnerability scanning | `xss`, `ssrf_checks`, `sqli`, `crlf_checks`, `lfi`, `ssti`, `smuggling`, `fuzzparams`, `nuclei_dast`, and others | `modules/vulns.sh` |
| OSINT collection | `domain_info`, `ip_info`, `emails`, `google_dorks`, `github_leaks`, `github_actions_audit`, `cloud_enum_scan`, etc. | `modules/osint.sh` |
| Shared utilities | `run_command`, `sed_i`, `deleteOutScoped`, `validate_config`, `cache_*`, `checkpoint_*`, `circuit_breaker_*`, rate-limit adaption | `modules/utils.sh` |
| Axiom/distributed mode | `axiom_launch`, `axiom_shutdown`, `axiom_selected`, `resolvers_update`, `ipcidr_target` | `modules/axiom.sh` |
| Parallel execution | `parallel_funcs`, `_throttle_jobs`, job heartbeat, progress live display, log mode output | `lib/parallel.sh` |
| Input validation/sanitization | `sanitize_domain`, `sanitize_ip`, `validate_domain`, `validate_integer`, `_sanitize_list_entry` | `lib/validation.sh` |
| Shared file/counter utilities | `ensure_dirs`, `ensure_webs_all`, `safe_backup`, `count_lines`, incident tracking | `lib/common.sh` |
| UI presentation layer | `_print_status`, `_print_msg`, `_print_section`, `_print_rule`, `ui_header`, `ui_summary`, TTY detection, color management, JSONL output | `lib/ui.sh` |
| Configuration | All runtime settings (~350 variables); sourced after CLI parse | `reconftw.cfg` |
## Pattern Overview
- Single process: `reconftw.sh` sources all libraries and modules at startup; every function lives in the same shell environment
- No subshell isolation between modules — all state is shared via global variables
- File-based checkpointing: `called_fn_dir/.funcname` sentinel files prevent re-running completed functions across invocations
- CLI-over-config: `reconftw.cfg` provides defaults; CLI flags set `CLI_*` variables that are re-applied after config sourcing to guarantee they cannot be overwritten
- All external tool invocations go through `run_command()` which handles dry-run mode, adaptive rate limiting, axiom dispatch, and debug logging
## Layers
- Purpose: Bootstrap, macOS re-exec, module loading, getopt CLI parsing, config sourcing, CLI override re-application, mode dispatch
- Location: `reconftw.sh`
- Contains: `normalize_vps_count_args()`, the main `while/case` getopt loop, the config `source` sequence, CLI override if-blocks, the final `case $opt_mode` dispatch
- Depends on: All libraries (sourced first), all modules (sourced second)
- Used by: End user / CI
- Purpose: Reusable utilities with no side effects; loadable independently for tests
- Location: `lib/validation.sh`, `lib/common.sh`, `lib/ui.sh`, `lib/parallel.sh`
- Contains: Input sanitization, file helpers, UI/color/progress, parallel job management
- Depends on: Nothing (source-guarded with `_*_LOADED` pattern)
- Used by: All modules and reconftw.sh
- Purpose: Implement all scanning, analysis, and orchestration functions
- Location: `modules/`
- Contains: All recon, vuln, OSINT, web, subdomain functions
- Depends on: Libraries (always loaded first), `reconftw.cfg` variables, external tools on PATH
- Used by: modes.sh orchestrates all others; reconftw.sh dispatches to modes.sh
- Purpose: Default runtime values for ~350 flags/paths/limits; can be overridden by `secrets.cfg` and custom config
- Location: `reconftw.cfg`, optionally `secrets.cfg`, optionally `$CUSTOM_CONFIG`
- Contains: Module enable/disable flags, tool flags, API key env-var references, paths, parallelism settings, verbosity, Axiom settings
- Depends on: Nothing
- Used by: Sourced by `reconftw.sh` between CLI parse and CLI override re-application
- Purpose: Store per-target findings in a stable directory hierarchy
- Location: `Recon/<domain>/` (created at `start()` time by `modules/modes.sh`)
- Contains: Standard subdirectories listed below
- Depends on: `start()` in modes.sh creates the directory tree
## Data Flow
### Primary Recon Request Path (`-r` / `--recon`)
### Function Execution Path (every leaf module function)
### Parallel Execution Path
### Axiom Distributed Scan Flow
- Global bash variables throughout (no encapsulation). Config vars, target vars (`domain`, `dir`, `called_fn_dir`, `LOGFILE`), and result counters are all globals
- `passive()` saves/restores module-enable globals before overriding them (`modules/modes.sh:549-611`)
## Key Abstractions
- Purpose: Lifecycle wrapper around every leaf scanning function
- Examples: Used in every function in `modules/subdomains.sh`, `modules/web.sh`, `modules/vulns.sh`, `modules/osint.sh`
- Pattern: `start_func "${FUNCNAME[0]}" "description"` at top; `end_func "output path" "${FUNCNAME[0]}"` at bottom; creates checkpoint file on end
- Purpose: Prevent re-running completed functions across multiple invocations of the same target
- Location: `Recon/<domain>/.called_fn/.funcname`
- Pattern: Each function tests `[[ ! -f "$called_fn_dir/.${FUNCNAME[0]}" ]] || [[ $DIFF == true ]]`; `end_func` writes the sentinel via `touch "$called_fn_dir/.${fn}"`
- Purpose: Universal external-tool gate for dry-run preview, axiom dispatch, adaptive rate limiting, and debug logging
- Location: `modules/utils.sh:468`
- Pattern: All tool calls inside module functions use `run_command <binary> <args>` rather than direct invocation
- Purpose: Allow modules to be sourced multiple times (test re-sourcing, `--source-only`) without re-executing
- Pattern: `[[ -n "$_FOO_LOADED" ]] && return 0` at top of each lib file (`lib/common.sh:6`, `lib/parallel.sh:6`, `lib/ui.sh:5`, `lib/validation.sh` — validation uses error-code guards instead)
- Purpose: Run independent module functions concurrently up to `PARALLEL_MAX_JOBS`
- Pattern: `parallel_funcs N func_a func_b func_c` — each function spawned as a background subshell; used in `recon()`, `osint()`, `vulns()` for independent groups
- Purpose: Transparent axiom/local fallback wrapper — if axiom fails during a module, retries locally
- Location: `modules/modes.sh:656`
- Pattern: All module calls inside `subs_menu`, `webs_menu`, `recon`, `passive` use this wrapper
## Entry Points
- Location: `reconftw.sh`
- Triggers: Direct execution (`./reconftw.sh -d example.com -r`)
- Responsibilities: Bootstrap, all module loading, CLI parse, config source, mode dispatch
- Location: `reconftw.sh:123-125`
- Triggers: `./reconftw.sh --source-only` (used by bats test `setup()` blocks)
- Responsibilities: Sources all modules without executing any recon
- Location: `modules/modes.sh:13`
- Triggers: Called at the top of most workflow functions (`recon`, `subs_menu`, `passive`, `osint`, `zen_menu`)
- Responsibilities: Create output directory tree, init LOGFILE, init cache/incremental/DNS/plugins, set global `dir` and `called_fn_dir`
- Location: `modules/modes.sh:286`
- Triggers: Called at the bottom of most workflow functions
- Responsibilities: AI report, cleanup, Faraday, screenshot diffs, plugin events, hotlist, `export_reports()`, timing summary
## Output Directory Structure
```
```
## Verbosity and Output Controls
- `0` (quiet): Only errors and final summary printed to terminal; banner suppressed
- `1` (normal, default): Errors + warnings printed; `notification()` info/good suppressed
- `2` (verbose): All `notification()` calls, PID info, full parallel output, `start_func` messages, `print_timing_summary`
- `summary`: One badge line per completed parallel job
- `tail`: Last `PARALLEL_TAIL_LINES` (default 20, doubled on failure) from each job's log
- `full`: Complete captured stdout from each job
- `jsonl-strict`: Forces `OUTPUT_VERBOSITY=0`, emits only machine-readable JSONL
## Architectural Constraints
- **Threading:** Single-threaded bash with optional background subshells via `parallel_funcs`; `wait -n` (bash 4.3+) used for job throttling in `_throttle_jobs`
- **Global state:** All config vars, `domain`, `dir`, `called_fn_dir`, `LOGFILE`, `start`, `runtime`, `DIFF`, `AXIOM`, and hundreds of module-enable flags are module-level globals; any sourced function can read or mutate them
- **Circular imports:** None by design — reconftw.sh sources libs first, then modules in explicit dependency order (`utils.sh` → `core.sh` → `osint.sh` → `subdomains.sh` → `web.sh` → `vulns.sh` → `axiom.sh` → `modes.sh`)
- **macOS bash version:** reconftw.sh re-execs itself under Homebrew bash ≥ 4 on macOS (system bash is 3.2); `lib/parallel.sh` requires bash 4.3+ for `wait -n`
- **Working directory:** `start()` calls `cd "$dir"` (the per-target output dir) before any module function runs; all relative paths inside modules resolve against the target dir. `reconftw.sh` captures `startdir=${PWD}` before this
- **No subshell isolation per module:** Modules are sourced functions, not subprocess commands. A `return` inside a module returns from the function; an `exit` would kill the whole shell
## Anti-Patterns
### Direct external tool calls without `run_command`
### Writing checkpoint files manually
### Skipping the `[[ ! -f "$called_fn_dir/.${FUNCNAME[0]}" ]] || [[ $DIFF == true ]]` guard
### Overriding config globals without save/restore in workflow functions
## Error Handling
- ERR trap in `start()` logs function name, line number, and command to `$LOGFILE` and calls `explain_err()` (`modules/modes.sh:140`)
- Non-zero exit from `parallel_funcs` increments `RECON_OSINT_PARALLEL_FAILURES` and sets `RECON_PARTIAL_RUN=true`
- `run_module_with_axiom_failover` catches axiom mid-run failures and retries locally
- Circuit-breaker helpers (`circuit_breaker_is_open`, `circuit_breaker_record_failure`) in `modules/utils.sh:1190` for persistent tool failures
## Cross-Cutting Concerns
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
