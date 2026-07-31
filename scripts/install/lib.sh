#!/usr/bin/env bash

###############################################################################
#
# Script Name : lib.sh
# Description : Shared prefix-canonicalization and symlink-verification
#               helpers used identically by install.sh and uninstall.sh, so
#               the two can never disagree on what counts as a safe prefix
#               or a launcher symlink that belongs to a given install.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.4.0
#
###############################################################################

[[ -n "${MAOPS_INSTALL_LIB_LOADED:-}" ]] && return
readonly MAOPS_INSTALL_LIB_LOADED=1

# install_canonicalize_prefix PREFIX
# Resolves PREFIX to an absolute, symlink-resolved path without depending on
# realpath/readlink -f (neither is guaranteed present nor a required
# runtime command). PREFIX need not exist yet: the nearest existing ancestor
# is canonicalized via cd+pwd -P, and any not-yet-created remainder is
# re-appended untouched. Prints the resolved path; returns 1 on failure.
install_canonicalize_prefix() {
    local raw="$1"
    [[ -z "$raw" ]] && return 1

    local abs="$raw"
    [[ "$abs" != /* ]] && abs="$(pwd)/$abs"

    local existing="$abs" remainder=""
    while [[ ! -d "$existing" ]]; do
        remainder="$(basename -- "$existing")${remainder:+/$remainder}"
        existing="$(dirname -- "$existing")"
    done

    local resolved
    resolved="$(cd -- "$existing" && pwd -P)" || return 1

    if [[ -n "$remainder" ]]; then
        printf '%s/%s' "$resolved" "$remainder"
    else
        printf '%s' "$resolved"
    fi
}

# install_resolve_symlink_target LINK
# Prints the absolute target of LINK, resolving a relative target against
# LINK's own directory (never the caller's CWD). Returns 1 if LINK is not a
# symlink, or if its target's directory cannot be resolved (a dangling
# target is treated as "does not match", the safe default).
install_resolve_symlink_target() {
    local link="$1"
    [[ -L "$link" ]] || return 1

    local dir target
    dir="$(cd -- "$(dirname -- "$link")" && pwd)" || return 1
    target="$(readlink -- "$link")"

    if [[ "$target" == /* ]]; then
        printf '%s' "$target"
        return 0
    fi

    local target_dir target_base resolved_dir
    target_dir="$(dirname -- "$target")"
    target_base="$(basename -- "$target")"
    resolved_dir="$(cd -- "$dir" && cd -- "$target_dir" 2>/dev/null && pwd)" || return 1

    printf '%s/%s' "$resolved_dir" "$target_base"
}

# install_launcher_is_ours LAUNCHER LIB_DIR
# True if LAUNCHER is a symlink whose target resolves to exactly
# LIB_DIR/bin/maops.
install_launcher_is_ours() {
    local launcher="$1" lib_dir="$2"
    local resolved
    resolved="$(install_resolve_symlink_target "$launcher")" || return 1
    [[ "$resolved" == "$lib_dir/bin/maops" ]]
}
