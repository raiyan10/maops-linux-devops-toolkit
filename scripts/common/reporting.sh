#!/usr/bin/env bash
# shellcheck disable=SC2034 # REPORT_* globals are consumed by operational-report.sh, which sources this file

###############################################################################
#
# Script Name : reporting.sh
# Description : Field-collection, status-aggregation, redaction, and
#               atomic-save primitives shared by the `maops report` command.
#               Every field here is a local, read-only fact (a command's
#               presence/output or a file's existence) -- never a password,
#               environment dump, process command line, username, group
#               membership, IP address, DNS detail, SSH key, config-file
#               content, token, or credential. No network request is ever
#               made.
#
#               Never duplicates doctor.sh's or integrity-check.sh's check
#               logic: reporting_collect() invokes those two scripts as
#               subprocesses and reads only their exit status, never their
#               output.
#
# Author      : Raiyan Yousuf
# Project     : MAOps Linux DevOps Toolkit
#
# Depends on scripts/common/config-file.sh (config_default_path,
# config_validate_file) already being loaded by the caller, and on the
# caller having set REPO_ROOT before calling reporting_collect. Not added to
# bootstrap.sh's own fixed load order, since most leaf scripts do not need
# reporting.
#
###############################################################################

[[ -n "${MAOPS_REPORTING_LOADED:-}" ]] && return
readonly MAOPS_REPORTING_LOADED=1

# Overridable only for tests -- points a resource collector's stable-Linux
# fallback source at a fixture file instead of the real /proc, since the
# real /proc/loadavg and /proc/meminfo exist on every actual Linux host
# (including CI/WSL2) regardless of PATH-based command stubbing. Mirrors
# config-file.sh's MAOPS_CONFIG_FILE override convention.
: "${MAOPS_PROC_LOADAVG:=/proc/loadavg}"
: "${MAOPS_PROC_MEMINFO:=/proc/meminfo}"

REPORT_VERSION=""
REPORT_GENERATED_AT=""
REPORT_EXEC_MODE=""
REPORT_HOSTNAME=""
REPORT_OS_DESCRIPTION=""
REPORT_KERNEL=""
REPORT_ARCH=""
REPORT_CPU_COUNT=""
REPORT_LOAD_AVERAGE=""
REPORT_MEM_TOTAL=""
REPORT_MEM_AVAILABLE=""
REPORT_ROOTFS_SIZE=""
REPORT_ROOTFS_USED=""
REPORT_ROOTFS_AVAILABLE=""
REPORT_ROOTFS_PERCENT=""
REPORT_CONFIG_PATH=""
REPORT_CONFIG_EXISTS=""
REPORT_CONFIG_VALID=""
REPORT_DOCTOR_OVERALL=""
REPORT_INTEGRITY_OVERALL=""
REPORT_OVERALL=""
REPORT_REQUIRED_MISSING=0
REPORT_OPTIONAL_MISSING=0

REPORT_SAVE_LAST_ERROR=""

###############################################################################
# Required-field collection (internal state or a trivial, always-terminating
# check -- a failure here means the report genuinely cannot vouch for its
# own basic facts, and drives overall=fail, not overall=warn)
###############################################################################

_reporting_collect_timestamp() {
    if REPORT_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" && [[ -n "$REPORT_GENERATED_AT" ]]; then
        return 0
    fi
    REPORT_GENERATED_AT="unavailable"
    REPORT_REQUIRED_MISSING=1
}

_reporting_collect_execution_mode() {
    if [[ -f "$REPO_ROOT/.install-manifest" ]]; then
        REPORT_EXEC_MODE="installed"
    else
        REPORT_EXEC_MODE="source-tree"
    fi
}

# A missing or invalid config file is never itself a required-section
# failure: existence/validity are always determinable (a file either exists
# or it doesn't; config_validate_file always terminates), and any
# config-driven health problem already surfaces through doctor.overall,
# since doctor.sh already treats config_valid as one of its own required
# checks whenever the file exists.
_reporting_collect_config() {
    REPORT_CONFIG_PATH="$(config_default_path)"

    if [[ -f "$REPORT_CONFIG_PATH" ]]; then
        REPORT_CONFIG_EXISTS="true"
        if config_validate_file "$REPORT_CONFIG_PATH"; then
            REPORT_CONFIG_VALID="true"
        else
            REPORT_CONFIG_VALID="false"
        fi
    else
        REPORT_CONFIG_EXISTS="false"
        REPORT_CONFIG_VALID="false"
    fi
}

# Runs doctor.sh/integrity-check.sh as subprocesses and reads only their
# exit status -- 0/1 map to pass/fail; anything else (missing/broken
# script) means the report cannot determine that subsystem's health at all,
# which *is* a required-section failure. The `||` form is exempt from
# `set -e`, so a nonzero exit here never aborts this script -- the report
# must still be emitted in full when doctor or integrity fails.
_reporting_collect_doctor() {
    local exit_code=0
    "$REPO_ROOT/scripts/diagnostics/doctor.sh" >/dev/null 2>&1 || exit_code=$?

    case "$exit_code" in
        0) REPORT_DOCTOR_OVERALL="pass" ;;
        1) REPORT_DOCTOR_OVERALL="fail" ;;
        *)
            REPORT_DOCTOR_OVERALL="unavailable"
            REPORT_REQUIRED_MISSING=1
            ;;
    esac
}

_reporting_collect_integrity() {
    local exit_code=0
    "$REPO_ROOT/scripts/diagnostics/integrity-check.sh" >/dev/null 2>&1 || exit_code=$?

    case "$exit_code" in
        0) REPORT_INTEGRITY_OVERALL="pass" ;;
        1) REPORT_INTEGRITY_OVERALL="fail" ;;
        *)
            REPORT_INTEGRITY_OVERALL="unavailable"
            REPORT_REQUIRED_MISSING=1
            ;;
    esac
}

###############################################################################
# Optional-field collection (system/resource facts -- a missing or failing
# command degrades this one field to "unavailable" and marks the report
# overall=warn; it never aborts collection of the rest of the report)
###############################################################################

_reporting_collect_hostname() {
    if REPORT_HOSTNAME="$(hostname 2>/dev/null)" && [[ -n "$REPORT_HOSTNAME" ]]; then
        return 0
    fi
    REPORT_HOSTNAME="unavailable"
    REPORT_OPTIONAL_MISSING=1
}

_reporting_collect_os_description() {
    if REPORT_OS_DESCRIPTION="$(uname -s 2>/dev/null)" && [[ -n "$REPORT_OS_DESCRIPTION" ]]; then
        return 0
    fi
    REPORT_OS_DESCRIPTION="unavailable"
    REPORT_OPTIONAL_MISSING=1
}

_reporting_collect_kernel() {
    if REPORT_KERNEL="$(uname -r 2>/dev/null)" && [[ -n "$REPORT_KERNEL" ]]; then
        return 0
    fi
    REPORT_KERNEL="unavailable"
    REPORT_OPTIONAL_MISSING=1
}

_reporting_collect_arch() {
    if REPORT_ARCH="$(uname -m 2>/dev/null)" && [[ -n "$REPORT_ARCH" ]]; then
        return 0
    fi
    REPORT_ARCH="unavailable"
    REPORT_OPTIONAL_MISSING=1
}

_reporting_collect_cpu_count() {
    local n
    if n="$(getconf _NPROCESSORS_ONLN 2>/dev/null)" && [[ "$n" =~ ^[0-9]+$ ]]; then
        REPORT_CPU_COUNT="$n"
        return 0
    fi
    REPORT_CPU_COUNT="0"
    REPORT_OPTIONAL_MISSING=1
}

# Shape a parsed field must match before it is trusted, so an unexpected or
# malformed column layout (a non-GNU/BusyBox command, an unfamiliar locale,
# a truncated line) degrades the field to "unavailable" instead of silently
# reporting garbage as if it were real data. These are deliberately loose
# (they validate *shape*, not exact command-specific formatting), so any
# genuinely GNU-coreutils/procps-shaped output continues to match exactly as
# it always has.
readonly _REPORT_LOAD_AVERAGE_SHAPE='^[0-9]+\.[0-9]+, [0-9]+\.[0-9]+, [0-9]+\.[0-9]+$'
# df -hP's unit convention: an optional single-letter K/M/G/T/P suffix (no
# leading "i"), or bare digits for very small values.
readonly _REPORT_HUMAN_SIZE_SHAPE='^[0-9]+(\.[0-9]+)?[KMGTPE]?$'
# free -h's unit convention differs from df's: always a unit, either a
# binary-prefix letter followed by "i" (Ki/Mi/Gi/Ti/Pi) or a bare "B" for
# byte values -- never a bare number. Requiring the unit here is what lets
# this reject a BusyBox/non-procps `free` whose misaligned columns would
# otherwise hand back a plausible-looking but meaningless raw byte count.
readonly _REPORT_MEM_SIZE_SHAPE='^[0-9]+(\.[0-9]+)?((Ki|Mi|Gi|Ti|Pi)|B)$'
readonly _REPORT_PERCENT_SHAPE='^[0-9]+%$'

# _reporting_load_average_from_proc
# Stable-Linux fallback source for load average, used only when `uptime`'s
# output is missing or fails the shape check above. /proc/loadavg's format
# ("0.10 0.05 0.01 1/523 12345") is a kernel ABI, not a locale- or
# implementation-dependent text rendering, so it is preferred over
# `uptime`'s free-text "load average:" parsing wherever it's readable.
_reporting_load_average_from_proc() {
    local raw f1 f2 f3
    [[ -r "$MAOPS_PROC_LOADAVG" ]] || return 1
    raw="$(cat -- "$MAOPS_PROC_LOADAVG" 2>/dev/null)" || return 1
    read -r f1 f2 f3 _ <<<"$raw"
    [[ "$f1" =~ ^[0-9]+\.[0-9]+$ && "$f2" =~ ^[0-9]+\.[0-9]+$ && "$f3" =~ ^[0-9]+\.[0-9]+$ ]] || return 1
    printf '%s, %s, %s' "$f1" "$f2" "$f3"
}

_reporting_collect_load_average() {
    local raw parsed proc_value

    if raw="$(uptime 2>/dev/null)" && [[ -n "$raw" ]]; then
        parsed="$(printf '%s' "$raw" | sed -E 's/^.*[Ll]oad average:?[[:space:]]*//')"
        if [[ -n "$parsed" && "$parsed" != "$raw" && "$parsed" =~ $_REPORT_LOAD_AVERAGE_SHAPE ]]; then
            REPORT_LOAD_AVERAGE="$parsed"
            return 0
        fi
    fi

    if proc_value="$(_reporting_load_average_from_proc)" && [[ "$proc_value" =~ $_REPORT_LOAD_AVERAGE_SHAPE ]]; then
        REPORT_LOAD_AVERAGE="$proc_value"
        return 0
    fi

    REPORT_LOAD_AVERAGE="unavailable"
    REPORT_OPTIONAL_MISSING=1
}

# _reporting_kb_to_human KB
# Binary-unit, one-decimal-place approximation used only on the
# /proc/meminfo fallback path. Deliberately not byte-identical to
# `free -h`'s own rounding table -- that table is never asserted char-for-
# char here, since this path is only reached when `free -h` itself is
# unavailable or fails the shape check.
_reporting_kb_to_human() {
    local kb="$1"
    awk -v kb="$kb" 'BEGIN {
        split("K M G T P", units, " ")
        v = kb; i = 1
        while (v >= 1024 && i < 5) { v /= 1024; i++ }
        printf "%.1f%s\n", v, units[i]
    }'
}

# _reporting_memory_from_proc
# Stable-Linux fallback source for total/available memory, used only when
# `free -h`'s output is missing or fails the shape check. MemAvailable is a
# kernel-computed field (not present in very old kernels, but universally
# present on any kernel this toolkit targets) intended to be the same
# "available for new applications" figure `free`'s available column shows.
_reporting_memory_from_proc() {
    local total_kb avail_kb
    [[ -r "$MAOPS_PROC_MEMINFO" ]] || return 1
    total_kb="$(awk '/^MemTotal:/{print $2}' "$MAOPS_PROC_MEMINFO" 2>/dev/null)"
    avail_kb="$(awk '/^MemAvailable:/{print $2}' "$MAOPS_PROC_MEMINFO" 2>/dev/null)"
    [[ "$total_kb" =~ ^[0-9]+$ && "$avail_kb" =~ ^[0-9]+$ ]] || return 1
    printf '%s %s' "$(_reporting_kb_to_human "$total_kb")" "$(_reporting_kb_to_human "$avail_kb")"
}

# free -h's standard (procps) column layout: Mem: total used free shared
# buff/cache available -- columns 2 and 7. A BusyBox/non-procps `free`
# (different column count, no "available" column) will not produce two
# shape-matching fields here, so this falls through to the proc fallback
# rather than trusting a misaligned column as if it were real data.
_reporting_collect_memory() {
    local line total avail proc_line

    if line="$(free -h 2>/dev/null | awk '/^Mem:/{print $2, $7}')" && [[ -n "$line" ]]; then
        total="$(awk '{print $1}' <<<"$line")"
        avail="$(awk '{print $2}' <<<"$line")"
        if [[ "$total" =~ $_REPORT_MEM_SIZE_SHAPE && "$avail" =~ $_REPORT_MEM_SIZE_SHAPE ]]; then
            REPORT_MEM_TOTAL="$total"
            REPORT_MEM_AVAILABLE="$avail"
            return 0
        fi
    fi

    if proc_line="$(_reporting_memory_from_proc)"; then
        REPORT_MEM_TOTAL="$(awk '{print $1}' <<<"$proc_line")"
        REPORT_MEM_AVAILABLE="$(awk '{print $2}' <<<"$proc_line")"
        return 0
    fi

    REPORT_MEM_TOTAL="unavailable"
    REPORT_MEM_AVAILABLE="unavailable"
    REPORT_OPTIONAL_MISSING=1
}

# `-P` forces df's POSIX single-line-per-filesystem output, avoiding the
# long-device-name line-wrap that plain `df -h` can produce; `-h` still
# applies human-readable units on top of that fixed layout. There is no
# /proc equivalent for filesystem usage, so a shape-check failure here
# degrades straight to "unavailable" rather than falling back to a second
# source.
_reporting_collect_rootfs() {
    local line size used avail pct
    if line="$(df -hP / 2>/dev/null | awk 'NR==2{print $2, $3, $4, $5}')" && [[ -n "$line" ]]; then
        size="$(awk '{print $1}' <<<"$line")"
        used="$(awk '{print $2}' <<<"$line")"
        avail="$(awk '{print $3}' <<<"$line")"
        pct="$(awk '{print $4}' <<<"$line")"
        if [[ "$size" =~ $_REPORT_HUMAN_SIZE_SHAPE && "$used" =~ $_REPORT_HUMAN_SIZE_SHAPE \
            && "$avail" =~ $_REPORT_HUMAN_SIZE_SHAPE && "$pct" =~ $_REPORT_PERCENT_SHAPE ]]; then
            REPORT_ROOTFS_SIZE="$size"
            REPORT_ROOTFS_USED="$used"
            REPORT_ROOTFS_AVAILABLE="$avail"
            REPORT_ROOTFS_PERCENT="$pct"
            return 0
        fi
    fi
    REPORT_ROOTFS_SIZE="unavailable"
    REPORT_ROOTFS_USED="unavailable"
    REPORT_ROOTFS_AVAILABLE="unavailable"
    REPORT_ROOTFS_PERCENT="unavailable"
    REPORT_OPTIONAL_MISSING=1
}

###############################################################################
# Collection entry point
###############################################################################

# reporting_collect
# Populates every REPORT_* field above. Caller must set REPO_ROOT first.
reporting_collect() {
    REPORT_REQUIRED_MISSING=0
    REPORT_OPTIONAL_MISSING=0

    REPORT_VERSION="$PROJECT_VERSION"
    _reporting_collect_timestamp
    _reporting_collect_execution_mode
    _reporting_collect_config
    _reporting_collect_doctor
    _reporting_collect_integrity

    _reporting_collect_hostname
    _reporting_collect_os_description
    _reporting_collect_kernel
    _reporting_collect_arch
    _reporting_collect_cpu_count
    _reporting_collect_load_average
    _reporting_collect_memory
    _reporting_collect_rootfs
}

###############################################################################
# Status aggregation
###############################################################################

# reporting_overall
# fail: doctor or integrity fails, or a required section is uncollectable.
# warn: only optional system/resource info is unavailable.
# pass: everything collected, doctor and integrity both pass.
reporting_overall() {
    if [[ "$REPORT_DOCTOR_OVERALL" == "fail" || "$REPORT_INTEGRITY_OVERALL" == "fail" || "$REPORT_REQUIRED_MISSING" -eq 1 ]]; then
        REPORT_OVERALL="fail"
    elif [[ "$REPORT_OPTIONAL_MISSING" -eq 1 ]]; then
        REPORT_OVERALL="warn"
    else
        REPORT_OVERALL="pass"
    fi
}

###############################################################################
# Redaction
###############################################################################

# reporting_redact
# Overwrites the two fields that can identify this specific host/user.
# Report structure and status are never affected. Must be called after
# reporting_collect and before any rendering/saving.
reporting_redact() {
    REPORT_HOSTNAME="<redacted>"
    REPORT_CONFIG_PATH="<redacted>"
}

###############################################################################
# Atomic save
###############################################################################

# report_save_atomic TARGET CONTENT FORCE
# FORCE: "1" if --force was given, anything else otherwise.
# All safety checks run here, immediately before mutation, rather than
# earlier in argument parsing, to keep the validate-to-mutate window as
# short as possible. Returns 0 on success, 1 on failure (with
# REPORT_SAVE_LAST_ERROR set). Caller is responsible for `umask 077` before
# calling this, matching config_write_atomic's convention.
report_save_atomic() {
    local target="$1" content="$2" force="${3:-0}"
    local dir tmp

    # A symlink is refused unconditionally, even with --force: `--force`
    # exists only to permit overwriting a regular file the caller already
    # owns, never to launder a write through a symlink to an unrelated path.
    if [[ -L "$target" ]]; then
        REPORT_SAVE_LAST_ERROR="refusing to replace a symbolic link: $target"
        return 1
    fi

    if [[ -d "$target" ]]; then
        REPORT_SAVE_LAST_ERROR="output path is a directory: $target"
        return 1
    fi

    # No mkdir -p here, deliberately: --output is an arbitrary user-supplied
    # path, not the one well-known XDG config location config_write_atomic
    # targets, so silently creating directory structure at an arbitrary
    # location would be a larger blast radius than this feature justifies.
    dir="$(dirname -- "$target")"
    if [[ ! -d "$dir" ]]; then
        REPORT_SAVE_LAST_ERROR="parent directory does not exist: $dir"
        return 1
    fi

    if [[ -e "$target" ]]; then
        if [[ "$force" != "1" ]]; then
            REPORT_SAVE_LAST_ERROR="output file already exists (use --force): $target"
            return 1
        fi

        if [[ ! -f "$target" ]]; then
            REPORT_SAVE_LAST_ERROR="refusing to replace a non-regular file: $target"
            return 1
        fi
    fi

    # Same directory as $target, so the final rename is a same-filesystem
    # atomic rename, never a cross-device copy+unlink fallback. Prefix is
    # distinct from config_write_atomic's ".config.XXXXXX" so the two can
    # never collide even if --output points inside the config directory.
    tmp="$(mktemp -- "$dir/.maops-report.XXXXXX")" || {
        REPORT_SAVE_LAST_ERROR="failed to create a temporary file in $dir"
        return 1
    }

    # Set explicitly rather than relying solely on the caller's umask, so
    # this guarantee doesn't depend on every call site remembering it.
    if ! chmod 0600 -- "$tmp"; then
        rm -f -- "$tmp"
        REPORT_SAVE_LAST_ERROR="failed to set permissions on temporary file"
        return 1
    fi

    if ! printf '%s\n' "$content" >"$tmp"; then
        rm -f -- "$tmp"
        REPORT_SAVE_LAST_ERROR="failed to write report content"
        return 1
    fi

    if ! mv -f -- "$tmp" "$target"; then
        rm -f -- "$tmp"
        REPORT_SAVE_LAST_ERROR="failed to move report into place: $target"
        return 1
    fi

    return 0
}
