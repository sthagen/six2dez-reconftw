#!/usr/bin/env bats
# Snapshot-like tests for stable UI contracts across modes/verbosity.

setup() {
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    # Reset source guards for isolated test runs.
    _COMMON_SH_LOADED=""
    _UI_SH_LOADED=""

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/ui.sh"

    # Deterministic, no-color output for fixtures.
    bred=""; bblue=""; bgreen=""; byellow=""; yellow=""; reset=""; red=""; blue=""; green=""; cyan=""

    export COLUMNS=80
    export TERM=dumb
}

normalize_output() {
    sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/<TS>/g'
}

generate_snapshot() {
    local mode_char="$1"
    local verbosity="$2"

    domain="example.com"
    CUSTOM_CONFIG="default"
    PARALLEL_MODE=true
    PARALLEL_MAX_JOBS=4
    dir="/tmp/recon"
    reconftw_version="test-v0"
    RECON_BEHIND_NAT="no"
    DNS_RESOLVER_SELECTED="dnsx"
    PERF_PROFILE_INFO="PERF_PROFILE=balanced | cores=8 mem=16GB"
    DISK_SPACE_INFO="Disk space OK: 10GB available at ."
    DEBUG_LOG="/tmp/recon/debug.log"
    LOG_FORMAT="plain"
    OUTPUT_VERBOSITY="$verbosity"
    opt_mode="$mode_char"

    _UI_OK_COUNT=0
    _UI_WARN_COUNT=0
    _UI_FAIL_COUNT=0
    _UI_SKIP_COUNT=0
    _UI_CACHE_COUNT=0

    ui_init

    local mode_label="FULL"
    [[ "$mode_char" == "s" ]] && mode_label="SUBDOMAINS"

    ui_header
    _print_section "Subdomains"
    _print_status OK "subdomains_full" "0s"
    _print_msg INFO "verbose_marker"
    ui_module_end "Subdomains" "subdomains/" "webs/"
    ui_summary "example.com" "1m 00s" "/tmp/recon" "$mode_label" "1" "0" 0 0 0 0 0
}

assert_fixture() {
    local mode_char="$1"
    local verbosity="$2"
    local fixture_name="$3"
    local fixture_path="$PROJECT_ROOT/tests/fixtures/ui/$fixture_name"

    run generate_snapshot "$mode_char" "$verbosity"
    [ "$status" -eq 0 ]

    local normalized expected
    normalized="$(printf '%s\n' "$output" | normalize_output)"
    expected="$(cat "$fixture_path")"

    if [[ "$normalized" != "$expected" ]]; then
        diff -u <(printf '%s' "$expected") <(printf '%s' "$normalized")
        return 1
    fi
}

@test "UI snapshot FULL verbosity 0" {
    assert_fixture "r" "0" "full_v0.txt"
}

@test "UI snapshot FULL verbosity 1" {
    assert_fixture "r" "1" "full_v1.txt"
}

@test "UI snapshot FULL verbosity 2" {
    assert_fixture "r" "2" "full_v2.txt"
}

@test "UI snapshot SUBDOMAINS verbosity 0" {
    assert_fixture "s" "0" "subdomains_v0.txt"
}

@test "UI snapshot SUBDOMAINS verbosity 1" {
    assert_fixture "s" "1" "subdomains_v1.txt"
}

@test "UI snapshot SUBDOMAINS verbosity 2" {
    assert_fixture "s" "2" "subdomains_v2.txt"
}
