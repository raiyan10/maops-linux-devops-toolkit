#!/usr/bin/env bash

[[ -n "${MAOPS_HELPERS_LOADED:-}" ]] && return
readonly MAOPS_HELPERS_LOADED=1

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {

    if ! command_exists "$1"; then
        echo "Required command not found: $1"
        exit 1
    fi
}

require_linux() {

    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "This toolkit supports Linux only."
        exit 1
    fi
}

divider() {
    printf '%0.s-' {1..80}
    echo
}

print_title() {

    divider
    echo "$1"
    divider
}

section() {

    echo
    divider
    echo "$1"
    divider
}

print_key_value() {

    printf "%-20s : %s\n" "$1" "$2"
}