# Changelog

All notable changes to the MAOps Linux DevOps Toolkit are documented here.

The project follows Semantic Versioning.

## [0.4.0] - 2026-07-31

### Added

- **Safe runtime installation** (`scripts/install/install.sh`, `scripts/install/uninstall.sh`): a user-local installer that never requires `sudo` and never installs system-wide by default. Installs to `${PREFIX:-$HOME/.local}` as `PREFIX/bin/maops` (a relative symlink to `../lib/maops/bin/maops`) plus a `PREFIX/lib/maops/` runtime tree. The runtime tree is built in a `mktemp -d` staging directory under `PREFIX/lib` (same filesystem as the final destination, so the swap into place is a same-filesystem rename rather than a cross-device copy) before anything is replaced, and an `.install-manifest` records every installed path so `uninstall.sh` can remove exactly what it owns and nothing else. Install refuses unconditionally — with no `--force` override — to replace an unrelated regular file found at `PREFIX/bin/maops`; `--force` only ever permits reinstalling over a *verified* prior MAOps install (a manifest whose recorded prefix matches). Uninstall requires either an interactive confirmation or `--yes`, preserves the user's configuration directory by default, supports `--purge-config` to remove it explicitly, and is idempotent (a second run against an already-removed install exits 0 with no side effects). Every mutating operation (`mkdir`, `mv`, `ln`, `rm`) is argument-quoted with a `--` end-of-options marker, so a `--prefix` value containing spaces or shell metacharacters is always treated as inert text, never re-parsed as shell syntax — no `eval`, no `bash -c` with an interpolated path, anywhere in either script.
- `bin/maops` now resolves its own location through symlinks: the previous `SCRIPT_DIR` derivation followed `${BASH_SOURCE[0]}`'s directory directly, which resolves to the *symlink's* directory rather than its target once installed — a bounded manual `readlink` loop (capped to guard against a cycle, with no dependency on `readlink -f`/`realpath`) fixes this, so an installed launcher works correctly from any working directory.
- **Configuration system** (`scripts/common/config-file.sh`, `scripts/config/config-manager.sh`): a plain-text config file at `${MAOPS_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/maops/config}` supporting four keys — `output_format` (`text`/`json`), `process_limit`, `ping_count`, `network_timeout` (all positive integers). The file is parsed line-by-line via a `read -r` loop and is never sourced or evaluated as Bash, so a value containing command substitution or shell metacharacters is always inert text and simply fails validation rather than executing. Unknown keys, duplicate keys, and malformed lines are all rejected. Precedence for every value is explicit CLI argument, then a `MAOPS_*` environment variable, then the config file, then a built-in default — implemented once as `config_resolve_value` and reused by `config show`, `doctor`, and the three leaf scripts below, so the precedence logic can never drift between call sites. New CLI routes: `maops config path`, `config init [--force]` (parent directories created safely, written under `umask 077` via a same-directory temp file plus atomic rename, refusing to overwrite an existing file without `--force`), `config show [--format text|json]`, and `config validate [PATH]` (exit 0 valid, exit 1 invalid). `process-monitor.sh`'s default `LIMIT`, `ping-check.sh`'s default `COUNT`, and `port-check.sh`'s default `TIMEOUT` now resolve through this precedence chain instead of a hardcoded constant, while an explicit positional argument continues to override everything.
- **Structured JSON output** (`scripts/common/format.sh`): dependency-free JSON string escaping (backslashes, double quotes, tabs, carriage returns, newlines) and flat-object assembly, with no `eval` and no runtime `jq` dependency. Scoped to exactly two commands in this release — `maops config show --format json` and `maops doctor --format json` — each emitting exactly one JSON document with no log output before or after it; existing human-readable output is unchanged.
- **Doctor command** (`scripts/diagnostics/doctor.sh`, `maops doctor [--format text|json]`): reports toolkit version, source-tree-vs-installed execution mode, operating system, Bash version, the resolved config path/existence/validity, and the presence of every required runtime command (`bash awk find sort ps getent ip ping timeout df free lscpu uptime`, plus a `systemctl`-or-`service` either/or check mirroring `service-status.sh`'s own systemd-vs-fallback detection) alongside optional development tools (`git make shellcheck bats python3`). Returns exit 1 only when a required check fails; a missing config file is a warning (normal for a fresh install), and missing optional dev tools are always warnings, never failures. Every check is a `command -v`, version-string, or local file read — doctor never makes a network request and never modifies the system.
- **Packaging** (`scripts/release/package.sh`, `scripts/release/verify-package.sh`): produces `dist/maops-linux-devops-toolkit-0.4.0.tar.gz` and its `.sha256` checksum from a staged copy of exactly the git-tracked files named in the new shared list `scripts/common/release-files.sh` (`bin/maops`, `scripts/`, `templates/script-template.sh`, `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, `Makefile`, `.gitattributes`) — the same list `install.sh` copies from, so the installed tree and the released tarball can never drift apart. Directory entries are expanded via `git ls-files` so a stray untracked temp or editor file is never silently packaged. The tarball is built with `tar --sort=name --mtime --owner=0 --group=0 --numeric-owner` and piped through `gzip -n`, so repeated builds from an unchanged tree are byte-for-byte identical. `verify-package.sh` checks the SHA-256 checksum first, then inspects every archive member name for an absolute path, a `..` path segment, or a name outside the single expected `maops-linux-devops-toolkit-0.4.0/` top-level directory — all before any extraction happens — and only then extracts to a scratch directory to confirm a fixed set of required paths exist.
- New Makefile targets: `config-init`, `doctor`, `install`, `uninstall`, `package`, `verify-package`, `smoke-install` (installs to a temporary prefix, runs the installed CLI and `doctor`, uninstalls, and verifies cleanup), with `PREFIX` defaulting to `$(HOME)/.local`.
- New `maops` CLI routes: `maops config path|init [--force]|show [--format text|json]|validate [PATH]` and `maops doctor [--format text|json]`.
- Bats coverage: `tests/config/config-manager.bats`, `tests/diagnostics/doctor.bats`, `tests/install/install.bats`, `tests/release/package.bats`, plus new dispatch-route tests in `tests/cli/maops.bats` — covering precedence resolution, injection-safety (a config value containing command substitution or shell metacharacters is proven to never execute, not merely to be rejected), the install/uninstall safety guarantees above, and archive integrity.

### Changed

- `scripts/common/config.sh`: `PROJECT_VERSION` bumped to `0.4.0`.
- `tests/cli/maops.bats`: version-string assertions read the project version dynamically instead of a hardcoded literal, so future version bumps no longer require editing this file.

## [0.3.0] - 2026-07-31

### Added

- User module (`scripts/users/user-report.sh`): read-only account report via `getent passwd`, `id -gn`/`id -nG`, and `who` — username, UID, primary GID, home directory, login shell, group memberships, and whether the target user currently has a logged-in session. USERNAME is optional and defaults to the current effective user (`id -un`). The passwd password field is read and immediately discarded; the script never calls `getent shadow` and never reads `/etc/shadow`, so no password hash is ever handled, let alone printed.
- Process module (`scripts/process/process-monitor.sh`): read-only top-N process report via `ps -eo pid,user,pcpu,pmem,etime,comm`, sorted by CPU (default) or memory. `comm` (executable name) is used instead of `args` (full command line) so secrets sometimes passed on a command line, such as `--password=...`, are never exposed. Row truncation happens in `awk`, not by piping into `head`, for the same reason `largest-files.sh` was fixed in 0.1.0 — `head` closing its read end early sends the producer a `SIGPIPE`, turning the pipeline's exit status into 141 under `pipefail`.
- Service module (`scripts/service/service-status.sh`): read-only service state inspection. Prefers `systemctl show --property=LoadState,ActiveState,SubState` when systemd is genuinely the running init system (detected via `/run/systemd/system`, the same probe systemd's own `sd_booted(3)` uses — more reliable than checking whether the `systemctl` binary merely exists, which is misleading in containers/WSL where the binary is present but systemd is not PID 1), and falls back to `service SERVICE status` (interpreted via LSB init-script exit codes: 0 running, 3 stopped, 4 unknown) otherwise. `systemctl show` is used instead of `systemctl is-active` because `show` exits 0 in every normal case including "unit not found," so any non-zero exit unambiguously means `systemctl` itself failed (bus error, permission issue) and is surfaced as a failure rather than silently mapped to "inactive." A new environment variable, `MAOPS_SYSTEMD_RUNTIME_DIR` (default `/run/systemd/system`), is a documented, read-only test seam that lets tests select either branch deterministically; it cannot cause a mutation, and the script never runs `start`, `stop`, `restart`, `reload`, `enable`, `disable`, `eval`, or a re-parsed shell string.
- Three new `maops` CLI routes: `maops user report [USERNAME]`, `maops process top [LIMIT] [cpu|memory]`, `maops service status SERVICE`, each wired into `bin/maops` with its own `dispatch_*` function following the existing group-dispatch pattern.
- Shared CLI validators in `scripts/common/cli.sh`: `is_non_option_argument`/`validate_non_option_argument` (rejects an empty value or one starting with `-`; used by USERNAME and SERVICE) and `is_one_of`/`validate_one_of` (generic allow-listed-value validator in the same family as `is_positive_integer`/`is_valid_port`; used today by process-monitor's `cpu|memory` SORT argument).
- A deterministic PATH-based command-stub convention for tests (`stub_bin_init`/`stub_command` in `tests/test-helper.bash`): a test-scoped stub directory generated fresh into `$BATS_TEST_TMPDIR` and prepended to `$PATH`, used to fake `getent`, `id`, `who`, `ps`, `systemctl`, and `service` so results never depend on the host's real accounts, process list, logged-in sessions, or init system.
- Bats coverage: `tests/users/user-report.bats`, `tests/process/process-monitor.bats`, `tests/service/service-status.bats`, plus new dispatch-route tests in `tests/cli/maops.bats` and validator tests in `tests/common/helpers.bats` — including command-injection and option-injection regression tests for USERNAME, SERVICE, and LIMIT.

### Changed

- `bin/maops`: `usage()` now lists the `user`, `process`, and `service` groups and includes them in the unknown-group error message.
- `scripts/common/config.sh`: `PROJECT_VERSION` bumped to `0.3.0`.
- `tests/cli/maops.bats`: the two version-string assertions updated from `0.2.0` to `0.3.0`.

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