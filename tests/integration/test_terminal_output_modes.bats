#!/usr/bin/env bats

setup() {
    SCRIPTPATH="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    export SCRIPTPATH
}

@test "--quiet hides header/sections but keeps final summary" {
    run timeout 45 bash "$SCRIPTPATH/reconftw.sh" -d example.com -s --dry-run --no-report --quiet 2>&1
    [ "$status" -eq 0 ]

    [[ "$output" != *"Mode: SUBDOMAINS | Target:"* ]]
    [[ "$output" != *"── SUBDOMAINS"* ]]
    [[ "$output" == *"RESULTS  example.com"* ]]
    [[ "$output" == *"Mode: SUBDOMAINS"* ]]
}

@test "--log-format jsonl-strict emits JSONL lines only" {
    run timeout 45 bash "$SCRIPTPATH/reconftw.sh" -d example.com -s --dry-run --no-report --log-format jsonl-strict 2>&1
    [ "$status" -eq 0 ]

    local has_header=0
    local has_summary=0
    local has_status=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ ! "$line" =~ ^\{.*\}$ ]]; then
            echo "non-json line: $line"
            return 1
        fi
        if command -v jq >/dev/null 2>&1; then
            if ! printf '%s\n' "$line" | jq -e . >/dev/null 2>&1; then
                echo "invalid json line: $line"
                return 1
            fi
            module=$(printf '%s\n' "$line" | jq -r '.module // empty')
            msg=$(printf '%s\n' "$line" | jq -r '.msg // empty')
            [[ "$module" == "header" ]] && has_header=1
            [[ "$module" == "summary" ]] && has_summary=1
            [[ "$msg" == "Status update" ]] && has_status=1
        fi
    done <<< "$output"

    if command -v jq >/dev/null 2>&1; then
        [ "$has_header" -eq 1 ]
        [ "$has_summary" -eq 1 ]
        [ "$has_status" -eq 1 ]
    else
        [[ "$output" == *'"module":"header"'* ]]
        [[ "$output" == *'"module":"summary"'* ]]
        [[ "$output" == *'"msg":"Status update"'* ]]
    fi
}
