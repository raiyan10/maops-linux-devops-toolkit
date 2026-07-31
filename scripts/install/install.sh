#!/usr/bin/env bash

###############################################################################
#
# Script Name : install.sh
# Description : User-local installer for the MAOps Linux DevOps Toolkit.
#               Never requires sudo, never installs system-wide by default,
#               stages the runtime tree before replacing anything, and
#               records an install manifest so uninstall.sh can safely
#               identify exactly what it owns.
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
# shellcheck source=scripts/common/release-files.sh
source "$REPO_ROOT/scripts/common/release-files.sh"
# shellcheck source=scripts/install/lib.sh
source "$SCRIPT_DIR/lib.sh"

FORCE=0
PREFIX_ARG=""
PREFIX=""
BIN_DIR=""
LIB_DIR=""
LAUNCHER=""
MANIFEST=""

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [--prefix DIRECTORY] [--force]

Options:
    --prefix DIRECTORY   Install location (default: \$HOME/.local)
    --force              Reinstall/upgrade over an existing MAOps install
    -h, --help           Show this help message
    -v, --version        Show project version

Examples:
    $(basename "$0")
    $(basename "$0") --prefix /opt/maops
    $(basename "$0") --force
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

            --force)
                FORCE=1
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
        cli_usage_error "Refusing to install to the filesystem root."
    fi

    BIN_DIR="$PREFIX/bin"
    LIB_DIR="$PREFIX/lib/maops"
    LAUNCHER="$BIN_DIR/maops"
    MANIFEST="$LIB_DIR/.install-manifest"
}

###############################################################################
# Safety checks (run before any filesystem mutation)
###############################################################################

check_launcher_safety() {
    if [[ -e "$LAUNCHER" || -L "$LAUNCHER" ]]; then
        if install_launcher_is_ours "$LAUNCHER" "$LIB_DIR"; then
            return 0
        fi

        # --force never overrides this refusal: it exists only to permit
        # replacing a *verified* prior MAOps installation, never to
        # overwrite an unrelated file the user happens to have at this path.
        log_error "Refusing to overwrite unrelated file at $LAUNCHER."
        log_error "Move or remove it manually, then re-run install."
        exit 1
    fi
}

check_existing_install() {
    if [[ -f "$MANIFEST" ]]; then
        if ((FORCE)); then
            return 0
        fi

        log_error "MAOps is already installed at $PREFIX (use --force to reinstall/upgrade)."
        exit 1
    fi
}

###############################################################################
# Install
###############################################################################

write_manifest() {
    local staging="$1"
    local manifest_tmp="$staging/.install-manifest"

    {
        printf 'MAOPS_INSTALL_VERSION=%s\n' "$PROJECT_VERSION"
        printf 'MAOPS_INSTALL_PREFIX=%s\n' "$PREFIX"
        printf 'MAOPS_INSTALL_DATE=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf -- '--- files ---\n'
        find "$staging" -type f -not -name '.install-manifest' | sed "s|^$staging|$LIB_DIR|" | LC_ALL=C sort
    } >"$manifest_tmp"
}

do_install() {
    mkdir -p -- "$PREFIX/lib" "$BIN_DIR"

    # Staged under $PREFIX/lib (same filesystem as the final destination)
    # so the swap below is a same-filesystem rename, never a cross-device
    # copy+unlink fallback.
    local staging
    staging="$(mktemp -d -- "$PREFIX/lib/.maops-staging.XXXXXX")"

    local entry src dest
    for entry in "${RELEASE_FILE_LIST[@]}"; do
        src="$REPO_ROOT/$entry"
        dest="$staging/$entry"
        mkdir -p -- "$(dirname -- "$dest")"
        cp -a -- "$src" "$dest"
    done

    write_manifest "$staging"

    local previous=""
    if [[ -d "$LIB_DIR" ]]; then
        previous="$LIB_DIR.old.$$"
        mv -- "$LIB_DIR" "$previous"
    fi

    mv -- "$staging" "$LIB_DIR"
    ln -sfn -- "../lib/maops/bin/maops" "$LAUNCHER"

    # The previous tree is only ever removed after the new one is
    # confirmed live, and only via a name this script itself generated
    # (a PID-suffixed sibling under $PREFIX/lib) — never a raw rm -rf
    # against user-supplied input.
    if [[ -n "$previous" && -d "$previous" ]]; then
        rm -rf -- "$previous"
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    check_launcher_safety
    check_existing_install
    do_install

    log_success "Installed $PROJECT_NAME $PROJECT_VERSION to $PREFIX"
    log_info "Run: $LAUNCHER --version"
}

parse_args "$@"
main
