#!/usr/bin/env bats
# Tests for lib/common.sh utility functions

setup() {
    # Source the common library
    source "${BATS_TEST_DIRNAME}/../../lib/common.sh"

    # Create temp directory for tests
    TEST_DIR=$(mktemp -d)
    MOCK_BIN="${TEST_DIR}/mockbin"
    ORIG_PATH="$PATH"
    mkdir -p "$MOCK_BIN"
    create_mock_anew
    export PATH="${MOCK_BIN}:$ORIG_PATH"
    cd "$TEST_DIR" || exit 1
    
    # Set up mock variables that would normally come from reconftw
    yellow=""
    reset=""
    bred=""
    cyan=""
    called_fn_dir="$TEST_DIR/.called_fn"
    LOGFILE="$TEST_DIR/test.log"
    DRY_RUN=false
}

teardown() {
    PATH="$ORIG_PATH"
    cd /
    rm -rf "$TEST_DIR"
}

create_mock_anew() {
    cat >"${MOCK_BIN}/anew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
quiet=false
if [[ "${1:-}" == "-q" ]]; then
    quiet=true
    shift
fi
target="${1:-}"
touch "$target"
added=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! grep -Fxq "$line" "$target"; then
        echo "$line" >>"$target"
        added=1
        if [[ "$quiet" != true ]]; then
            echo "$line"
        fi
    fi
done
if [[ "$added" -eq 0 ]]; then
    exit 1
fi
exit 0
EOF
    chmod +x "${MOCK_BIN}/anew"
}

###############################################################################
# ensure_dirs tests
###############################################################################

@test "ensure_dirs creates single directory" {
    run ensure_dirs testdir
    [ "$status" -eq 0 ]
    [ -d "testdir" ]
}

@test "ensure_dirs creates multiple directories" {
    run ensure_dirs dir1 dir2 dir3
    [ "$status" -eq 0 ]
    [ -d "dir1" ]
    [ -d "dir2" ]
    [ -d "dir3" ]
}

@test "ensure_dirs creates nested directories" {
    run ensure_dirs "a/b/c"
    [ "$status" -eq 0 ]
    [ -d "a/b/c" ]
}

@test "ensure_dirs returns 0 with no arguments" {
    run ensure_dirs
    [ "$status" -eq 0 ]
}

@test "ensure_dirs succeeds if directory already exists" {
    mkdir -p existing_dir
    run ensure_dirs existing_dir
    [ "$status" -eq 0 ]
}

###############################################################################
# safe_backup tests
###############################################################################

@test "safe_backup copies existing file" {
    mkdir -p .tmp
    echo "test content" > original.txt
    run safe_backup original.txt .tmp/backup.txt
    [ "$status" -eq 0 ]
    [ -f ".tmp/backup.txt" ]
    [ "$(cat .tmp/backup.txt)" = "test content" ]
}

@test "safe_backup skips empty file" {
    mkdir -p .tmp
    touch empty.txt
    run safe_backup empty.txt .tmp/backup.txt
    [ "$status" -eq 0 ]
    [ ! -f ".tmp/backup.txt" ]
}

@test "safe_backup skips non-existent file" {
    mkdir -p .tmp
    run safe_backup nonexistent.txt .tmp/backup.txt
    [ "$status" -eq 0 ]
    [ ! -f ".tmp/backup.txt" ]
}

@test "safe_backup uses default destination" {
    mkdir -p .tmp
    echo "content" > myfile.txt
    run safe_backup myfile.txt
    [ "$status" -eq 0 ]
    [ -f ".tmp/myfile.txt.bak" ]
}

###############################################################################
# count_lines tests
###############################################################################

@test "count_lines returns correct count" {
    printf "line1\nline2\nline3\n" > test.txt
    result=$(count_lines test.txt)
    [ "$result" -eq 3 ]
}

@test "count_lines ignores empty lines" {
    printf "line1\n\nline2\n\n\nline3\n" > test.txt
    result=$(count_lines test.txt)
    [ "$result" -eq 3 ]
}

@test "count_lines returns 0 for empty file" {
    touch empty.txt
    result=$(count_lines empty.txt)
    [ "$result" -eq 0 ]
}

@test "count_lines returns 0 for non-existent file" {
    result=$(count_lines nonexistent.txt)
    [ "$result" -eq 0 ]
}

###############################################################################
# count_lines_stdin tests
###############################################################################

@test "count_lines_stdin counts from pipe" {
    result=$(printf "a\nb\nc\n" | count_lines_stdin)
    [ "$result" -eq 3 ]
}

@test "count_lines_stdin ignores empty lines from pipe" {
    result=$(printf "a\n\nb\n\n" | count_lines_stdin)
    [ "$result" -eq 2 ]
}

###############################################################################
# skip_notification tests
###############################################################################

@test "skip_notification outputs message" {
    # Define a wrapper function to test FUNCNAME
    test_func() {
        skip_notification "disabled"
    }
    run test_func
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
}

@test "skip_notification processed-visible renders SKIP with cache reason and cache marker" {
    OUTPUT_VERBOSITY=1
    SHOW_CACHE=false
    mkdir -p "$called_fn_dir"

    test_func() {
        skip_notification "processed-visible"
    }

    run test_func
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
    [[ "$output" == *"reason: cache"* ]]
    [[ "$output" != *"CACHE"* ]]
    [ -f "$called_fn_dir/.cache_test_func" ]
    [ ! -f "$called_fn_dir/.skip_test_func" ]
    [ -f "$called_fn_dir/.status_reason_test_func" ]
    [ "$(cat "$called_fn_dir/.status_reason_test_func")" = "cache" ]
}

###############################################################################
# output formatting tests
###############################################################################

@test "print_artifacts uses INFO Artifacts format without brackets" {
    OUTPUT_VERBOSITY=1
    bblue="<BLUE>"
    reset="<RESET>"

    run print_artifacts "osint/, subdomains/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"<BLUE>INFO<RESET> Artifacts: osint/, subdomains/"* ]]
    [[ "$output" != *"[INFO] Artifacts"* ]]
}

@test "print_notice RUN uses cyan color for state" {
    OUTPUT_VERBOSITY=1
    cyan="<CYAN>"
    reset="<RESET>"

    run print_notice RUN "sub_brute" "bruteforcing subdomains"
    [ "$status" -eq 0 ]
    [[ "$output" == *"<CYAN>RUN  <RESET>"* ]]
    [[ "$output" == *"sub_brute"* ]]
    [[ "$output" == *"(bruteforcing subdomains)"* ]]
}

###############################################################################
# run_tool tests
###############################################################################

@test "run_tool executes command normally" {
    run run_tool "echo" echo "hello"
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello"* ]]
}

@test "run_tool respects DRY_RUN mode" {
    DRY_RUN=true
    run run_tool "test" echo "should not run"
    [ "$status" -eq 0 ]
    [[ "$output" == *"DRY-RUN"* ]]
}

###############################################################################
# safe_count tests
###############################################################################

@test "safe_count returns valid number" {
    printf "line1\nline2\n" > test.txt
    result=$(safe_count "cat test.txt")
    [ "$result" -eq 2 ]
}

@test "safe_count returns 0 on failure" {
    result=$(safe_count "cat nonexistent_file_xyz.txt")
    [ "$result" -eq 0 ]
}

###############################################################################
# process_results tests
###############################################################################

@test "process_results deduplicates and counts" {
    # Skip if anew not available
    command -v anew &>/dev/null || skip "anew not installed"
    
    printf "a\nb\nc\n" > input.txt
    touch output.txt
    result=$(process_results input.txt output.txt)
    [ "$result" -eq 3 ]
    [ -f "output.txt" ]
}

###############################################################################
# should_run_function tests
###############################################################################

@test "should_run_function returns true when checkpoint missing" {
    mkdir -p "$called_fn_dir"
    test_func() {
        should_run_function
    }
    run test_func
    [ "$status" -eq 0 ]
}

@test "should_run_function returns false when checkpoint exists" {
    mkdir -p "$called_fn_dir"
    DIFF=false
    test_func() {
        touch "$called_fn_dir/.test_func"
        should_run_function
    }
    run test_func
    [ "$status" -eq 1 ]
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

###############################################################################
# anew_safe / anew_q_safe tests
###############################################################################

@test "anew_q_safe returns 0 when anew adds new lines" {
    local outfile="$TEST_DIR/out.txt"
    touch "$outfile"
    _run_anew_q() { echo "newline" | anew_q_safe "$outfile"; }
    run _run_anew_q
    [ "$status" -eq 0 ]
    grep -q "newline" "$outfile"
}

@test "anew_q_safe returns 0 when anew adds no new lines (rc=1 from anew)" {
    local outfile="$TEST_DIR/out.txt"
    echo "duplicate" > "$outfile"
    _run_anew_q_dup() { echo "duplicate" | anew_q_safe "$outfile"; }
    run _run_anew_q_dup
    [ "$status" -eq 0 ]
}

@test "anew_q_safe writes unique lines to file" {
    local outfile="$TEST_DIR/out.txt"
    echo "existing" > "$outfile"
    _run_anew_q_mix() { printf "existing\nnewone\n" | anew_q_safe "$outfile"; }
    run _run_anew_q_mix
    [ "$status" -eq 0 ]
    grep -q "newone" "$outfile"
    [ "$(wc -l < "$outfile")" -eq 2 ]
}

@test "anew_safe returns 0 and outputs new lines" {
    local outfile="$TEST_DIR/out.txt"
    echo "old" > "$outfile"
    _run_anew_mix() { printf "old\nnew\n" | anew_safe "$outfile"; }
    run _run_anew_mix
    [ "$status" -eq 0 ]
    [[ "$output" == *"new"* ]]
    grep -q "new" "$outfile"
}

###############################################################################
# stream sanitization tests
###############################################################################

@test "strip_ansi_stream keeps final carriage-return segment" {
    _run_strip_cr() { printf "line1\rline2\n" | strip_ansi_stream; }
    run _run_strip_cr
    [ "$status" -eq 0 ]
    [ "$output" = "line2" ]
}

@test "strip_ansi_stream removes backspace redraw artifacts" {
    _run_strip_bs() { printf "abc\b\bXY\n" | strip_ansi_stream; }
    run _run_strip_bs
    [ "$status" -eq 0 ]
    [ "$output" = "aXY" ]
}

###############################################################################
# domain matching helpers tests
###############################################################################

@test "grep_domain matches exact domain and subdomains only" {
    cat > domains.txt <<'EOF'
example.com
api.example.com
badexample.com
foo.example.net
EOF

    run grep_domain domains.txt "example.com"
    [ "$status" -eq 0 ]
    [[ "$output" == *"example.com"* ]]
    [[ "$output" == *"api.example.com"* ]]
    [[ "$output" != *"badexample.com"* ]]
    [[ "$output" != *"foo.example.net"* ]]
}

###############################################################################
# warning helpers tests
###############################################################################

@test "warn_once emits the same warning key only once" {
    WARN_ONCE_KEYS=()
    _warn_twice() {
        warn_once "missing-tool-dnstake" "dnstake missing"
        warn_once "missing-tool-dnstake" "dnstake missing" || true
    }

    run _warn_twice
    [ "$status" -eq 0 ]
    local warn_count
    warn_count=$(printf "%s\n" "$output" | grep -c "dnstake missing" || true)
    [ "$warn_count" -eq 1 ]
}
