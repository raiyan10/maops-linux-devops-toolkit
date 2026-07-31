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

@test "maops --version shows 0.3.0" {
    run "$MAOPS_BIN" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.3.0"* ]]
}

@test "maops version shows 0.3.0" {
    run "$MAOPS_BIN" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.3.0"* ]]
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
