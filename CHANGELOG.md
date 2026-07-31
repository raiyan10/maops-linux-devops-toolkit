# Changelog

All notable changes to the MAOps Linux DevOps Toolkit are documented here.

The project follows Semantic Versioning.

## [0.2.0] - 2026-07-30

### Added

- Unified `maops` CLI (`bin/maops`) dispatching to the existing system, monitoring, and filesystem utilities, plus a new network module
- Shared CLI support library (`scripts/common/cli.sh`): version output, help/version flag recognition, usage-error handling, positive-integer validation, TCP port validation
- Network module (`scripts/network/`): network information, ping checker, DNS lookup, TCP port checker
- Bats test suite (`tests/`) covering the CLI dispatcher, shared CLI validation helpers, and network utilities
- `make test` runs the Bats suite; `make cli-help` runs `bin/maops --help`

### Changed

- `Makefile`: `quality` now includes the Bats test suite; `validate`/`lint`/`check-executable` cover `bin/` in addition to `scripts/` and `templates/`; `run` now invokes `bin/maops system info`
- `.github/workflows/bash-validation.yml`: installs Bats alongside ShellCheck and runs `make quality` instead of duplicating each check inline
- `scripts/common/config.sh`: `PROJECT_VERSION` bumped to `0.2.0`

### Fixed

- **Security:** `scripts/network/port-check.sh` built its TCP-connect check as `bash -c "exec 3<>/dev/tcp/$HOST/$PORT"`, interpolating the unvalidated `HOST` argument directly into a string re-parsed as shell code by the inner `bash` — any shell metacharacter in `HOST` executed as an arbitrary command. Fixed by passing `HOST`/`PORT` as the inner `bash -c`'s own positional parameters (`bash -c 'exec 3<>"/dev/tcp/$1/$2"' bash "$HOST" "$PORT"`) instead of string interpolation, so `HOST`'s content is only ever substituted as a value, never re-parsed as command syntax. Found and fixed as part of the Day 3 release-readiness review before any tag was cut; `ping-check.sh` and `dns-lookup.sh` were checked and were never vulnerable to this class of bug, since both pass `HOST`/`TARGET` as a normal argument to `ping`/`getent` rather than through a re-parsed shell string.
- `ping-check.sh`/`port-check.sh`: a negative numeric argument (e.g. `-1` for `COUNT`, `PORT`, or `TIMEOUT`) was previously caught by the generic unknown-flag branch and reported as `Unknown option: -1`, even though the exit code (`2`) was already correct. Both scripts now recognize a leading-dash argument that looks like a negative number and route it to the existing positive-integer/port validators, which report it with a specific, accurate message (e.g. `COUNT must be a positive integer: -1`).
- `CONTRIBUTING.md`: added Bats to the "Required tools" list — `make test`/`make quality` have required it since this release, but the list was never updated.

## [0.1.0] - 2026-07-30

### Added

- Reusable Bash bootstrap framework
- Centralized color, configuration, logging, helper, and output libraries
- System information utilities
- Operating-system details utility
- Hostname reporting utility
- CPU, memory, and load-average monitoring utilities
- Disk-usage reporting utility
- Largest-files reporting utility
- Safe temporary-file dry-run scanner
- Reusable Bash script template
- ShellCheck and Bash syntax validation
- GitHub Actions Bash validation workflow
- Claude Code project guidance
- Project-specific Claude Code Skills
- Initial engineering documentation and review process

### Fixed

- Duplicate sourcing of readonly color variables
- `largest-files.sh` SIGPIPE failure under `pipefail`
- Empty temporary-file output
- Missing strict Bash mode in filesystem utilities
- Git executable modes for shell files