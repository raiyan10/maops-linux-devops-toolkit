#!/usr/bin/env bats
#
# Tests for scripts/config/config-manager.sh and the config precedence
# resolver in scripts/common/config-file.sh. isolate_config_env (from
# tests/test-helper.bash) points HOME/XDG_CONFIG_HOME at fresh per-test
# directories so these tests never read or write the real ~/.config.

setup() {
    load '../test-helper'
    SCRIPT="$REPO_ROOT/scripts/config/config-manager.sh"
    isolate_config_env
}

@test "config-manager.sh --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "config-manager.sh --version exits 0 and shows the current project version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "config with no subcommand exits 2" {
    run "$SCRIPT"
    [ "$status" -eq 2 ]
}

@test "config bogus exits 2 with an unknown-command message" {
    run "$SCRIPT" bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown config command"* ]]
}

# --- path ---------------------------------------------------------------

@test "config path defaults to HOME/.config/maops/config when XDG_CONFIG_HOME is unset" {
    unset XDG_CONFIG_HOME
    run "$SCRIPT" path
    [ "$status" -eq 0 ]
    [ "$output" = "$HOME/.config/maops/config" ]
}

@test "config path honors XDG_CONFIG_HOME" {
    run "$SCRIPT" path
    [ "$status" -eq 0 ]
    [ "$output" = "$XDG_CONFIG_HOME/maops/config" ]
}

@test "config path honors MAOPS_CONFIG_FILE above XDG_CONFIG_HOME and HOME" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/custom/cfg"
    run "$SCRIPT" path
    [ "$status" -eq 0 ]
    [ "$output" = "$MAOPS_CONFIG_FILE" ]
}

@test "config path rejects a trailing extra argument" {
    run "$SCRIPT" path bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unexpected argument: bogus"* ]]
}

# --- init -----------------------------------------------------------------

@test "config init creates the file and parent directories" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/deep/nested/config"
    run "$SCRIPT" init
    [ "$status" -eq 0 ]
    [ -f "$MAOPS_CONFIG_FILE" ]
}

@test "config init writes the file with mode 600" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    run "$SCRIPT" init
    [ "$status" -eq 0 ]
    [ "$(stat -c '%a' "$MAOPS_CONFIG_FILE")" = "600" ]
}

@test "config init refuses to overwrite an existing file without --force" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'output_format=json\n' >"$MAOPS_CONFIG_FILE"

    run "$SCRIPT" init
    [ "$status" -eq 1 ]
    grep -qx 'output_format=json' "$MAOPS_CONFIG_FILE"
}

@test "config init --force overwrites an existing file" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'process_limit=999\n' >"$MAOPS_CONFIG_FILE"

    run "$SCRIPT" init --force
    [ "$status" -eq 0 ]
    ! grep -q '999' "$MAOPS_CONFIG_FILE"
    grep -q '^process_limit=10$' "$MAOPS_CONFIG_FILE"
}

@test "config init leaves no stray temp file behind after a successful write" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    run "$SCRIPT" init
    [ "$status" -eq 0 ]

    local leftovers
    leftovers="$(find "$BATS_TEST_TMPDIR" -maxdepth 1 -name '.config.*')"
    [ -z "$leftovers" ]
}

@test "config init unknown flag exits 2" {
    run "$SCRIPT" init --bogus
    [ "$status" -eq 2 ]
}

# --- validate: structure ---------------------------------------------------

@test "config validate accepts a well-formed file" {
    local cfg="$BATS_TEST_TMPDIR/config"
    cat >"$cfg" <<'EOF'
# a comment
output_format=text

process_limit=10
ping_count=4
network_timeout=5
EOF
    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 0 ]
}

@test "config validate rejects an unknown key" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'bogus_key=1\n' >"$cfg"

    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bogus_key"* ]]
}

@test "config validate rejects a duplicate key" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'output_format=text\noutput_format=json\n' >"$cfg"

    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
    [[ "$output" == *"duplicate"* ]]
}

@test "config validate rejects a malformed line" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'not_a_kv_pair\n' >"$cfg"

    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
    [[ "$output" == *"malformed"* ]]
}

@test "config validate allows blank lines and full-line comments" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf '# just a comment\n\noutput_format=text\n' >"$cfg"

    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 0 ]
}

@test "config validate handles leading/trailing whitespace around key and value" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf '  output_format   =   json  \n' >"$cfg"

    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 0 ]
}

@test "config validate on a missing path reports invalid (exit 1)" {
    run "$SCRIPT" validate "$BATS_TEST_TMPDIR/nonexistent"
    [ "$status" -eq 1 ]
}

@test "config validate --help dispatches and exits 0" {
    run "$SCRIPT" validate --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "config validate rejects a trailing extra argument after PATH" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'output_format=text\n' >"$cfg"

    run "$SCRIPT" validate "$cfg" extra
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unexpected argument: extra"* ]]
}

# --- validate: value ranges --------------------------------------------

@test "config validate rejects an invalid output_format enum value" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'output_format=xml\n' >"$cfg"

    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
    [[ "$output" == *"output_format"* ]]
}

@test "config validate accepts both output_format enum values" {
    local cfg="$BATS_TEST_TMPDIR/config"

    printf 'output_format=text\n' >"$cfg"
    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 0 ]

    printf 'output_format=json\n' >"$cfg"
    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 0 ]
}

@test "config validate rejects process_limit=0" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'process_limit=0\n' >"$cfg"
    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
}

@test "config validate rejects a negative ping_count" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'ping_count=-1\n' >"$cfg"
    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
}

@test "config validate rejects a leading-zero network_timeout" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'network_timeout=007\n' >"$cfg"
    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
}

@test "config validate accepts the minimum positive-integer boundary value 1" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'process_limit=1\n' >"$cfg"
    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 0 ]
}

@test "config validate rejects non-numeric text for a positive-integer key" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'ping_count=four\n' >"$cfg"
    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
}

# --- injection / inert-parsing safety ---------------------------------------

@test "command substitution in a value is treated as inert text, not executed" {
    local cfg="$BATS_TEST_TMPDIR/config"
    local marker="$BATS_TEST_TMPDIR/marker"
    printf 'process_limit=$(touch %s)\n' "$marker" >"$cfg"

    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
    [ ! -e "$marker" ]
}

@test "backtick command substitution in a value is inert" {
    local cfg="$BATS_TEST_TMPDIR/config"
    printf 'process_limit=`id`\n' >"$cfg"

    stub_bin_init
    stub_command id <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/id.calls"
STUB

    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
    [ ! -f "$BATS_TEST_TMPDIR/id.calls" ]
}

@test "semicolon-chained shell metacharacters in a value never execute" {
    local cfg="$BATS_TEST_TMPDIR/config"
    local marker="$BATS_TEST_TMPDIR/marker2"
    printf 'ping_count=5; touch %s\n' "$marker" >"$cfg"

    run "$SCRIPT" validate "$cfg"
    [ "$status" -eq 1 ]
    [ ! -e "$marker" ]
}

@test "config-file.sh contains no eval, source, or re-parsed shell string" {
    # Comment lines are excluded so prose describing the "never sourced or
    # eval'd" guarantee doesn't false-positive against itself; this checks
    # actual code.
    ! grep -v '^[[:space:]]*#' "$REPO_ROOT/scripts/common/config-file.sh" |
        grep -qE '\beval\b|bash -c|sh -c|(^|[^[:alnum:]_])source[[:space:]]'
}

# --- precedence --------------------------------------------------------

@test "config show reflects a value from the config file when no env var is set" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'ping_count=7\n' >"$MAOPS_CONFIG_FILE"

    run "$SCRIPT" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"ping_count           : 7"* ]]
}

@test "MAOPS_* env var overrides the config file value" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'ping_count=7\n' >"$MAOPS_CONFIG_FILE"
    export MAOPS_PING_COUNT=3

    run "$SCRIPT" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"ping_count           : 3"* ]]
}

@test "built-in default is used when neither env var nor config file set a key" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'output_format=json\n' >"$MAOPS_CONFIG_FILE"

    run "$SCRIPT" show
    [ "$status" -eq 0 ]
    [[ "$output" == *"network_timeout      : 5"* ]]
}

@test "config show --format json emits a single valid JSON document" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    run "$SCRIPT" show --format json
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^\{.*\}$ ]]
    printf '%s' "$output" | python3 -c 'import json,sys; json.load(sys.stdin)'
}

@test "config show --format json numeric fields are unquoted JSON numbers" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    run "$SCRIPT" show --format json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"process_limit":10'* ]]
    [[ "$output" != *'"process_limit":"10"'* ]]
}

@test "config show text output is unaffected by --format text" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    run "$SCRIPT" show
    local default_output="$output"

    run "$SCRIPT" show --format text
    [ "$output" = "$default_output" ]
}

@test "config show rejects an invalid --format value with exit 2" {
    run "$SCRIPT" show --format xml
    [ "$status" -eq 2 ]
}

@test "config show rejects an unexpected positional argument" {
    run "$SCRIPT" show bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown option: bogus"* ]]
}

# --- integration: leaf-script defaults flow through config ------------------

stub_ps_many_rows() {
    stub_command ps <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/ps.calls"
printf '  PID USER             %%CPU %%MEM     ELAPSED COMMAND\n'
for i in $(seq 1 50); do
    printf '%5d %-16s %4d.0  0.1       00:%02d bash\n' "$((1000 + i))" "user$i" "$i" "$((i % 60))"
done
STUB
}

@test "process-monitor.sh honors process_limit from the config file when no LIMIT is given" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'process_limit=3\n' >"$MAOPS_CONFIG_FILE"

    stub_bin_init
    stub_ps_many_rows

    run "$REPO_ROOT/scripts/process/process-monitor.sh"
    [ "$status" -eq 0 ]

    local data_rows
    data_rows="$(printf '%s\n' "$output" | grep -c 'bash$' || true)"
    [ "$data_rows" -eq 3 ]
}

@test "an explicit LIMIT argument still overrides the config file's process_limit" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'process_limit=50\n' >"$MAOPS_CONFIG_FILE"

    stub_bin_init
    stub_ps_many_rows

    run "$REPO_ROOT/scripts/process/process-monitor.sh" 3
    [ "$status" -eq 0 ]

    local data_rows
    data_rows="$(printf '%s\n' "$output" | grep -c 'bash$' || true)"
    [ "$data_rows" -eq 3 ]
}

@test "ping-check.sh honors ping_count from the config file when no COUNT is given" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'ping_count=2\n' >"$MAOPS_CONFIG_FILE"

    stub_bin_init
    stub_command ping <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/ping.calls"
exit 0
STUB

    run "$REPO_ROOT/scripts/network/ping-check.sh" example.invalid
    [ "$status" -eq 0 ]
    grep -q -- "-c 2" "$BATS_TEST_TMPDIR/ping.calls"
}

@test "port-check.sh honors network_timeout from the config file when no TIMEOUT is given" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'network_timeout=9\n' >"$MAOPS_CONFIG_FILE"

    stub_bin_init
    stub_command timeout <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/timeout.calls"
exit 0
STUB

    run "$REPO_ROOT/scripts/network/port-check.sh" example.invalid 443
    [ "$status" -eq 0 ]
    grep -q -- "^9 " "$BATS_TEST_TMPDIR/timeout.calls"
}
