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
#
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/common/bootstrap.sh
source "$REPO_ROOT/scripts/common/bootstrap.sh"
# shellcheck source=scripts/common/release-files.sh
source "$REPO_ROOT/scripts/common/release-files.sh"
# shellcheck source=scripts/common/integrity.sh
source "$REPO_ROOT/scripts/common/integrity.sh"
# shellcheck source=scripts/install/lib.sh
source "$SCRIPT_DIR/lib.sh"

FORCE=0
PREFIX_ARG=""
PREFIX=""
BIN_DIR=""
LIB_DIR=""
LAUNCHER=""
MANIFEST=""
SOURCE_MODE=""

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

    # LIB_DIR can exist without a manifest (a pre-manifest-era install, a
    # manually cleaned-up prior install, or unrelated content that happens
    # to sit there) -- do_install would otherwise move it aside and delete
    # it unconditionally. Require --force here too, the same discipline
    # check_launcher_safety already applies to an unrecognized file at
    # LAUNCHER, rather than treating "no manifest" as "safe to destroy."
    if [[ -d "$LIB_DIR" ]]; then
        if ((FORCE)); then
            return 0
        fi

        log_error "Refusing to install over existing, unrecognized content at $LIB_DIR (use --force to replace it, or remove it manually first)."
        exit 1
    fi
}

###############################################################################
# Source-mode detection
###############################################################################

# install_detect_source_mode
# Determines whether REPO_ROOT is a Git checkout (mode "git" -- modes are
# derived from Git's index) or an extracted release archive (mode
# "archive" -- modes and content are derived from the package's trusted
# MAOPS-MANIFEST.tsv). Fails closed rather than guessing: neither source
# present is fatal, and so is both being present at once (a state with no
# legitimate cause).
install_detect_source_mode() {
    local has_git=0 has_manifest=0

    if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        has_git=1
    fi
    [[ -f "$REPO_ROOT/MAOPS-MANIFEST.tsv" ]] && has_manifest=1

    if ((has_git && has_manifest)); then
        log_error "Ambiguous install source: both a Git checkout and a MAOPS-MANIFEST.tsv are present at $REPO_ROOT."
        exit 1
    elif ((has_git)); then
        SOURCE_MODE="git"
    elif ((has_manifest)); then
        SOURCE_MODE="archive"
    else
        log_error "Cannot determine install source: no Git checkout and no MAOPS-MANIFEST.tsv found at $REPO_ROOT."
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

# install_stage_from_git STAGING
# Source-tree install: derives every file's mode from Git's index via the
# same integrity_copy_git_tracked helper package.sh uses, so the two can
# never disagree on what a "correct" install/package looks like.
install_stage_from_git() {
    local staging="$1"
    local manifest_tmp="$staging/.manifest.tmp"

    if ! integrity_copy_git_tracked "$staging" "$REPO_ROOT" "${RELEASE_FILE_LIST[@]}" >"$manifest_tmp"; then
        log_error "${INTEGRITY_LAST_ERROR:-Failed to stage Git-tracked release files.}"
        exit 1
    fi

    LC_ALL=C sort -o "$staging/.integrity-manifest" "$manifest_tmp"
    rm -f -- "$manifest_tmp"
    find "$staging" -type d -exec chmod 0755 {} +
}

# install_stage_from_archive STAGING
# Archive install: verifies REPO_ROOT/MAOPS-MANIFEST.tsv -- each entry's
# source file must exist, and its real SHA-256 (computed from the staged
# copy, not a separate read of the source) must match -- before that
# entry's copy is trusted; the first bad entry aborts the whole install
# before STAGING is ever promoted to a live install. Modes are applied
# from the manifest's MODE field, never derived from the extracted
# archive's own stat.
install_stage_from_archive() {
    local staging="$1"

    if ! integrity_verify_and_copy_from_manifest "$staging" "$REPO_ROOT" "$REPO_ROOT/MAOPS-MANIFEST.tsv"; then
        log_error "${INTEGRITY_LAST_ERROR:-Failed to verify the package manifest.}"
        exit 1
    fi

    LC_ALL=C sort -o "$staging/.integrity-manifest" "$REPO_ROOT/MAOPS-MANIFEST.tsv"
    find "$staging" -type d -exec chmod 0755 {} +
}

do_install() {
    mkdir -p -- "$PREFIX/lib" "$BIN_DIR"

    # Staged under $PREFIX/lib (same filesystem as the final destination)
    # so the swap below is a same-filesystem rename, never a cross-device
    # copy+unlink fallback. The EXIT trap ensures a staging directory left
    # behind by a failed install_stage_from_*/write_manifest call (which
    # exit directly, without unwinding through here) never accumulates as
    # stale garbage under $PREFIX/lib.
    local staging
    staging="$(mktemp -d -- "$PREFIX/lib/.maops-staging.XXXXXX")"
    trap 'rm -rf -- "$staging"' EXIT

    if [[ "$SOURCE_MODE" == "git" ]]; then
        install_stage_from_git "$staging"
    else
        install_stage_from_archive "$staging"
    fi

    write_manifest "$staging"

    # Re-verify immediately before the first mutation of the live install:
    # check_launcher_safety already ran once in main(), but the staging
    # work above takes real time, and a shared/writable PREFIX/bin could
    # have had something planted at LAUNCHER in that window. Re-checking
    # here -- before LIB_DIR or LAUNCHER are touched at all -- means a
    # failure at this point still leaves the install fully untouched,
    # rather than only re-checking right before ln -sfn, which would leave
    # LIB_DIR already swapped but the launcher not yet updated on failure.
    check_launcher_safety

    local previous=""
    if [[ -d "$LIB_DIR" ]]; then
        # mktemp -u prints a name guaranteed not to already exist without
        # creating it, so `mv` below performs the rename onto a fresh,
        # unpredictable path rather than a PID-suffixed (guessable) one.
        previous="$(mktemp -d -u -- "$PREFIX/lib/.maops-old.XXXXXX")"
        mv -- "$LIB_DIR" "$previous"
    fi

    mv -- "$staging" "$LIB_DIR"
    trap - EXIT
    ln -sfn -- "../lib/maops/bin/maops" "$LAUNCHER"

    # The previous tree is only ever removed after the new one is
    # confirmed live, and only via a name this script itself generated
    # (a private mktemp-allocated sibling under $PREFIX/lib) — never a raw
    # rm -rf against user-supplied input.
    if [[ -n "$previous" && -d "$previous" ]]; then
        rm -rf -- "$previous"
    fi
}

###############################################################################
# Main
###############################################################################

main() {
    install_detect_source_mode
    check_launcher_safety
    check_existing_install
    do_install

    log_success "Installed $PROJECT_NAME $PROJECT_VERSION to $PREFIX"
    log_info "Run: $LAUNCHER --version"
}

parse_args "$@"
main
