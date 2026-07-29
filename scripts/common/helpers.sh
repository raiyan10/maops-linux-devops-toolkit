#!/usr/bin/env bash

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {

    if ! command_exists "$1"; then
        echo "$1 is required."

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

print_key_value() {
    printf "%-20s : %s\n" "$1" "$2"
}

section() {
    echo
    divider
    echo "$1"
    divider
}

require_linux() {
    if [[ "$(uname -s)" != "Linux" ]]; then
        echo "This script only supports Linux."
        exit 1
    fi
}