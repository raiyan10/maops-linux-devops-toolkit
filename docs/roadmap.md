# Roadmap

Module-level detail behind the summary checklist in
[README.md](../README.md#roadmap). Updated after the Day 2 engineering
review (`docs/engineering-reviews/day-02.md`) closed out its Critical and
High findings.

## Completed

**Common library** (`scripts/common/`)
- Bootstrap loader with fixed, dependency-correct load order
- Colors, configuration, logging, and output libraries, each guarded against
  duplicate sourcing

**System module** (`scripts/system/`)
- System information, OS details, hostname report

**Monitoring module** (`scripts/monitoring/`)
- CPU, memory, and load-average reporting

**Filesystem module** (`scripts/filesystem/`)
- Disk usage, largest-files, dry-run temporary-file scanning

**CI and quality gates**
- Bash syntax validation (`bash -n`) in CI and `make validate`
- ShellCheck integration in CI and `make lint`
- Git executable-mode enforcement in CI and `make check-executable`
- Fixed: scripts were tracked as non-executable (`100644`); a WSL/Windows
  `drvfs` mount reports every file as executable locally regardless of the
  tracked git mode, which had masked this from previously passing on a
  native Linux checkout
- Fixed: `largest-files.sh` crashed with exit `141` (SIGPIPE under
  `pipefail`) on any directory with more files than its limit; row-limiting
  now happens in `awk` instead of terminating the pipeline with `head`
- `set -euo pipefail` made consistent across all filesystem-module scripts

**Governance and project files**
- `LICENSE` (MIT), `CHANGELOG.md`, `CONTRIBUTING.md`, and `Makefile`
  populated with real content (previously empty placeholders)

**Claude Code integration**
- `.claude/CLAUDE.md` project guidance
- Claude Code Skills: `bash-review`, `devops-review`, `documentation`,
  `github-actions`, `linux-best-practices`, `new-bash-tool`

**Templates**
- `templates/script-template.sh` — full boilerplate with `--help`/`--version`
  support, used by the `new-bash-tool` skill

**Documentation**
- `docs/architecture.md`, `docs/best-practices.md`, and
  `docs/troubleshooting.md` rewritten as substantive references (previously
  bullet-point stubs)
- `README.md` repository-structure and utilities sections reconciled with
  what is actually tracked in git
- Engineering review process established (`docs/engineering-reviews/`)

**Unified `maops` CLI** (`bin/maops`)
- Thin dispatcher over `system`, `monitoring`, `filesystem`, and `network`;
  see [architecture.md §7](architecture.md#7-unified-maops-cli) for the
  dispatch table and exit-code design
- Shared CLI support library `scripts/common/cli.sh` (version output,
  help/version flag recognition, usage-error handling, positive-integer and
  TCP-port validation)

**Network module** (`scripts/network/`)
- Network information, ping checker, DNS lookup, TCP port checker; see
  [architecture.md §8](architecture.md#8-network-module) for tool choices
- Fixed (Day 3 release-readiness review, before any tag was cut): a command
  injection in `port-check.sh` via an unvalidated `HOST` argument reaching a
  string-interpolated `bash -c` — see
  [architecture.md §8](architecture.md#8-network-module),
  [best-practices.md §11](best-practices.md#11-parameterized-bash--c-instead-of-string-interpolation),
  and [troubleshooting.md §12](troubleshooting.md#12-why-port-checksh-uses-bash--c-with-1-2-instead-of-host-directly)
- Fixed (same review): `ping-check.sh`/`port-check.sh` misreported a
  negative-number `COUNT`/`PORT`/`TIMEOUT` as an "unknown option" instead of
  the correct validation message; both exited `2` either way, but the
  message now matches the actual problem

**Bats automated tests** (`tests/`)
- Covers the CLI dispatcher, `scripts/common/cli.sh`'s validation helpers,
  and the network module's `--help` and invalid-input rejection paths; no
  test requires internet access
- `scripts/common/{colors,config,helpers,logger,output}.sh` and the
  `system`/`monitoring`/`filesystem` leaf scripts still have no dedicated
  Bats coverage — see Planned below

## Planned

- **User and process module** (`scripts/users/`) — user report, last-login
  report; directory does not exist yet
- **Installation and packaging** — no installer or package target yet
- **Architecture diagrams** — visual complement to `docs/architecture.md`
- **Medium technical article**
- **Remaining template stubs** — `templates/readme-template.md`,
  `templates/skill-template.md`, and `templates/github-workflow-template.yml`
  are still empty placeholders; only `script-template.sh` is implemented
- **`require_command` adoption audit** — the guard exists in
  `scripts/common/helpers.sh` and is used by the filesystem and network
  modules; extend its use to `system` and `monitoring` scripts for
  missing-dependency messages on `lscpu`/`free`/`uptime`/`hostname`
- **Decide on `LOG_DIRECTORY`** in `scripts/common/config.sh` — still defined
  but unused; either implement file-based logging or remove it.
  `DEFAULT_TIMEOUT` is no longer in this category — it is now consumed by
  `ping-check.sh` (per-packet wait) and `port-check.sh` (default connection
  timeout)
- **Bats coverage for `scripts/common/*.sh` core libraries and the
  `system`/`monitoring`/`filesystem` leaf scripts** — the Day 3 suite covers
  the CLI/network additions only
