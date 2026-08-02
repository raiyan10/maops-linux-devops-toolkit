# Portfolio Case Study: MAOps Linux DevOps Toolkit

An engineering-practice write-up of building a production-inspired Bash CLI
toolkit from scratch, over eight development days, to v1.0.0. This document
is based on the repository's actual history — commits, CHANGELOG entries,
test counts, and engineering-review documents — not aspirational claims.

## Problem Statement

Most "learn Bash scripting" projects stop at a handful of standalone
scripts. This project instead asks: what does it take to bring
*production-inspired engineering discipline* — modularity, input
validation, deterministic testing, supply-chain-aware packaging, CI
enforcement — to a Linux diagnostics/reporting toolkit, without ever
requiring `sudo`, a package manager, or a runtime language beyond Bash?

## Project Goals

- A single, consistent CLI (`maops <group> <command>`) instead of a folder
  of disconnected scripts.
- Every command safe to run unattended: read-only by default, `set -euo
  pipefail` everywhere, no destructive defaults.
- A real test suite, not spot-checks — deterministic, offline, no
  dependence on the state of the machine running it.
- A packaging and installation story with actual integrity guarantees
  (not just "download and run"), reachable without `sudo`.
- Documentation and CI treated as first-class engineering artifacts, not an
  afterthought bolted on at the end.

## Architecture

`bin/maops` is a thin dispatcher: it resolves its own symlink chain,
sources a fixed-order bootstrap (`colors.sh` → `config.sh` → `helpers.sh` →
`logger.sh` → `output.sh` → `cli.sh`), and `exec`s straight into the
matching leaf script under `scripts/`, so the leaf script's own exit code
becomes the CLI's exit code with no wrapper subshell in between. Every
leaf script shares the same common libraries rather than reimplementing
logging, argument validation, or JSON assembly independently. See
[architecture.md](architecture.md) for the full breakdown, including the
Day 8 runtime-architecture, distribution/integrity-chain, and
configuration-precedence diagrams.

## Security Model

- **Read-only by default.** Only four code paths intentionally mutate
  anything: `install.sh`/`uninstall.sh`, `config init`, and `report save`.
  Everything else only reads local system state.
- **No `eval`, no `jq`, no sourced configuration.** JSON is assembled by
  hand (`scripts/common/format.sh`) with proper escaping; config files are
  parsed line-by-line (`scripts/common/config-file.sh`), never `source`d,
  so a malicious config file can't execute arbitrary code.
- **Two-tier archive integrity**, not a single checksum: an external
  `.sha256` proves archive-level byte fidelity; `MAOPS-MANIFEST.tsv`
  independently proves per-file content and mode. Neither proves publisher
  identity — that boundary is documented explicitly, not glossed over (see
  [SECURITY.md](../SECURITY.md)).
- **Redaction by design**, not by accident: `report --redact` overwrites
  identifying fields (hostname, config path) before rendering, with a
  regression test asserting no `$HOME`/repo-path/IP leak survives it.

## Testing Strategy

478 deterministic Bats tests (`tests/`, one directory per `scripts/`
module) as of v1.0.0, all offline and none dependent on real system state:
PATH-based command stubs (`stub_command`, `stub_shadow_path_except`,
`stub_fixed_output`) make "missing dependency" and "specific field content"
scenarios reproducible on any machine, a WSL/drvfs permission-symptom
fixture (`build_drvfs_clone_fixture`) reproduces a real filesystem quirk
without needing an actual drvfs mount, and a Python-`tarfile`-based fixture
builder (`craft_tar_with_member`) constructs real malicious archives
(symlinks, hardlinks, devices, path traversal) to test the packaging
verifier against actual attack shapes rather than assertions about intent.

## CI/CD Workflow

A single GitHub Actions workflow (`Bash Validation`) runs on every push and
pull request to `main`: checkout (pinned to a full commit SHA, enforced by
its own regression test), install `shellcheck`/`bats`/`python3`, then `make
final-check` — syntax validation, ShellCheck, executable-mode enforcement,
the full Bats suite, package build, package verification, install/uninstall
smoke test, documentation validation, example validation, and a final
JSON-report/integrity sanity pass, all under a redirected temporary `$HOME`
so nothing touches the runner's real environment. `contents: read` is the
only permission granted — nothing in this pipeline can publish, tag, or
write back to the repository.

## Packaging and Release Strategy

Release contents are driven by one array (`RELEASE_FILE_LIST`) shared
between `install.sh` and `package.sh`, so the installed runtime tree and
the release tarball can never drift apart. Only Git-tracked files are ever
staged (`integrity_copy_git_tracked`), with every file's mode taken from
Git's index — never from the source filesystem's own `stat` (see below).
The archive is built reproducibly (`tar --sort=name --mtime=@0
--owner=0 --group=0 --numeric-owner`, `gzip -n`) so the same source tree
always produces byte-identical output.

## The WSL/drvfs Issue

The most consequential bug found during development wasn't in any
script's logic — it was an environment assumption. On a Windows filesystem
mounted into WSL as `/mnt/c/...` (`drvfs`), every file reports mode `0777`
to `stat`/`ls -l` regardless of what Git's index actually records. Early
packaging/install code used `cp -a`, which propagates whatever the *source
filesystem* reports — meaning a release built from a drvfs checkout could
silently ship world-writable files even though Git's own index correctly
recorded `100644`/`100755`.

The fix was structural, not a patch: packaging and installation now derive
every file's mode exclusively from `git ls-files -s` (never filesystem
`stat`), apply it with a plain `cp` plus an explicit `chmod`, and
immediately re-read the mode back to confirm it actually took — so a
destination filesystem that silently ignores `chmod` produces a loud build
failure instead of a package that only *looks* correct. The regression
test for this doesn't require an actual drvfs mount: `build_drvfs_clone_fixture`
reproduces the *observed symptom* (stat lies, Git index stays correct) on
any filesystem, including a plain CI runner, by copying the repo and
forcing every file to `0777` before running the same checks a real drvfs
checkout would face. See [best-practices.md §9](best-practices.md#9-git-executable-modes-under-wsl)
and [troubleshooting.md](troubleshooting.md) for the complete writeup.

## Major Engineering Lessons

- **Trust the index, not the filesystem**, whenever "what mode should this
  file have" matters for security — a lesson that generalizes well beyond
  WSL to any environment where `stat` and version control can legitimately
  disagree.
- **A test that requires a specific real environment to run is a test that
  won't run in CI.** Every environment-specific bug found here (drvfs
  permissions, BusyBox-shaped command output, missing optional commands)
  ended up as a synthetic fixture instead of a "works on my machine"
  assumption.
- **Diagnostic commands should report health, not silently coerce it.**
  `report`'s exit code reflects the actual pass/warn/fail verdict it found,
  not just "did the command run" — which took explicit design (and
  explicit documentation in troubleshooting.md) to keep from looking like a
  bug the first time someone saw a "successful" report exit non-zero.
- **A single source of truth beats keeping two things in sync by
  discipline.** `RELEASE_FILE_LIST`, `PROJECT_VERSION`, and the shared
  bootstrap load order all exist specifically to remove a category of "I
  forgot to update the other place" bug, rather than relying on a reviewer
  to catch it.

## Measurable Outcomes

As of the v1.0.0 release, drawn directly from repository state:

- 6 pre-1.0 releases (v0.1.0 → v0.6.0) plus this v1.0.0 stabilization
  release, per [CHANGELOG.md](../CHANGELOG.md).
- 478 deterministic Bats tests across 18 test files.
- 37 executable scripts under `scripts/`, unified behind one CLI entry
  point (`bin/maops`).
- A single GitHub Actions workflow gating every push/PR to `main`, with a
  pinned-SHA regression test guarding its own supply-chain hardening.
- Zero `sudo`, zero `eval`, zero `jq` runtime dependency, across the entire
  codebase.

These are the only outcomes this document claims. No production adoption,
user count, uptime, or performance figures are claimed anywhere in this
project, because none exist to measure — this is a portfolio and
engineering-practice project, not a deployed service.

## Command and Module Inventory

- **`system`** — info, os, hostname
- **`monitoring`** — memory, cpu, load
- **`filesystem`** — disk, largest, temp
- **`network`** — info, ping, dns, port
- **`user`** — report
- **`process`** — top
- **`service`** — status
- **`config`** — path, init, show, validate
- **`doctor`** — dependency/environment health check
- **`integrity`** — source-tree or installed-tree tamper detection
- **`report`** — summary, save (text/JSON, optional redaction)

Plus the release-engineering tooling that ships alongside but isn't part of
the CLI surface: `scripts/install/{install,uninstall}.sh`,
`scripts/release/{package,verify-package,validate-documentation}.sh`.

## Release Timeline

| Version | Date | Highlights |
|---|---|---|
| v0.1.0 | 2026-07-30 | Initial system/monitoring/filesystem scripts, common libraries |
| v0.2.0 | 2026-07-30 | Network diagnostics; command-injection hardening |
| v0.3.0 | 2026-07-31 | Unified `bin/maops` CLI dispatcher |
| v0.4.0 | 2026-07-31 | User/process/service inspection |
| v0.5.0 | 2026-08-01 | Persistent configuration, `doctor`, `integrity` |
| v0.6.0 | 2026-08-01 | Operational reporting, redaction, secure reports |
| v1.0.0 | 2026-08-02 | CLI consistency audit, resource-parser hardening, full v1 documentation set, examples, offline documentation validation, `final-check` release gate |

See [CHANGELOG.md](../CHANGELOG.md) for the complete, detailed history.
