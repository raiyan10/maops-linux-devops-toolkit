#!/usr/bin/env bats
#
# Tests for scripts/common/cli.sh (the new positive-integer / TCP-port
# validation helpers used by the CLI dispatcher and network scripts).
#
# NOTE: despite the filename, this deliberately targets cli.sh, not the
# older scripts/common/helpers.sh, which has no integer/port logic.

setup() {
    load '../test-helper'
    # shellcheck source=/dev/null
    source "$REPO_ROOT/scripts/common/bootstrap.sh"
}

# --- is_positive_integer ----------------------------------------------------

@test "is_positive_integer accepts 5" {
    is_positive_integer "5"
}

@test "is_positive_integer accepts 1" {
    is_positive_integer "1"
}

@test "is_positive_integer accepts 42" {
    is_positive_integer "42"
}

@test "is_positive_integer rejects 0" {
    ! is_positive_integer "0"
}

@test "is_positive_integer rejects negative numbers" {
    ! is_positive_integer "-1"
}

@test "is_positive_integer rejects non-numeric input" {
    ! is_positive_integer "abc"
}

@test "is_positive_integer rejects empty string" {
    ! is_positive_integer ""
}

@test "is_positive_integer rejects decimals" {
    ! is_positive_integer "3.5"
}

# --- is_valid_port -----------------------------------------------------------

@test "is_valid_port accepts boundary value 1" {
    is_valid_port "1"
}

@test "is_valid_port accepts boundary value 65535" {
    is_valid_port "65535"
}

@test "is_valid_port accepts 80" {
    is_valid_port "80"
}

@test "is_valid_port rejects boundary value 0" {
    ! is_valid_port "0"
}

@test "is_valid_port rejects boundary value 65536" {
    ! is_valid_port "65536"
}

@test "is_valid_port rejects negative numbers" {
    ! is_valid_port "-1"
}

@test "is_valid_port rejects non-numeric input" {
    ! is_valid_port "abc"
}

# --- validate_positive_integer ------------------------------------------------

@test "validate_positive_integer exits 2 on invalid input" {
    run validate_positive_integer "abc" "COUNT"
    [ "$status" -eq 2 ]
}

@test "validate_positive_integer exits 2 on zero" {
    run validate_positive_integer "0" "COUNT"
    [ "$status" -eq 2 ]
}

@test "validate_positive_integer succeeds silently on valid input" {
    run validate_positive_integer "5" "COUNT"
    [ "$status" -eq 0 ]
}

# --- validate_tcp_port ---------------------------------------------------------

@test "validate_tcp_port exits 2 on out-of-range port" {
    run validate_tcp_port "65536"
    [ "$status" -eq 2 ]
}

@test "validate_tcp_port exits 2 on non-numeric port" {
    run validate_tcp_port "abc"
    [ "$status" -eq 2 ]
}

@test "validate_tcp_port succeeds silently on valid port" {
    run validate_tcp_port "443"
    [ "$status" -eq 0 ]
}
