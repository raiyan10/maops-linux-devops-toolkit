#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/helpers.sh"

show_header() {
    print_title "$1"
}

show_footer() {
    echo
    divider
}

show_section() {
    section "$1"
}