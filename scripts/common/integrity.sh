#!/usr/bin/env bash
# shellcheck disable=SC2034 # INTEGRITY_LAST_ERROR and INTEGRITY_MANIFEST_* are consumed by callers, not this file

###############################################################################
#
# Script Name : integrity.sh
# Description : Shared release-integrity primitives: Git-index-derived mode
#               normalization, MAOPS-MANIFEST.tsv generation/parsing, and
#               relative-path safety validation. Used by package.sh,
#               install.sh, uninstall.sh, verify-package.sh, and
#               integrity-check.sh so none of them re-implement the same
#               trust logic differently. Deliberately has no CLI output and
#               no command routing of its own -- callers own their own
#               logging and exit codes; on failure this file only returns 1
#               and sets INTEGRITY_LAST_ERROR for the caller to report.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
#
###############################################################################

[[ -n "${MAOPS_INTEGRITY_LOADED:-}" ]] && return
readonly MAOPS_INTEGRITY_LOADED=1

INTEGRITY_LAST_ERROR=""

INTEGRITY_MANIFEST_MODES=()
INTEGRITY_MANIFEST_SHAS=()
INTEGRITY_MANIFEST_PATHS=()

###############################################################################
# Mode normalization
###############################################################################

# integrity_git_mode_to_perm GIT_MODE
# Prints the filesystem permission ("0644"/"0755") for a Git index mode.
# Returns 1 for any mode this toolkit does not distribute as a regular file
# (symlinks "120000", gitlinks "160000", etc.) -- the caller must treat this
# as fatal, never silently skip the entry.
integrity_git_mode_to_perm() {
    case "$1" in
        100644) printf '0644' ;;
        100755) printf '0755' ;;
        *) return 1 ;;
    esac
}

###############################################################################
# Path safety
###############################################################################

# integrity_path_has_dotdot_component PATH
# True if PATH contains a literal ".." path segment, checked component by
# component (never a substring match, so a legitimate name like "v1.2..3"
# is never a false positive).
integrity_path_has_dotdot_component() {
    local part
    local IFS='/'
    for part in $1; do
        [[ "$part" == ".." ]] && return 0
    done
    return 1
}

# integrity_is_unsafe_relative_path PATH
# True if PATH is empty, absolute, contains a ".." component, or contains a
# raw tab/newline byte (which would corrupt MAOPS-MANIFEST.tsv's
# tab-delimited format or a manifest file-list entry).
integrity_is_unsafe_relative_path() {
    local path="$1"
    [[ -z "$path" ]] && return 0
    [[ "$path" == /* ]] && return 0
    [[ "$path" == *$'\t'* || "$path" == *$'\n'* ]] && return 0
    integrity_path_has_dotdot_component "$path" && return 0
    return 1
}

###############################################################################
# Manifest line validation
###############################################################################

# integrity_validate_manifest_line MODE SHA256 PATH
# True if the triple is a well-formed MAOPS-MANIFEST.tsv entry: MODE is
# exactly "0644" or "0755"; SHA256 is exactly 64 lowercase hex characters;
# PATH passes integrity_is_unsafe_relative_path in the safe direction.
integrity_validate_manifest_line() {
    local mode="$1" sha="$2" path="$3"
    [[ "$mode" == "0644" || "$mode" == "0755" ]] || return 1
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || return 1
    integrity_is_unsafe_relative_path "$path" && return 1
    return 0
}

###############################################################################
# Checksums
###############################################################################

# integrity_sha256_file PATH
# Prints the lowercase hex SHA-256 of PATH.
integrity_sha256_file() {
    sha256sum -- "$1" | awk '{print $1}'
}

###############################################################################
# chmod with verification
###############################################################################

# integrity_chmod_verified MODE PATH
# chmods PATH to MODE, then re-reads the mode back via stat to confirm the
# destination filesystem actually applied it. A silently ignored chmod
# (some mount types accept the call but never change what stat reports) is
# treated as a hard failure rather than allowed to produce a package/install
# that only looks correct.
integrity_chmod_verified() {
    local mode="$1" path="$2" observed
    chmod "$mode" -- "$path"
    observed="$(stat -c '%a' -- "$path")"
    if [[ "$observed" != "${mode#0}" ]]; then
        INTEGRITY_LAST_ERROR="chmod $mode did not take effect on $path (observed: $observed)"
        return 1
    fi
    return 0
}

###############################################################################
# Git-index-driven staging
###############################################################################

# integrity_copy_git_tracked STAGE_DIR REPO_ROOT ENTRY...
# Copies every Git-tracked path under ENTRY... from REPO_ROOT into
# STAGE_DIR, deriving each file's filesystem mode from Git's index (never
# from the source filesystem's stat, and never via cp -a), and prints one
# MODE<TAB>SHA256<TAB>RELATIVE_PATH manifest line per copied file to stdout.
# Aborts (returns 1, INTEGRITY_LAST_ERROR set) on any unsupported Git mode.
integrity_copy_git_tracked() {
    local stage_dir="$1" repo_root="$2"
    shift 2

    local record meta path git_mode perm src dest sha
    while IFS= read -r -d '' record; do
        meta="${record%%$'\t'*}"
        path="${record#*$'\t'}"
        git_mode="${meta%% *}"

        if ! perm="$(integrity_git_mode_to_perm "$git_mode")"; then
            INTEGRITY_LAST_ERROR="Unsupported Git mode $git_mode for tracked path: $path"
            return 1
        fi

        src="$repo_root/$path"
        dest="$stage_dir/$path"
        mkdir -p -- "$(dirname -- "$dest")"
        cp -- "$src" "$dest"
        integrity_chmod_verified "$perm" "$dest" || return 1

        sha="$(integrity_sha256_file "$dest")"
        printf '%s\t%s\t%s\n' "$perm" "$sha" "$path"
    done < <(cd "$repo_root" && git ls-files -s -z -- "$@")
}

###############################################################################
# Manifest parsing
###############################################################################

# integrity_read_manifest MANIFEST_PATH
# Reads and validates every line of MANIFEST_PATH (plain `read`, never
# sourced/eval'd, tabs split via parameter expansion rather than `read -a`
# so an empty field is never silently collapsed away). On success,
# populates the parallel arrays INTEGRITY_MANIFEST_MODES/SHAS/PATHS (reset
# at call start) and returns 0. Fails closed: the first malformed,
# wrong-field-count, or duplicate-path line aborts the whole read, leaves
# the arrays empty, sets INTEGRITY_LAST_ERROR, and returns 1.
integrity_read_manifest() {
    local manifest="$1"

    INTEGRITY_MANIFEST_MODES=()
    INTEGRITY_MANIFEST_SHAS=()
    INTEGRITY_MANIFEST_PATHS=()

    if [[ ! -f "$manifest" ]]; then
        INTEGRITY_LAST_ERROR="Manifest not found: $manifest"
        return 1
    fi

    local -A seen=()
    local line mode sha path rest tab_count

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && {
            INTEGRITY_LAST_ERROR="Malformed manifest: blank line"
            INTEGRITY_MANIFEST_MODES=()
            INTEGRITY_MANIFEST_SHAS=()
            INTEGRITY_MANIFEST_PATHS=()
            return 1
        }

        tab_count="$(awk -F'\t' '{print NF - 1}' <<<"$line")"
        if [[ "$tab_count" != "2" ]]; then
            INTEGRITY_LAST_ERROR="Malformed manifest line (expected 3 tab-separated fields): $line"
            INTEGRITY_MANIFEST_MODES=()
            INTEGRITY_MANIFEST_SHAS=()
            INTEGRITY_MANIFEST_PATHS=()
            return 1
        fi

        mode="${line%%$'\t'*}"
        rest="${line#*$'\t'}"
        sha="${rest%%$'\t'*}"
        path="${rest#*$'\t'}"

        if ! integrity_validate_manifest_line "$mode" "$sha" "$path"; then
            INTEGRITY_LAST_ERROR="Malformed manifest entry: $line"
            INTEGRITY_MANIFEST_MODES=()
            INTEGRITY_MANIFEST_SHAS=()
            INTEGRITY_MANIFEST_PATHS=()
            return 1
        fi

        if [[ -n "${seen[$path]:-}" ]]; then
            INTEGRITY_LAST_ERROR="Duplicate manifest entry: $path"
            INTEGRITY_MANIFEST_MODES=()
            INTEGRITY_MANIFEST_SHAS=()
            INTEGRITY_MANIFEST_PATHS=()
            return 1
        fi
        seen[$path]=1

        INTEGRITY_MANIFEST_MODES+=("$mode")
        INTEGRITY_MANIFEST_SHAS+=("$sha")
        INTEGRITY_MANIFEST_PATHS+=("$path")
    done <"$manifest"

    return 0
}

###############################################################################
# Manifest-driven staging (archive-mode install)
###############################################################################

# integrity_verify_and_copy_from_manifest STAGE_DIR SOURCE_ROOT MANIFEST_PATH
# Reads and validates MANIFEST_PATH via integrity_read_manifest, then for
# each entry: copies the source file into STAGE_DIR first, and only then
# hashes and verifies *that copy* (never a separate read of the source)
# against the manifest's SHA-256, so verification always checks exactly the
# bytes that end up staged -- a source file modified between two separate
# reads (verify, then copy) could otherwise let mismatched content slip
# through undetected. Fails closed on the first bad entry: STAGE_DIR is a
# throwaway staging directory the caller only ever promotes to a live
# location after this function returns success, so a failure partway
# through never results in a partially-installed live tree, even though
# STAGE_DIR itself may hold a partial copy at that point.
integrity_verify_and_copy_from_manifest() {
    local stage_dir="$1" source_root="$2" manifest="$3"

    integrity_read_manifest "$manifest" || return 1

    local i path abs_path dest actual_sha
    for i in "${!INTEGRITY_MANIFEST_PATHS[@]}"; do
        path="${INTEGRITY_MANIFEST_PATHS[$i]}"
        abs_path="$source_root/$path"

        if [[ ! -f "$abs_path" ]]; then
            INTEGRITY_LAST_ERROR="Manifest entry missing from source: $path"
            return 1
        fi

        dest="$stage_dir/$path"
        mkdir -p -- "$(dirname -- "$dest")"
        cp -- "$abs_path" "$dest"

        actual_sha="$(integrity_sha256_file "$dest")"
        if [[ "$actual_sha" != "${INTEGRITY_MANIFEST_SHAS[$i]}" ]]; then
            INTEGRITY_LAST_ERROR="Checksum mismatch for manifest entry: $path"
            return 1
        fi

        integrity_chmod_verified "${INTEGRITY_MANIFEST_MODES[$i]}" "$dest" || return 1
    done

    return 0
}
