#!/usr/bin/env bats

setup() {
  local project_root
  project_root="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export SCRIPTPATH="$project_root"
}

@test "reconftw.sh passes bash syntax check" {
  run bash -n "$SCRIPTPATH/reconftw.sh"
  [ "$status" -eq 0 ]
}

@test "critical modules pass bash syntax check" {
  run bash -n \
    "$SCRIPTPATH/lib/common.sh" \
    "$SCRIPTPATH/modules/core.sh" \
    "$SCRIPTPATH/modules/modes.sh" \
    "$SCRIPTPATH/modules/web.sh" \
    "$SCRIPTPATH/modules/subdomains.sh" \
    "$SCRIPTPATH/modules/osint.sh" \
    "$SCRIPTPATH/modules/utils.sh" \
    "$SCRIPTPATH/modules/axiom.sh" \
    "$SCRIPTPATH/modules/vulns.sh"
  [ "$status" -eq 0 ]
}
