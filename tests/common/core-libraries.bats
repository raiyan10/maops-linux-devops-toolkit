#!/usr/bin/env bats
#
# Tests for the scripts/common/*.sh libraries that had no direct unit
# coverage before Day 6: colors.sh, config.sh, cli.sh, format.sh,
# config-file.sh, release-files.sh, install/lib.sh, integrity.sh, plus
# logger.sh/helpers.sh/output.sh (some of which tests/common/helpers.bats
# already covers indirectly under a misleading filename -- that file
# actually tests cli.sh). Duplicate-sourcing checks run in a fresh `bash
# -c` subshell per library, since test-helper.bash itself already sources
# config.sh once in this process.

setup() {
    load '../test-helper'
    COMMON="$REPO_ROOT/scripts/common"
}

# --- duplicate-sourcing safety ---------------------------------------------

@test "colors.sh can be sourced twice without error" {
    run bash -c "source '$COMMON/colors.sh'; source '$COMMON/colors.sh'; echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "config.sh can be sourced twice without error" {
    run bash -c "source '$COMMON/config.sh'; source '$COMMON/config.sh'; echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "cli.sh can be sourced twice without error" {
    run bash -c "source '$COMMON/colors.sh'; source '$COMMON/config.sh'; source '$COMMON/logger.sh'; source '$COMMON/cli.sh'; source '$COMMON/cli.sh'; echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "format.sh can be sourced twice without error" {
    run bash -c "source '$COMMON/format.sh'; source '$COMMON/format.sh'; echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "config-file.sh can be sourced twice without error" {
    run bash -c "source '$COMMON/colors.sh'; source '$COMMON/config.sh'; source '$COMMON/logger.sh'; source '$COMMON/cli.sh'; source '$COMMON/config-file.sh'; source '$COMMON/config-file.sh'; echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "release-files.sh can be sourced twice without error" {
    run bash -c "source '$COMMON/release-files.sh'; source '$COMMON/release-files.sh'; echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "integrity.sh can be sourced twice without error" {
    run bash -c "source '$COMMON/integrity.sh'; source '$COMMON/integrity.sh'; echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "scripts/install/lib.sh can be sourced twice without error" {
    run bash -c "source '$REPO_ROOT/scripts/install/lib.sh'; source '$REPO_ROOT/scripts/install/lib.sh'; echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "bootstrap.sh can be sourced twice without error" {
    run bash -c "source '$COMMON/bootstrap.sh'; source '$COMMON/bootstrap.sh'; echo OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

# --- logging levels ----------------------------------------------------

@test "log_info emits an INFO tag with a timestamp" {
    run bash -c "source '$COMMON/colors.sh'; source '$COMMON/logger.sh'; log_info hi"
    [[ "$output" == *"[INFO]"*"hi"* ]]
    [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "log_success emits a SUCCESS tag" {
    run bash -c "source '$COMMON/colors.sh'; source '$COMMON/logger.sh'; log_success hi"
    [[ "$output" == *"[SUCCESS]"*"hi"* ]]
}

@test "log_warn emits a WARNING tag" {
    run bash -c "source '$COMMON/colors.sh'; source '$COMMON/logger.sh'; log_warn hi"
    [[ "$output" == *"[WARNING]"*"hi"* ]]
}

@test "log_error emits an ERROR tag" {
    run bash -c "source '$COMMON/colors.sh'; source '$COMMON/logger.sh'; log_error hi"
    [[ "$output" == *"[ERROR]"*"hi"* ]]
}

# --- NO_COLOR / non-terminal output behavior --------------------------

@test "log_* output contains no ANSI escapes when captured through a non-terminal pipe" {
    # bats' `run` always captures via a pipe, so every log_* call in this
    # suite already exercises the non-tty path -- this test documents and
    # locks in that guarantee explicitly.
    run bash -c "source '$COMMON/colors.sh'; source '$COMMON/logger.sh'; log_error hi"
    [[ "$output" != *$'\033'* ]]
}

@test "colors.sh suppresses ANSI codes when NO_COLOR is set" {
    run bash -c "export NO_COLOR=1; source '$COMMON/colors.sh'; printf '%s' \"\$RED\""
    [ -z "$output" ]
}

@test "colors.sh source contains the NO_COLOR / non-tty suppression check" {
    grep -q 'NO_COLOR' "$COMMON/colors.sh"
    grep -q -- '-t 1' "$COMMON/colors.sh"
}

# --- require_command / require_linux -----------------------------------

@test "require_command fails with exit 1 and a clear message for a nonexistent command" {
    run bash -c "source '$COMMON/helpers.sh'; require_command definitely-not-a-real-cmd-xyz"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Required command not found"*"definitely-not-a-real-cmd-xyz"* ]]
}

@test "require_command succeeds silently for an existing command" {
    run bash -c "source '$COMMON/helpers.sh'; require_command bash"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "require_linux exits 1 with a Linux-only message when uname reports non-Linux" {
    stub_bin_init
    stub_command uname <<'STUB'
echo "Darwin"
STUB
    run bash -c "source '$COMMON/helpers.sh'; require_linux"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Linux only"* ]]
}

# --- divider / output behavior ------------------------------------------

@test "divider prints exactly 80 dashes" {
    run bash -c "source '$COMMON/helpers.sh'; divider"
    [ "${#output}" -eq 80 ]
    [[ "$output" =~ ^-{80}$ ]]
}

@test "print_title wraps its argument between two dividers" {
    run bash -c "source '$COMMON/helpers.sh'; print_title MyTitle"
    [ "$(wc -l <<<"$output")" -eq 3 ]
    [[ "$output" == *"MyTitle"* ]]
}

@test "show_header delegates to print_title verbatim" {
    local a b
    a="$(bash -c "source '$COMMON/helpers.sh'; print_title Same")"
    b="$(bash -c "source '$COMMON/helpers.sh'; source '$COMMON/output.sh'; show_header Same")"
    [ "$a" = "$b" ]
}

@test "show_section delegates to section verbatim" {
    local a b
    a="$(bash -c "source '$COMMON/helpers.sh'; section Same")"
    b="$(bash -c "source '$COMMON/helpers.sh'; source '$COMMON/output.sh'; show_section Same")"
    [ "$a" = "$b" ]
}

@test "show_footer prints a single 80-dash divider" {
    run bash -c "source '$COMMON/helpers.sh'; source '$COMMON/output.sh'; show_footer"
    [ "$(wc -l <<<"$output")" -eq 1 ]
    [[ "$output" =~ ^-{80}$ ]]
}

@test "print_key_value formats a key/value pair with a colon separator" {
    run bash -c "source '$COMMON/helpers.sh'; print_key_value Key Value"
    [[ "$output" =~ ^Key\ +:\ Value$ ]]
}

# --- configuration version access ---------------------------------------

@test "config.sh exposes PROJECT_VERSION matching the toolkit's single source of truth" {
    [ -n "$PROJECT_VERSION" ]
    run bash -c "source '$COMMON/config.sh'; echo \"\$PROJECT_VERSION\""
    [ "$output" = "$PROJECT_VERSION" ]
}

@test "PROJECT_VERSION is readonly and rejects reassignment" {
    run bash -c "source '$COMMON/config.sh'; PROJECT_VERSION=x 2>&1"
    [ "$status" -ne 0 ]
    [[ "$output" == *"readonly"* ]]
}

# --- format.sh JSON helpers ----------------------------------------------

@test "json_kv escapes embedded quotes and backslashes" {
    run bash -c "source '$COMMON/format.sh'; json_kv key 'a\"b\\c'"
    [ "$status" -eq 0 ]
    [ "$output" = '"key":"a\"b\\c"' ]
}

@test "json_kv --raw emits the value unescaped" {
    run bash -c "source '$COMMON/format.sh'; json_kv ok true --raw"
    [ "$output" = '"ok":true' ]
}

@test "json_object assembles a flat multi-key object that parses as valid JSON" {
    run bash -c "source '$COMMON/format.sh'; json_object a 1 b 2"
    [ "$status" -eq 0 ]
    assert_valid_json "$output"
}
