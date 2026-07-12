# Codebase Structure

**Analysis Date:** 2026-05-13

## Directory Layout

```
reconftw/
├── reconftw.sh              # Main entry point, CLI parser, module loader, mode dispatch
├── reconftw.cfg             # Runtime configuration (~350 vars, sourced after CLI parse)
├── secrets.cfg.example      # Template for gitignored secrets.cfg (API keys, tokens)
├── install.sh               # Tool installer (~59k lines, standalone)
├── banners.txt              # ASCII art banner definitions (sourced by core.sh banner_grabber)
├── Makefile                 # Dev targets: lint, test, format, install
│
├── lib/                     # Pure utility libraries (no recon logic)
│   ├── validation.sh        # Input sanitization: sanitize_domain, sanitize_ip, validate_*
│   ├── common.sh            # File/dir helpers, incident tracking, count_lines
│   ├── ui.sh                # TTY detection, color management, _print_status/_print_msg, progress
│   └── parallel.sh          # parallel_funcs, _throttle_jobs, live progress, job output modes
│
├── modules/                 # Recon modules (sourced in dependency order)
│   ├── utils.sh             # run_command, validate_config, cache_*, checkpoint_*, rate-limit
│   ├── core.sh              # start_func/end_func, banner, tools_installed, logging, reporting
│   ├── osint.sh             # domain_info, emails, github_leaks, cloud_enum_scan, etc.
│   ├── subdomains.sh        # sub_passive, sub_brute, sub_permut, subtakeover, zonetransfer, etc.
│   ├── web.sh               # webprobe_full, screenshot, nuclei_check, fuzz, jschecks, etc.
│   ├── vulns.sh             # xss, sqli, ssrf_checks, lfi, ssti, smuggling, nuclei_dast, etc.
│   ├── axiom.sh             # axiom_launch, axiom_shutdown, axiom_selected, resolvers_update
│   └── modes.sh             # start, end, recon, passive, all, osint, vulns, subs_menu,
│                            #   webs_menu, zen_menu, multi_recon, monitor_mode, help
│
├── config/                  # Static data files read by reconftw.cfg
│   ├── reconftw_full.cfg    # Extended config preset (DEEP/all enabled)
│   ├── reconftw_quick.cfg   # Quick-scan config preset
│   ├── reconftw_stealth.cfg # Stealth config preset (passive-heavy)
│   ├── sensitive_domains.txt # Domains excluded when EXCLUDE_SENSITIVE=true
│   ├── ssrf_payloads.txt    # SSRF payload list for ssrf_checks()
│   ├── tls_ports.txt        # TLS ports used by sub_tls() (read into TLS_PORTS var)
│   └── uncommon_ports_web.txt # Non-standard web ports (read into UNCOMMON_PORTS_WEB var)
│
├── data/                    # Wordlists and pattern files
│   ├── wordlists/           # Bundled wordlist files for brute-forcing, fuzzing
│   └── patterns/            # Pattern files for URL classification (used by url_gf)
│
├── tests/                   # Test suite
│   ├── unit/                # bats unit tests (25 files)
│   ├── security/            # bats security/integration tests (14 files)
│   ├── fixtures/            # Static test fixture files
│   ├── helpers/             # Shared bats helper scripts
│   ├── mocks/               # Mock tool stubs for isolated unit testing
│   ├── run_tests.sh         # Test runner wrapper
│   ├── check_artifacts.sh   # Verify expected output files exist after a run
│   └── check_artifacts_all.sh
│
├── Recon/                   # Runtime output root (created if missing)
│   └── <domain>/            # Per-target output tree (created by start() in modes.sh)
│
├── Docker/                  # Dockerfile and docker-compose definitions
├── Terraform/               # Cloud provisioning for Axiom/VPS infrastructure
├── Proxmox/                 # Proxmox VM provisioning scripts
├── documentation/           # Extended docs (tool explanations, workflow diagrams)
├── docs/                    # mkdocs or similar documentation source
├── images/                  # Screenshots used in README.md
├── .cache/                  # Runtime cache (resolvers, wordlists, tool metadata; gitignored)
│   ├── resolvers/
│   ├── tools/
│   └── wordlists/
├── .github/                 # GitHub Actions workflows and issue templates
├── .planning/               # GSD planning artifacts (codebase maps, phase plans)
└── .venv/                   # Python virtualenv for getjswords.py and similar tools
```

## Directory Purposes

**`lib/`:**
- Purpose: Pure, reusable utilities with no recon side effects; safe to source in test harnesses
- Contains: 4 files: `validation.sh`, `common.sh`, `ui.sh`, `parallel.sh`
- Key files: `lib/ui.sh` (all terminal output primitives), `lib/parallel.sh` (all parallel job management)
- Source order: loaded first in `reconftw.sh` before any modules

**`modules/`:**
- Purpose: All reconnaissance, analysis, and orchestration logic
- Contains: 8 files loaded in strict dependency order: `utils.sh` → `core.sh` → `osint.sh` → `subdomains.sh` → `web.sh` → `vulns.sh` → `axiom.sh` → `modes.sh`
- Key files: `modules/core.sh` (function lifecycle), `modules/modes.sh` (all workflow orchestration), `modules/subdomains.sh` (largest enumeration module, 2406 lines)

**`config/`:**
- Purpose: Static configuration presets and data tables; machine-readable by reconftw.cfg
- Contains: 3 cfg preset files (full/quick/stealth), 4 data text files (sensitive_domains, ssrf_payloads, tls_ports, uncommon_ports_web)
- Usage: Preset cfgs passed via `-f config/reconftw_quick.cfg`; data files loaded with `cat ... | tr -d '\n'` in `reconftw.cfg`

**`data/`:**
- Purpose: Bundled wordlists and URL-pattern files shipped with the tool
- Contains: `wordlists/` (brute-force and fuzzing lists), `patterns/` (gf pattern files for url_gf)
- Referenced via `WORDLISTS_DIR="${DATA_DIR}/wordlists"` and `PATTERNS_DIR="${DATA_DIR}/patterns"` set in `reconftw.cfg`

**`tests/`:**
- Purpose: Automated test suite using the bats framework
- Contains: Unit tests (`tests/unit/`), security/integration tests (`tests/security/`), fixtures, helpers, mocks
- Run with: `bats tests/unit/` or `bats tests/security/` or `make test`

**`Recon/`:**
- Purpose: Runtime output root; all per-target output directories are created here
- Contains: Per-domain subdirectories created by `start()` in `modules/modes.sh`
- Generated: Yes, created at runtime
- Committed: Only example outputs committed to repo for illustration

**`.cache/`:**
- Purpose: Resolver lists and wordlist caches managed by `cache_init`/`cache_clean`/`cached_download_typed` in `modules/utils.sh`
- Contains: Downloaded resolver files, wordlists, tool metadata
- Generated: Yes
- Committed: No (in `.gitignore`)

## Key File Locations

**Entry Points:**
- `reconftw.sh`: Main executable; source all libs/modules, parse CLI, dispatch to modes

**Configuration:**
- `reconftw.cfg`: All default settings; sourced at `reconftw.sh:497`
- `secrets.cfg` (gitignored): API keys and tokens; auto-sourced if present at `reconftw.sh:503`
- `config/reconftw_quick.cfg`, `config/reconftw_full.cfg`, `config/reconftw_stealth.cfg`: Preset profiles

**Core Logic:**
- `modules/modes.sh`: Workflow entry points (`start`, `end`, `recon`, `all`, `passive`, `osint`, etc.)
- `modules/core.sh`: `start_func`, `end_func`, `notification`, `generate_consolidated_report`, `export_reports`, `health_check`
- `modules/utils.sh`: `run_command`, `validate_config`, cache helpers, circuit breaker, checkpoint system

**Testing:**
- `tests/unit/`: 25 bats test files covering specific functions
- `tests/security/`: 14 bats test files covering injection, redaction, scope, full-flow smoke tests
- `tests/run_tests.sh`: Convenience runner

**Documentation:**
- `README.md`: Primary end-user documentation
- `CONTRIBUTING.md`: Contributor guide
- `CHANGELOG.md`: Version history
- `documentation/`: Extended per-module documentation

## Naming Conventions

**Files:**
- Module scripts: lowercase `<module>.sh` in `modules/` (e.g., `subdomains.sh`, `vulns.sh`)
- Library scripts: lowercase `<name>.sh` in `lib/` (e.g., `common.sh`, `ui.sh`)
- Config preset files: `reconftw_<profile>.cfg` in `config/`
- Test files: `test_<subject>.bats` in `tests/unit/` and `tests/security/`

**Functions:**
- Leaf recon functions: `lowercase_snake_case` matching the subject tool or technique (e.g., `sub_passive`, `webprobe_full`, `github_leaks`, `nuclei_check`)
- Lifecycle functions: `start_func` / `end_func` / `start_subfunc` / `end_subfunc`
- Internal helpers with underscore prefix: `_subdomains_init`, `_subdomains_enumerate`, `_print_status`, `_throttle_jobs`
- Workflow orchestrators: verb-noun or noun-only (`recon`, `passive`, `subs_menu`, `webs_menu`, `all`, `osint`, `vulns`)

**Configuration Variables:**
- Module enable/disable flags: `UPPERCASE_SCREAMING_SNAKE_CASE` (e.g., `SUBPASSIVE=true`, `VULNS_GENERAL=false`)
- Tool-specific settings: `TOOLNAME_SETTING` (e.g., `NUCLEI_SEVERITY`, `FFUF_RATELIMIT`, `PUREDNS_PUBLIC_LIMIT`)
- CLI override intermediates: `CLI_` prefix (e.g., `CLI_OUTPUT_VERBOSITY`, `CLI_PARALLEL_MODE`, `CLI_AXIOM_FLEET_COUNT`)
- Parallel batch sizing: `PAR_MODULE_GROUP_SIZE` (e.g., `PAR_OSINT_GROUP1_SIZE`, `PAR_VULNS_GROUP2_SIZE`)

## Where to Add New Code

**New leaf recon function (e.g., a new scanning tool):**
- Implementation: Add `function my_tool()` in the relevant module — `modules/subdomains.sh` for enumeration, `modules/web.sh` for web analysis, `modules/vulns.sh` for vuln checks, `modules/osint.sh` for OSINT
- Pattern: Open with checkpoint guard `if [[ ! -f "$called_fn_dir/.${FUNCNAME[0]}" ]] || [[ $DIFF == true ]]; then`, call `start_func "${FUNCNAME[0]}" "Description"`, use `run_command <tool>`, call `end_func "output path" "${FUNCNAME[0]}"`. Close with `fi`.
- Config flag: Add `MYTOOL=true` to `reconftw.cfg`; guard function body with `&& [[ $MYTOOL == true ]]`
- Wiring: Add call to `recon()` or appropriate workflow function in `modules/modes.sh`; wrap with `run_module_with_axiom_failover my_tool` or include in a `parallel_funcs` group

**New workflow mode:**
- Implementation: Add a new `function mymode()` in `modules/modes.sh` following the `start()` / module-calls / `end()` pattern
- Wiring: Add a new `opt_mode` letter and CLI flag in `reconftw.sh` getopt string and `while/case` loop; add the mode dispatch case in the final `case $opt_mode` block

**New configuration variable:**
- Add to `reconftw.cfg` with a descriptive inline comment
- If it can be set via CLI, add a `CLI_MYVAR=""` pre-parse init, a `--my-flag` option to the getopt string, a `case` arm in the CLI parse loop that sets `CLI_MYVAR`, and a re-application block after config sourcing (`reconftw.sh:513-578` pattern)

**New utility function:**
- Pure utilities (no recon side effects, usable in tests): Add to `lib/common.sh`
- Input validation/sanitization: Add to `lib/validation.sh`
- UI/display: Add to `lib/ui.sh`
- Recon-specific helpers used across multiple modules: Add to `modules/utils.sh`

**New test:**
- Unit test for a utility/lib function: Add `test_<subject>.bats` to `tests/unit/`
- Security or integration test: Add `test_<subject>.bats` to `tests/security/`
- Tests source the full script via `source "$project_root/reconftw.sh" --source-only` in the `setup()` block (see `tests/unit/test_utils.bats:17`)

## Special Directories

**`Recon/<domain>/`:**
- Purpose: Complete per-target output for a recon run
- Generated: Yes (created by `start()` in `modules/modes.sh:92`)
- Committed: No (example directories exist in repo for illustration only)
- Subdirectories created at start time: `.log`, `.tmp`, `webs`, `hosts`, `vulns`, `osint`, `screenshots`, `subdomains`

**`Recon/<domain>/.called_fn/`:**
- Purpose: Checkpoint sentinel files (`.funcname`) that prevent function re-execution on subsequent runs
- Generated: Yes
- Committed: No
- Cleared by: `--force` flag removes all sentinels; `DIFF=true` causes functions to run regardless

**`Recon/<domain>/.tmp/`:**
- Purpose: Intermediate working files used within and between module functions
- Generated: Yes
- Committed: No
- Cleaned by: `REMOVETMP=true` config option calls `rm -rf -- "$dir/.tmp"` in `end()`

**`Recon/<domain>/.incremental/`:**
- Purpose: State files for incremental/monitor mode (baseline snapshots, alert fingerprints)
- Generated: Yes, when `INCREMENTAL_MODE=true` or `--monitor`
- Committed: No

**`.cache/`:**
- Purpose: Cached resolvers and wordlists managed by `cache_init`/`cached_download_typed` in `modules/utils.sh`
- Generated: Yes
- Committed: No (gitignored)
- Cleaned by: `cache_clean "$CACHE_MAX_AGE_DAYS"` called in `start()`

**`plugins/` (optional, not committed):**
- Purpose: User-supplied shell scripts sourced at `start()` time via `plugins_load()`; receive `reconftw_plugins start|end domain dir` events
- Generated: User-created
- Committed: No (not in default repo; users create this directory)

---

*Structure analysis: 2026-05-13*
