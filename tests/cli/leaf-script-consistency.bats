#!/usr/bin/env bats
#
# Day 8 final CLI-consistency audit: a fixed, explicit roster of the leaf
# scripts that had zero -h/--help/-v/--version handling before this audit
# (scripts/system/*, scripts/monitoring/*, scripts/filesystem/{disk-usage,
# largest-files,cleanup-temp}.sh). Deliberately a fixed array, not a `find`
# sweep -- a sweep would silently start covering future scripts with a
# different intentional contract; this test's job is to prove the audit's
# fix for *these specific* scripts, once, durably.
#
# Individual --help/--version/usage-error assertions for each script also
# live alongside that script's other tests (tests/system/system-tools.bats,
# tests/monitoring/monitoring-tools.bats, tests/filesystem/filesystem-tools.bats)
# -- this file is the consolidated audit artifact, not a replacement for
# those.

setup() {
    load '../test-helper'
}

REMEDIATED_SCRIPTS=(
    "scripts/system/system-info.sh"
    "scripts/system/os-details.sh"
    "scripts/system/hostname-report.sh"
    "scripts/monitoring/cpu-monitor.sh"
    "scripts/monitoring/load-average.sh"
    "scripts/monitoring/memory-report.sh"
    "scripts/filesystem/disk-usage.sh"
    "scripts/filesystem/largest-files.sh"
    "scripts/filesystem/cleanup-temp.sh"
)

@test "every Day 8 remediated leaf script supports -h and --help (exit 0)" {
    local rel script
    for rel in "${REMEDIATED_SCRIPTS[@]}"; do
        script="$REPO_ROOT/$rel"
        run "$script" -h
        [ "$status" -eq 0 ] || {
            echo "FAILED: $rel -h -> exit $status" >&2
            return 1
        }
        [[ "$output" == *"Usage:"* ]] || {
            echo "FAILED: $rel -h did not print Usage:" >&2
            return 1
        }

        run "$script" --help
        [ "$status" -eq 0 ] || {
            echo "FAILED: $rel --help -> exit $status" >&2
            return 1
        }
        [[ "$output" == *"Usage:"* ]] || {
            echo "FAILED: $rel --help did not print Usage:" >&2
            return 1
        }
    done
}

@test "every Day 8 remediated leaf script supports -v and --version (exit 0, shows PROJECT_VERSION)" {
    local rel script
    for rel in "${REMEDIATED_SCRIPTS[@]}"; do
        script="$REPO_ROOT/$rel"
        run "$script" -v
        [ "$status" -eq 0 ] || {
            echo "FAILED: $rel -v -> exit $status" >&2
            return 1
        }
        [[ "$output" == *"$PROJECT_VERSION"* ]] || {
            echo "FAILED: $rel -v did not contain PROJECT_VERSION" >&2
            return 1
        }

        run "$script" --version
        [ "$status" -eq 0 ] || {
            echo "FAILED: $rel --version -> exit $status" >&2
            return 1
        }
        [[ "$output" == *"$PROJECT_VERSION"* ]] || {
            echo "FAILED: $rel --version did not contain PROJECT_VERSION" >&2
            return 1
        }
    done
}

@test "the three no-positional-argument system scripts reject an unknown flag with exit 2" {
    local rel
    for rel in "scripts/system/system-info.sh" "scripts/system/os-details.sh" "scripts/system/hostname-report.sh"; do
        run "$REPO_ROOT/$rel" --bogus
        [ "$status" -eq 2 ] || {
            echo "FAILED: $rel --bogus -> exit $status (expected 2)" >&2
            return 1
        }
    done
}

@test "the three no-positional-argument monitoring scripts reject an unknown flag with exit 2" {
    local rel
    for rel in "scripts/monitoring/cpu-monitor.sh" "scripts/monitoring/load-average.sh" "scripts/monitoring/memory-report.sh"; do
        run "$REPO_ROOT/$rel" --bogus
        [ "$status" -eq 2 ] || {
            echo "FAILED: $rel --bogus -> exit $status (expected 2)" >&2
            return 1
        }
    done
}

@test "disk-usage.sh rejects an unknown flag with exit 2" {
    run "$REPO_ROOT/scripts/filesystem/disk-usage.sh" --bogus
    [ "$status" -eq 2 ]
}

@test "largest-files.sh and cleanup-temp.sh still validate positional TARGET/LIMIT with exit 1, unaffected by the flag audit" {
    run "$REPO_ROOT/scripts/filesystem/largest-files.sh" "$BATS_TEST_TMPDIR/does-not-exist" 5
    [ "$status" -eq 1 ]

    run "$REPO_ROOT/scripts/filesystem/cleanup-temp.sh" "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -eq 1 ]
}

# --- Edge-case argument shapes, exercising the new parse_args/case blocks
# themselves rather than just the documented happy path -----------------

@test "the seven no-positional-argument remediated scripts reject an empty-string argument with exit 2" {
    local rel
    for rel in "scripts/system/system-info.sh" "scripts/system/os-details.sh" "scripts/system/hostname-report.sh" \
        "scripts/monitoring/cpu-monitor.sh" "scripts/monitoring/load-average.sh" "scripts/monitoring/memory-report.sh" \
        "scripts/filesystem/disk-usage.sh"; do
        run "$REPO_ROOT/$rel" ""
        [ "$status" -eq 2 ] || {
            echo "FAILED: $rel '' -> exit $status (expected 2)" >&2
            return 1
        }
    done
}

@test "the seven no-positional-argument remediated scripts reject a bare -- with exit 2" {
    local rel
    for rel in "scripts/system/system-info.sh" "scripts/system/os-details.sh" "scripts/system/hostname-report.sh" \
        "scripts/monitoring/cpu-monitor.sh" "scripts/monitoring/load-average.sh" "scripts/monitoring/memory-report.sh" \
        "scripts/filesystem/disk-usage.sh"; do
        run "$REPO_ROOT/$rel" --
        [ "$status" -eq 2 ] || {
            echo "FAILED: $rel -- -> exit $status (expected 2)" >&2
            return 1
        }
    done
}
