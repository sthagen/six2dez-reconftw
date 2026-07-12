# Testing Patterns

**Analysis Date:** 2026-05-13

## Test Framework

**Runner:**
- [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System)
- Config: none (no `bats.run.yaml`; runner invoked directly via `tests/run_tests.sh`)

**Assertion library:**
- Built-in bats `[ ]` / `[[ ]]` expressions plus bats `run` command

**Run Commands:**
```bash
./tests/run_tests.sh --unit          # Unit tests only (fastest, CI default)
./tests/run_tests.sh --smoke         # Integration smoke subset
./tests/run_tests.sh --integration   # Full integration suite
./tests/run_tests.sh --all           # Unit + full integration
bats tests/unit/                     # Run all unit tests directly
bats tests/unit/test_common.bats     # Run single file
bats tests/security/                 # Security tests only
```

**Requires bash >= 4** (bats shell auto-detected in `tests/run_tests.sh`; macOS re-execs with Homebrew bash).

## Test File Organization

**Layout:**
```
tests/
├── unit/              # 246 @test blocks across 22 files
├── integration/       # 71 @test blocks across 10 files
├── security/          # 34 @test blocks across 3 files
├── fixtures/          # Expected output snapshots (ui/ and monitor_cycle*)
├── helpers/           # Shared setup helper (common.bash)
├── mocks/             # Executable mock scripts for external tools
└── run_tests.sh       # Test runner with --unit / --smoke / --integration
```

**Naming:**
- Files: `test_<area>.bats` (e.g., `test_common.bats`, `test_sanitize.bats`)
- Tests: `@test "verb noun expected behavior"` — plain English description

## Test File Structure

Every `.bats` file follows this structure:
```bash
#!/usr/bin/env bats

setup() {
    # Create temp dir, set up PATH, source libraries
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR" || exit 1
    # ... mock and library setup
}

teardown() {
    cd /
    rm -rf "$TEST_DIR"
}

# Group related tests with section comments
###############################################################################
# feature area tests
###############################################################################

@test "description of what should happen" {
    run function_under_test "arg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"expected"* ]]
}
```

`teardown()` always does `cd /` before `rm -rf "$TEST_DIR"` to avoid cwd-deletion issues.

## Two Setup Patterns

### Pattern 1: Isolated library testing (unit tests for lib/)

Source only the specific library. Create a `TEST_DIR` and set up mocks inline:
```bash
setup() {
    source "${BATS_TEST_DIRNAME}/../../lib/common.sh"
    TEST_DIR=$(mktemp -d)
    MOCK_BIN="${TEST_DIR}/mockbin"
    ORIG_PATH="$PATH"
    mkdir -p "$MOCK_BIN"
    create_mock_anew    # defined in setup or as helper
    export PATH="${MOCK_BIN}:$ORIG_PATH"
    cd "$TEST_DIR" || exit 1
    yellow="" reset="" bred="" cyan=""   # stub color vars
    called_fn_dir="$TEST_DIR/.called_fn"
    LOGFILE="$TEST_DIR/test.log"
    DRY_RUN=false
}
teardown() {
    PATH="$ORIG_PATH"
    cd /
    rm -rf "$TEST_DIR"
}
```
See `tests/unit/test_common.bats` and `tests/unit/test_parallel.bats`.

### Pattern 2: Full reconftw source (module/integration tests)

Uses `tests/helpers/common.bash` or inline equivalent — sources `reconftw.sh --source-only`:
```bash
setup() {
    local project_root
    project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export tools="$HOME/Tools"
    export LOGFILE="/dev/null"
    export bred='' bblue='' bgreen='' byellow='' yellow='' reset=''
    export NOTIFICATION=false
    export AXIOM=false
    source "$project_root/reconftw.cfg" 2>/dev/null || true
    export SCRIPTPATH="$project_root"
    source "$project_root/reconftw.sh" --source-only
}
```
The `--source-only` flag in `reconftw.sh` causes immediate `return 0` before any execution. After sourcing, all functions are available for testing.
See `tests/unit/test_sanitize.bats`, `tests/security/test_injection.bats`.

### Pattern 3: Extracting individual functions from modules

For testing functions from `modules/core.sh` without triggering the full module:
```bash
# In setup():
eval "$(sed -n '/^function notification()/,/^}/p' "$corefile")"
eval "$(sed -n '/^function start_func()/,/^}/p' "$corefile")"
eval "$(sed -n '/^function end_func()/,/^}/p' "$corefile")"
```
Use `sed -n '/^function name()/,/^}/p'` — NOT `grep -A N` (fragile to line count changes).
See `tests/unit/test_verbosity.bats`.

### Pattern 4: awk extraction for non-function blocks

For extracting variable declarations and multi-block sequences from `modules/core.sh`:
```bash
awk '/^REDACT_VARS=\(/,/^\)/ {print}
     /^REGISTERED_SECRETS=\(\)$/ {print}
     /^function register_secret\(\)/,/^}$/ {print}
     /^function redact_secrets\(\)/,/^}$/ {print}' \
    "$project_root/modules/core.sh" > "$BATS_TMPDIR/_redact.sh"
source "$BATS_TMPDIR/_redact.sh"
```
See `tests/security/test_redact_secrets.bats`.

## Mocking

### PATH Manipulation

The primary mocking strategy: place stub executables in a `MOCK_BIN` directory prepended to `PATH`.

```bash
MOCK_BIN="${TEST_DIR}/mockbin"
mkdir -p "$MOCK_BIN"
export PATH="${MOCK_BIN}:$ORIG_PATH"
```

Restore `PATH` in `teardown()`: `PATH="$ORIG_PATH"`.

### Inline Mock Creation

Mocks written inline in `setup()` or a helper function:
```bash
create_mock_anew() {
    cat >"${MOCK_BIN}/anew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
quiet=false
if [[ "${1:-}" == "-q" ]]; then
    quiet=true; shift
fi
target="${1:-}"
touch "$target"
added=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! grep -Fxq "$line" "$target"; then
        echo "$line" >>"$target"
        added=1
        [[ "$quiet" != true ]] && echo "$line"
    fi
done
[[ "$added" -eq 0 ]] && exit 1
exit 0
EOF
    chmod +x "${MOCK_BIN}/anew"
}
```

### Persistent Mocks (`tests/mocks/`)

Pre-built mock scripts checked into `tests/mocks/`:
- `tests/mocks/subfinder` — returns predefined subdomain list
- `tests/mocks/httpx` — returns predefined HTTP probe results
- `tests/mocks/sleep` — no-op (speeds up timing-sensitive tests)

Add `tests/mocks/` to PATH when needed: `export PATH="$SCRIPTPATH/tests/mocks:$PATH"`.

### Stub Functions

For functions called by the code under test that don't need to do anything:
```bash
getElapsedTime() { runtime="0s"; }
record_func_timing() { :; }
log_json() { :; }
```
Defined inline in `setup()`.

### Notify Mock

For notification integration tests:
```bash
create_mock_notify() {
    cat >"$MOCK_BIN/notify" <<'EOF'
#!/usr/bin/env bash
cat >>"${NOTIFY_LOG}"
EOF
    chmod +x "$MOCK_BIN/notify"
}
# Test verifies: [ -s "$NOTIFY_LOG" ] and grep -Fq "[INFO] msg - domain" "$NOTIFY_LOG"
```

## Fixtures

**Location:** `tests/fixtures/`

**UI snapshot fixtures** (`tests/fixtures/ui/`):
- `full_v0.txt`, `full_v1.txt`, `full_v2.txt` — expected output for verbosity 0/1/2 in full mode
- `subdomains_v0.txt`, `subdomains_v1.txt`, `subdomains_v2.txt` — for subdomain mode

Snapshot comparison in `tests/unit/test_ui_snapshots.bats`:
```bash
normalize_output() {
    sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/<TS>/g'
}
assert_fixture() {
    run generate_snapshot "$mode_char" "$verbosity"
    local normalized expected
    normalized="$(printf '%s\n' "$output" | normalize_output)"
    expected="$(cat "$fixture_path")"
    if [[ "$normalized" != "$expected" ]]; then
        diff -u <(printf '%s' "$expected") <(printf '%s' "$normalized")
        return 1
    fi
}
```
Timestamps are normalized to `<TS>` before comparison. If UI output changes intentionally, update fixtures to match.

**Monitor fixtures** (`tests/fixtures/monitor_cycle1/`, `monitor_cycle2/`):
- Pre-populated subdomain, web, and nuclei output files for monitor-mode diff tests.

## Test Counts

| Suite | Files | Tests |
|-------|-------|-------|
| `tests/unit/` | 22 | 246 |
| `tests/security/` | 3 | 34 |
| `tests/integration/` | 10 | 71 |
| **Total** | **35** | **351** |

## CI Integration

**File:** `.github/workflows/tests.yml`

**Jobs:**
| Job | Trigger | Command |
|-----|---------|---------|
| `shellcheck` | every push/PR | `shellcheck -S error reconftw.sh modules/*.sh lib/*.sh install.sh` |
| `unit-fast` | every push/PR | `./tests/run_tests.sh --unit` |
| `integration-smoke` | every push/PR (after unit-fast) | `./tests/run_tests.sh --smoke` |
| `macos-smoke` | every push/PR | `./tests/run_tests.sh --unit && ./tests/run_tests.sh --smoke` |
| `integration-full` | weekly cron + manual dispatch | `./tests/run_tests.sh --integration` |

**shellcheck config** (`.shellcheckrc`):
```
external-sources=true
severity=warning
source-path=SCRIPTDIR
source-path=SCRIPTDIR/lib
source-path=SCRIPTDIR/modules
```

## Common Test Patterns

**Testing exit status:**
```bash
run function_name "arg"
[ "$status" -eq 0 ]      # success
[ "$status" -ne 0 ]      # any failure
[ "$status" -eq 1 ]      # specific code
```

**Testing output content:**
```bash
[[ "$output" == *"expected substring"* ]]
[[ "$output" != *"should not appear"* ]]
[ "$output" = "exact match" ]
```

**Testing file side effects:**
```bash
[ -f "$called_fn_dir/.test_func" ]    # checkpoint created
[ -s "output.txt" ]                    # file non-empty
grep -q "expected" "$file"
```

**Checkpoint / DIFF mode testing:**
```bash
@test "should_run_function returns true when checkpoint missing" {
    mkdir -p "$called_fn_dir"
    test_func() { should_run_function; }
    run test_func
    [ "$status" -eq 0 ]
}

@test "should_run_function returns true in DIFF mode even with checkpoint" {
    mkdir -p "$called_fn_dir"
    DIFF=true
    test_func() {
        touch "$called_fn_dir/.test_func"
        should_run_function
    }
    run test_func
    [ "$status" -eq 0 ]
}
```

**Verbosity gating tests:**
```bash
@test "notification suppresses info at verbosity 1" {
    OUTPUT_VERBOSITY=1
    run notification "hello world" info
    [ "$status" -eq 0 ]
    [[ "$output" == "" ]]
}
```

**Async/parallel tests:** Use `parallel_funcs 2 func1 func2` and check file side effects — not timing.

**Security / injection tests:** Verify that dangerous characters in inputs are either stripped or cause non-zero exit:
```bash
@test "sanitize_domain blocks semicolon injection" {
    run sanitize_domain "example.com;whoami"
    [ "$status" -ne 0 ]
}
```

## Coverage Gaps

**Not directly unit-tested:**
- `modules/modes.sh` — mode orchestration functions (`recon()`, `passive()`, `all()`)
- `modules/vulns.sh` — individual vuln scan functions (tool-dependent, no mocks)
- `modules/web.sh` — webprobe functions (tool-dependent)
- `modules/axiom.sh` — Axiom fleet management (requires Axiom infrastructure)
- `install.sh` — installer logic
- `parallel_funcs` behavior under real concurrent load (tested serially in unit tests)
- `run_with_heartbeat()` / `run_with_heartbeat_shell()` — heartbeat timing behavior

**Covered by integration-smoke only (not unit):**
- CLI argument parsing end-to-end
- Config override order (CLI > custom_config.cfg > reconftw.cfg)
- Monitor mode diff logic

**Where to add new tests:**
- Unit tests for new lib/ functions: `tests/unit/test_<lib_name>.bats`
- Unit tests for new module helpers: `tests/unit/test_<module_name>.bats`, using `sed -n '/^function name()/,/^}/p'` extraction
- Security tests for new input paths: `tests/security/test_injection.bats`
- Snapshot tests for UI changes: update `tests/fixtures/ui/` and `tests/unit/test_ui_snapshots.bats`

---

*Testing analysis: 2026-05-13*
