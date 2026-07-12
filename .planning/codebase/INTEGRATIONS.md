# External Integrations

**Analysis Date:** 2026-05-13

## APIs & External Services

### Passive Subdomain Intelligence

- **subfinder** — aggregates many passive sources (configured via `~/.config/subfinder/provider-config.yaml`)
  - Supported providers include: SecurityTrails, VirusTotal, Shodan, Censys, BinaryEdge, BEVigil, Chaos/ProjectDiscovery, FOFA, ZoomEye, C99, Fullhunt, IntelX, Netlas, and others
  - Auth: each source's API key in subfinder's own config file (not reconftw.cfg)
- **crt.sh** — certificate transparency log search
  - Used in: `modules/subdomains.sh` (`sub_crt()`)
  - Query: `https://crt.sh/?q=%25.${domain}&output=json`
  - Optional time-fence filter: `DNS_TIME_FENCE_DAYS`
- **ip.thc.org** — subdomain enumeration endpoint
  - Used in: `modules/subdomains.sh` (`sub_passive()`)
  - Query: `https://ip.thc.org/sb/$domain`
- **BuildWith** — Google Analytics relationships
  - Indirectly via `analyticsrelationships` tool

### Host Intelligence & Port Data

- **Shodan** — passive port scan and internet scan data
  - Used in: `modules/web.sh` (`portscanner()`)
  - API: `https://internetdb.shodan.io/${ip}` (free tier, no key) and optional Shodan CLI
  - Auth: `SHODAN_API_KEY` env var or `reconftw.cfg`; Shodan CLI installed via `uv tool install shodan`
  - Also sourced by `smap` (passive Shodan-powered port scan tool)

### Domain & IP Intelligence

- **WhoisXML API** — reverse IP lookup, WHOIS data, IP geolocation
  - Used in: `modules/osint.sh` (`ip_info()`)
  - Endpoints:
    - `https://reverse-ip.whoisxmlapi.com/api/v1?apiKey=...`
    - `https://www.whoisxmlapi.com/whoisserver/WhoisService?apiKey=...`
    - `https://ip-geolocation.whoisxmlapi.com/api/v1?apiKey=...`
  - Auth: `WHOISXML_API` env var or `reconftw.cfg`; skipped if unset

### ProjectDiscovery Cloud Platform (PDCP)

- Used by `asnmap` for ASN-to-CIDR enumeration
  - Used in: `modules/subdomains.sh` (`sub_asn()`)
  - Auth: `PDCP_API_KEY` env var or `reconftw.cfg`; enumeration skipped if key absent

## GitHub API Usage

### Authentication

- Tokens stored one-per-line in `$HOME/Tools/.github_tokens` (`GITHUB_TOKENS` config var)
- GitLab tokens stored in `$HOME/Tools/.gitlab_tokens` (`GITLAB_TOKENS` config var)
- Tools rotate through multiple tokens to avoid rate limiting

### Tools Using GitHub Tokens

- **gitdorks_go** — GitHub code search dork automation
  - Uses `-tf "$GITHUB_TOKENS"` flag
  - Wordlists: `${tools}/gitdorks_go/Dorks/smalldorks.txt` (normal) / `medium_dorks.txt` (DEEP)
  - Configured: `GITHUB_DORKS=true`

- **github-subdomains** — subdomain discovery via GitHub search
  - Token file passed at runtime

- **github-endpoints** — endpoint extraction from GitHub repos

- **enumerepo** — GitHub org repository enumeration
  - Uses `-token-file` (temp file to avoid process list exposure)
  - Output parsed with `jq` for repo URLs

- **trufflehog** — secret scanning in cloned repos
  - Runs `trufflehog git <repo_url>` per discovered repository
  - Output: JSON per repo in `.tmp/github/`

- **ghleaks** — GitHub-wide organization-level secret search
  - Reads token from `$GITHUB_TOKENS`
  - Optional `--exhaustive` flag in DEEP mode

- **gato** — GitHub Actions artifact and workflow audit
  - Used in: `modules/osint.sh` (`github_actions_audit()`)
  - Args: `e --enum_wf_artifacts --skip_sh_runner_enum -O orgs.txt -oJ output.json`
  - Optional: `--include_all_artifact_secrets` controlled by `GATO_INCLUDE_ALL_ARTIFACT_SECRETS`
  - Auth: uses GITHUB_TOKENS

### Secrets Engine Selection

- `SECRETS_ENGINE="titus"` (default) or `"noseyparker"`
- `titus` (praetorian-inc) — Go binary, validates detected secrets against provider APIs when `SECRETS_VALIDATE=true`
- `noseyparker` — Rust binary, external dependency, must be in PATH

## Notification Integrations

All notifications are routed through **projectdiscovery/notify** with config at `~/.config/notify/provider-config.yaml`.

### Slack

- Config vars: `slack_channel`, `slack_auth` (Bearer token)
- Two paths:
  1. In-band via `notify` (uses YAML config)
  2. Direct file upload: `curl -F file=@${file} -F channels=${slack_channel} -H "Authorization: Bearer ${slack_auth}" https://slack.com/api/files.upload`
- Controlled by: `NOTIFICATION=true` or `SOFT_NOTIFICATION=true`, `SENDZIPNOTIFY=true`

### Telegram

- Config: YAML block under `telegram:` in `notify.conf` / provider-config.yaml
- API key: `telegram_api_key` field
- Chat ID: `telegram_chat_id` field
- Direct file send (>8MB): `curl -F document=@file https://api.telegram.org/bot${telegram_key}/sendDocument`
- Template in `Docker/notify.conf`

### Discord

- Config: YAML block under `discord:` in provider-config.yaml
- Webhook: `discord_webhook_url`
- Direct file upload via multipart POST to Discord webhook URL

### Burp Collaborator / Out-of-Band (OOB)

- For SSRF checks: `COLLAB_SERVER` env var points to a collaborator-like OOB server
- If unset, `interactsh-client` is launched automatically as fallback
- For blind XSS: `XSS_SERVER` passed to `dalfox -b` flag

### ProjectDiscovery Interactsh

- Used in: `modules/vulns.sh` (`ssrf_checks()`) when `COLLAB_SERVER` is unset
- Launched as background process: `interactsh-client &>.tmp/ssrf_callback.txt &`
- Provides `*.oast.fun` (or similar) domain for OOB callbacks

## Cloud & Distributed Scanning (Axiom / Ax Fleet)

Axiom provides distributed scanning across a fleet of cloud VPS instances.

### ax / axiom (attacksurge/ax)

- Installed to `/root/.axiom/` in Docker; uses SSH for fleet management
- Config: `~/.axiom/axiom.json`, `~/.axiom/configs/`, `~/.axiom/selected.conf`
- CLI tools: `axiom-fleet2`, `axiom-select`, `axiom-scan`, `axiom-exec`, `axiom-ls`, `axiom-rm`, `axiom-build`
- Cloud provider: configurable (DigitalOcean, AWS, GCP, Azure, Linode — depends on axiom account JSON)

### Fleet Configuration (`reconftw.cfg`)

```bash
AXIOM=false                      # Enable with -v flag at runtime
AXIOM_FLEET_LAUNCH=true          # Spin up new fleet automatically
AXIOM_FLEET_NAME="reconFTW"      # Fleet name prefix
AXIOM_FLEET_COUNT=10             # Number of VPS instances
AXIOM_FLEET_REGIONS="eu-central" # Preferred region
AXIOM_FLEET_SHUTDOWN=true        # Auto-teardown after scan
AXIOM_AUTO_FIX_HOSTKEY=true      # Auto-repair SSH known_hosts mismatches
AXIOM_POST_START=""              # Optional post-launch hook script
AXIOM_EXTRA_ARGS=""              # Extra args passed to axiom-scan calls
```

### Axiom-Scan Usage (modules that support fleet offload)

- `modules/subdomains.sh`: `sub_passive`, `sub_recursive_passive`, `sub_brute`, `s3buckets`
- `modules/vulns.sh`: `xss`, `fuzzparams`, `nuclei_dast`
- `modules/web.sh`: `portscanner` (nmap via `nmapx`), `webprobe_full`
- Resolver paths on fleet instances: `AXIOM_RESOLVERS_PATH="/home/op/lists/resolvers.txt"`, `AXIOM_RESOLVERS_TRUSTED_PATH`

## Vulnerability Management Integration

### Faraday Server

- Import scan results into Faraday vulnerability management platform
- Used in: `modules/subdomains.sh`, `modules/modes.sh`, `modules/web.sh`
- CLI: `faraday-cli tool report -w "$FARADAY_WORKSPACE" --plugin-id nuclei|nmap <file>`
- Config: `FARADAY=false` (opt-in), `FARADAY_WORKSPACE="reconftw"`
- Reports imported: nuclei JSON, nmap XML
- Dependency: `faraday-cli` must be installed separately (not installed by `install.sh`)

## AI Analysis Integration

### reconftw_ai (six2dez/reconftw_ai)

- Python script: `${tools}/reconftw_ai/reconftw_ai.py`
- Venv: `${tools}/reconftw_ai/venv/bin/python3`
- LLM backend: Ollama (local) with configurable model
- Config:
  - `AI_MODEL="llama3:8b"` — Ollama model name
  - `AI_EXECUTABLE="python3"` — fallback Python if venv absent
  - `AI_REPORT_TYPE="md"` — output format (md or txt)
  - `AI_REPORT_PROFILE="bughunter"` — prompt profile (executive, brief, bughunter)
  - `AI_MAX_CHARS_PER_FILE=50000` — truncation limit
  - `AI_REDACT=true` — redact sensitive indicators before sending to model
  - `AI_ALLOW_MODEL_PULL=false` — allow auto-pull of missing models
- Invoked from: `modules/modes.sh` (after full recon scan completes)

## DNS Resolvers Update Channels

- **Public resolvers**: downloaded from `https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt`
- **Trusted resolvers**: from `https://gist.githubusercontent.com/six2dez/ae9ed7e5c786461868abd3f2344401b6/raw/trusted_resolvers.txt`
- **dnsvalidator**: optional generation using `https://public-dns.info/nameservers.txt` and massdns resolver lists
- Cache TTL: `CACHE_MAX_AGE_DAYS_RESOLVERS=7` days

## Nuclei Templates Update

- Templates path: `$HOME/nuclei-templates` (`NUCLEI_TEMPLATES_PATH`)
- DAST templates: `${NUCLEI_TEMPLATES_PATH}/dast`
- Auto-update (once per scan session): `nuclei -update-templates -update-template-dir ${NUCLEI_TEMPLATES_PATH}`
- Community templates via `cent` (xm1k3/cent)
- Stamp file prevents repeated updates: `.tmp/.nuclei_updated`

## File Transfer (Optional Opt-in)

- **bashupload.com** — uploads recon result archives when `ALLOW_TRANSFER=true`
  - Function: `transfer()` in `modules/core.sh`
  - Disabled by default; opt-in required to prevent accidental data exfiltration
  - Can chain with `notify`: `transfer "${file}" | notify -silent`

## CI/CD Integration

- **GitHub Actions** (`.github/workflows/tests.yml`)
  - Triggers: push, pull_request, weekly schedule (Sunday 03:00), manual dispatch
  - Jobs: `shellcheck`, `unit-fast`, `integration-smoke`, `macos-smoke`, `integration-full`
  - Ubuntu-latest and macos-latest runners
- **Docker Nightly** (`.github/workflows/docker_nightly.yml`)
  - Pushes updated Docker image automatically

## Environment Configuration

### Required for Core Operation

- None strictly required — all API key features degrade gracefully when keys are absent

### Enables Additional Features

| Variable | Feature | Where Set |
|----------|---------|-----------|
| `SHODAN_API_KEY` | Passive port scan via Shodan CLI | env or `reconftw.cfg` |
| `WHOISXML_API` | Reverse IP, WHOIS, geolocation | env or `reconftw.cfg` |
| `PDCP_API_KEY` | ASN enumeration via asnmap | env or `reconftw.cfg` |
| `XSS_SERVER` | Blind XSS callback server | env or `reconftw.cfg` |
| `COLLAB_SERVER` | SSRF/OOB callback server | env or `reconftw.cfg` |
| `slack_channel` + `slack_auth` | Slack notifications | env or `reconftw.cfg` |
| `$HOME/Tools/.github_tokens` | GitHub dorks, repos, secret scanning | token file |
| `$HOME/Tools/.gitlab_tokens` | GitLab subdomain search | token file |
| `~/.config/notify/provider-config.yaml` | Telegram/Discord/Slack via notify | notify config file |
| `~/.config/subfinder/provider-config.yaml` | All subfinder passive sources | subfinder config |

### Secrets Storage

- Preferred: environment variables (take precedence over file-based config)
- Alternative: `secrets.cfg` in repo root (gitignored, auto-sourced by `reconftw.sh`)
- Template: `secrets.cfg.example`
- GitHub tokens: multi-token file at `$HOME/Tools/.github_tokens` (one per line)
- Docker runtime: pass as `-e KEY=value` at `docker run` time; never baked into image

### Redacted at Runtime

All of the following are scrubbed from log output via `redact_secrets()` in `modules/core.sh`:
`SHODAN_API_KEY`, `WHOISXML_API`, `PDCP_API_KEY`, `GITHUB_TOKEN`, `GH_TOKEN`, `GITLAB_TOKEN`, `DISCORD_WEBHOOK_URL`, `SLACK_WEBHOOK_URL`, `SLACK_BOT_TOKEN`, `TELEGRAM_BOT_TOKEN`, `slack_auth`, `telegram_key`, `telegram_api_key`, `discord_url`, `discord_webhook_url`, `XSS_SERVER`, `COLLAB_SERVER`

---

*Integration audit: 2026-05-13*
