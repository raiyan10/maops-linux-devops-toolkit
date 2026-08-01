# Contributing

Thank you for contributing to the MAOps Linux DevOps Toolkit.

## Development environment

The recommended environment is Ubuntu or Ubuntu under WSL2.

Required tools:

- Bash
- Git
- GNU coreutils
- ShellCheck
- Bats (bats-core) — required by `make test`/`make quality`
- Python 3 — used by the config/doctor Bats suites to validate JSON output
  (`python3 -m json.tool`); not a runtime dependency of the toolkit itself
- Make

`make quality` (syntax, ShellCheck, executable-mode, Bats) is the gate to
run before every push. `make package`, `make verify-package`, `make
smoke-install`, and `make integrity` are separate, filesystem-heavier
release checks — not required for every commit, but chained together as
`make release-check` and run in CI on every push and pull request. Run
`make release-check` locally before pushing anything that touches
`scripts/install/`, `scripts/release/`, `scripts/common/integrity.sh`,
`scripts/diagnostics/integrity-check.sh`, `scripts/common/reporting.sh`, or
`scripts/reports/`, to reproduce CI exactly. `make release-check` does not
clean `dist/` between runs (fast local iteration); use `make clean
release-check` when a fully fresh artifact directory is required.

## Pinned GitHub Actions

Every external action referenced from a workflow file
(`.github/workflows/*.yml`) must be pinned to a full 40-character commit SHA,
never a mutable tag or branch:

```yaml
# Correct
uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

# Wrong — a tag can be re-pointed to different code without this file changing
uses: actions/checkout@v4
```

A version comment after the SHA is expected, for human readability — it is
not what's trusted; the SHA is. Local, same-repository actions referenced
with a `./` prefix are exempt (there is no separate artifact to pin — the
checked-out commit already is the pin). `tests/workflows/actions-pinning.bats`
enforces this statically and will fail CI if a workflow file is ever edited
to reference an external action by tag instead of a SHA.

## Branch naming

Use one of these formats:

- `feature/<description>`
- `fix/<description>`
- `docs/<description>`
- `refactor/<description>`
- `chore/<description>`

Example:

```text
fix/largest-files-pipefail