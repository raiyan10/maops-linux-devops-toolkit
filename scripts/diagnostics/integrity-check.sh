#!/usr/bin/env bash

###############################################################################
#
# Script Name : integrity-check.sh
# Description : Read-only integrity verification for the MAOps Linux
#               DevOps Toolkit. In an installed tree, verifies every file
#               listed in PREFIX/lib/maops/.integrity-manifest (existence,
#               SHA-256 content, and mode). In a source-tree checkout,
#               verifies tracked release-file content and expected
#               executable modes directly from Git's index -- never from
#               working-tree stat, which is not trustworthy on filesystems
#               such as WSL/drvfs that misreport tracked-file permissions.
#               Never modifies or repairs anything.
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
# shellcheck source=scripts/common/integrity.sh
source "$SCRIPT_DIR/../common/integrity.sh"
# shellcheck source=scripts/common/release-files.sh
source "$SCRIPT_DIR/../common/release-files.sh"

FORMAT="text"
EXEC_MODE=""

CHECKED_COUNT=0
PASSED_COUNT=0
FAILURE_PATHS=()
FAILURE_CATEGORIES=()
FAILURE_DETAILS=()

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [--format text|json]

Verifies release integrity: an installed tree against
PREFIX/lib/maops/.integrity-manifest, or a source-tree checkout against
Git's tracked index. Never modifies or repairs anything.

Options:
    -h, --help       Show this help message
    -v, --version    Show project version
    --format FORMAT  Output format: text (default) or json

Examples:
    $(basename "$0")
    $(basename "$0") --format json
EOF
}

###############################################################################
# Argument parsing
###############################################################################

parse_args() {
    local explicit_format=""

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

            --format)
                shift
                [[ $# -gt 0 ]] || cli_usage_error "--format requires an argument."
                explicit_format="$1"
                shift
                ;;

            --format=*)
                explicit_format="${1#--format=}"
                shift
                ;;

            *)
                cli_usage_error "Unknown option: $1"
                ;;
        esac
    done

    FORMAT="$(config_resolve_value output_format "$explicit_format" MAOPS_OUTPUT_FORMAT text)"
    validate_one_of "$FORMAT" "--format" text json
}

###############################################################################
# Execution-mode detection
###############################################################################

# detect_execution_mode
# Installed mode is recognized by the presence of .integrity-manifest at
# REPO_ROOT (which resolves to LIB_DIR when this script runs from an
# installed tree, exactly like doctor.sh's own execution_mode check).
# Source-tree mode requires real Git metadata -- a directory that is
# neither an installed tree nor a Git checkout has nothing trustworthy to
# verify against, so this exits 1 rather than guessing.
detect_execution_mode() {
    if [[ -f "$REPO_ROOT/.integrity-manifest" ]]; then
        EXEC_MODE="installed"
    elif git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        EXEC_MODE="source-tree"
    else
        log_error "No .integrity-manifest found and no Git metadata available at $REPO_ROOT."
        exit 1
    fi
}

###############################################################################
# Check collection
###############################################################################

add_failure() {
    FAILURE_PATHS+=("$1")
    FAILURE_CATEGORIES+=("$2")
    FAILURE_DETAILS+=("$3")
}

# run_installed_checks
# Reads PREFIX/lib/maops/.integrity-manifest and verifies every entry:
# existence, then SHA-256 content, then mode -- in that priority order, so
# each file contributes at most one failure entry. Never writes anything.
run_installed_checks() {
    local manifest="$REPO_ROOT/.integrity-manifest"

    if ! integrity_read_manifest "$manifest"; then
        add_failure "$manifest" "malformed-manifest" "$INTEGRITY_LAST_ERROR"
        return 0
    fi

    local i path abs_path actual_sha actual_mode
    for i in "${!INTEGRITY_MANIFEST_PATHS[@]}"; do
        path="${INTEGRITY_MANIFEST_PATHS[$i]}"
        abs_path="$REPO_ROOT/$path"
        CHECKED_COUNT=$((CHECKED_COUNT + 1))

        if [[ ! -f "$abs_path" ]]; then
            add_failure "$path" "missing" "expected installed file not found"
            continue
        fi

        actual_sha="$(integrity_sha256_file "$abs_path")"
        if [[ "$actual_sha" != "${INTEGRITY_MANIFEST_SHAS[$i]}" ]]; then
            add_failure "$path" "modified" "content does not match the installed manifest"
            continue
        fi

        actual_mode="$(stat -c '%a' -- "$abs_path")"
        if [[ "$actual_mode" != "${INTEGRITY_MANIFEST_MODES[$i]#0}" ]]; then
            add_failure "$path" "unexpected-mode" "mode $actual_mode, expected ${INTEGRITY_MANIFEST_MODES[$i]}"
            continue
        fi

        PASSED_COUNT=$((PASSED_COUNT + 1))
    done
}

# run_source_tree_checks
# Verifies every RELEASE_FILE_LIST path tracked by Git: existence in the
# working tree, then content via `git diff --quiet` against Git's index
# (immune to the permission-bit noise this repo already ignores via
# core.fileMode=false), then the expected executable mode read from Git's
# own index -- never from working-tree stat.
run_source_tree_checks() {
    local record meta path git_mode expected_mode

    while IFS= read -r -d '' record; do
        meta="${record%%$'\t'*}"
        path="${record#*$'\t'}"
        git_mode="${meta%% *}"
        CHECKED_COUNT=$((CHECKED_COUNT + 1))

        if [[ ! -e "$REPO_ROOT/$path" ]]; then
            add_failure "$path" "missing" "tracked file missing from working tree"
            continue
        fi

        if ! git -C "$REPO_ROOT" diff --quiet -- "$path" 2>/dev/null; then
            add_failure "$path" "modified" "working tree content differs from Git's index"
            continue
        fi

        case "$path" in
            *.sh | bin/maops) expected_mode="100755" ;;
            *) expected_mode="100644" ;;
        esac

        if [[ "$git_mode" != "$expected_mode" ]]; then
            add_failure "$path" "unexpected-mode" "Git index mode $git_mode, expected $expected_mode"
            continue
        fi

        PASSED_COUNT=$((PASSED_COUNT + 1))
    done < <(cd "$REPO_ROOT" && git ls-files -s -z -- "${RELEASE_FILE_LIST[@]}")
}

###############################################################################
# Rendering
###############################################################################

render_text() {
    show_header "MAOps Integrity Check"

    print_key_value "Execution mode" "$EXEC_MODE"
    if [[ "$EXEC_MODE" == "installed" ]]; then
        print_key_value "Manifest path" "$REPO_ROOT/.integrity-manifest"
    else
        print_key_value "Repository root" "$REPO_ROOT"
        print_key_value "Verification basis" "Git index metadata (not filesystem stat)"
    fi
    print_key_value "Checked" "$CHECKED_COUNT"
    print_key_value "Passed" "$PASSED_COUNT"
    print_key_value "Failed" "${#FAILURE_PATHS[@]}"

    if ((${#FAILURE_PATHS[@]} > 0)); then
        echo
        local i
        for i in "${!FAILURE_PATHS[@]}"; do
            printf "%-16s %-45s %s\n" "${FAILURE_CATEGORIES[$i]}" "${FAILURE_PATHS[$i]}" "${FAILURE_DETAILS[$i]}"
        done
    fi

    echo
    if ((${#FAILURE_PATHS[@]} > 0)); then
        log_error "Integrity check found issues."
    else
        log_success "All integrity checks passed."
    fi
}

render_json() {
    local overall="pass"
    ((${#FAILURE_PATHS[@]} > 0)) && overall="fail"

    local mode_field
    if [[ "$EXEC_MODE" == "installed" ]]; then
        mode_field="$(json_kv manifest_path "$REPO_ROOT/.integrity-manifest")"
    else
        mode_field="$(json_kv repository_root "$REPO_ROOT")"
    fi

    local parts=() i
    for i in "${!FAILURE_PATHS[@]}"; do
        parts+=("$(printf '{%s,%s,%s}' \
            "$(json_kv path "${FAILURE_PATHS[$i]}")" \
            "$(json_kv category "${FAILURE_CATEGORIES[$i]}")" \
            "$(json_kv detail "${FAILURE_DETAILS[$i]}")")")
    done

    local failures_json=""
    if ((${#parts[@]} > 0)); then
        failures_json="$(
            IFS=,
            printf '%s' "${parts[*]}"
        )"
    fi

    printf '{%s,%s,%s,%s,%s,%s,%s,"failures":[%s]}\n' \
        "$(json_kv version "$PROJECT_VERSION")" \
        "$(json_kv execution_mode "$EXEC_MODE")" \
        "$mode_field" \
        "$(json_kv overall "$overall")" \
        "$(json_kv checked_count "$CHECKED_COUNT" --raw)" \
        "$(json_kv passed_count "$PASSED_COUNT" --raw)" \
        "$(json_kv failed_count "${#FAILURE_PATHS[@]}" --raw)" \
        "$failures_json"
}

###############################################################################
# Main
###############################################################################

main() {
    detect_execution_mode

    if [[ "$EXEC_MODE" == "installed" ]]; then
        run_installed_checks
    else
        run_source_tree_checks
    fi

    if [[ "$FORMAT" == "json" ]]; then
        render_json
    else
        render_text
    fi

    if ((${#FAILURE_PATHS[@]} > 0)); then
        exit 1
    fi
    exit 0
}

parse_args "$@"
main
