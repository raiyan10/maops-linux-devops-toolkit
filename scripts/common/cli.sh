#!/usr/bin/env bash

[[ -n "${MAOPS_CLI_LOADED:-}" ]] && return
readonly MAOPS_CLI_LOADED=1

readonly CLI_EXIT_USAGE_ERROR=2

cli_show_version() {
    printf '%s %s\n' "$PROJECT_NAME" "$PROJECT_VERSION"
}

is_help_flag() {
    [[ "$1" == "-h" || "$1" == "--help" || "$1" == "help" ]]
}

is_version_flag() {
    [[ "$1" == "-v" || "$1" == "--version" || "$1" == "version" ]]
}

cli_usage_error() {
    log_error "$1"
    exit "$CLI_EXIT_USAGE_ERROR"
}

is_positive_integer() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

validate_positive_integer() {
    local value="$1"
    local label="$2"

    is_positive_integer "$value" || cli_usage_error "$label must be a positive integer: $value"
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

validate_tcp_port() {
    local value="$1"

    is_valid_port "$value" || cli_usage_error "Port must be an integer from 1 to 65535: $value"
}

is_non_option_argument() {
    [[ -n "$1" && "$1" != -* ]]
}

validate_non_option_argument() {
    local value="$1"
    local label="$2"

    is_non_option_argument "$value" || cli_usage_error "$label must not be empty or start with '-': $value"
}

is_one_of() {
    local value="$1"
    shift

    local choice
    for choice in "$@"; do
        [[ "$value" == "$choice" ]] && return 0
    done

    return 1
}

validate_one_of() {
    local value="$1"
    local label="$2"
    shift 2

    is_one_of "$value" "$@" || {
        local choices="$*"
        cli_usage_error "$label must be one of: ${choices// /, } (got: $value)"
    }
}
