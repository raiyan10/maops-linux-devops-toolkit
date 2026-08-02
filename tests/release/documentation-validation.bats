#!/usr/bin/env bats
#
# Tests for scripts/release/validate-documentation.sh. Runs entirely
# offline against real repository files plus, where a negative case is
# needed, a scratch copy of the repo so a deliberately broken doc never
# touches the real checkout.

setup() {
    load '../test-helper'
    VALIDATE="$REPO_ROOT/scripts/release/validate-documentation.sh"
}

@test "validate-documentation.sh --help exits 0" {
    run "$VALIDATE" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "validate-documentation.sh --version exits 0 and shows the current project version" {
    run "$VALIDATE" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$PROJECT_VERSION"* ]]
}

@test "validate-documentation.sh rejects an unknown option with exit 2" {
    run "$VALIDATE" --bogus
    [ "$status" -eq 2 ]
}

@test "validate-documentation.sh passes against the real repository once the current version is reflected" {
    # The real checkout's README.md is only guaranteed to mention whatever
    # PROJECT_VERSION currently is once Day 8's version bump has landed; run
    # this against a scratch copy with a forced-consistent version stamp so
    # the test doesn't depend on exactly when in the Day 8 sequence it runs.
    local scratch="$BATS_TEST_TMPDIR/consistent"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"

    sed -i "s/PROJECT_VERSION=\"[^\"]*\"/PROJECT_VERSION=\"9.9.9\"/" "$scratch/scripts/common/config.sh"
    printf '# MAOps Linux DevOps Toolkit\n\nversion 9.9.9\n' >"$scratch/README.md"
    sed -i "1i## [9.9.9] - 2026-01-01\n" "$scratch/CHANGELOG.md"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"passed"* ]]
}

@test "validate-documentation.sh fails when a required root document is missing" {
    local scratch="$BATS_TEST_TMPDIR/missing-root-doc"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    rm -f "$scratch/SUPPORT.md"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"SUPPORT.md"* ]]
}

@test "validate-documentation.sh fails when a required Day 8 user doc is missing" {
    local scratch="$BATS_TEST_TMPDIR/missing-day8-doc"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    rm -f "$scratch/docs/quickstart.md"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docs/quickstart.md"* ]]
}

@test "validate-documentation.sh detects a broken local link in README.md" {
    local scratch="$BATS_TEST_TMPDIR/broken-link"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    printf '\n[broken](docs/does-not-exist.md)\n' >>"$scratch/README.md"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docs/does-not-exist.md"* ]]
}

@test "validate-documentation.sh detects a broken local link outside README (selected-docs sweep)" {
    local scratch="$BATS_TEST_TMPDIR/broken-link-selected-doc"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    printf '\n[broken](docs/does-not-exist-either.md)\n' >>"$scratch/docs/architecture.md"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docs/does-not-exist-either.md"* ]]
    [[ "$output" == *"docs/architecture.md"* ]]
}

@test "validate-documentation.sh does not reject external (http/https) or anchor-only links" {
    local scratch="$BATS_TEST_TMPDIR/external-links"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    printf '\n[ext](https://example.com/nonexistent)\n[anchor](#some-heading)\n' >>"$scratch/README.md"

    run "$scratch/scripts/release/validate-documentation.sh"
    [[ "$output" != *"example.com"* ]]
    [[ "$output" != *"#some-heading"* ]]
}

@test "validate-documentation.sh detects a referenced screenshot that does not exist" {
    local scratch="$BATS_TEST_TMPDIR/missing-screenshot"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    printf '\n![missing](docs/images/day-99/does-not-exist.png)\n' >>"$scratch/README.md"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"day-99/does-not-exist.png"* ]]
}

@test "validate-documentation.sh rejects a stale CHANGELOG top entry" {
    local scratch="$BATS_TEST_TMPDIR/stale-changelog"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"

    sed -i "s/PROJECT_VERSION=\"[^\"]*\"/PROJECT_VERSION=\"9.9.9\"/" "$scratch/scripts/common/config.sh"
    printf '# MAOps Linux DevOps Toolkit\n\nversion 9.9.9\n' >"$scratch/README.md"
    # CHANGELOG.md is left with its real (non-9.9.9) top entry.

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CHANGELOG.md"* ]]
}

@test "validate-documentation.sh fails when README omits the current version even though CHANGELOG is current" {
    # Isolates the README-version check's fail path from the
    # CHANGELOG-version check -- both are exercised together by every other
    # version-consistency test above, so neither one's independent failure
    # branch is otherwise proven.
    local scratch="$BATS_TEST_TMPDIR/readme-only-stale"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"

    sed -i "s/PROJECT_VERSION=\"[^\"]*\"/PROJECT_VERSION=\"9.9.9\"/" "$scratch/scripts/common/config.sh"
    sed -i "1i## [9.9.9] - 2026-01-01\n" "$scratch/CHANGELOG.md"
    # README.md is left completely unmodified (no "9.9.9" anywhere in it).

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"README.md"*"does not mention the current version"* ]]
    [[ "$output" == *"9.9.9"* ]]
}

@test "validate-documentation.sh fails when CHANGELOG.md has no version-header entry at all" {
    local scratch="$BATS_TEST_TMPDIR/no-changelog-header"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    printf 'This changelog has no version headers.\n' >"$scratch/CHANGELOG.md"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no version-header entry at all"* ]]
}

@test "validate-documentation.sh fails on a real ShellCheck violation even though bash -n passes" {
    command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"

    local scratch="$BATS_TEST_TMPDIR/shellcheck-violation"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    # Syntactically valid (bash -n passes) but trips SC2086 (unquoted
    # expansion) -- a real ShellCheck finding, not a syntax error.
    printf '#!/usr/bin/env bash\nset -euo pipefail\nTARGET_DIR=$1\nrm -rf $TARGET_DIR\n' >"$scratch/examples/automation/health-report.sh"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"fails ShellCheck"* ]]
}

@test "validate-documentation.sh does not falsely reject historical version references in CHANGELOG.md" {
    # The real CHANGELOG.md legitimately contains every past version
    # (0.1.0 through the current one). This must never be treated as a
    # "placeholder" or "inconsistent version" failure on its own.
    run "$VALIDATE"
    [[ "$output" != *"0.1.0"* ]]
    [[ "$output" != *"0.2.0"* ]]
}

@test "validate-documentation.sh detects a placeholder marker in a release-facing document" {
    local scratch="$BATS_TEST_TMPDIR/placeholder"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    printf '\nTODO: finish this section\n' >>"$scratch/SUPPORT.md"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"TODO"* ]]
    [[ "$output" == *"SUPPORT.md"* ]]
}

@test "validate-documentation.sh does not flag a benign 'XXXXXX' mktemp template as a placeholder" {
    # troubleshooting.md and best-practices.md legitimately contain
    # ".maops-report.XXXXXX"-style mktemp templates; the placeholder-marker
    # list must not include a generic token that would false-positive here.
    run "$VALIDATE"
    [[ "$output" != *"XXXXXX"* ]]
}

@test "validate-documentation.sh fails when the example config is invalid" {
    local scratch="$BATS_TEST_TMPDIR/bad-example-config"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    printf 'not_a_supported_key=1\n' >"$scratch/examples/config/maops.conf"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"maops.conf"* ]]
}

@test "validate-documentation.sh fails when the example script has a syntax error" {
    local scratch="$BATS_TEST_TMPDIR/bad-example-script"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    printf '#!/usr/bin/env bash\nif [[ true \n' >"$scratch/examples/automation/health-report.sh"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"health-report.sh"* ]]
}

@test "validate-documentation.sh fails when a required Day 8 doc is missing from RELEASE_FILE_LIST" {
    local scratch="$BATS_TEST_TMPDIR/missing-from-list"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    sed -i '/"docs\/quickstart.md"/d' "$scratch/scripts/common/release-files.sh"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docs/quickstart.md"*"RELEASE_FILE_LIST"* ]]
}

@test "validate-documentation.sh fails when RELEASE_FILE_LIST contains a developer-only path" {
    local scratch="$BATS_TEST_TMPDIR/leaked-devonly"
    cp -a "$REPO_ROOT" "$scratch"
    rm -rf "$scratch/dist"
    sed -i 's/"examples"/"examples"\n    "docs\/engineering-reviews"/' "$scratch/scripts/common/release-files.sh"

    run "$scratch/scripts/release/validate-documentation.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"docs/engineering-reviews"* ]]
}

@test "validate-documentation.sh makes no network requests and contains no curl/wget/raw-socket usage" {
    ! grep -qE '\bcurl\b|\bwget\b|/dev/tcp/' "$VALIDATE"
}

@test "validate-documentation.sh source contains no sudo or eval" {
    ! grep -qE '\bsudo\b|\beval\b' "$VALIDATE"
}
