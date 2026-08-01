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
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$REPO_ROOT/scripts/common/bootstrap.sh"
# shellcheck source=scripts/install/lib.sh
source "$SCRIPT_DIR/lib.sh"
# shellcheck source=scripts/common/integrity.sh
source "$REPO_ROOT/scripts/common/integrity.sh"

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
            # A blank line inside the file-list section is never written by
            # install.sh's write_manifest -- treat it as a malformed/tampered
            # manifest and abort immediately (with a clear message) rather
            # than silently skip it, which is what the task's "reject empty
            # entries" requirement calls for.
            if [[ -z "$line" ]]; then
                log_error "Malformed manifest: empty file entry."
                exit 1
            fi
            MANIFEST_FILES+=("$line")
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
# Manifest validation (read-only; runs before anything is removed)
###############################################################################

# validate_manifest_files
# Validates every entry in MANIFEST_FILES before remove_files() ever calls
# rm. Fails closed on the whole manifest -- a single unsafe, malformed, or
# duplicate entry aborts the entire uninstall with zero files removed,
# rather than skipping just the bad entry. Entries are restricted to
# LIB_DIR specifically (not merely PREFIX), since PREFIX is frequently a
# shared location (e.g. $HOME/.local) hosting other tools' files under
# sibling directories like PREFIX/bin or PREFIX/share that this manifest
# must never be able to reach.
validate_manifest_files() {
    local path
    local -A seen=()

    for path in "${MANIFEST_FILES[@]}"; do
        if [[ -z "$path" ]]; then
            log_error "Malformed manifest: empty file entry."
            exit 1
        fi

        case "$path" in
            "$LIB_DIR"/*) : ;;
            *)
                log_error "Refusing manifest entry outside $LIB_DIR: $path"
                exit 1
                ;;
        esac

        if integrity_path_has_dotdot_component "$path"; then
            log_error "Refusing manifest entry with path traversal: $path"
            exit 1
        fi

        if [[ -n "${seen[$path]:-}" ]]; then
            log_error "Duplicate manifest entry: $path"
            exit 1
        fi
        seen[$path]=1
    done
}

###############################################################################
# Removal
###############################################################################

# remove_files
# Assumes validate_manifest_files has already verified every path is
# well-formed and confined to LIB_DIR -- this loop only checks existence
# before removing, it never re-derives safety here.
remove_files() {
    local path
    for path in "${MANIFEST_FILES[@]}"; do
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

    # The same "never operate on/near the filesystem root" discipline
    # parse_args already applies to PREFIX -- an empty or unset
    # HOME/XDG_CONFIG_HOME would otherwise resolve cfg_dir to "/maops" or
    # "/.config/maops", uncomfortably close to the root for an rm -rf.
    case "$cfg_dir" in
        /maops | /.config/maops | "")
            log_error "Refusing to purge an unsafe configuration path: ${cfg_dir:-<empty>}"
            exit 1
            ;;
    esac

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

    read_manifest_files "$MANIFEST"
    validate_manifest_files

    confirm_removal

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
