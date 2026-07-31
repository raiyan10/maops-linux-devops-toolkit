#!/usr/bin/env bash

###############################################################################
#
# Script Name : config-manager.sh
# Description : Configuration subcommands (path, init, show, validate) for
#               the MAOps configuration system
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.4.0
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"
# shellcheck source=scripts/common/config-file.sh
source "$SCRIPT_DIR/../common/config-file.sh"
# shellcheck source=scripts/common/format.sh
source "$SCRIPT_DIR/../common/format.sh"

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") path
    $(basename "$0") init [--force]
    $(basename "$0") show [--format text|json]
    $(basename "$0") validate [PATH]

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Subcommands:
    path             Print the resolved configuration file path
    init             Create a default configuration file
    show             Display effective configuration values
    validate         Validate a configuration file (default: resolved path)

Examples:
    $(basename "$0") path
    $(basename "$0") init
    $(basename "$0") init --force
    $(basename "$0") show
    $(basename "$0") show --format json
    $(basename "$0") validate
    $(basename "$0") validate /path/to/config
EOF
}

###############################################################################
# Subcommands
###############################################################################

cmd_path() {
    if (($# > 0)); then
        if is_help_flag "$1"; then
            usage
            exit 0
        fi
        cli_usage_error "Unexpected argument: $1"
    fi

    config_default_path
}

cmd_init() {
    local force=0

    while (($# > 0)); do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;

            --force)
                force=1
                shift
                ;;

            *)
                cli_usage_error "Unknown option: $1"
                ;;
        esac
    done

    local target
    target="$(config_default_path)"

    if [[ -e "$target" && "$force" -ne 1 ]]; then
        log_error "Config already exists at $target (use --force to overwrite)."
        exit 1
    fi

    umask 077
    config_write_atomic "$target" "$(config_default_template)"
    log_success "Initialized config at $target"
}

cmd_show() {
    local format="text"

    while (($# > 0)); do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;

            --format)
                shift
                [[ $# -gt 0 ]] || cli_usage_error "--format requires an argument."
                format="$1"
                shift
                ;;

            --format=*)
                format="${1#--format=}"
                shift
                ;;

            *)
                cli_usage_error "Unknown option: $1"
                ;;
        esac
    done

    validate_one_of "$format" "--format" text json

    local output_format process_limit ping_count network_timeout
    output_format="$(config_resolve_value output_format "" MAOPS_OUTPUT_FORMAT text)"
    process_limit="$(config_resolve_value process_limit "" MAOPS_PROCESS_LIMIT 10)"
    ping_count="$(config_resolve_value ping_count "" MAOPS_PING_COUNT 4)"
    network_timeout="$(config_resolve_value network_timeout "" MAOPS_NETWORK_TIMEOUT "$DEFAULT_TIMEOUT")"

    if [[ "$format" == "json" ]]; then
        printf '{%s,%s,%s,%s}\n' \
            "$(json_kv output_format "$output_format")" \
            "$(json_kv process_limit "$process_limit" --raw)" \
            "$(json_kv ping_count "$ping_count" --raw)" \
            "$(json_kv network_timeout "$network_timeout" --raw)"
    else
        print_key_value "output_format" "$output_format"
        print_key_value "process_limit" "$process_limit"
        print_key_value "ping_count" "$ping_count"
        print_key_value "network_timeout" "$network_timeout"
    fi
}

cmd_validate() {
    local target=""

    if (($# > 0)) && is_help_flag "$1"; then
        usage
        exit 0
    fi

    if (($# > 0)); then
        target="$1"
        shift
    fi

    if (($# > 0)); then
        cli_usage_error "Unexpected argument: $1"
    fi

    [[ -z "$target" ]] && target="$(config_default_path)"

    if [[ ! -e "$target" ]]; then
        log_error "Config file not found: $target"
        exit 1
    fi

    if config_validate_file "$target"; then
        log_success "Config is valid: $target"
        exit 0
    fi

    log_error "Config is invalid: $target"
    local err
    for err in "${CONFIG_VALIDATION_ERRORS[@]}"; do
        log_error "  $err"
    done
    exit 1
}

###############################################################################
# Main
###############################################################################

main() {
    if (($# == 0)); then
        cli_usage_error "Missing subcommand. Expected: path, init, show, validate"
    fi

    if is_help_flag "$1"; then
        usage
        exit 0
    fi

    if is_version_flag "$1"; then
        cli_show_version
        exit 0
    fi

    local subcommand="$1"
    shift

    case "$subcommand" in
        path) cmd_path "$@" ;;
        init) cmd_init "$@" ;;
        show) cmd_show "$@" ;;
        validate) cmd_validate "$@" ;;
        *) cli_usage_error "Unknown config command: $subcommand (expected: path, init, show, validate)" ;;
    esac
}

main "$@"
