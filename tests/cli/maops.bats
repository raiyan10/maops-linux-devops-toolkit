#!/usr/bin/env bats
#
# Tests for the bin/maops unified CLI dispatcher.

setup() {
    load '../test-helper'
}

@test "maops --help exits 0" {
    run "$MAOPS_BIN" --help
    [ "$status" -eq 0 ]
}

@test "maops help exits 0" {
    run "$MAOPS_BIN" help
    [ "$status" -eq 0 ]
}

@test "maops --version shows the current project version" {
    run "$MAOPS_BIN" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "maops version shows the current project version" {
    run "$MAOPS_BIN" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "unknown group exits 2" {
    run "$MAOPS_BIN" bogus info
    [ "$status" -eq 2 ]
}

@test "unknown command within known group exits 2" {
    run "$MAOPS_BIN" system bogus
    [ "$status" -eq 2 ]
}

@test "no command at all exits 2" {
    run "$MAOPS_BIN"
    [ "$status" -eq 2 ]
}

@test "maops system hostname dispatches and succeeds" {
    run "$MAOPS_BIN" system hostname
    [ "$status" -eq 0 ]
    [[ "$output" == *"Hostname"* ]]
}

@test "maops filesystem largest forwards PATH and LIMIT arguments" {
    : >"$BATS_TEST_TMPDIR/file-small"
    printf 'a%.0s' {1..1000} >"$BATS_TEST_TMPDIR/file-medium"
    printf 'a%.0s' {1..5000} >"$BATS_TEST_TMPDIR/file-large"

    run "$MAOPS_BIN" filesystem largest "$BATS_TEST_TMPDIR" 2
    [ "$status" -eq 0 ]

    local entry_count
    entry_count="$(printf '%s\n' "$output" | grep -c ' MB  ' || true)"
    [ "$entry_count" -le 2 ]
}

# --- Day 4: user / process / service dispatch routes -----------------------

@test "maops --help lists the user, process, and service groups" {
    run "$MAOPS_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"user"* ]]
    [[ "$output" == *"process"* ]]
    [[ "$output" == *"service"* ]]
}

@test "maops user with no command exits 2" {
    run "$MAOPS_BIN" user
    [ "$status" -eq 2 ]
}

@test "maops user bogus exits 2 with an unknown-command message" {
    run "$MAOPS_BIN" user bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown user command"* ]]
}

@test "maops user report --help dispatches to user-report.sh" {
    run "$MAOPS_BIN" user report --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"USERNAME"* ]]
}

@test "maops process with no command exits 2" {
    run "$MAOPS_BIN" process
    [ "$status" -eq 2 ]
}

@test "maops process bogus exits 2 with an unknown-command message" {
    run "$MAOPS_BIN" process bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown process command"* ]]
}

@test "maops process top --help dispatches to process-monitor.sh" {
    run "$MAOPS_BIN" process top --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"LIMIT"* ]]
}

@test "maops process top abc forwards the invalid LIMIT and preserves its exit code" {
    run "$MAOPS_BIN" process top abc
    [ "$status" -eq 2 ]
}

@test "maops service with no command exits 2" {
    run "$MAOPS_BIN" service
    [ "$status" -eq 2 ]
}

@test "maops service bogus exits 2 with an unknown-command message" {
    run "$MAOPS_BIN" service bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown service command"* ]]
}

@test "maops service status --help dispatches to service-status.sh" {
    run "$MAOPS_BIN" service status --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"SERVICE"* ]]
}

@test "maops service status with no SERVICE exits 2 from the leaf script, not the dispatcher" {
    run "$MAOPS_BIN" service status
    [ "$status" -eq 2 ]
    [[ "$output" == *"SERVICE is required"* ]]
}

@test "maops bogus report still exits 2 as an unknown top-level group" {
    run "$MAOPS_BIN" bogus report
    [ "$status" -eq 2 ]
}

# --- Day 5: config / doctor dispatch routes ---------------------------------

@test "maops --help lists the config and doctor groups" {
    run "$MAOPS_BIN" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"config"* ]]
    [[ "$output" == *"doctor"* ]]
}

@test "maops config with no subcommand exits 2" {
    isolate_config_env
    run "$MAOPS_BIN" config
    [ "$status" -eq 2 ]
}

@test "maops config bogus exits 2 with an unknown-command message" {
    isolate_config_env
    run "$MAOPS_BIN" config bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown config command"* ]]
}

@test "maops config path dispatches to config-manager.sh" {
    isolate_config_env
    run "$MAOPS_BIN" config path
    [ "$status" -eq 0 ]
    [ "$output" = "$XDG_CONFIG_HOME/maops/config" ]
}

@test "maops config init --help dispatches and forwards --help" {
    isolate_config_env
    run "$MAOPS_BIN" config init --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "maops doctor dispatches to doctor.sh and forwards its exit code" {
    isolate_config_env
    stub_shadow_path_except
    run "$REAL_BASH" "$MAOPS_BIN" doctor
    [ "$status" -eq 0 ]
    [[ "$output" == *"MAOps Doctor"* ]]
}

@test "maops doctor --format json forwards the flag through the dispatcher" {
    isolate_config_env
    stub_shadow_path_except
    run "$REAL_BASH" "$MAOPS_BIN" doctor --format json
    [ "$status" -eq 0 ]
    printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "maops doctor --nonsense forwards doctor.sh's own usage error and exit code" {
    isolate_config_env
    run "$MAOPS_BIN" doctor --nonsense
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown option"* ]]
}
