#!/usr/bin/env bats

setup() {
  local project_root
  project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export SCRIPTPATH="$project_root"
  export LOGFILE="/dev/null"
  export bred='' bblue='' bgreen='' byellow='' yellow='' reset=''

  export TEST_DIR="$BATS_TEST_TMPDIR/reconftw_webprobe_full"
  mkdir -p "$TEST_DIR"
  export dir="$TEST_DIR/example.com"
  export called_fn_dir="$dir/.called_fn"
  mkdir -p "$called_fn_dir" "$dir"
  cd "$dir"

  export MOCK_BIN="$TEST_DIR/mockbin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"

  source "$project_root/reconftw.sh" --source-only
  export domain="example.com"
  export DIFF=false
  export AXIOM=false
  export WEBPROBEFULL=true
  export PROXY=false
  export UNCOMMON_PORTS_WEB="8080,8443"
  export HTTPX_UNCOMMONPORTS_THREADS=10
  export HTTPX_UNCOMMONPORTS_TIMEOUT=10
}

teardown() {
  [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

@test "webprobe_full accepts URL-list output and updates uncommon/webs_all targets" {
  mkdir -p .tmp webs subdomains
  printf "a.example.com\n" > subdomains/subdomains.txt

  cat > "$MOCK_BIN/httpx" <<'SH'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "https://*.edge.example.com:8443" "https://api.example.com:8080" > "$out"
SH
  chmod +x "$MOCK_BIN/httpx"

  run webprobe_full
  [ "$status" -eq 0 ]
  [ -s "webs/webs_uncommon_ports.txt" ]
  grep -q "https://edge.example.com:8443" "webs/webs_uncommon_ports.txt"
  grep -q "https://api.example.com:8080" "webs/webs_uncommon_ports.txt"
  [ -s "webs/webs_all.txt" ]
  grep -q "https://edge.example.com:8443" "webs/webs_all.txt"
}

@test "webprobe_full falls back to cached uncommon output when current extraction is empty" {
  mkdir -p .tmp webs subdomains
  printf "a.example.com\n" > subdomains/subdomains.txt
  printf '%s\n' "https://cached.example.com:8443" > webs/web_full_info_uncommon.txt

  cat > "$MOCK_BIN/httpx" <<'SH'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s\n' "https://not-in-scope.invalid:8443" > "$out"
SH
  chmod +x "$MOCK_BIN/httpx"

  run webprobe_full
  [ "$status" -eq 0 ]
  [ -s "webs/webs_uncommon_ports.txt" ]
  grep -q "https://cached.example.com:8443" "webs/webs_uncommon_ports.txt"
}
