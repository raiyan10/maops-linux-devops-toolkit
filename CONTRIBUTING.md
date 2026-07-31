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
run before every push. `make package`, `make verify-package`, and `make
smoke-install` are separate, release-time checks — not required for every
commit, but run in CI immediately after `make quality` on every push and
pull request.

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