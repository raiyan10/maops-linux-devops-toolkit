#!/usr/bin/env bash

[[ -n "${MAOPS_OUTPUT_LOADED:-}" ]] && return
readonly MAOPS_OUTPUT_LOADED=1

show_header() {
    print_title "$1"
}

show_section() {
    section "$1"
}

show_footer() {
    divider
}