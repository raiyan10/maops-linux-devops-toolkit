#!/usr/bin/env bash

###############################################################################
#
# Script Name : format.sh
# Description : Minimal, dependency-free JSON string escaping and object
#               assembly. Never uses eval and never requires jq at runtime.
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
#
###############################################################################

[[ -n "${MAOPS_FORMAT_LOADED:-}" ]] && return
readonly MAOPS_FORMAT_LOADED=1

# json_escape STRING
# Escapes backslashes, double quotes, tabs, carriage returns, and newlines.
# Order matters: backslashes must be escaped first, or later substitutions
# would double-escape the backslashes they themselves introduce.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

# json_kv KEY VALUE [--raw]
# Prints "key":"value" (both escaped), or "key":value verbatim with --raw
# for non-string JSON values (numbers, booleans, nested [...]/{...}).
json_kv() {
    local key="$1" value="$2" raw="${3:-}"

    if [[ "$raw" == "--raw" ]]; then
        printf '"%s":%s' "$(json_escape "$key")" "$value"
    else
        printf '"%s":"%s"' "$(json_escape "$key")" "$(json_escape "$value")"
    fi
}

# json_object KEY1 VALUE1 [KEY2 VALUE2 ...]
# Assembles a flat JSON object from string key/value pairs. Callers needing
# a mix of string and raw (numeric/boolean) fields, or array-of-object
# shapes, compose them directly with json_kv instead of this convenience
# wrapper.
json_object() {
    local out="{" first=1

    while (($# >= 2)); do
        [[ $first -eq 0 ]] && out+=","
        out+="$(json_kv "$1" "$2")"
        first=0
        shift 2
    done

    out+="}"
    printf '%s' "$out"
}
