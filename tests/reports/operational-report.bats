#!/usr/bin/env bats
#
# Tests for scripts/reports/operational-report.sh (maops report). Follows
# the same deterministic-PATH conventions as doctor.bats/integrity-check.bats:
# stub_shadow_path_except rebuilds PATH from scratch so "missing command"
# scenarios are genuine, and stub_fixed_output (layered on top of an
# already-built shadow dir) makes date/hostname/uname/getconf/uptime/free/df
# emit byte-exact, host-independent content for field assertions. Because
# PATH is fully replaced, the script under test is always invoked as
# "$REAL_BASH" "$SCRIPT" ..., exactly like doctor.bats.
#
# Only the handful of tests that assert a specific overall=pass/warn use a
# shared, once-per-file "healthy" fixture (a build_drvfs_clone_fixture
# snapshot with a fresh `git add -A`, built in setup_file so live, in-progress
# uncommitted changes to this repo don't make `maops integrity` flaky).
# Everything else -- field content, redaction, save mechanics, network/
# mutation safety -- runs directly against the live checkout, exactly like
# doctor.bats does, since those assertions don't depend on integrity's
# pass/fail state.

bats_require_minimum_version 1.5.0

setup_file() {
    load '../test-helper'
    build_drvfs_clone_fixture "$BATS_FILE_TMPDIR/fixture"
    (
        cd "$BATS_FILE_TMPDIR/fixture"
        git add -A
        # With core.fileMode=false (this project's WSL/drvfs default), `git
        # add` on a brand-new file stages it at 100644 regardless of its
        # real on-disk mode -- core.fileMode only suppresses mode-change
        # detection on already-tracked files, it doesn't make `add` read the
        # real mode for a first-time add. If operational-report.sh/reporting.sh
        # aren't yet committed in the real repository, they need the same
        # explicit correction here so this fixture's integrity check sees
        # the correct 100755.
        git update-index --chmod=+x scripts/common/reporting.sh scripts/reports/operational-report.sh 2>/dev/null || true
    )
}

setup() {
    load '../test-helper'
    SCRIPT="$REPO_ROOT/scripts/reports/operational-report.sh"
    FIXTURE_SCRIPT="$BATS_FILE_TMPDIR/fixture/scripts/reports/operational-report.sh"
    isolate_config_env
}

# stub_deterministic_system_facts
# Layers fixed, host-independent output for every command the report's
# optional system/resource fields depend on, on top of an already-called
# stub_shadow_path_except. Must be called after stub_shadow_path_except, and
# never after omitting one of these same commands from the roster (it would
# silently re-add a wrapper for it).
stub_deterministic_system_facts() {
    stub_fixed_output hostname <<'STUB'
printf 'report-test-host\n'
STUB

    stub_fixed_output uname <<'STUB'
case "$1" in
    -s) printf 'Linux\n' ;;
    -r) printf '6.18.0-test\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Linux\n' ;;
esac
STUB

    stub_fixed_output getconf <<'STUB'
printf '4\n'
STUB

    stub_fixed_output uptime <<'STUB'
printf ' 12:00:00 up 1 day,  2:34,  1 user,  load average: 0.10, 0.05, 0.01\n'
STUB

    stub_fixed_output free <<'STUB'
printf '              total        used        free      shared  buff/cache   available\n'
printf 'Mem:           15Gi       4.0Gi        8Gi       200Mi       3.0Gi        10Gi\n'
printf 'Swap:            0B          0B          0B\n'
STUB

    stub_fixed_output df <<'STUB'
printf 'Filesystem      Size  Used Avail Use%% Mounted on\n'
printf '/dev/sda1       100G   40G   55G  43%% /\n'
STUB
}

# --- CLI surface -----------------------------------------------------------

@test "operational-report.sh --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "operational-report.sh --version exits 0 and shows the current project version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "report with no subcommand prints usage to stderr and exits 2" {
    run --separate-stderr "$SCRIPT"
    [ "$status" -eq 2 ]
    [[ "$stderr" == *"Usage:"* ]]
    [[ "$output" != *"MAOps Operational Report"* ]]
}

@test "report bogus subcommand exits 2 with an unknown-command message" {
    run "$SCRIPT" bogus
    [ "$status" -eq 2 ]
    [[ "$output" == *"Unknown report command"* ]]
}

@test "maops report summary dispatches through bin/maops" {
    run "$MAOPS_BIN" report summary --format json
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    assert_valid_json "$output"
    [ "$(json_field "$output" 'doc["version"]')" = "$PROJECT_VERSION" ]
}

@test "maops report with no subcommand exits 2" {
    run "$MAOPS_BIN" report
    [ "$status" -eq 2 ]
}

# --- text/JSON shape ---------------------------------------------------

@test "report summary defaults to text output" {
    run "$SCRIPT" summary
    [[ "$output" == *"MAOps Operational Report"* ]]
    [[ "$output" == *"overall"* ]]
}

@test "report summary --format text is identical to the default" {
    # Uses deterministic stubs for every field, not just the timestamp: the
    # real, unstubbed load average/memory/disk figures genuinely change
    # between two consecutive invocations (this is live system state, not a
    # one-second-boundary artifact like the timestamp), which made an
    # earlier version of this test flaky through no fault of the script
    # itself. Stripping generated_at_utc is still needed on top of that,
    # exactly like the identical fix in doctor.bats/integrity-check.bats.
    stub_shadow_path_except
    stub_deterministic_system_facts

    run "$REAL_BASH" "$SCRIPT" summary
    local default_output
    default_output="$(grep -v '^generated_at_utc' <<<"$output")"

    run "$REAL_BASH" "$SCRIPT" summary --format text
    local this_output
    this_output="$(grep -v '^generated_at_utc' <<<"$output")"

    [ "$this_output" = "$default_output" ]
}

@test "report summary --format json is exactly one valid JSON document" {
    run "$SCRIPT" summary --format json
    [[ "$output" =~ ^\{.*\}$ ]]
    assert_valid_json "$output"
}

@test "report summary --format xml is rejected with exit 2" {
    run "$SCRIPT" summary --format xml
    [ "$status" -eq 2 ]
}

@test "report summary --format JSON (uppercase) is rejected predictably, not silently normalized" {
    run "$SCRIPT" summary --format JSON
    [ "$status" -eq 2 ]
}

@test "operational-report.sh -v exits 0 and shows the current project version" {
    run "$SCRIPT" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "operational-report.sh version (bare subcommand) exits 0 and shows the current project version" {
    run "$SCRIPT" version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "report summary --format=json (combined-flag syntax) works" {
    run "$SCRIPT" summary --format=json
    assert_valid_json "$output"
}

@test "report summary --format with no argument is a usage error" {
    run "$SCRIPT" summary --format
    [ "$status" -eq 2 ]
}

@test "report summary --help dispatches and exits 0" {
    run "$SCRIPT" summary --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "report save --help dispatches and exits 0" {
    run "$SCRIPT" save --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "report JSON has no ANSI escape sequences" {
    run "$SCRIPT" summary --format json
    [[ "$output" != *$'\e['* ]]
}

@test "report text has no ANSI escape sequences" {
    run "$SCRIPT" summary
    [[ "$output" != *$'\e['* ]]
}

# --- field content (deterministic) --------------------------------------

@test "JSON version field matches PROJECT_VERSION" {
    run "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["version"]')" = "$PROJECT_VERSION" ]
}

@test "JSON generated_at_utc is a deterministic ISO-8601 UTC timestamp" {
    run "$SCRIPT" summary --format json
    local ts
    ts="$(json_field "$output" 'doc["generated_at_utc"]')"
    [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "JSON execution_mode is source-tree when run from a checkout" {
    run "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["execution_mode"]')" = "source-tree" ]
}

@test "JSON execution_mode is installed when run from an installed prefix" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$REPO_ROOT/scripts/install/install.sh" --prefix "$prefix" >/dev/null

    run "$prefix/bin/maops" report summary --format json
    [ "$(json_field "$output" 'doc["execution_mode"]')" = "installed" ]
}

@test "JSON system fields match the stubbed hostname/uname output" {
    stub_shadow_path_except
    stub_deterministic_system_facts

    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["system"]["hostname"]')" = "report-test-host" ]
    [ "$(json_field "$output" 'doc["system"]["operating_system"]')" = "Linux" ]
    [ "$(json_field "$output" 'doc["system"]["kernel"]')" = "6.18.0-test" ]
    [ "$(json_field "$output" 'doc["system"]["architecture"]')" = "x86_64" ]
}

@test "JSON logical_cpu_count is a real JSON number, not a string" {
    stub_shadow_path_except
    stub_deterministic_system_facts

    run "$REAL_BASH" "$SCRIPT" summary --format json
    [[ "$output" == *'"logical_cpu_count":4'* ]]
    [[ "$output" != *'"logical_cpu_count":"4"'* ]]
    [ "$(json_field "$output" 'doc["system"]["logical_cpu_count"]')" = "4" ]
}

@test "JSON resource fields match stubbed uptime/free/df output" {
    stub_shadow_path_except
    stub_deterministic_system_facts

    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["resources"]["load_average"]')" = "0.10, 0.05, 0.01" ]
    [ "$(json_field "$output" 'doc["resources"]["memory_total"]')" = "15Gi" ]
    [ "$(json_field "$output" 'doc["resources"]["memory_available"]')" = "10Gi" ]
    [ "$(json_field "$output" 'doc["resources"]["root_filesystem_size"]')" = "100G" ]
    [ "$(json_field "$output" 'doc["resources"]["root_filesystem_used"]')" = "40G" ]
    [ "$(json_field "$output" 'doc["resources"]["root_filesystem_available"]')" = "55G" ]
    [ "$(json_field "$output" 'doc["resources"]["root_filesystem_usage_percent"]')" = "43%" ]
}

@test "an unavailable optional command degrades its field rather than crashing" {
    # uptime is shadowed away (genuinely missing, not just PATH-stubbed), and
    # MAOPS_PROC_LOADAVG is redirected to a nonexistent path so the
    # /proc/loadavg fallback introduced for Day 8 also genuinely fails --
    # otherwise the real host's actual /proc/loadavg would be read and the
    # field would populate instead of degrading, since the fallback exists
    # precisely to avoid "unavailable" when only one of the two sources is
    # missing.
    stub_shadow_path_except uptime
    export MAOPS_PROC_LOADAVG="$BATS_TEST_TMPDIR/no-such-loadavg"
    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["resources"]["load_average"]')" = "unavailable" ]
}

@test "the /proc/loadavg fallback is used when uptime is unavailable but /proc/loadavg is readable" {
    stub_shadow_path_except uptime
    export MAOPS_PROC_LOADAVG="$BATS_TEST_TMPDIR/loadavg"
    printf '0.52 0.58 0.59 1/523 12345\n' >"$MAOPS_PROC_LOADAVG"

    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["resources"]["load_average"]')" = "0.52, 0.58, 0.59" ]
}

@test "a malformed /proc/loadavg fixture degrades to unavailable rather than emitting garbage" {
    stub_shadow_path_except uptime
    export MAOPS_PROC_LOADAVG="$BATS_TEST_TMPDIR/loadavg"
    printf 'not-a-load-average\n' >"$MAOPS_PROC_LOADAVG"

    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["resources"]["load_average"]')" = "unavailable" ]
}

@test "a BusyBox-shaped free with no available column falls back to /proc/meminfo" {
    stub_shadow_path_except
    stub_fixed_output hostname <<'STUB'
printf 'report-test-host\n'
STUB
    stub_fixed_output uname <<'STUB'
case "$1" in
    -s) printf 'Linux\n' ;;
    -r) printf '6.18.0-test\n' ;;
    -m) printf 'x86_64\n' ;;
    *) printf 'Linux\n' ;;
esac
STUB
    stub_fixed_output getconf <<'STUB'
printf '4\n'
STUB
    stub_fixed_output uptime <<'STUB'
printf ' 12:00:00 up 1 day,  load average: 0.10, 0.05, 0.01\n'
STUB
    # BusyBox `free` (no -h flag support assumed, no "available" column):
    # Mem: total used free shared buffers cached -- column 7 is populated
    # (it's "cached", not empty), but it's a bare byte count with no unit
    # suffix, so it fails _REPORT_MEM_SIZE_SHAPE's mandatory Ki/Mi/Gi/Ti/Pi/B
    # requirement and correctly falls through to the /proc/meminfo fallback
    # below rather than being misread as a valid "available" figure.
    stub_fixed_output free <<'STUB'
printf '             total       used       free     shared    buffers     cached\n'
printf 'Mem:       16336864    4211200   12125664          0     102400    2048000\n'
STUB
    stub_fixed_output df <<'STUB'
printf 'Filesystem      Size  Used Avail Use%% Mounted on\n'
printf '/dev/sda1       100G   40G   55G  43%% /\n'
STUB

    export MAOPS_PROC_MEMINFO="$BATS_TEST_TMPDIR/meminfo"
    printf 'MemTotal:       16336864 kB\nMemAvailable:   14173664 kB\n' >"$MAOPS_PROC_MEMINFO"

    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["resources"]["memory_total"]')" = "15.6G" ]
    [ "$(json_field "$output" 'doc["resources"]["memory_available"]')" = "13.5G" ]
}

@test "malformed free output with no /proc/meminfo fixture degrades memory fields to unavailable" {
    stub_shadow_path_except
    stub_deterministic_system_facts
    stub_fixed_output free <<'STUB'
printf 'garbage output, not a memory table\n'
STUB
    export MAOPS_PROC_MEMINFO="$BATS_TEST_TMPDIR/no-such-meminfo"

    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["resources"]["memory_total"]')" = "unavailable" ]
    [ "$(json_field "$output" 'doc["resources"]["memory_available"]')" = "unavailable" ]
}

@test "a malformed df Use% column degrades rootfs fields to unavailable instead of a wrong value" {
    stub_shadow_path_except
    stub_deterministic_system_facts
    stub_fixed_output df <<'STUB'
printf 'Filesystem      Size  Used Avail Use%% Mounted on\n'
printf '/dev/sda1       100G   40G   55G  43 /\n'
STUB

    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["resources"]["root_filesystem_size"]')" = "unavailable" ]
    [ "$(json_field "$output" 'doc["resources"]["root_filesystem_used"]')" = "unavailable" ]
    [ "$(json_field "$output" 'doc["resources"]["root_filesystem_available"]')" = "unavailable" ]
    [ "$(json_field "$output" 'doc["resources"]["root_filesystem_usage_percent"]')" = "unavailable" ]
}

@test "JSON boolean configuration fields are real JSON booleans" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/no-such-config"
    run "$SCRIPT" summary --format json
    [[ "$output" == *'"exists":false'* ]]
    [[ "$output" != *'"exists":"false"'* ]]
}

# --- configuration section -----------------------------------------------

@test "config exists and valid are reflected when a valid config is present" {
    stub_shadow_path_except
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    "$REPO_ROOT/scripts/config/config-manager.sh" init

    run "$REAL_BASH" "$FIXTURE_SCRIPT" summary --format json
    [ "$status" -eq 0 ]
    [ "$(json_field "$output" 'doc["configuration"]["exists"]')" = "True" ]
    [ "$(json_field "$output" 'doc["configuration"]["valid"]')" = "True" ]
    [ "$(json_field "$output" 'doc["overall"]')" = "pass" ]
}

@test "an absent config file does not by itself fail the report" {
    stub_shadow_path_except
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/no-such-config"

    run "$REAL_BASH" "$FIXTURE_SCRIPT" summary --format json
    [ "$status" -eq 0 ]
    [ "$(json_field "$output" 'doc["configuration"]["exists"]')" = "False" ]
    [ "$(json_field "$output" 'doc["configuration"]["valid"]')" = "False" ]
    [ "$(json_field "$output" 'doc["overall"]')" = "pass" ]
}

@test "an invalid config file drives doctor.overall=fail and report overall=fail" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    printf 'bogus_key=1\n' >"$MAOPS_CONFIG_FILE"

    run "$SCRIPT" summary --format json
    [ "$status" -eq 1 ]
    [ "$(json_field "$output" 'doc["configuration"]["valid"]')" = "False" ]
    [ "$(json_field "$output" 'doc["doctor"]["overall"]')" = "fail" ]
    [ "$(json_field "$output" 'doc["overall"]')" = "fail" ]
}

# --- status aggregation --------------------------------------------------

@test "overall is pass and exit is 0 when doctor, integrity, and every field are healthy" {
    stub_shadow_path_except
    stub_deterministic_system_facts

    run "$REAL_BASH" "$FIXTURE_SCRIPT" summary --format json
    [ "$status" -eq 0 ]
    [ "$(json_field "$output" 'doc["doctor"]["overall"]')" = "pass" ]
    [ "$(json_field "$output" 'doc["integrity"]["overall"]')" = "pass" ]
    [ "$(json_field "$output" 'doc["overall"]')" = "pass" ]
}

@test "overall is warn and exit is 1 when only an optional field is unavailable" {
    stub_shadow_path_except hostname

    run "$REAL_BASH" "$FIXTURE_SCRIPT" summary --format json
    [ "$status" -eq 1 ]
    [ "$(json_field "$output" 'doc["system"]["hostname"]')" = "unavailable" ]
    [ "$(json_field "$output" 'doc["doctor"]["overall"]')" = "pass" ]
    [ "$(json_field "$output" 'doc["integrity"]["overall"]')" = "pass" ]
    [ "$(json_field "$output" 'doc["overall"]')" = "warn" ]
}

@test "overall is fail and exit is 1 when doctor fails (required command missing)" {
    stub_shadow_path_except ip
    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$status" -eq 1 ]
    [ "$(json_field "$output" 'doc["doctor"]["overall"]')" = "fail" ]
    [ "$(json_field "$output" 'doc["overall"]')" = "fail" ]
}

@test "overall is fail and exit is 1 when integrity fails (tampered tracked file)" {
    local fixture="$BATS_TEST_TMPDIR/tampered-fixture"
    cp -a "$BATS_FILE_TMPDIR/fixture" "$fixture"
    printf '\n# tampered\n' >>"$fixture/README.md"

    run "$fixture/scripts/reports/operational-report.sh" summary --format json
    [ "$status" -eq 1 ]
    [ "$(json_field "$output" 'doc["integrity"]["overall"]')" = "fail" ]
    [ "$(json_field "$output" 'doc["overall"]')" = "fail" ]
}

@test "the report is still fully emitted and remains valid JSON when overall is fail" {
    stub_shadow_path_except ip
    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$status" -eq 1 ]
    assert_valid_json "$output"
    [ -n "$(json_field "$output" 'doc["version"]')" ]
}

@test "required-section-uncollectable (date missing) drives overall=fail" {
    stub_shadow_path_except date
    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$status" -eq 1 ]
    assert_valid_json "$output"
    [ "$(json_field "$output" 'doc["generated_at_utc"]')" = "unavailable" ]
    [ "$(json_field "$output" 'doc["overall"]')" = "fail" ]
}

# --- redaction -------------------------------------------------------------

@test "--redact replaces hostname in text output" {
    stub_shadow_path_except
    stub_deterministic_system_facts

    run "$REAL_BASH" "$SCRIPT" summary --redact
    [[ "$output" == *"<redacted>"* ]]
    [[ "$output" != *"report-test-host"* ]]
}

@test "--redact replaces hostname and configuration.path in JSON output" {
    stub_shadow_path_except
    stub_deterministic_system_facts
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"

    run "$REAL_BASH" "$SCRIPT" summary --format json --redact
    [ "$(json_field "$output" 'doc["system"]["hostname"]')" = "<redacted>" ]
    [ "$(json_field "$output" 'doc["configuration"]["path"]')" = "<redacted>" ]
}

@test "a non-redacted run really does contain the real hostname (negative control)" {
    stub_shadow_path_except
    stub_deterministic_system_facts

    run "$REAL_BASH" "$SCRIPT" summary --format json
    [ "$(json_field "$output" 'doc["system"]["hostname"]')" = "report-test-host" ]
}

@test "regression guard: --redact output never leaks $HOME, REPO_ROOT, or an IP address" {
    # Only the $HOME assertion has current teeth (configuration.path embeds
    # $HOME when unredacted -- proven with real content by the dedicated
    # configuration.path test above). The report has no username or IP
    # field today, so those two assertions cannot currently fail regardless
    # of whether reporting_redact() does anything -- they exist as a
    # forward-looking trip-wire against a future field that *would*
    # introduce such a leak, not as proof of current redaction behavior.
    stub_shadow_path_except
    stub_deterministic_system_facts
    export MAOPS_CONFIG_FILE="$HOME/.config/maops/config"

    run "$REAL_BASH" "$SCRIPT" summary --format json --redact
    [[ "$output" != *"$HOME"* ]]
    [[ "$output" != *"$REPO_ROOT"* ]]
    ! grep -qE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' <<<"$output"
}

# --- report save -------------------------------------------------------

@test "report save writes a text report to the target file" {
    local target="$BATS_TEST_TMPDIR/report.txt"
    run "$SCRIPT" save --output "$target"
    [ -f "$target" ]
    grep -q "MAOps Operational Report" "$target"
}

@test "report save writes a valid JSON report to the target file" {
    local target="$BATS_TEST_TMPDIR/report.json"
    run "$SCRIPT" save --output "$target" --format json
    python3 -c "import json; json.load(open('$target'))"
}

@test "a saved report file has mode 0600" {
    local target="$BATS_TEST_TMPDIR/report.json"
    run "$SCRIPT" save --output "$target" --format json
    [ "$(stat -c '%a' "$target")" = "600" ]
}

@test "report save --force atomically replaces an existing file, leaving no stray temp files" {
    local target="$BATS_TEST_TMPDIR/report.json"
    printf 'old content\n' >"$target"

    run "$SCRIPT" save --output "$target" --format json --force
    [ "$(cat "$target")" != "old content" ]
    python3 -c "import json; json.load(open('$target'))"

    local leftovers
    leftovers="$(find "$BATS_TEST_TMPDIR" -maxdepth 1 -name '.maops-report.*')"
    [ -z "$leftovers" ]
}

@test "report save refuses to overwrite an existing file without --force" {
    local target="$BATS_TEST_TMPDIR/report.json"
    printf 'old content\n' >"$target"

    run "$SCRIPT" save --output "$target" --format json
    [ "$status" -eq 1 ]
    [ "$(cat "$target")" = "old content" ]
}

@test "report save refuses a symlink target without --force" {
    local real="$BATS_TEST_TMPDIR/real.json"
    local link="$BATS_TEST_TMPDIR/link.json"
    printf 'real content\n' >"$real"
    ln -s "$real" "$link"

    run "$SCRIPT" save --output "$link" --format json
    [ "$status" -eq 1 ]
    [ -L "$link" ]
    [ "$(cat "$real")" = "real content" ]
}

@test "report save refuses a symlink target even with --force" {
    local real="$BATS_TEST_TMPDIR/real2.json"
    local link="$BATS_TEST_TMPDIR/link2.json"
    printf 'real content\n' >"$real"
    ln -s "$real" "$link"

    run "$SCRIPT" save --output "$link" --format json --force
    [ "$status" -eq 1 ]
    [ -L "$link" ]
    [ "$(cat "$real")" = "real content" ]
}

@test "report save fails when the parent directory does not exist, without creating it" {
    local target="$BATS_TEST_TMPDIR/does-not-exist/report.json"
    run "$SCRIPT" save --output "$target" --format json
    [ "$status" -eq 1 ]
    [ ! -d "$BATS_TEST_TMPDIR/does-not-exist" ]
}

@test "report save rejects an existing directory as the target" {
    local target="$BATS_TEST_TMPDIR/adir"
    mkdir -p "$target"

    run "$SCRIPT" save --output "$target" --format json
    [ "$status" -eq 1 ]
    [ -z "$(find "$target" -mindepth 1)" ]
}

@test "report save leaves no temp file behind after a mktemp failure" {
    local dir="$BATS_TEST_TMPDIR/readonly-dir"
    mkdir -p "$dir"
    chmod 555 "$dir"

    run "$SCRIPT" save --output "$dir/report.json" --format json
    [ "$status" -eq 1 ]

    chmod 755 "$dir"
    local leftovers
    leftovers="$(find "$dir" -mindepth 1)"
    [ -z "$leftovers" ]
}

@test "report save cleans up the temp file after a chmod failure" {
    stub_bin_init
    stub_command chmod <<'STUB'
exit 1
STUB
    local target="$BATS_TEST_TMPDIR/chmod-fail-report.json"

    run "$SCRIPT" save --output "$target" --format json
    [ "$status" -eq 1 ]
    [ ! -e "$target" ]
    local leftovers
    leftovers="$(find "$BATS_TEST_TMPDIR" -maxdepth 1 -name '.maops-report.*')"
    [ -z "$leftovers" ]
}

@test "report save cleans up the temp file after an mv failure" {
    stub_bin_init
    stub_command mv <<'STUB'
exit 1
STUB
    local target="$BATS_TEST_TMPDIR/mv-fail-report.json"

    run "$SCRIPT" save --output "$target" --format json
    [ "$status" -eq 1 ]
    [ ! -e "$target" ]
    local leftovers
    leftovers="$(find "$BATS_TEST_TMPDIR" -maxdepth 1 -name '.maops-report.*')"
    [ -z "$leftovers" ]
}

@test "report save output path with shell metacharacters stays inert" {
    # The crafted filename component itself must contain no "/" -- a real
    # path separator embedded in a "fake command substitution" would change
    # dirname's parse of the path, which is a filesystem-parsing question,
    # not the command-injection question this test targets.
    local weird_dir="$BATS_TEST_TMPDIR/weird dir"
    mkdir -p "$weird_dir"
    local target="$weird_dir/a;b\$(touch pwned-marker).json"

    cd "$BATS_TEST_TMPDIR"
    run "$SCRIPT" save --output "$target" --format json
    [ ! -e "$BATS_TEST_TMPDIR/pwned-marker" ]
    [ -f "$target" ]
}

@test "report save output path containing a literal embedded newline stays inert" {
    # A newline embedded in --output's value is a legal (if unusual) filename
    # byte on Linux. This asserts it stays inert (no path-splitting, no
    # unintended second file, no command injection) rather than asserting it
    # is rejected -- the value flows through dirname/mktemp/mv entirely via
    # quoted expansion, so it should simply become part of a literal
    # filename.
    local weird_name=$'weird\nname.json'
    local target="$BATS_TEST_TMPDIR/$weird_name"

    run "$SCRIPT" save --output "$target" --format json
    [ -f "$target" ]
    # A NUL-delimited count, not a newline-delimited one: the target
    # filename itself contains a newline, so `find ... | wc -l` would
    # over-count a single real file as two lines.
    local file_count
    file_count="$(find "$BATS_TEST_TMPDIR" -mindepth 1 -maxdepth 1 -type f -print0 | grep -zc . || true)"
    [ "$file_count" -eq 1 ]
}

@test "report save without --output is a usage error (exit 2)" {
    run "$SCRIPT" save
    [ "$status" -eq 2 ]
}

@test "report save --output with no argument is a usage error" {
    run "$SCRIPT" save --output
    [ "$status" -eq 2 ]
}

@test "report save --output=PATH (combined-flag syntax) works" {
    local target="$BATS_TEST_TMPDIR/combined.json"
    run "$SCRIPT" save "--output=$target" --format json
    [ -f "$target" ]
}

@test "report save rejects an --output value that looks like a flag" {
    cd "$BATS_TEST_TMPDIR"
    run "$SCRIPT" save --output --force
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/--force" ]
}

@test "report save rejects an --output=VALUE that looks like a flag" {
    cd "$BATS_TEST_TMPDIR"
    run "$SCRIPT" save --output=-rf
    [ "$status" -eq 2 ]
    [ ! -e "$BATS_TEST_TMPDIR/-rf" ]
}

@test "report save --force on a target that does not yet exist is a normal save, not an error" {
    local target="$BATS_TEST_TMPDIR/report.json"
    run "$SCRIPT" save --output "$target" --format json --force
    [ -f "$target" ]
    python3 -c "import json; json.load(open('$target'))"
}

@test "report save rejects a FIFO target even with --force" {
    local target="$BATS_TEST_TMPDIR/report.fifo"
    mkfifo "$target"

    run "$SCRIPT" save --output "$target" --format json --force
    [ "$status" -eq 1 ]
    [ -p "$target" ]
}

@test "report save refuses a dangling symlink target" {
    local link="$BATS_TEST_TMPDIR/dangling-link.json"
    ln -s "$BATS_TEST_TMPDIR/nonexistent-target" "$link"

    run "$SCRIPT" save --output "$link" --format json --force
    [ "$status" -eq 1 ]
    [ -L "$link" ]
    [ ! -e "$BATS_TEST_TMPDIR/nonexistent-target" ]
}

@test "report save accepts a relative --output path" {
    cd "$BATS_TEST_TMPDIR"
    run "$SCRIPT" save --output "relative-report.json" --format json
    [ -f "$BATS_TEST_TMPDIR/relative-report.json" ]
}

@test "report save preserves the report's health-based exit code after a successful save" {
    stub_shadow_path_except ip
    local target="$BATS_TEST_TMPDIR/report.json"

    run "$REAL_BASH" "$SCRIPT" save --output "$target" --format json
    [ "$status" -eq 1 ]
    [ -f "$target" ]
    python3 -c "import json; json.load(open('$target'))"
}

# --- safety net ----------------------------------------------------------

@test "report summary never actually invokes ping" {
    stub_bin_init
    stub_command ping <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/ping.calls"
exit 0
STUB

    run "$SCRIPT" summary
    [ ! -f "$BATS_TEST_TMPDIR/ping.calls" ]
}

@test "report scripts contain no curl, wget, or raw socket invocation" {
    ! grep -qE '\bcurl\b|\bwget\b|/dev/tcp/' "$REPO_ROOT/scripts/reports/operational-report.sh" "$REPO_ROOT/scripts/common/reporting.sh"
}

@test "report summary never invokes systemctl with a mutating verb" {
    stub_bin_init
    stub_command systemctl <<'STUB'
printf '%s\n' "$*" >>"$BATS_TEST_TMPDIR/systemctl.calls"
exit 0
STUB

    run "$SCRIPT" summary
    if [ -f "$BATS_TEST_TMPDIR/systemctl.calls" ]; then
        ! grep -qE '\b(start|stop|restart|enable|disable|mask)\b' "$BATS_TEST_TMPDIR/systemctl.calls"
    fi
}

@test "report summary does not modify an existing config file" {
    export MAOPS_CONFIG_FILE="$BATS_TEST_TMPDIR/config"
    "$REPO_ROOT/scripts/config/config-manager.sh" init

    local before after
    before="$(stat -c '%Y %s' "$MAOPS_CONFIG_FILE")"
    run "$SCRIPT" summary
    after="$(stat -c '%Y %s' "$MAOPS_CONFIG_FILE")"

    [ "$before" = "$after" ]
}

@test "report summary never mutates the source tree it inspects" {
    local before after
    before="$(snapshot_tree "$REPO_ROOT/scripts")"
    run "$SCRIPT" summary --format json
    after="$(snapshot_tree "$REPO_ROOT/scripts")"

    [ "$before" = "$after" ]
}

@test "report save mutates only its target file, nothing else" {
    local outdir="$BATS_TEST_TMPDIR/outdir"
    mkdir -p "$outdir"

    local before after
    before="$(snapshot_tree "$REPO_ROOT/scripts")"
    run "$SCRIPT" save --output "$outdir/report.json" --format json
    after="$(snapshot_tree "$REPO_ROOT/scripts")"

    [ -f "$outdir/report.json" ]
    [ "$before" = "$after" ]
}
