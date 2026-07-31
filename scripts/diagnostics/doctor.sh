#!/usr/bin/env bash

###############################################################################
#
# Script Name : doctor.sh
# Description : Read-only environment/health diagnostic for the MAOps Linux
#               DevOps Toolkit. Never modifies the system and never makes a
#               network request — every check is a command-presence,
#               version-string, or local file-existence read.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.4.0
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"
# shellcheck source=scripts/common/config-file.sh
source "$SCRIPT_DIR/../common/config-file.sh"
# shellcheck source=scripts/common/format.sh
source "$SCRIPT_DIR/../common/format.sh"

readonly REQUIRED_COMMANDS=(bash awk find sort ps getent ip ping timeout df free lscpu uptime)
readonly OPTIONAL_COMMANDS=(git make shellcheck bats python3)

FORMAT="text"

CHECK_NAMES=()
CHECK_STATUSES=()
CHECK_REQUIRED=()
CHECK_DETAILS=()

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [--format text|json]

Options:
    -h, --help       Show this help message
    -v, --version    Show project version
    --format FORMAT  Output format: text (default) or json

Examples:
    $(basename "$0")
    $(basename "$0") --format json
EOF
}

###############################################################################
# Argument parsing
###############################################################################

parse_args() {
    local explicit_format=""

    while (($# > 0)); do
        case "$1" in
            -h | --help)
                usage
                exit 0
                ;;

            -v | --version)
                cli_show_version
                exit 0
                ;;

            --format)
                shift
                [[ $# -gt 0 ]] || cli_usage_error "--format requires an argument."
                explicit_format="$1"
                shift
                ;;

            --format=*)
                explicit_format="${1#--format=}"
                shift
                ;;

            *)
                cli_usage_error "Unknown option: $1"
                ;;
        esac
    done

    FORMAT="$(config_resolve_value output_format "$explicit_format" MAOPS_OUTPUT_FORMAT text)"
    validate_one_of "$FORMAT" "--format" text json
}

###############################################################################
# Check collection
###############################################################################

add_check() {
    CHECK_NAMES+=("$1")
    CHECK_STATUSES+=("$2")
    CHECK_REQUIRED+=("$3")
    CHECK_DETAILS+=("$4")
}

run_checks() {
    add_check "toolkit_version" "info" "false" "$PROJECT_VERSION"

    local exec_mode="source-tree"
    [[ -f "$REPO_ROOT/.install-manifest" ]] && exec_mode="installed"
    add_check "execution_mode" "info" "false" "$exec_mode"

    local os_name
    os_name="$(uname -s)"
    if [[ "$os_name" == "Linux" ]]; then
        add_check "operating_system" "pass" "true" "$os_name"
    else
        add_check "operating_system" "fail" "true" "$os_name (Linux required)"
    fi

    if ((BASH_VERSINFO[0] >= 4)); then
        add_check "bash_version" "pass" "true" "$BASH_VERSION"
    else
        add_check "bash_version" "fail" "true" "$BASH_VERSION (requires >= 4)"
    fi

    local cfg_path
    cfg_path="$(config_default_path)"
    add_check "config_path" "info" "false" "$cfg_path"

    if [[ -f "$cfg_path" ]]; then
        add_check "config_exists" "pass" "false" "present"

        if config_validate_file "$cfg_path"; then
            add_check "config_valid" "pass" "true" "valid"
        else
            add_check "config_valid" "fail" "true" "invalid: ${CONFIG_VALIDATION_ERRORS[0]:-unknown error}"
        fi
    else
        # A missing config file is normal on a fresh install or source
        # checkout (every value falls back to a built-in default) — this is
        # a warning, never a required failure.
        add_check "config_exists" "warn" "false" "not found"
    fi

    local cmd
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if command_exists "$cmd"; then
            add_check "command_$cmd" "pass" "true" "present"
        else
            add_check "command_$cmd" "fail" "true" "missing"
        fi
    done

    # systemctl and service(8) are treated as an either/or requirement,
    # mirroring scripts/service/service-status.sh's own systemd-vs-fallback
    # detection — a host only needs one working service manager, not both.
    if command_exists systemctl || command_exists service; then
        local detail="systemctl"
        command_exists systemctl || detail="service"
        add_check "service_manager" "pass" "true" "$detail"
    else
        add_check "service_manager" "fail" "true" "neither systemctl nor service found"
    fi

    for cmd in "${OPTIONAL_COMMANDS[@]}"; do
        if command_exists "$cmd"; then
            add_check "dev_$cmd" "pass" "false" "present"
        else
            add_check "dev_$cmd" "warn" "false" "missing"
        fi
    done
}

required_failed() {
    local i
    for i in "${!CHECK_STATUSES[@]}"; do
        if [[ "${CHECK_REQUIRED[$i]}" == "true" && "${CHECK_STATUSES[$i]}" == "fail" ]]; then
            return 0
        fi
    done
    return 1
}

###############################################################################
# Rendering
###############################################################################

render_text() {
    show_header "MAOps Doctor"

    local i
    for i in "${!CHECK_NAMES[@]}"; do
        printf "%-22s : %-6s %s\n" "${CHECK_NAMES[$i]}" "${CHECK_STATUSES[$i]}" "${CHECK_DETAILS[$i]}"
    done

    echo
    if required_failed; then
        log_error "Doctor found required issues."
    else
        log_success "All required checks passed."
    fi
}

render_json() {
    local parts=() i
    for i in "${!CHECK_NAMES[@]}"; do
        parts+=("$(printf '{%s,%s,%s,%s}' \
            "$(json_kv name "${CHECK_NAMES[$i]}")" \
            "$(json_kv status "${CHECK_STATUSES[$i]}")" \
            "$(json_kv required "${CHECK_REQUIRED[$i]}" --raw)" \
            "$(json_kv detail "${CHECK_DETAILS[$i]}")")")
    done

    local checks_json=""
    if ((${#parts[@]} > 0)); then
        checks_json="$(
            IFS=,
            printf '%s' "${parts[*]}"
        )"
    fi

    local overall="pass"
    if required_failed; then
        overall="fail"
    fi

    printf '{%s,%s,"checks":[%s],%s}\n' \
        "$(json_kv version "$PROJECT_VERSION")" \
        "$(json_kv execution_mode "$([[ -f "$REPO_ROOT/.install-manifest" ]] && echo installed || echo source-tree)")" \
        "$checks_json" \
        "$(json_kv overall "$overall")"
}

###############################################################################
# Main
###############################################################################

main() {
    run_checks

    if [[ "$FORMAT" == "json" ]]; then
        render_json
    else
        render_text
    fi

    if required_failed; then
        exit 1
    fi
    exit 0
}

parse_args "$@"
main
