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

@test "maops --version shows 0.2.0" {
    run "$MAOPS_BIN" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.2.0"* ]]
}

@test "maops version shows 0.2.0" {
    run "$MAOPS_BIN" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"0.2.0"* ]]
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
