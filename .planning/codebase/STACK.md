# Technology Stack

**Analysis Date:** 2026-05-13

## Languages

**Primary:**
- Bash 4+ - All core framework logic (`reconftw.sh`, `modules/*.sh`, `lib/*.sh`, `install.sh`)
  - Requires Bash ≥ 4 (uses `mapfile`, associative arrays, `wait -n`)
  - macOS ships Bash 3; installer auto-re-execs with Homebrew Bash 4+ via `/opt/homebrew/bin/bash` or `/usr/local/bin/bash`
  - `set -o pipefail`, `set -E`, `set +e`, `IFS=$'\n\t'` used throughout

**Secondary:**
- Python 3.7+ - Python-backed tools (each runs in isolated `uv venv`): `dorks_hunter`, `CMSeeK`, `EmailHarvester`, `Spoofy`, `SSTImap`, `gato`, `regulator`, `reconftw_ai`, `getjswords.py`
- Go (latest, min ~1.21) - Primary binary language for ~55 security tools installed via `go install @latest`

## Runtime

**Environment:**
- Linux (Debian/Ubuntu/RHEL/Arch) or macOS (Apple Silicon / Intel)
- Docker: Ubuntu 24.04 base image (`Docker/Dockerfile`)
- ARM64/aarch64, ARMv6l/v7l, and x86_64 all supported for Go binary installs

**Shell Features Used:**
- `getopt` (GNU getopt required on macOS via `brew install gnu-getopt`)
- `nproc` / `sysctl -n hw.ncpu` for CPU core auto-detection
- `timeout` / `gtimeout` (macOS Homebrew `coreutils`)
- `gnu-sed` (macOS requires `brew install gnu-sed`)
- `gnu-coreutils` (macOS requires `brew install coreutils`)

**Package Manager:**
- Go tools: `go install` (`GOPATH=$HOME/go`, `GOROOT=/usr/local/go`)
- Python tools: `uv tool install` from GitHub (most) or PyPI (`fray`)
- Python repo venvs: `uv venv venv && uv pip install -r requirements.txt`
- Lockfile: None (always installs `@latest`)

## Frameworks

**Core:**
- No framework — pure Bash with sourced module files
- Module loading order: `lib/validation.sh` → `lib/common.sh` → `lib/ui.sh` → `lib/parallel.sh` → `modules/utils.sh` → `modules/core.sh` → `modules/osint.sh` → `modules/subdomains.sh` → `modules/web.sh` → `modules/vulns.sh` → `modules/axiom.sh` → `modules/modes.sh`

**Testing:**
- bats-core (Bash Automated Testing System)
  - 25 unit test files: `tests/unit/*.bats`
  - 3 security test files: `tests/security/*.bats`
  - Run: `bats tests/unit/`, `bats tests/security/*.bats`

**Build/Dev:**
- GNU make (`Makefile`) — test, lint, format targets
- shellcheck (error-level) — `make lint`, pre-commit hook
- shfmt (4-space indent, `-bn`, `-ci`) — `make fmt`, pre-commit hook
- pre-commit hooks defined in `.pre-commit-config.yaml`
- semgrep: `.github/workflows/semgrep.yml` (CI only)

## Key Dependencies

### Go Tools (installed via `go install @latest`)

**Subdomain Enumeration:**
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

**HTTP / Web Probing:**
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

**Vulnerability Detection:**
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

**OSINT / Recon:**
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

**Spraying / Auth:**
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

**Primary Config:**
- `reconftw.cfg` — sourced after CLI parsing; all feature flags, rate limits, timeouts, wordlist paths, API keys, thread counts
- `secrets.cfg` (gitignored, auto-sourced) — API keys and tokens separated from main config
- `secrets.cfg.example` — template showing all supported secret vars

**Config Structure:**
- Feature flags: `OSINT=true`, `SUBDOMAINS_GENERAL=true`, `VULNS_GENERAL=false`, etc.
- Rate limits: `HTTPX_RATELIMIT=150`, `NUCLEI_RATELIMIT=150`, `FFUF_RATELIMIT=0`
- Thread counts: auto-scaled via `AVAILABLE_CORES=$(nproc)` with multipliers per tool
- Timeouts: per-tool in seconds or minutes (`CMSSCAN_TIMEOUT=3600`, `SUBFINDER_ENUM_TIMEOUT=180`)
- Wordlist paths: `fuzz_wordlist`, `lfi_wordlist`, `subs_wordlist` etc. under `${WORDLISTS_DIR}`
- Output: `EXPORT_FORMAT`, `AI_REPORT_TYPE`, `ASSET_STORE`

**CLI Flag Parsing:**
- GNU `getopt` long options, parsed in `reconftw.sh` while/case loop
- All CLI overrides use `CLI_*` pattern and are re-applied after `reconftw.cfg` is sourced
- Full list from `getopt` call: `domain`, `list`, `recon`, `subdomains`, `passive`, `all`, `web`, `osint`, `zen`, `deep`, `help`, `vps`, `vps-count`, `ai`, `check-tools`, `health-check`, `quick-rescan`, `incremental`, `adaptive-rate`, `dry-run`, `parallel`, `no-parallel`, `monitor`, `monitor-interval`, `monitor-cycles`, `refresh-cache`, `gen-resolvers`, `force`, `export`, `report-only`, `no-report`, `parallel-log`, `quiet`, `verbose`, `no-color`, `log-format`, `show-cache`, `banner`, `no-banner`, `legal`

**Environment Variables:**
- `SHODAN_API_KEY`, `WHOISXML_API`, `PDCP_API_KEY`, `XSS_SERVER`, `COLLAB_SERVER` — preferred over config file
- `GOROOT`, `GOPATH`, `PATH` — extended by `reconftw.cfg` for Go and Rust binaries
- `LOGFILE` — per-target log path

**Config Presets:**
- `config/reconftw_full.cfg` — full-scan preset
- `config/reconftw_quick.cfg` — quick-scan preset
- `config/reconftw_stealth.cfg` — low-noise preset

## Build

**Go Version:**
- Default: `go1.23.6` (fetches latest from `https://go.dev/VERSION?m=text`)
- Installed to `/usr/local/go`; set `install_golang=false` in config to skip

**Python Version:**
- Minimum: Python 3.7 (enforced in `install_yum()`)
- Virtual environments per tool via `uv venv`
- Root venv at `.venv/` for `getjswords.py` and similar helpers

## Platform Requirements

**Development (Linux/macOS):**
- Bash ≥ 4.3 (for `wait -n` used in `lib/parallel.sh`)
- Go ≥ 1.21 (tools use SIV module paths like `/v2`, `/v3`)
- Python ≥ 3.7
- `uv` package manager
- Rust / Cargo (for `smugglex`)
- GNU coreutils, getopt, sed (macOS only via Homebrew)
- ~5GB free disk space for Go cache, tools, and repos
- ~1GB RAM minimum (Go compilation)

**Production (Docker):**
- Base image: `ubuntu:24.04`
- Build arg `INSTALL_AXIOM=true` (default) installs axiom fleet tooling
- Ports 85-90 exposed (for headless browser tooling)
- Runs as root (required for raw socket operations by some tools)
- Health check: `./reconftw.sh --health-check`

---

*Stack analysis: 2026-05-13*
