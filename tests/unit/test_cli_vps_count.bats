#!/usr/bin/env bats

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

normalize_to_lines() {
  local -a normalized=()
  mapfile -d '' -t normalized < <(normalize_vps_count_args "$@")
  printf '%s\n' "${normalized[@]}"
}

@test "normalize_vps_count_args rewrites '-v 20 -r' to include --vps-count" {
  run normalize_to_lines -v 20 -r
  [ "$status" -eq 0 ]
  [ "$output" = $'-v\n--vps-count\n20\n-r' ]
}

@test "normalize_vps_count_args keeps plain '-v -r' unchanged" {
  run normalize_to_lines -v -r
  [ "$status" -eq 0 ]
  [ "$output" = $'-v\n-r' ]
}

@test "normalize_vps_count_args keeps '-v foo -r' unchanged" {
  run normalize_to_lines -v foo -r
  [ "$status" -eq 0 ]
  [ "$output" = $'-v\nfoo\n-r' ]
}
