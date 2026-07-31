#!/usr/bin/env bats
#
# Tests for scripts/network/*.sh.
#
# Hard constraint: no test here may require real internet access.
# Validation-rejection tests are designed to fail before any network I/O;
# any test that does touch the network is loopback/localhost only.

setup() {
    load '../test-helper'
    NETWORK_DIR="$REPO_ROOT/scripts/network"
}

# --- help exits 0 for every network script -----------------------------------

@test "network-info.sh --help exits 0" {
    run "$NETWORK_DIR/network-info.sh" --help
    [ "$status" -eq 0 ]
}

@test "ping-check.sh --help exits 0" {
    run "$NETWORK_DIR/ping-check.sh" --help
    [ "$status" -eq 0 ]
}

@test "dns-lookup.sh --help exits 0" {
    run "$NETWORK_DIR/dns-lookup.sh" --help
    [ "$status" -eq 0 ]
}

@test "port-check.sh --help exits 0" {
    run "$NETWORK_DIR/port-check.sh" --help
    [ "$status" -eq 0 ]
}

# --- ping-check.sh: invalid COUNT rejected before any ping ------------------

@test "ping-check.sh rejects COUNT=0 with exit 2, no ping attempted" {
    run "$NETWORK_DIR/ping-check.sh" 127.0.0.1 0
    [ "$status" -eq 2 ]
}

@test "ping-check.sh rejects COUNT=-1 with exit 2, no ping attempted" {
    run "$NETWORK_DIR/ping-check.sh" 127.0.0.1 -1
    [ "$status" -eq 2 ]
}

@test "ping-check.sh rejects COUNT=-1 with a positive-integer message, not 'unknown option'" {
    run "$NETWORK_DIR/ping-check.sh" 127.0.0.1 -1
    [ "$status" -eq 2 ]
    [[ "$output" == *"positive integer"* ]]
    [[ "$output" != *"Unknown option"* ]]
}

@test "ping-check.sh rejects non-numeric COUNT with exit 2, no ping attempted" {
    run "$NETWORK_DIR/ping-check.sh" 127.0.0.1 abc
    [ "$status" -eq 2 ]
}

@test "ping-check.sh rejects missing HOST with exit 2" {
    run "$NETWORK_DIR/ping-check.sh"
    [ "$status" -eq 2 ]
}

# --- port-check.sh: invalid PORT rejected before any connection ------------

@test "port-check.sh rejects PORT=0 with exit 2, no connection attempted" {
    run "$NETWORK_DIR/port-check.sh" 127.0.0.1 0
    [ "$status" -eq 2 ]
}

@test "port-check.sh rejects PORT=-1 with a range-validation message, not 'unknown option'" {
    run "$NETWORK_DIR/port-check.sh" 127.0.0.1 -1
    [ "$status" -eq 2 ]
    [[ "$output" == *"Port must be an integer from 1 to 65535"* ]]
    [[ "$output" != *"Unknown option"* ]]
}

@test "port-check.sh rejects PORT=65536 with exit 2, no connection attempted" {
    run "$NETWORK_DIR/port-check.sh" 127.0.0.1 65536
    [ "$status" -eq 2 ]
}

@test "port-check.sh rejects non-numeric PORT with exit 2, no connection attempted" {
    run "$NETWORK_DIR/port-check.sh" 127.0.0.1 abc
    [ "$status" -eq 2 ]
}

# --- port-check.sh: invalid TIMEOUT rejected before any connection ---------

@test "port-check.sh rejects TIMEOUT=0 with exit 2, no connection attempted" {
    run "$NETWORK_DIR/port-check.sh" 127.0.0.1 80 0
    [ "$status" -eq 2 ]
}

@test "port-check.sh rejects TIMEOUT=-1 with a positive-integer message, not 'unknown option'" {
    run "$NETWORK_DIR/port-check.sh" 127.0.0.1 80 -1
    [ "$status" -eq 2 ]
    [[ "$output" == *"positive integer"* ]]
    [[ "$output" != *"Unknown option"* ]]
}

@test "port-check.sh rejects non-numeric TIMEOUT with exit 2, no connection attempted" {
    run "$NETWORK_DIR/port-check.sh" 127.0.0.1 80 abc
    [ "$status" -eq 2 ]
}

# --- optional: offline, loopback-only reachability checks ------------------

@test "port-check.sh reports an unreachable closed loopback port without hanging" {
    # Port 1 is reserved/unlikely to be listening; bounded by a 1s timeout.
    # Accept either exit 0 (unexpectedly open) or 1 (closed/unreachable) --
    # the point is that it completes quickly and deterministically offline,
    # never a usage error (2).
    run "$NETWORK_DIR/port-check.sh" 127.0.0.1 1 1
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "dns-lookup.sh resolves localhost offline via /etc/hosts" {
    run "$NETWORK_DIR/dns-lookup.sh" localhost
    [ "$status" -eq 0 ]
}

# --- security regression: HOST must never reach a re-parsed shell ----------
#
# port-check.sh previously built `bash -c "exec 3<>/dev/tcp/$HOST/$PORT"` by
# string interpolation, so shell metacharacters in HOST were re-parsed and
# executed by the inner bash. The fix passes HOST/PORT as the inner bash's
# own positional parameters ($1/$2) inside a fixed, single-quoted script, so
# HOST's content is only ever used as a substituted value, never re-parsed
# as command syntax. This test proves the injected command never runs.

@test "port-check.sh does not execute shell metacharacters embedded in HOST" {
    local marker="$BATS_TEST_TMPDIR/injection-marker"
    run "$NETWORK_DIR/port-check.sh" "127.0.0.1;touch $marker;" 80 1
    [ ! -e "$marker" ]
}
