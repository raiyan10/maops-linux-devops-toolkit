#!/usr/bin/env bash

###############################################################################
#
# Script Name : user-report.sh
# Description : Read-only account report for a local user (passwd fields,
#               group memberships, active session count)
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"

USERNAME=""

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [USERNAME]

Options:
    -h, --help       Show this help message
    -v, --version    Show project version

Arguments:
    USERNAME         User to report on (default: current effective user)

Examples:
    $(basename "$0")
    $(basename "$0") alice
EOF
}

###############################################################################
# Argument parsing
###############################################################################

parse_args() {
    local positional=()

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

            # No other flags are supported; everything else (including a
            # leading-dash value) is collected as the candidate USERNAME so
            # validate_non_option_argument below can report a precise,
            # label-specific error instead of a generic "Unknown option".
            *)
                positional+=("$1")
                shift
                ;;
        esac
    done

    if ((${#positional[@]} > 1)); then
        cli_usage_error "Too many arguments. Expected at most one USERNAME."
    fi

    USERNAME="${positional[0]:-}"

    if [[ -n "$USERNAME" ]]; then
        validate_non_option_argument "$USERNAME" "USERNAME"
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    require_linux
    require_command getent
    require_command id
    require_command who

    local target="${USERNAME:-$(id -un)}"

    show_header "User Report"
    log_info "Collecting account details for $target..."

    local entry
    if ! entry="$(getent passwd -- "$target" 2>/dev/null)"; then
        log_error "User not found: $target"
        exit 1
    fi

    # passwd(5) fields: name:password:uid:gid:gecos:home:shell.
    # The password field is intentionally discarded (into "_") and never
    # printed; this script never reads /etc/shadow or getent shadow, so no
    # password hash is ever handled, let alone exposed. GECOS is also
    # discarded — it can carry a full name/phone/room number that adds
    # nothing to a DevOps account report.
    local name uid gid home shell
    IFS=: read -r name _ uid gid _ home shell <<<"$entry"

    local primary_group
    if ! primary_group="$(id -gn -- "$target" 2>/dev/null)"; then
        log_warn "Primary group name could not be resolved for $target; showing numeric GID only."
        primary_group="$gid"
    fi

    local groups
    if ! groups="$(id -nG -- "$target" 2>/dev/null)"; then
        log_warn "Group names could not be resolved for $target."
        groups="(unavailable)"
    fi

    # The awk program is a fixed single-quoted literal; the username enters
    # only via -v user=, never string-interpolated into the program, so a
    # crafted username cannot inject awk code.
    local session_count
    session_count="$(who 2>/dev/null | awk -v user="$target" '$1 == user { count++ } END { print count + 0 }')"

    local has_session="no"
    if ((session_count > 0)); then
        has_session="yes"
    fi

    print_key_value "Username" "$name"
    print_key_value "UID" "$uid"
    print_key_value "Primary GID" "$gid ($primary_group)"
    print_key_value "Home directory" "$home"
    print_key_value "Login shell" "$shell"
    print_key_value "Groups" "$groups"
    print_key_value "Logged-in sessions" "$session_count"
    print_key_value "Has active session" "$has_session"

    log_success "User report completed."
}

parse_args "$@"
main
