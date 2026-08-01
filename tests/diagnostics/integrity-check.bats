#!/usr/bin/env bats
#
# Tests for scripts/diagnostics/integrity-check.sh (maops integrity).
# Installed-mode fixtures are built via a real install.sh run against a
# throwaway PREFIX (mirroring tests/install/install.bats), then tampered
# with for the negative cases. Source-tree fixtures use
# build_drvfs_clone_fixture to prove drvfs-observed 0777 permissions never
# affect the result. "Missing git" scenarios use stub_shadow_path_except
# and REAL_BASH, exactly like doctor.bats.

setup() {
    load '../test-helper'
    SCRIPT="$REPO_ROOT/scripts/diagnostics/integrity-check.sh"
    INSTALL="$REPO_ROOT/scripts/install/install.sh"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    unset XDG_CONFIG_HOME MAOPS_CONFIG_FILE
}

# --- CLI surface ---------------------------------------------------------

@test "integrity-check.sh --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "integrity-check.sh --version exits 0 and shows the current project version" {
    run "$SCRIPT" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "integrity-check.sh rejects an unknown option with exit 2" {
    run "$SCRIPT" --bogus
    [ "$status" -eq 2 ]
}

@test "integrity-check.sh rejects an invalid --format value with exit 2" {
    run "$SCRIPT" --format xml
    [ "$status" -eq 2 ]
}

@test "integrity-check.sh --format text output is identical to the no-flag default" {
    # Strips the leading "[YYYY-MM-DD HH:MM:SS]" timestamp from the final
    # log line before comparing: on this host a script invocation can take
    # long enough that two consecutive runs cross a one-second boundary,
    # which would otherwise make this comparison flaky through no fault of
    # the script itself.
    run "$SCRIPT"
    local default_output
    default_output="$(sed -E 's/^\[[0-9-]+ [0-9:]+\]//' <<<"$output")"

    run "$SCRIPT" --format text
    local this_output
    this_output="$(sed -E 's/^\[[0-9-]+ [0-9:]+\]//' <<<"$output")"

    [ "$this_output" = "$default_output" ]
}

# --- source-tree mode ------------------------------------------------------

@test "healthy source tree passes with exit 0, even when observed permissions are 0777" {
    build_drvfs_clone_fixture "$BATS_TEST_TMPDIR/fixture"
    (cd "$BATS_TEST_TMPDIR/fixture" && git add -A)

    run "$BATS_TEST_TMPDIR/fixture/scripts/diagnostics/integrity-check.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Execution mode"*"source-tree"* ]]
    [[ "$output" == *"Failed"*"0"* ]]
}

@test "source-tree mode exits 1 when Git is unavailable" {
    stub_shadow_path_except git
    run "$REAL_BASH" "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "exits 1 when run from a directory with neither an installed manifest nor Git metadata" {
    local scratch="$BATS_TEST_TMPDIR/no-git-no-manifest"
    mkdir -p "$scratch"
    cp -a "$REPO_ROOT/scripts" "$scratch/"
    cp -a "$REPO_ROOT/bin" "$scratch/"

    run "$scratch/scripts/diagnostics/integrity-check.sh"
    [ "$status" -eq 1 ]
}

@test "source-tree mode reports a modified tracked release file" {
    build_drvfs_clone_fixture "$BATS_TEST_TMPDIR/fixture"
    (cd "$BATS_TEST_TMPDIR/fixture" && git add -A)
    printf '\n# tampered\n' >>"$BATS_TEST_TMPDIR/fixture/README.md"

    run "$BATS_TEST_TMPDIR/fixture/scripts/diagnostics/integrity-check.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified"*"README.md"* ]]
}

@test "source-tree mode reports a missing tracked release file" {
    build_drvfs_clone_fixture "$BATS_TEST_TMPDIR/fixture"
    (cd "$BATS_TEST_TMPDIR/fixture" && git add -A)
    rm -f "$BATS_TEST_TMPDIR/fixture/LICENSE"

    run "$BATS_TEST_TMPDIR/fixture/scripts/diagnostics/integrity-check.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"*"LICENSE"* ]]
}

# --- installed mode: healthy -------------------------------------------

@test "healthy installed tree passes with exit 0" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null

    run "$prefix/bin/maops" integrity
    [ "$status" -eq 0 ]
    [[ "$output" == *"Execution mode"*"installed"* ]]
    [[ "$output" == *"Manifest path"*".integrity-manifest"* ]]
}

@test "installed mode reports a missing installed file" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null
    rm -f "$prefix/lib/maops/LICENSE"

    run "$prefix/bin/maops" integrity
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing"*"LICENSE"* ]]
}

@test "installed mode reports a modified installed file and never repairs it" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null
    printf 'TAMPERED\n' >>"$prefix/lib/maops/README.md"
    local before after
    before="$(cat "$prefix/lib/maops/README.md")"

    run "$prefix/bin/maops" integrity
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified"*"README.md"* ]]

    after="$(cat "$prefix/lib/maops/README.md")"
    [ "$before" = "$after" ]
}

@test "installed mode reports a mode mismatch for an installed file" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null
    chmod 600 "$prefix/lib/maops/README.md"

    run "$prefix/bin/maops" integrity
    [ "$status" -eq 1 ]
    [[ "$output" == *"unexpected-mode"*"README.md"* ]]
}

@test "installed mode reports a malformed manifest without crashing" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null
    printf '%s\n' "${MALFORMED_MANIFEST_LINES[0]}" >"$prefix/lib/maops/.integrity-manifest"

    run "$prefix/bin/maops" integrity
    [ "$status" -eq 1 ]
    [[ "$output" == *"malformed-manifest"* ]]
}

@test "installed mode refuses a manifest path with .. traversal" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null
    printf '0644\t0000000000000000000000000000000000000000000000000000000000000000\t../../../etc/passwd\n' \
        >"$prefix/lib/maops/.integrity-manifest"

    run "$prefix/bin/maops" integrity
    [ "$status" -eq 1 ]
    [[ "$output" == *"malformed-manifest"* ]]
    [[ "$output" != *"root:"* ]]
}

@test "installed mode refuses an absolute manifest path" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null
    printf '0644\t0000000000000000000000000000000000000000000000000000000000000000\t/etc/passwd\n' \
        >"$prefix/lib/maops/.integrity-manifest"

    run "$prefix/bin/maops" integrity
    [ "$status" -eq 1 ]
    [[ "$output" == *"malformed-manifest"* ]]
}

@test "installed mode flags an invalid checksum format distinctly from a wrong-but-valid-format checksum" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null

    # Malformed: non-hex checksum -> the whole manifest is malformed.
    printf '0644\tnotahash\tREADME.md\n' >"$prefix/lib/maops/.integrity-manifest"
    run "$prefix/bin/maops" integrity
    [ "$status" -eq 1 ]
    [[ "$output" == *"malformed-manifest"* ]]

    # Well-formed but incorrect: valid-looking 64-hex checksum that simply
    # does not match README.md's real content -> a per-file "modified"
    # failure, not a manifest-parse failure.
    printf '0644\t0000000000000000000000000000000000000000000000000000000000000000\tREADME.md\n' \
        >"$prefix/lib/maops/.integrity-manifest"
    run "$prefix/bin/maops" integrity
    [ "$status" -eq 1 ]
    [[ "$output" == *"modified"*"README.md"* ]]
    [[ "$output" != *"malformed-manifest"* ]]
}

@test "installed mode: shell metacharacters in a manifest path remain inert" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null
    local marker="$BATS_TEST_TMPDIR/marker"
    printf '0644\t0000000000000000000000000000000000000000000000000000000000000000\t$(touch %s)\n' "$marker" \
        >"$prefix/lib/maops/.integrity-manifest"

    run "$prefix/bin/maops" integrity
    [ "$status" -eq 1 ]
    [ ! -e "$marker" ]
}

@test "installed mode never mutates the installed tree during a passing run" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null

    local before after
    before="$(snapshot_tree "$prefix/lib/maops")"
    run "$prefix/bin/maops" integrity
    after="$(snapshot_tree "$prefix/lib/maops")"

    [ "$status" -eq 0 ]
    [ "$before" = "$after" ]
}

@test "installed mode never mutates the installed tree during a failing run" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null
    chmod 600 "$prefix/lib/maops/README.md"

    local before after
    before="$(snapshot_tree "$prefix/lib/maops")"
    run "$prefix/bin/maops" integrity
    after="$(snapshot_tree "$prefix/lib/maops")"

    [ "$status" -eq 1 ]
    [ "$before" = "$after" ]
}

# --- output format -----------------------------------------------------

@test "--format json emits exactly one valid JSON document on the healthy path" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null

    run "$prefix/bin/maops" integrity --format json
    [ "$status" -eq 0 ]
    assert_valid_json "$output"
    [ "$(json_field "$output" 'doc["overall"]')" = "pass" ]
    [ "$(json_field "$output" 'doc["failed_count"]')" = "0" ]
}

@test "--format json remains valid JSON on a failing run and includes the failure detail" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null
    rm -f "$prefix/lib/maops/LICENSE"

    run "$prefix/bin/maops" integrity --format json
    [ "$status" -eq 1 ]
    assert_valid_json "$output"
    [ "$(json_field "$output" 'doc["overall"]')" = "fail" ]
    [ "$(json_field "$output" 'len(doc["failures"])')" = "$(json_field "$output" 'doc["failed_count"]')" ]
}

@test "JSON document includes version, execution_mode, and manifest_path in installed mode" {
    local prefix="$BATS_TEST_TMPDIR/prefix"
    "$INSTALL" --prefix "$prefix" >/dev/null

    run "$prefix/bin/maops" integrity --format json
    [ "$(json_field "$output" 'doc["version"]')" = "$PROJECT_VERSION" ]
    [ "$(json_field "$output" 'doc["execution_mode"]')" = "installed" ]
    [[ "$(json_field "$output" 'doc["manifest_path"]')" == *".integrity-manifest" ]]
}

@test "JSON document includes repository_root in source-tree mode" {
    run "$SCRIPT" --format json
    [ "$(json_field "$output" 'doc["execution_mode"]')" = "source-tree" ]
    [ "$(json_field "$output" 'doc["repository_root"]')" = "$REPO_ROOT" ]
}
