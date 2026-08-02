#!/usr/bin/env bash

###############################################################################
#
# Script Name : validate-documentation.sh
# Description : Offline validation of the v1.0.0 documentation surface.
#               Checks required root/user documentation exists, local
#               Markdown links and referenced screenshots resolve, the
#               current version is consistent where it should be (without
#               falsely rejecting historical CHANGELOG entries), no known
#               placeholder markers remain in release-facing documentation,
#               the example config/script are valid, and the release
#               package's file list includes required docs while excluding
#               developer-only material. Runs entirely offline: every check
#               is local file inspection, never a network request.
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

readonly REQUIRED_ROOT_DOCS=(
    "README.md"
    "CHANGELOG.md"
    "CONTRIBUTING.md"
    "LICENSE"
    "SECURITY.md"
    "SUPPORT.md"
)

readonly REQUIRED_DAY8_DOCS=(
    "docs/quickstart.md"
    "docs/install-from-release.md"
    "docs/compatibility.md"
    "docs/demo-workflow.md"
    "docs/portfolio-case-study.md"
)

# Docs whose local links are swept in addition to README.md.
readonly SELECTED_DOCS_FOR_LINK_CHECK=(
    "README.md"
    "SECURITY.md"
    "SUPPORT.md"
    "docs/quickstart.md"
    "docs/install-from-release.md"
    "docs/compatibility.md"
    "docs/demo-workflow.md"
    "docs/portfolio-case-study.md"
    "docs/architecture.md"
    "docs/best-practices.md"
    "docs/troubleshooting.md"
    "docs/roadmap.md"
    "examples/README.md"
)

# Release-facing documentation: what actually ships to an end user, plus
# README/CHANGELOG (the two files everyone sees first). Engineering-review
# write-ups are deliberately excluded -- historical/dated notes are allowed
# to contain draft language a shipped doc should not.
readonly RELEASE_FACING_DOCS=(
    "README.md"
    "CHANGELOG.md"
    "SECURITY.md"
    "SUPPORT.md"
    "docs/quickstart.md"
    "docs/install-from-release.md"
    "docs/compatibility.md"
    "docs/demo-workflow.md"
    "docs/portfolio-case-study.md"
    "examples/README.md"
)

readonly PLACEHOLDER_MARKERS=(
    "TODO"
    "TBD"
    "FIXME"
    "PLACEHOLDER"
    "CHANGEME"
    "REPLACE_ME"
    "INSERT_YOUR"
    "YOUR-USERNAME"
    "YOUR_USERNAME"
)

FAILED=0

fail() {
    log_error "$1"
    FAILED=1
}

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [OPTIONS]

Offline validation of the documentation surface required for a v1.0.0
release: required files, local link resolution, referenced screenshots,
version consistency, placeholder markers, example validity, and release
package content alignment.

Options:
    -h, --help       Show this help message
    -v, --version    Show project version
EOF
}

parse_args() {
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

            *)
                cli_usage_error "Unknown option: $1"
                ;;
        esac
    done
}

###############################################################################
# Required files
###############################################################################

check_required_root_docs_exist() {
    local rel
    for rel in "${REQUIRED_ROOT_DOCS[@]}"; do
        [[ -f "$REPO_ROOT/$rel" ]] || fail "Missing required root document: $rel"
    done
}

check_required_day8_docs_exist() {
    local rel
    for rel in "${REQUIRED_DAY8_DOCS[@]}"; do
        [[ -f "$REPO_ROOT/$rel" ]] || fail "Missing required Day 8 user document: $rel"
    done
}

###############################################################################
# Local link resolution
#
# Extracts every Markdown "](...)" target (covers both [text](target) links
# and ![alt](target) images), skips external (http/https/mailto) and
# same-file-anchor-only (#foo) targets, strips any trailing #anchor from a
# file-path target, and resolves the remainder relative to the linking
# file's own directory.
###############################################################################

check_links_in_file() {
    local rel="$1" file="$REPO_ROOT/$1"
    local dir target path

    [[ -f "$file" ]] || return 0
    dir="$(dirname -- "$file")"

    while IFS= read -r target; do
        [[ -z "$target" ]] && continue
        [[ "$target" == http://* || "$target" == https://* || "$target" == mailto:* ]] && continue
        [[ "$target" == \#* ]] && continue

        path="${target%%#*}"
        [[ -z "$path" ]] && continue

        if [[ ! -e "$dir/$path" ]]; then
            fail "Broken local link in $rel: $target"
        fi
    done < <(grep -oE '\]\([^)[:space:]]+\)' -- "$file" | sed -E 's/^\]\(//; s/\)$//')
}

check_readme_local_links_resolve() {
    check_links_in_file "README.md"
}

check_selected_documentation_links_resolve() {
    local rel
    for rel in "${SELECTED_DOCS_FOR_LINK_CHECK[@]}"; do
        check_links_in_file "$rel"
    done
}

###############################################################################
# Referenced screenshots
###############################################################################

check_referenced_screenshots_exist() {
    local file="$REPO_ROOT/README.md"
    local dir target path
    dir="$(dirname -- "$file")"

    [[ -f "$file" ]] || return 0

    while IFS= read -r target; do
        [[ -z "$target" ]] && continue
        [[ "$target" == http://* || "$target" == https://* ]] && continue

        path="${target%%#*}"
        case "$path" in
            *.png | *.PNG | *.jpg | *.jpeg | *.gif | *.svg)
                if [[ ! -f "$dir/$path" ]]; then
                    fail "README references a screenshot that does not exist: $target"
                fi
                ;;
        esac
    done < <(grep -oE '!\[[^]]*\]\([^)[:space:]]+\)' -- "$file" | grep -oE '\([^)]+\)' | sed -E 's/^\(//; s/\)$//')
}

###############################################################################
# Version consistency (narrowly scoped, so historical references are never
# falsely rejected)
###############################################################################

check_current_version_in_readme() {
    grep -q -- "$PROJECT_VERSION" "$REPO_ROOT/README.md" ||
        fail "README.md does not mention the current version ($PROJECT_VERSION)"
}

check_changelog_top_entry_is_current_version() {
    local top_entry
    top_entry="$(grep -m1 -E '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' -- "$REPO_ROOT/CHANGELOG.md" || true)"

    if [[ -z "$top_entry" ]]; then
        fail "CHANGELOG.md has no version-header entry at all"
        return
    fi

    if [[ "$top_entry" != *"[$PROJECT_VERSION]"* ]]; then
        fail "CHANGELOG.md's most recent entry is not the current version ($PROJECT_VERSION): $top_entry"
    fi
}

###############################################################################
# Placeholder markers
###############################################################################

check_no_placeholder_markers() {
    local rel marker
    for rel in "${RELEASE_FACING_DOCS[@]}"; do
        [[ -f "$REPO_ROOT/$rel" ]] || continue
        for marker in "${PLACEHOLDER_MARKERS[@]}"; do
            if grep -qE "\\b${marker}\\b" -- "$REPO_ROOT/$rel"; then
                fail "Placeholder marker '$marker' found in release-facing document: $rel"
            fi
        done
    done
}

###############################################################################
# Example validity
###############################################################################

check_example_config_validates() {
    if ! "$REPO_ROOT/scripts/config/config-manager.sh" validate "$REPO_ROOT/examples/config/maops.conf" >/dev/null 2>&1; then
        fail "examples/config/maops.conf does not pass 'maops config validate'"
    fi
}

check_example_script_syntax_and_lint() {
    local script="$REPO_ROOT/examples/automation/health-report.sh"

    [[ -f "$script" ]] || {
        fail "examples/automation/health-report.sh is missing"
        return
    }

    if ! bash -n "$script"; then
        fail "examples/automation/health-report.sh fails bash -n"
    fi

    if command_exists shellcheck; then
        if ! shellcheck "$script" >/dev/null 2>&1; then
            fail "examples/automation/health-report.sh fails ShellCheck"
        fi
    fi
}

###############################################################################
# Release package content alignment
###############################################################################

check_package_content_alignment() {
    local rel is_listed entry

    # docs/portfolio-case-study.md is deliberately excluded: it's portfolio-
    # presentation material for this repository specifically, not toolkit
    # documentation an installed copy needs -- see RELEASE_FILE_LIST's own
    # comment in scripts/common/release-files.sh.
    local packaged_day8_docs=(
        "docs/quickstart.md"
        "docs/install-from-release.md"
        "docs/compatibility.md"
        "docs/demo-workflow.md"
    )

    for rel in "${packaged_day8_docs[@]}" "SECURITY.md" "SUPPORT.md" "examples"; do
        is_listed=0
        for entry in "${RELEASE_FILE_LIST[@]}"; do
            [[ "$entry" == "$rel" ]] && is_listed=1 && break
        done
        ((is_listed)) || fail "$rel is required for v1.0.0 but is not in RELEASE_FILE_LIST"
    done

    for entry in "${RELEASE_FILE_LIST[@]}"; do
        case "$entry" in
            docs/engineering-reviews* | docs/images*)
                fail "Developer-only path is present in RELEASE_FILE_LIST: $entry"
                ;;
        esac
    done
}

###############################################################################
# Main
###############################################################################

main() {
    check_required_root_docs_exist
    check_required_day8_docs_exist
    check_readme_local_links_resolve
    check_selected_documentation_links_resolve
    check_referenced_screenshots_exist
    check_current_version_in_readme
    check_changelog_top_entry_is_current_version
    check_no_placeholder_markers
    check_example_config_validates
    check_example_script_syntax_and_lint
    check_package_content_alignment

    if ((FAILED)); then
        log_error "Documentation validation failed."
        exit 1
    fi

    log_success "Documentation validation passed."
}

parse_args "$@"
main
