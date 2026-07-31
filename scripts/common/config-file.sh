#!/usr/bin/env bash

###############################################################################
#
# Script Name : config-file.sh
# Description : Config-file parsing, validation, precedence resolution, and
#               atomic writes for the MAOps configuration system. The file is
#               parsed as inert text via a line-by-line `read` loop only — it
#               is never sourced or eval'd, so a value containing shell
#               metacharacters or command substitution can never execute.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
# Version     : 0.4.0
#
# Depends on scripts/common/cli.sh (is_one_of, is_positive_integer) already
# being loaded by the caller via bootstrap.sh. Not added to bootstrap.sh's
# own fixed load order, since most leaf scripts do not need config parsing.
#
###############################################################################

[[ -n "${MAOPS_CONFIG_FILE_LIB_LOADED:-}" ]] && return
readonly MAOPS_CONFIG_FILE_LIB_LOADED=1

readonly CONFIG_VALID_KEYS=(output_format process_limit ping_count network_timeout)

# Tracks whether config_load has already parsed the file in this process, so
# repeated calls to config_resolve_value don't re-read/re-parse it each time.
MAOPS_CONFIG_LOADED_ONCE=""

###############################################################################
# Path resolution
###############################################################################

config_default_path() {
    printf '%s\n' "${MAOPS_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/maops/config}"
}

###############################################################################
# Line classification and parsing helpers
###############################################################################

_config_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# config_classify_line LINE
# Prints one of: blank | comment | kv | malformed
config_classify_line() {
    local trimmed
    trimmed="$(_config_trim "$1")"

    if [[ -z "$trimmed" ]]; then
        printf 'blank'
        return 0
    fi

    if [[ "$trimmed" == '#'* ]]; then
        printf 'comment'
        return 0
    fi

    if [[ "$trimmed" =~ ^[a-z_][a-z0-9_]*[[:space:]]*=.*$ ]]; then
        printf 'kv'
        return 0
    fi

    printf 'malformed'
}

###############################################################################
# Per-key value validation (reuses scripts/common/cli.sh predicates)
###############################################################################

config_validate_value() {
    local key="$1" value="$2"

    case "$key" in
        output_format) is_one_of "$value" text json ;;
        process_limit | ping_count | network_timeout) is_positive_integer "$value" ;;
        *) return 1 ;;
    esac
}

###############################################################################
# Strict validation — used by `config validate` and doctor's config check
###############################################################################

# config_validate_file PATH
# Populates the global array CONFIG_VALIDATION_ERRORS with one message per
# problem found; returns 0 if the file is fully valid, 1 otherwise. Never
# sources or evaluates the file — reads it line-by-line via `read -r` only.
config_validate_file() {
    local path="$1"
    CONFIG_VALIDATION_ERRORS=()

    local -A seen_keys=()
    local line_no=0
    local line trimmed key value
    local ok=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_no=$((line_no + 1))
        trimmed="$(_config_trim "$line")"

        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" == '#'* ]] && continue

        if [[ ! "$trimmed" =~ ^([a-z_][a-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            CONFIG_VALIDATION_ERRORS+=("line $line_no: malformed line")
            ok=1
            continue
        fi

        key="${BASH_REMATCH[1]}"
        value="$(_config_trim "${BASH_REMATCH[2]}")"

        if ! is_one_of "$key" "${CONFIG_VALID_KEYS[@]}"; then
            CONFIG_VALIDATION_ERRORS+=("line $line_no: unknown key '$key'")
            ok=1
            continue
        fi

        if [[ -n "${seen_keys[$key]:-}" ]]; then
            CONFIG_VALIDATION_ERRORS+=("line $line_no: duplicate key '$key'")
            ok=1
            continue
        fi
        seen_keys["$key"]=1

        if ! config_validate_value "$key" "$value"; then
            CONFIG_VALIDATION_ERRORS+=("line $line_no: invalid value for $key: $value")
            ok=1
            continue
        fi
    done <"$path"

    return "$ok"
}

###############################################################################
# Permissive load — used by config_resolve_value; never fails a leaf script
# over a stray line in the user's config file (config validate is the
# dedicated strict-mode entry point for that).
###############################################################################

config_load() {
    [[ -n "$MAOPS_CONFIG_LOADED_ONCE" ]] && return 0
    MAOPS_CONFIG_LOADED_ONCE=1

    CONFIG_OUTPUT_FORMAT=""
    CONFIG_PROCESS_LIMIT=""
    CONFIG_PING_COUNT=""
    CONFIG_NETWORK_TIMEOUT=""

    local path
    path="$(config_default_path)"
    [[ -f "$path" ]] || return 0

    local -A values=()
    local line trimmed key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        trimmed="$(_config_trim "$line")"

        [[ -z "$trimmed" ]] && continue
        [[ "$trimmed" == '#'* ]] && continue
        [[ "$trimmed" =~ ^([a-z_][a-z0-9_]*)[[:space:]]*=(.*)$ ]] || continue

        key="${BASH_REMATCH[1]}"
        value="$(_config_trim "${BASH_REMATCH[2]}")"

        is_one_of "$key" "${CONFIG_VALID_KEYS[@]}" || continue
        config_validate_value "$key" "$value" || continue

        # Last-value-wins on a duplicate key; `config validate` is the
        # strict entry point that rejects duplicates outright.
        values["$key"]="$value"
    done <"$path"

    [[ -n "${values[output_format]:-}" ]] && CONFIG_OUTPUT_FORMAT="${values[output_format]}"
    [[ -n "${values[process_limit]:-}" ]] && CONFIG_PROCESS_LIMIT="${values[process_limit]}"
    [[ -n "${values[ping_count]:-}" ]] && CONFIG_PING_COUNT="${values[ping_count]}"
    [[ -n "${values[network_timeout]:-}" ]] && CONFIG_NETWORK_TIMEOUT="${values[network_timeout]}"
}

###############################################################################
# Precedence resolution: explicit CLI value > MAOPS_* env var > config file
# > built-in default. This is the single reusable entry point every
# consumer (leaf scripts, config-manager.sh, doctor.sh) calls into.
###############################################################################

# config_resolve_value KEY CLI_VALUE ENV_VAR_NAME DEFAULT
config_resolve_value() {
    local key="$1" cli_value="$2" env_name="$3" default_value="$4"

    if [[ -n "$cli_value" ]]; then
        printf '%s' "$cli_value"
        return 0
    fi

    if [[ -n "${!env_name:-}" ]]; then
        printf '%s' "${!env_name}"
        return 0
    fi

    config_load

    local from_file=""
    case "$key" in
        output_format) from_file="$CONFIG_OUTPUT_FORMAT" ;;
        process_limit) from_file="$CONFIG_PROCESS_LIMIT" ;;
        ping_count) from_file="$CONFIG_PING_COUNT" ;;
        network_timeout) from_file="$CONFIG_NETWORK_TIMEOUT" ;;
    esac

    if [[ -n "$from_file" ]]; then
        printf '%s' "$from_file"
        return 0
    fi

    printf '%s' "$default_value"
}

###############################################################################
# Atomic write
###############################################################################

# config_write_atomic TARGET CONTENT
# Writes CONTENT to TARGET via a same-directory temp file + rename, so a
# crash mid-write can never leave a partial config file in place. Caller is
# responsible for setting `umask 077` beforehand.
config_write_atomic() {
    local target="$1" content="$2"
    local dir tmp
    dir="$(dirname -- "$target")"
    mkdir -p -- "$dir"
    tmp="$(mktemp -- "$dir/.config.XXXXXX")"
    printf '%s\n' "$content" >"$tmp"
    mv -f -- "$tmp" "$target"
}

config_default_template() {
    cat <<'EOF'
# MAOps Linux DevOps Toolkit configuration file
#
# Lines starting with # and blank lines are ignored. This file is parsed as
# plain text only — it is never sourced or evaluated as a shell script, so
# shell metacharacters in a value are never executed.

output_format=text
process_limit=10
ping_count=4
network_timeout=5
EOF
}
