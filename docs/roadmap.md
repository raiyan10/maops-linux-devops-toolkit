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

## Planned

- **Unified `maops` CLI** — not started; see
  [architecture.md §7](architecture.md#7-planned-unified-maops-cli) for the
  intended dispatch design
- **Network module** (`scripts/network/`) — network info, ping checker, port
  checker; directory does not exist yet
- **User and process module** (`scripts/users/`) — user report, last-login
  report; directory does not exist yet
- **Bats automated tests** for `scripts/common/*.sh` — zero test coverage
  today
- **Installation and packaging** — no installer or package target yet
- **Architecture diagrams** — visual complement to `docs/architecture.md`
- **Medium technical article**
- **Remaining template stubs** — `templates/readme-template.md`,
  `templates/skill-template.md`, and `templates/github-workflow-template.yml`
  are still empty placeholders; only `script-template.sh` is implemented
- **`require_command` adoption audit** — the guard exists in
  `scripts/common/helpers.sh` and is used by the filesystem module; extend
  its use to `system` and `monitoring` scripts for missing-dependency
  messages on `lscpu`/`free`/`uptime`/`hostname`
- **Decide on `LOG_DIRECTORY`/`DEFAULT_TIMEOUT`** in `scripts/common/config.sh`
  — currently defined but unused; either implement file-based logging and
  timeout enforcement, or remove the dead configuration
