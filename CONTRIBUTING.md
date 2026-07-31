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
- Make

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