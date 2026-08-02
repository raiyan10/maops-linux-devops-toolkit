#!/usr/bin/env bats
#
# Deterministic tests for examples/. These are separate from
# `make examples-check`'s bash -n/ShellCheck/config-validate sweep (which
# covers static correctness) -- this file covers actual runtime behavior of
# examples/automation/health-report.sh.

setup() {
    load '../test-helper'
    HEALTH_REPORT="$REPO_ROOT/examples/automation/health-report.sh"
}

@test "examples/config/maops.conf validates via maops config validate" {
    run "$REPO_ROOT/scripts/config/config-manager.sh" validate "$REPO_ROOT/examples/config/maops.conf"
    [ "$status" -eq 0 ]
}

@test "examples/config/maops.conf contains no secret-shaped keys" {
    ! grep -qiE 'password|secret|token|api[_-]?key' "$REPO_ROOT/examples/config/maops.conf"
}

@test "health-report.sh --help exits 0" {
    run "$HEALTH_REPORT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "health-report.sh -h (short flag) exits 0" {
    run "$HEALTH_REPORT" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "health-report.sh fails clearly when maops cannot be resolved" {
    run env -u MAOPS_BIN PATH="/usr/bin:/bin" "$HEALTH_REPORT" "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not find 'maops'"* ]]
}

@test "health-report.sh rejects MAOPS_BIN pointing at a non-executable path" {
    local fake="$BATS_TEST_TMPDIR/not-executable"
    printf 'not a script\n' >"$fake"
    run env MAOPS_BIN="$fake" "$HEALTH_REPORT" "$BATS_TEST_TMPDIR/out"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not executable"* ]]
}

@test "health-report.sh generates a valid, mode-0600 redacted JSON report using MAOPS_BIN and exits 0 on a healthy report" {
    local outdir="$BATS_TEST_TMPDIR/reports"
    run env MAOPS_BIN="$MAOPS_BIN" "$HEALTH_REPORT" "$outdir"

    local report
    report="$(find "$outdir" -maxdepth 1 -type f -name 'health-report-*.json')"
    [ -n "$report" ]
    [ "$(stat -c '%a' "$report")" = "600" ]
    python3 -c "import json; json.load(open('$report'))"
    [ "$(json_field "$(cat "$report")" 'doc["system"]["hostname"]')" = "<redacted>" ]
    [ "$(json_field "$(cat "$report")" 'doc["overall"]')" = "pass" ]
    [ "$status" -eq 0 ]
}

@test "health-report.sh forwards a non-zero (unhealthy) report verdict as its own exit code" {
    # Documents the contract stated in health-report.sh's own usage text:
    # "Exit status reflects the report's own health verdict." Shadowing away
    # `ip` (a doctor.sh required command) drives doctor.overall=fail, which
    # drives the underlying `maops report save`'s exit code to 1 -- this
    # must propagate through health-report.sh's own exit, not get masked to
    # 0 just because the file was written successfully.
    stub_shadow_path_except ip
    export MAOPS_BIN
    local outdir="$BATS_TEST_TMPDIR/reports"

    run "$REAL_BASH" "$HEALTH_REPORT" "$outdir"
    [ "$status" -eq 1 ]

    local report
    report="$(find "$outdir" -maxdepth 1 -type f -name 'health-report-*.json')"
    [ -n "$report" ]
    python3 -c "import json; json.load(open('$report'))"
    [ "$(json_field "$(cat "$report")" 'doc["overall"]')" = "fail" ]
}

@test "health-report.sh refuses an OUTPUT_DIR that is an existing non-directory" {
    local not_a_dir="$BATS_TEST_TMPDIR/plainfile"
    printf 'x\n' >"$not_a_dir"

    run env MAOPS_BIN="$MAOPS_BIN" "$HEALTH_REPORT" "$not_a_dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not a directory"* ]]
}

@test "health-report.sh refuses an OUTPUT_DIR that is a symlink" {
    local real="$BATS_TEST_TMPDIR/real-outdir"
    local link="$BATS_TEST_TMPDIR/link-outdir"
    mkdir -p "$real"
    ln -s "$real" "$link"

    run env MAOPS_BIN="$MAOPS_BIN" "$HEALTH_REPORT" "$link"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is a symlink"* ]]
}

@test "health-report.sh makes no network requests and contains no curl/wget/raw-socket usage" {
    ! grep -qE '\bcurl\b|\bwget\b|/dev/tcp/' "$HEALTH_REPORT"
}

@test "health-report.sh contains no sudo usage" {
    ! grep -qE '\bsudo\b' "$HEALTH_REPORT"
}
