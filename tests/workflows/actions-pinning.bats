#!/usr/bin/env bats
#
# Regression guard: every external GitHub Action referenced from a workflow
# file must be pinned to a full 40-character commit SHA, never a tag or
# branch. Local actions (a "uses:" value starting with "./") are exempt.
# Purely static -- greps workflow YAML, never runs a workflow.

setup() {
    load '../test-helper'
    WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
}

@test "at least one workflow file exists to check" {
    run bash -c "find '$WORKFLOWS_DIR' -type f \( -name '*.yml' -o -name '*.yaml' \)"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "every external action reference is pinned to a full commit SHA" {
    local unpinned=""
    local file line ref

    while IFS= read -r -d '' file; do
        while IFS= read -r line; do
            ref="$(printf '%s\n' "$line" | sed -E 's/^[[:space:]]*uses:[[:space:]]*//')"
            ref="${ref%%[[:space:]]#*}"
            ref="$(printf '%s' "$ref" | sed -E 's/[[:space:]]+$//')"

            [[ -z "$ref" ]] && continue
            [[ "$ref" == ./* ]] && continue

            if [[ ! "$ref" =~ @[0-9a-f]{40}$ ]]; then
                unpinned+="$file: $ref"$'\n'
            fi
        done < <(grep -E '^[[:space:]]*uses:[[:space:]]*' "$file")
    done < <(find "$WORKFLOWS_DIR" -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

    if [[ -n "$unpinned" ]]; then
        echo "Unpinned external action references found:"
        echo "$unpinned"
        return 1
    fi
    return 0
}

@test "the pinned checkout reference includes a version comment" {
    run grep -E 'uses:[[:space:]]*actions/checkout@[0-9a-f]{40}[[:space:]]*#' "$WORKFLOWS_DIR/bash-validation.yml"
    [ "$status" -eq 0 ]
}

@test "local (./) action references are exempt from SHA pinning" {
    run bash -c "printf 'uses: ./local-action\n' | grep -E '^uses:[[:space:]]*\./'"
    [ "$status" -eq 0 ]
}
