# Support

This document explains what kind of help is available for MAOps Linux
DevOps Toolkit, what environments are actually supported, and what to
include in a bug report.

## Supported Use Cases

- Local, single-host Linux diagnostics and reporting on systems you own or
  administer (system/network/user/process/service inspection, `doctor`,
  `integrity`, `report`).
- Read-only operational visibility — ad hoc use, scripted use in your own
  automation, or as a reference implementation for similar tooling.
- Installing/upgrading/uninstalling the toolkit itself on a single machine.

## Unsupported Use Cases

- Production monitoring or alerting at scale, or as a component of an
  incident-response pipeline. MAOps has no daemon mode, no alerting, and no
  fleet-management features.
- Any workload requiring a guaranteed uptime or response-time commitment.
  This is a portfolio/engineering-demonstration project, not a maintained
  production dependency.
- Automated system repair. `doctor`, `integrity`, and `report` are
  diagnostic-only by design — none of them fix anything they find wrong.

## Supported and Tested Environments

Actively validated, with direct CI/development evidence:

- **Ubuntu, `ubuntu-latest`** — exercised on every push/PR via GitHub
  Actions (`.github/workflows/bash-validation.yml`).
- **WSL2 Ubuntu** — the author's development environment; several
  WSL/drvfs-specific findings are documented in
  [docs/troubleshooting.md](docs/troubleshooting.md) and
  [docs/compatibility.md](docs/compatibility.md).

## Best-Effort Environments

Other Debian/Ubuntu-family systemd Linux distributions (Debian, Pop!_OS,
Linux Mint, etc.) share the same GNU coreutils/procps/systemd assumptions
as Ubuntu and are likely to work, but are never CI- or dev-exercised —
issues here are welcome but may take longer to diagnose without a reporter
able to reproduce and test a fix.

See [docs/compatibility.md](docs/compatibility.md) for the full breakdown,
including explicitly unsupported environments (Alpine/BusyBox/musl,
macOS/BSD).

## Filing an Issue

Please include:

1. `maops --version`
2. `maops doctor --format json`
3. `maops integrity --format json`
4. `maops report summary --redact` (the `--redact` flag strips hostname and
   config-path before you paste it anywhere)
5. `uname -a`
6. The exact command you ran and its full output.

Reports without at least the diagnostic commands above will likely get a
request to re-file with them, since most environment-shaped issues are
otherwise unreproducible.

## No SLA

There is no guaranteed response time for issues or pull requests. This is a
solo-maintained project reviewed on a best-effort basis.

## Version-Support Policy

Only the latest tagged release is supported. There is no backport policy
and no long-term-support branch. See [SECURITY.md](SECURITY.md) for the
same policy as it applies to security fixes specifically, and
[CHANGELOG.md](CHANGELOG.md) for the release history.

## Upgrade Expectations

`scripts/install/install.sh --force` performs an in-place upgrade: the new
version is staged in a temporary directory and atomically swapped in, with
the previous installation removed only after the new one is confirmed live.
Your configuration file (`${XDG_CONFIG_HOME:-$HOME/.config}/maops/config`)
lives entirely outside the install prefix and is never touched by install
or uninstall unless you explicitly pass `--purge-config` to
`uninstall.sh`. See [docs/install-from-release.md](docs/install-from-release.md)
for the full upgrade walkthrough.
