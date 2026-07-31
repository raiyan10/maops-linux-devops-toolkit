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

# --- is_non_option_argument / validate_non_option_argument --------------------

@test "is_non_option_argument accepts a normal token" {
    is_non_option_argument "alice"
}

@test "is_non_option_argument rejects a leading-dash value" {
    ! is_non_option_argument "-x"
}

@test "is_non_option_argument rejects a leading-dash long option" {
    ! is_non_option_argument "--help"
}

@test "is_non_option_argument rejects the empty string" {
    ! is_non_option_argument ""
}

@test "validate_non_option_argument exits 2 on a leading-dash value" {
    run validate_non_option_argument "-x" "USERNAME"
    [ "$status" -eq 2 ]
}

@test "validate_non_option_argument succeeds silently on a normal token" {
    run validate_non_option_argument "alice" "USERNAME"
    [ "$status" -eq 0 ]
}

# --- is_one_of / validate_one_of -----------------------------------------------

@test "is_one_of accepts a listed choice" {
    is_one_of "cpu" cpu memory
}

@test "is_one_of rejects an unlisted choice" {
    ! is_one_of "disk" cpu memory
}

@test "validate_one_of exits 2 on an unlisted value and names the allowed choices" {
    run validate_one_of "disk" "SORT" cpu memory
    [ "$status" -eq 2 ]
    [[ "$output" == *"cpu, memory"* ]]
}

@test "validate_one_of succeeds silently on a listed value" {
    run validate_one_of "memory" "SORT" cpu memory
    [ "$status" -eq 0 ]
}
