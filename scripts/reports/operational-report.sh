#!/usr/bin/env bash

###############################################################################
#
# Script Name : operational-report.sh
# Description : Read-only operational report for the MAOps Linux DevOps
#               Toolkit. Consolidates toolkit version, execution mode,
#               local system/resource facts, configuration state, and the
#               doctor/integrity pass-fail verdicts into one document (text
#               or JSON), optionally redacted, optionally saved atomically
#               to a file. Never modifies the system and never makes a
#               network request -- every field is a local, read-only fact.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
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
# shellcheck source=scripts/common/reporting.sh
source "$SCRIPT_DIR/../common/reporting.sh"

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") summary [--format text|json] [--redact]
    $(basename "$0") save --output PATH [--format text|json] [--redact] [--force]

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Subcommands:
    summary          Print an operational report to stdout
    save             Write an operational report to a file atomically

Examples:
    $(basename "$0") summary
    $(basename "$0") summary --format json
    $(basename "$0") summary --redact
    $(basename "$0") save --output /tmp/report.json --format json
    $(basename "$0") save --output /tmp/report.txt --force
EOF
}

usage_error() {
    log_error "$1"
    usage >&2
    exit 2
}

###############################################################################
# Rendering
###############################################################################

render_text() {
    show_header "MAOps Operational Report"

    print_key_value "version" "$REPORT_VERSION"
    print_key_value "generated_at_utc" "$REPORT_GENERATED_AT"
    print_key_value "execution_mode" "$REPORT_EXEC_MODE"

    echo
    print_key_value "system.hostname" "$REPORT_HOSTNAME"
    print_key_value "system.operating_system" "$REPORT_OS_DESCRIPTION"
    print_key_value "system.kernel" "$REPORT_KERNEL"
    print_key_value "system.architecture" "$REPORT_ARCH"
    print_key_value "system.logical_cpu_count" "$REPORT_CPU_COUNT"

    echo
    print_key_value "resources.load_average" "$REPORT_LOAD_AVERAGE"
    print_key_value "resources.memory_total" "$REPORT_MEM_TOTAL"
    print_key_value "resources.memory_available" "$REPORT_MEM_AVAILABLE"
    print_key_value "resources.root_filesystem_size" "$REPORT_ROOTFS_SIZE"
    print_key_value "resources.root_filesystem_used" "$REPORT_ROOTFS_USED"
    print_key_value "resources.root_filesystem_available" "$REPORT_ROOTFS_AVAILABLE"
    print_key_value "resources.root_filesystem_usage_percent" "$REPORT_ROOTFS_PERCENT"

    echo
    print_key_value "configuration.path" "$REPORT_CONFIG_PATH"
    print_key_value "configuration.exists" "$REPORT_CONFIG_EXISTS"
    print_key_value "configuration.valid" "$REPORT_CONFIG_VALID"

    echo
    print_key_value "doctor.overall" "$REPORT_DOCTOR_OVERALL"
    print_key_value "integrity.overall" "$REPORT_INTEGRITY_OVERALL"

    # Deliberately plain (no log_success/log_warn/log_error, which are
    # colorized): this text body is shared verbatim by `report save`, and a
    # file must never contain ANSI escapes regardless of whether the
    # invoking terminal happens to be interactive -- colors.sh fixes color
    # on/off once at process start, before this function knows whether its
    # output is headed for a terminal or a saved file.
    echo
    print_key_value "overall" "$REPORT_OVERALL"
}

render_json() {
    printf '{%s,%s,%s,"system":{%s,%s,%s,%s,%s},"resources":{%s,%s,%s,%s,%s,%s,%s},"configuration":{%s,%s,%s},"doctor":{%s},"integrity":{%s},%s}\n' \
        "$(json_kv version "$REPORT_VERSION")" \
        "$(json_kv generated_at_utc "$REPORT_GENERATED_AT")" \
        "$(json_kv execution_mode "$REPORT_EXEC_MODE")" \
        "$(json_kv hostname "$REPORT_HOSTNAME")" \
        "$(json_kv operating_system "$REPORT_OS_DESCRIPTION")" \
        "$(json_kv kernel "$REPORT_KERNEL")" \
        "$(json_kv architecture "$REPORT_ARCH")" \
        "$(json_kv logical_cpu_count "$REPORT_CPU_COUNT" --raw)" \
        "$(json_kv load_average "$REPORT_LOAD_AVERAGE")" \
        "$(json_kv memory_total "$REPORT_MEM_TOTAL")" \
        "$(json_kv memory_available "$REPORT_MEM_AVAILABLE")" \
        "$(json_kv root_filesystem_size "$REPORT_ROOTFS_SIZE")" \
        "$(json_kv root_filesystem_used "$REPORT_ROOTFS_USED")" \
        "$(json_kv root_filesystem_available "$REPORT_ROOTFS_AVAILABLE")" \
        "$(json_kv root_filesystem_usage_percent "$REPORT_ROOTFS_PERCENT")" \
        "$(json_kv path "$REPORT_CONFIG_PATH")" \
        "$(json_kv exists "$REPORT_CONFIG_EXISTS" --raw)" \
        "$(json_kv valid "$REPORT_CONFIG_VALID" --raw)" \
        "$(json_kv overall "$REPORT_DOCTOR_OVERALL")" \
        "$(json_kv overall "$REPORT_INTEGRITY_OVERALL")" \
        "$(json_kv overall "$REPORT_OVERALL")"
}

render_report() {
    local format="$1"
    if [[ "$format" == "json" ]]; then
        render_json
    else
        render_text
    fi
}

###############################################################################
# Subcommands
###############################################################################

cmd_summary() {
    local format="" redact=0

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

            --redact)
                redact=1
                shift
                ;;

            *)
                cli_usage_error "Unknown option: $1"
                ;;
        esac
    done

    format="$(config_resolve_value output_format "$format" MAOPS_OUTPUT_FORMAT text)"
    validate_one_of "$format" "--format" text json

    reporting_collect
    ((redact)) && reporting_redact
    reporting_overall

    render_report "$format"

    [[ "$REPORT_OVERALL" == "pass" ]] && exit 0
    exit 1
}

cmd_save() {
    local format="" redact=0 force=0 output=""

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

            --redact)
                redact=1
                shift
                ;;

            --force)
                force=1
                shift
                ;;

            --output)
                shift
                [[ $# -gt 0 ]] || cli_usage_error "--output requires an argument."
                output="$1"
                shift
                ;;

            --output=*)
                output="${1#--output=}"
                shift
                ;;

            *)
                cli_usage_error "Unknown option: $1"
                ;;
        esac
    done

    [[ -z "$output" ]] && cli_usage_error "report save: --output PATH is required."
    validate_non_option_argument "$output" "--output"

    format="$(config_resolve_value output_format "$format" MAOPS_OUTPUT_FORMAT text)"
    validate_one_of "$format" "--format" text json

    reporting_collect
    ((redact)) && reporting_redact
    reporting_overall

    local content
    content="$(render_report "$format")"

    umask 077
    local force_flag="0"
    ((force)) && force_flag="1"

    if ! report_save_atomic "$output" "$content" "$force_flag"; then
        log_error "Failed to save report to $output: $REPORT_SAVE_LAST_ERROR"
        exit 1
    fi

    log_success "Report saved to $output"

    [[ "$REPORT_OVERALL" == "pass" ]] && exit 0
    exit 1
}

###############################################################################
# Main
###############################################################################

main() {
    if (($# == 0)); then
        usage_error "Missing subcommand. Expected: summary, save"
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
        summary) cmd_summary "$@" ;;
        save) cmd_save "$@" ;;
        *) usage_error "Unknown report command: $subcommand (expected: summary, save)" ;;
    esac
}

main "$@"
