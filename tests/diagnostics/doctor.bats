#!/usr/bin/env bats
#
# Tests for scripts/diagnostics/doctor.sh. "Missing command" scenarios use
# stub_shadow_path_except (tests/test-helper.bash) to rebuild PATH from
# scratch as passthrough wrappers for every command doctor.sh's dependency
# chain might invoke, omitting only the command(s) under test — a full PATH
# replacement is required because doctor reports "missing" via `command -v`,
# which a merely-prepended stub cannot hide the real binary from. Because
# PATH is fully replaced, doctor.sh must always be invoked as
# "$REAL_BASH" "$SCRIPT" ... rather than relying on its own shebang, which
# would otherwise need to re-resolve "bash" through the very PATH being
# restricted.

setup() {
    load '../test-helper'
    SCRIPT="$REPO_ROOT/scripts/diagnostics/doctor.sh"
    isolate_config_env
}

@test "doctor.sh --help exits 0" {
    stub_shadow_path_except
    run "$REAL_BASH" "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "doctor.sh --version exits 0 and shows the current project version" {
    stub_shadow_path_except
    run "$REAL_BASH" "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "doctor reports healthy and exits 0 when everything required is present" {
    stub_shadow_path_except
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" != *"fail"* ]]
    [[ "$output" == *"All required checks passed."* ]]
}

@test "doctor reports the toolkit version matching PROJECT_VERSION" {
    stub_shadow_path_except
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"toolkit_version"*"$PROJECT_VERSION"* ]]
}

@test "doctor detects source-tree execution mode when run from the repo checkout" {
    stub_shadow_path_except
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"execution_mode"*"source-tree"* ]]
}

# --- missing required commands ----------------------------------------------

@test "doctor fails when a required command (ip) is missing" {
    stub_shadow_path_except ip
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"command_ip"*"fail"*"missing"* ]]
}

@test "doctor fails when a required command (ps) is missing" {
    stub_shadow_path_except ps
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"command_ps"*"fail"*"missing"* ]]
}

@test "doctor fails when a required command (df) is missing" {
    stub_shadow_path_except df
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"command_df"*"fail"*"missing"* ]]
}

@test "doctor fails when bash itself is reported missing" {
    stub_shadow_path_except bash
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"command_bash"*"fail"*"missing"* ]]
}

@test "doctor fails when neither systemctl nor service is available" {
    stub_shadow_path_except systemctl service
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"service_manager"*"fail"* ]]
}

@test "doctor passes the service-manager check when only service (no systemctl) is present" {
    stub_shadow_path_except systemctl
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"service_manager"*"pass"*"service"* ]]
}

@test "doctor passes the service-manager check when only systemctl (no service) is present" {
    stub_shadow_path_except service
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"service_manager"*"pass"*"systemctl"* ]]
}

# --- optional dev tools: warnings only, never a required failure -----------

@test "doctor still exits 0 when git is missing (warning, not a failure)" {
    stub_shadow_path_except git
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dev_git"*"warn"*"missing"* ]]
}

@test "doctor still exits 0 when python3 is missing (warning, not a failure)" {
    stub_shadow_path_except python3
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dev_python3"*"warn"*"missing"* ]]
}

@test "doctor exits 0 when all optional dev tools are simultaneously missing" {
    stub_shadow_path_except git make shellcheck bats python3
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"dev_git"*"warn"* ]]
    [[ "$output" == *"dev_make"*"warn"* ]]
    [[ "$output" == *"dev_shellcheck"*"warn"* ]]
    [[ "$output" == *"dev_bats"*"warn"* ]]
    [[ "$output" == *"dev_python3"*"warn"* ]]
}

# --- config-check integration ------------------------------------------

@test "doctor warns (not fails) when the config file does not exist" {
    stub_shadow_path_except
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/no-such-config"
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"config_exists"*"warn"*"not found"* ]]
}

@test "doctor fails when the config file exists but is invalid" {
    stub_shadow_path_except
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'bogus_key=1\n' >"$MAOPS_CONFIG_FILE"

    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"config_valid"*"fail"* ]]
}

@test "doctor passes the config checks when the file exists and is valid" {
    stub_shadow_path_except
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    "$REPO_ROOT/scripts/config/config-manager.sh" init

    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"config_exists"*"pass"* ]]
    [[ "$output" == *"config_valid"*"pass"* ]]
}

# --- output format -----------------------------------------------------

@test "doctor --format text output is identical to the no-flag default" {
    # Strips the leading "[YYYY-MM-DD HH:MM:SS]" timestamp from the final
    # log line before comparing: on a slow enough host, two consecutive
    # script invocations can cross a one-second boundary, which would
    # otherwise make this comparison flaky through no fault of doctor.sh
    # itself (see the identical fix applied to integrity-check.bats).
    stub_shadow_path_except
    run "$REAL_BASH" "$SCRIPT"
    local default_output
    default_output="$(sed -E 's/^\[[0-9-]+ [0-9:]+\]//' <<<"$output")"

    run "$REAL_BASH" "$SCRIPT" --format text
    local this_output
    this_output="$(sed -E 's/^\[[0-9-]+ [0-9:]+\]//' <<<"$output")"

    [ "$this_output" = "$default_output" ]
}

@test "doctor --format json emits exactly one valid JSON document on the healthy path" {
    stub_shadow_path_except
    run "$REAL_BASH" "$SCRIPT" --format json
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^\{.*\}$ ]]
    printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "doctor --format json remains valid JSON even when a required check fails" {
    stub_shadow_path_except df
    run "$REAL_BASH" "$SCRIPT" --format json
    [ "$status" -eq 1 ]
    printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "doctor JSON failure document names the specific failed check" {
    stub_shadow_path_except df
    run "$REAL_BASH" "$SCRIPT" --format json
    [ "$status" -eq 1 ]

    local failed
    failed="$(printf '%s' "$output" | python3 -c '
import json, sys
doc = json.load(sys.stdin)
names = [c["name"] for c in doc["checks"] if c["status"] == "fail"]
print(",".join(names))
')"
    [[ "$failed" == *"command_df"* ]]
    [[ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["overall"])')" == "fail" ]]
}

@test "doctor rejects an invalid --format value with exit 2" {
    stub_shadow_path_except
    run "$REAL_BASH" "$SCRIPT" --format xml
    [ "$status" -eq 2 ]
}

# --- network abstinence -----------------------------------------------

@test "doctor never actually invokes ping (presence-check only, no real ping attempt)" {
    stub_shadow_path_except
    stub_bin_init
    stub_command ping <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/ping.calls"
exit 0
STUB

    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/ping.calls" ]
}

@test "doctor source contains no curl, wget, or raw socket invocation" {
    ! grep -qE '\bcurl\b|\bwget\b|/dev/tcp/' "$REPO_ROOT/scripts/diagnostics/doctor.sh"
}

# --- read-only / safety guarantees ---------------------------------------

@test "doctor never invokes systemctl with a mutating verb" {
    stub_shadow_path_except
    stub_bin_init
    stub_command systemctl <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/systemctl.calls"
exit 0
STUB

    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 0 ]
    if [ -f "$BATS_TEST_TMPDIR/systemctl.calls" ]; then
        ! grep -qE '\b(start|stop|restart|enable|disable|mask)\b' "$BATS_TEST_TMPDIR/systemctl.calls"
    fi
}

@test "doctor does not modify an existing config file" {
    stub_shadow_path_except
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    "$REPO_ROOT/scripts/config/config-manager.sh" init

    local before after
    before="$(stat -c '%Y %s' "$MAOPS_CONFIG_FILE")"
    run "$REAL_BASH" "$SCRIPT"
    after="$(stat -c '%Y %s' "$MAOPS_CONFIG_FILE")"

    [ "$status" -eq 0 ]
    [ "$before" = "$after" ]
}
