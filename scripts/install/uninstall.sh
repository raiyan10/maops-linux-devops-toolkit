#!/usr/bin/env bash

###############################################################################
#
# Script Name : uninstall.sh
# Description : Manifest-verified uninstaller for the MAOps Linux DevOps
#               Toolkit. Never removes anything without first verifying an
#               install manifest belonging to the resolved prefix, and never
#               runs an unrestricted rm -rf against a user-supplied path.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.4.0
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$REPO_ROOT/scripts/common/bootstrap.sh"
# shellcheck source=scripts/install/lib.sh
source "$SCRIPT_DIR/lib.sh"

PURGE_CONFIG=0
ASSUME_YES=0
PREFIX_ARG=""
PREFIX=""
BIN_DIR=""
LIB_DIR=""
LAUNCHER=""
MANIFEST=""

MANIFEST_PREFIX=""
MANIFEST_FILES=()

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [--prefix DIRECTORY] [--purge-config] [--yes]

Options:
    --prefix DIRECTORY   Installation location (default: \$HOME/.local)
    --purge-config       Also remove the user configuration directory
    --yes                Do not prompt for confirmation (required for
                         non-interactive removal)
    -h, --help           Show this help message
    -v, --version        Show project version

Examples:
    $(basename "$0")
    $(basename "$0") --prefix /opt/maops --yes
    $(basename "$0") --purge-config --yes
EOF
}

###############################################################################
# Argument parsing
###############################################################################

parse_args() {
    PREFIX_ARG="${HOME:-}/.local"

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

            --purge-config)
                PURGE_CONFIG=1
                shift
                ;;

            --yes)
                ASSUME_YES=1
                shift
                ;;

            --prefix)
                shift
                [[ $# -gt 0 ]] || cli_usage_error "--prefix requires an argument."
                PREFIX_ARG="$1"
                shift
                ;;

            --prefix=*)
                PREFIX_ARG="${1#--prefix=}"
                shift
                ;;

            *)
                cli_usage_error "Unknown option: $1"
                ;;
        esac
    done

    [[ -z "$PREFIX_ARG" ]] && cli_usage_error "Prefix must not be empty."

    PREFIX="$(install_canonicalize_prefix "$PREFIX_ARG")" || cli_usage_error "Invalid prefix: $PREFIX_ARG"

    if [[ "$PREFIX" == "/" ]]; then
        cli_usage_error "Refusing to operate on the filesystem root."
    fi

    BIN_DIR="$PREFIX/bin"
    LIB_DIR="$PREFIX/lib/maops"
    LAUNCHER="$BIN_DIR/maops"
    MANIFEST="$LIB_DIR/.install-manifest"
}

###############################################################################
# Manifest parsing (plain read-loop, never sourced/eval'd)
###############################################################################

read_manifest_header() {
    local manifest="$1" line
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "--- files ---" ]] && break
        case "$line" in
            MAOPS_INSTALL_PREFIX=*) MANIFEST_PREFIX="${line#MAOPS_INSTALL_PREFIX=}" ;;
        esac
    done <"$manifest"
}

read_manifest_files() {
    local manifest="$1" line in_files=0
    MANIFEST_FILES=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        if ((in_files)); then
            [[ -n "$line" ]] && MANIFEST_FILES+=("$line")
        elif [[ "$line" == "--- files ---" ]]; then
            in_files=1
        fi
    done <"$manifest"
}

###############################################################################
# Confirmation
###############################################################################

confirm_removal() {
    ((ASSUME_YES)) && return 0

    if [[ ! -t 0 ]]; then
        cli_usage_error "Non-interactive removal requires --yes."
    fi

    local reply=""
    read -r -p "Remove MAOps installed at $PREFIX? [y/N] " reply
    case "$reply" in
        y | Y | yes | YES) return 0 ;;
        *)
            log_info "Aborted."
            exit 1
            ;;
    esac
}

###############################################################################
# Removal
###############################################################################

remove_files() {
    local path
    for path in "${MANIFEST_FILES[@]}"; do
        case "$path" in
            "$PREFIX"/*) : ;;
            *)
                log_error "Refusing to remove out-of-prefix path from manifest: $path"
                exit 1
                ;;
        esac

        if [[ -e "$path" || -L "$path" ]]; then
            rm -f -- "$path"
        fi
    done
}

remove_empty_dirs() {
    [[ -d "$LIB_DIR" ]] || return 0

    local dir
    # `find -depth` visits each directory's contents before the directory
    # itself, giving reverse-depth order for free.
    while IFS= read -r dir; do
        if ! rmdir -- "$dir" 2>/dev/null; then
            log_warn "Left non-empty directory in place: $dir"
        fi
    done < <(find "$LIB_DIR" -mindepth 1 -depth -type d)
}

remove_launcher() {
    if [[ -L "$LAUNCHER" ]] && install_launcher_is_ours "$LAUNCHER" "$LIB_DIR"; then
        rm -f -- "$LAUNCHER"
    elif [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
        log_warn "Leaving $LAUNCHER in place (does not resolve to this install)."
    fi
}

purge_config() {
    local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/maops"
    if [[ -d "$cfg_dir" ]]; then
        rm -rf -- "$cfg_dir"
        log_info "Removed configuration directory: $cfg_dir"
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    if [[ ! -f "$MANIFEST" ]]; then
        log_info "Nothing to uninstall at $PREFIX."
        exit 0
    fi

    read_manifest_header "$MANIFEST"

    if [[ "$MANIFEST_PREFIX" != "$PREFIX" ]]; then
        log_error "Manifest at $MANIFEST does not match prefix $PREFIX (found: ${MANIFEST_PREFIX:-<empty>})."
        exit 1
    fi

    confirm_removal

    read_manifest_files "$MANIFEST"
    remove_files
    remove_launcher
    rm -f -- "$MANIFEST"
    remove_empty_dirs
    rmdir -- "$LIB_DIR" 2>/dev/null || true

    if ((PURGE_CONFIG)); then
        purge_config
    fi

    log_success "Uninstalled $PROJECT_NAME from $PREFIX"
}

parse_args "$@"
main
