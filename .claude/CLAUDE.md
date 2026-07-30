# Linux DevOps Toolkit

## Purpose

Build reusable Linux automation tools following production-inspired engineering practices.

## Standards

- Bash best practices
- Reusable functions
- Comprehensive documentation
- Modular design
- Safe scripting
- Logging
- Error handling
- Testing

## Review Checklist

Before completing a script:

- Is it modular?
- Is it reusable?
- Does it validate inputs?
- Does it fail safely?
- Is documentation updated?

## Code Standards

- Use `#!/usr/bin/env bash`.
- Enable `set -euo pipefail` in executable scripts.
- Use the common bootstrap library.
- Avoid duplicated logic.
- Prefer small, reusable functions.
- Keep functions focused and generally below 25 lines.
- Quote variable expansions unless intentional word splitting is required.
- Validate all user-supplied paths and arguments.
- Use safe defaults for potentially destructive operations.
- Never hardcode credentials or secrets.
- Ensure all Bash files pass `bash -n` and ShellCheck.
- Update documentation when behavior or architecture changes.
- Do not modify unrelated files.
- Explain important architectural and security decisions.