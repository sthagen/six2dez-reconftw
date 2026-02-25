#!/usr/bin/env bats

setup() {
    local project_root
    project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPTPATH="$project_root"
    export TEST_DIR="$BATS_TEST_TMPDIR/reconftw_list_targets"
    export MOCK_BIN="$TEST_DIR/mockbin"
    mkdir -p "$TEST_DIR" "$MOCK_BIN"

    cat >"$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    fetch)
        exit 0
        ;;
    rev-parse)
        shift
        case "${1:-}" in
            --is-inside-work-tree)
                echo "true"
                ;;
            --abbrev-ref)
                if [[ "${2:-}" == "HEAD" ]]; then
                    echo "dev"
                elif [[ "${2:-}" == "--symbolic-full-name" ]]; then
                    echo "origin/dev"
                fi
                ;;
            HEAD | origin/dev)
                echo "deadbeef"
                ;;
            *)
                echo "deadbeef"
                ;;
        esac
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
    chmod +x "$MOCK_BIN/git"
}

teardown() {
    [[ -n "${TARGET_1:-}" ]] && rm -rf "$SCRIPTPATH/Recon/$TARGET_1"
    [[ -n "${TARGET_2:-}" ]] && rm -rf "$SCRIPTPATH/Recon/$TARGET_2"
    [[ -d "${TEST_DIR:-}" ]] && rm -rf "$TEST_DIR"
}

@test "-l processes final target even without trailing newline" {
    TARGET_1="noeof-$RANDOM-one.example.com"
    TARGET_2="noeof-$RANDOM-two.example.com"
    local list_file="$TEST_DIR/targets-noeof.txt"
    printf "%s\n%s" "$TARGET_1" "$TARGET_2" >"$list_file"

    run env PATH="$MOCK_BIN:$PATH" SKIP_CRITICAL_CHECK=true timeout 60 \
        bash "$SCRIPTPATH/reconftw.sh" -l "$list_file" -s --dry-run --no-report --quiet --no-banner 2>&1

    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULTS  $TARGET_1"* ]]
    [[ "$output" == *"RESULTS  $TARGET_2"* ]]
}

@test "-l processes CRLF target lists without dropping entries" {
    TARGET_1="crlf-$RANDOM-one.example.com"
    TARGET_2="crlf-$RANDOM-two.example.com"
    local list_file="$TEST_DIR/targets-crlf.txt"
    printf "%s\r\n%s\r\n" "$TARGET_1" "$TARGET_2" >"$list_file"

    run env PATH="$MOCK_BIN:$PATH" SKIP_CRITICAL_CHECK=true timeout 60 \
        bash "$SCRIPTPATH/reconftw.sh" -l "$list_file" -s --dry-run --no-report --quiet --no-banner 2>&1

    [ "$status" -eq 0 ]
    [[ "$output" == *"RESULTS  $TARGET_1"* ]]
    [[ "$output" == *"RESULTS  $TARGET_2"* ]]
}
