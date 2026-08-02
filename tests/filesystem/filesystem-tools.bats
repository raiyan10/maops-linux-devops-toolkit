#!/usr/bin/env bats
#
# Tests for scripts/filesystem/disk-usage.sh, largest-files.sh, and
# cleanup-temp.sh. All destructive-looking operations target a throwaway
# directory under $BATS_TEST_TMPDIR; cleanup-temp.sh is dry-run only and
# never deletes anything regardless.

setup() {
    load '../test-helper'
    DISK_USAGE="$REPO_ROOT/scripts/filesystem/disk-usage.sh"
    LARGEST_FILES="$REPO_ROOT/scripts/filesystem/largest-files.sh"
    CLEANUP_TEMP="$REPO_ROOT/scripts/filesystem/cleanup-temp.sh"
}

# --- disk-usage.sh ---------------------------------------------------------

@test "disk-usage.sh exits 0 and excludes tmpfs" {
    run "$DISK_USAGE"
    [ "$status" -eq 0 ]
    [[ "$output" != *"  tmpfs  "* ]]
}

@test "disk-usage.sh fails cleanly when df is unavailable" {
    stub_shadow_path_except df
    run "$REAL_BASH" "$DISK_USAGE"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Required command not found: df"* ]]
}

@test "disk-usage.sh --help exits 0" {
    run "$DISK_USAGE" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "disk-usage.sh --version exits 0 and shows the current project version" {
    run "$DISK_USAGE" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

# --- largest-files.sh --------------------------------------------------

@test "largest-files.sh default TARGET/LIMIT works from a populated directory" {
    local dir="$BATS_TEST_TMPDIR/scan"
    mkdir -p "$dir"
    printf 'x' >"$dir/a.txt"

    run "$LARGEST_FILES" "$dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"a.txt"* ]]
}

@test "largest-files.sh ranks files by size, largest first, within LIMIT" {
    local dir="$BATS_TEST_TMPDIR/scan"
    mkdir -p "$dir"
    head -c 300 /dev/zero >"$dir/small.bin"
    head -c 900 /dev/zero >"$dir/big.bin"

    run "$LARGEST_FILES" "$dir" 5
    [ "$status" -eq 0 ]
    local big_line small_line
    big_line="$(grep -n 'big.bin' <<<"$output" | cut -d: -f1)"
    small_line="$(grep -n 'small.bin' <<<"$output" | cut -d: -f1)"
    [ -n "$big_line" ]
    [ -n "$small_line" ]
    [ "$big_line" -lt "$small_line" ]
}

@test "largest-files.sh rejects a non-numeric LIMIT with exit 1" {
    run "$LARGEST_FILES" "$BATS_TEST_TMPDIR" abc
    [ "$status" -eq 1 ]
}

@test "largest-files.sh rejects LIMIT=0" {
    run "$LARGEST_FILES" "$BATS_TEST_TMPDIR" 0
    [ "$status" -eq 1 ]
}

@test "largest-files.sh rejects a negative LIMIT" {
    run "$LARGEST_FILES" "$BATS_TEST_TMPDIR" -5
    [ "$status" -eq 1 ]
}

@test "largest-files.sh rejects a LIMIT with leading zeros" {
    run "$LARGEST_FILES" "$BATS_TEST_TMPDIR" 007
    [ "$status" -eq 1 ]
}

@test "largest-files.sh rejects a nonexistent TARGET directory" {
    run "$LARGEST_FILES" "$BATS_TEST_TMPDIR/does-not-exist" 5
    [ "$status" -eq 1 ]
    [[ "$output" == *"Directory not found"* ]]
}

@test "largest-files.sh does not SIGPIPE when the scanned tree has far more files than LIMIT" {
    local dir="$BATS_TEST_TMPDIR/many"
    mkdir -p "$dir"
    local i
    for i in $(seq 1 500); do
        printf 'x' >"$dir/f$i"
    done

    run "$LARGEST_FILES" "$dir" 1
    [ "$status" -eq 0 ]
    [ "$status" -ne 141 ]
}

@test "largest-files.sh shell metacharacters in TARGET are never executed" {
    local marker="$BATS_TEST_TMPDIR/marker"
    local evil="$BATS_TEST_TMPDIR/evil-\$(touch $marker)"

    run "$LARGEST_FILES" "$evil" 5
    [ ! -e "$marker" ]
}

@test "largest-files.sh --help exits 0" {
    run "$LARGEST_FILES" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "largest-files.sh --version exits 0 and shows the current project version" {
    run "$LARGEST_FILES" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

# --- cleanup-temp.sh --------------------------------------------------

@test "cleanup-temp.sh reports no results and stays a dry run on an empty directory" {
    local dir="$BATS_TEST_TMPDIR/empty"
    mkdir -p "$dir"

    run "$CLEANUP_TEMP" "$dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No accessible regular files found"* ]]
    [[ "$output" == *"Dry-run only. No files were removed."* ]]
}

@test "cleanup-temp.sh never deletes files regardless of output" {
    local dir="$BATS_TEST_TMPDIR/populated"
    mkdir -p "$dir"
    printf 'keep me\n' >"$dir/file.txt"

    run "$CLEANUP_TEMP" "$dir"
    [ "$status" -eq 0 ]
    [ -f "$dir/file.txt" ]
    [ "$(cat "$dir/file.txt")" = "keep me" ]
}

@test "cleanup-temp.sh tolerates an inaccessible subdirectory without failing" {
    local dir="$BATS_TEST_TMPDIR/withsub"
    mkdir -p "$dir/sub"
    chmod 000 "$dir/sub"

    run "$CLEANUP_TEMP" "$dir"
    local rc="$status"
    chmod 700 "$dir/sub"

    [ "$rc" -eq 0 ]
    [[ "$output" != *"Permission denied"* ]]
}

@test "cleanup-temp.sh prunes systemd-private-* directories" {
    local dir="$BATS_TEST_TMPDIR/prune1"
    mkdir -p "$dir/systemd-private-test"
    printf 'secret\n' >"$dir/systemd-private-test/secret.txt"

    run "$CLEANUP_TEMP" "$dir"
    [ "$status" -eq 0 ]
    [[ "$output" != *"secret.txt"* ]]
}

@test "cleanup-temp.sh prunes snap-private-tmp" {
    local dir="$BATS_TEST_TMPDIR/prune2"
    mkdir -p "$dir/snap-private-tmp"
    printf 'secret\n' >"$dir/snap-private-tmp/secret.txt"

    run "$CLEANUP_TEMP" "$dir"
    [ "$status" -eq 0 ]
    [[ "$output" != *"secret.txt"* ]]
}

@test "cleanup-temp.sh rejects a non-numeric LIMIT with exit 1" {
    run "$CLEANUP_TEMP" "$BATS_TEST_TMPDIR" abc
    [ "$status" -eq 1 ]
}

@test "cleanup-temp.sh rejects a nonexistent TARGET" {
    run "$CLEANUP_TEMP" "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Directory not found"* ]]
}

@test "cleanup-temp.sh shell metacharacters in TARGET are never executed" {
    local marker="$BATS_TEST_TMPDIR/marker-cleanup"
    local evil="$BATS_TEST_TMPDIR/evil2-\$(touch $marker)"

    run "$CLEANUP_TEMP" "$evil"
    [ ! -e "$marker" ]
}

@test "cleanup-temp.sh --help exits 0" {
    run "$CLEANUP_TEMP" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "cleanup-temp.sh --version exits 0 and shows the current project version" {
    run "$CLEANUP_TEMP" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}
