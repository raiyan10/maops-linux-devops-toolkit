#!/usr/bin/env bash
#
# health-report.sh -- Example automation script for the MAOps Linux DevOps
# Toolkit. Generates a redacted JSON operational report and saves it to a
# safe location, suitable for a cron job or CI health check.
#
# This is a standalone example, not a MAOps CLI command: it resolves the
# `maops` executable itself (PATH or MAOPS_BIN) and calls it exactly like
# any other external user of the toolkit would.

set -euo pipefail

###############################################################################
# Resolve the maops executable
###############################################################################

resolve_maops_bin() {
    if [[ -n "${MAOPS_BIN:-}" ]]; then
        if [[ ! -x "$MAOPS_BIN" ]]; then
            echo "MAOPS_BIN is set but not executable: $MAOPS_BIN" >&2
            exit 1
        fi
        printf '%s' "$MAOPS_BIN"
        return 0
    fi

    if command -v maops >/dev/null 2>&1; then
        command -v maops
        return 0
    fi

    echo "Could not find 'maops' on PATH and MAOPS_BIN is not set." >&2
    echo "Set MAOPS_BIN=/path/to/bin/maops or install maops first." >&2
    exit 1
}

###############################################################################
# Usage
###############################################################################

usage() {
    cat <<EOF
Usage:
    $(basename "$0") [OUTPUT_DIR]

Generates a redacted JSON operational report via 'maops report save' and
saves it under OUTPUT_DIR (default: \$HOME/.local/state/maops/reports).

Environment:
    MAOPS_BIN   Path to the maops executable (overrides PATH lookup)

Exit status reflects the report's own health verdict: 0 if the underlying
'maops report' considered itself healthy ("pass"), 1 otherwise (including
if the report itself could not be generated or saved).
EOF
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
esac

###############################################################################
# Resolve and validate the output directory
###############################################################################

OUTPUT_DIR="${1:-$HOME/.local/state/maops/reports}"

if [[ -e "$OUTPUT_DIR" && ! -d "$OUTPUT_DIR" ]]; then
    echo "Refusing to use OUTPUT_DIR, it exists and is not a directory: $OUTPUT_DIR" >&2
    exit 1
fi

if [[ -L "$OUTPUT_DIR" ]]; then
    echo "Refusing to use OUTPUT_DIR, it is a symlink: $OUTPUT_DIR" >&2
    exit 1
fi

umask 077
mkdir -p -- "$OUTPUT_DIR"

MAOPS_BIN="$(resolve_maops_bin)"
readonly MAOPS_BIN

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_PATH="$OUTPUT_DIR/health-report-$TIMESTAMP.json"
readonly TIMESTAMP REPORT_PATH

###############################################################################
# Generate the report
###############################################################################

set +e
"$MAOPS_BIN" report save --output "$REPORT_PATH" --format json --redact
save_status=$?
set -e

if [[ ! -f "$REPORT_PATH" ]]; then
    echo "Report was not written: $REPORT_PATH" >&2
    exit 1
fi

echo "Report saved: $REPORT_PATH"

###############################################################################
# Validate the JSON with python3 when available
###############################################################################

if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import json; json.load(open('$REPORT_PATH'))" 2>/dev/null; then
        echo "JSON validation: OK"
    else
        echo "JSON validation: FAILED (report file is not valid JSON)" >&2
        exit 1
    fi
else
    echo "python3 not available; skipping JSON validation."
fi

###############################################################################
# Reflect the report's own health verdict as this script's exit status
###############################################################################

exit "$save_status"
