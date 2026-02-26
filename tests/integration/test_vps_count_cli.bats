#!/usr/bin/env bats

setup() {
  local project_root
  project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export SCRIPTPATH="$project_root"

  export TEST_DIR="$BATS_TEST_TMPDIR/vps_count_cli"
  export MOCK_BIN="$TEST_DIR/mockbin"
  export AXIOM_CALL_LOG="$TEST_DIR/axiom_calls.log"
  export CUSTOM_CFG="$TEST_DIR/custom_axiom.cfg"
  export TEST_DOMAIN="vpscount.example.com"
  export TARGET_DIR="$SCRIPTPATH/Recon/$TEST_DOMAIN"

  mkdir -p "$TEST_DIR" "$MOCK_BIN" "$TARGET_DIR/.log"
  mkdir -p "$TARGET_DIR"/{subdomains,webs,hosts,nuclei_output,report}
  : > "$AXIOM_CALL_LOG"

  cat > "$MOCK_BIN/axiom-ls" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$MOCK_BIN/axiom-ls"

  cat > "$MOCK_BIN/axiom-select" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$MOCK_BIN/axiom-select"

  cat > "$MOCK_BIN/axiom-fleet2" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${AXIOM_CALL_LOG:-}" ]]; then
  printf 'axiom-fleet2:%s\n' "$*" >> "$AXIOM_CALL_LOG"
fi
exit 0
EOF
  chmod +x "$MOCK_BIN/axiom-fleet2"

  cat > "$CUSTOM_CFG" <<'EOF'
AXIOM_FLEET_LAUNCH=false
AXIOM_FLEET_COUNT=3
EOF

  echo "a.$TEST_DOMAIN" > "$TARGET_DIR/subdomains/subdomains.txt"
  echo "https://a.$TEST_DOMAIN" > "$TARGET_DIR/webs/webs_all.txt"
  echo "1.1.1.1" > "$TARGET_DIR/hosts/ips.txt"
}

teardown() {
  rm -rf "$TEST_DIR"
  rm -rf "$TARGET_DIR"
}

@test "help advertises --vps-count" {
  run timeout 20 bash "$SCRIPTPATH/reconftw.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"--vps-count n"* ]]
}

@test "--vps-count rejects 0" {
  run timeout 20 bash "$SCRIPTPATH/reconftw.sh" --vps-count 0 -h 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --vps-count value"* ]]
}

@test "--vps-count rejects non-numeric values" {
  run timeout 20 bash "$SCRIPTPATH/reconftw.sh" --vps-count abc -h 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --vps-count value"* ]]
}

@test "--vps-count accepts valid value" {
  run timeout 20 bash "$SCRIPTPATH/reconftw.sh" --vps-count 30 -h
  [ "$status" -eq 0 ]
}

@test "--report-only accepts --vps-count override parsing" {
  run env SKIP_CRITICAL_CHECK=true timeout 30 bash "$SCRIPTPATH/reconftw.sh" \
    -d "$TEST_DOMAIN" --report-only --vps-count 20 --export all
  [ "$status" -eq 0 ]
}

@test "--vps-count override forces fleet launch/count over custom config values" {
  run env PATH="$MOCK_BIN:$PATH" SKIP_CRITICAL_CHECK=true timeout 30 bash "$SCRIPTPATH/reconftw.sh" \
    -d "$TEST_DOMAIN" -c axiom_launch --vps-count 20 -f "$CUSTOM_CFG" --no-banner
  [ "$status" -eq 0 ]
  [[ "$output" == *"axiom_launch"* ]]
  [[ -f "$AXIOM_CALL_LOG" ]]
  run cat "$AXIOM_CALL_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-i 20"* ]]
}
