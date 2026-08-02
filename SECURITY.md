# Security Policy

MAOps Linux DevOps Toolkit is a solo-maintained, portfolio-grade engineering
project. This document explains what security support looks like for it,
how to report a suspected vulnerability, and — most importantly — exactly
what the toolkit's integrity verification does and does not prove.

## Supported Versions

There is no long-term-support branch and no backport policy. Only the
**latest tagged release** (starting at `v1.0.0`) is supported with fixes.
See [CHANGELOG.md](CHANGELOG.md) for the full release history. If you are
running an older release, upgrading to the latest tag is the only supported
path to a fix.

## Reporting a Suspected Vulnerability

Please report suspected vulnerabilities privately rather than in a public
issue, using one of GitHub's repository-native mechanisms:

- This repository's **Security** tab, if private vulnerability reporting is
  enabled for it, or
- A GitHub Issue, if the report does not need to stay private (for example,
  a hardening suggestion rather than an actively exploitable flaw).

There is no separate email address or contact channel for this project
beyond what GitHub itself provides — please don't look for one.

When reporting, please include:

- Steps to reproduce.
- The output of `maops --version` and `maops doctor --format json`.
- `uname -a` for the environment where the issue was observed.

**Do not post secrets, tokens, private system report output, or exploit
details in a public issue.** If your report or its reproduction steps would
expose any of these, use the private reporting mechanism above and redact
before posting anywhere public.

## Scope

MAOps is a **read-only diagnostic and reporting toolkit**. The only code
paths that intentionally mutate anything are:

- `scripts/install/install.sh` / `scripts/install/uninstall.sh` (installing
  or removing the toolkit itself),
- `maops config init` (writing a config file),
- `maops report save` (writing a report file the caller explicitly asked
  for, atomically and at mode `0600`).

Every other command — `system`, `monitoring`, `filesystem`, `network`,
`user`, `process`, `service`, `doctor`, `integrity`, `report summary` —
only reads local system state and never makes a network request. Reports of
issues within this scope (command injection, path traversal, unsafe
temp-file handling, privilege-related bugs in the four mutating paths
above) are the most actionable and welcome.

Out of scope: vulnerabilities in the underlying OS, kernel, shell, or any
third-party command the toolkit invokes (e.g. `free`, `df`, `systemctl`) —
please report those to their own maintainers.

## Integrity vs. Publisher Authenticity

This is the single most important distinction to understand before trusting
a downloaded release:

- **SHA-256 checksum** (the `.sha256` file next to each release tarball)
  proves the archive you downloaded is byte-for-byte the archive that was
  produced by whoever ran `package.sh`.
- **`MAOPS-MANIFEST.tsv`** (shipped inside the archive) proves that every
  individual distributed file, once you trust the archive itself, still has
  its expected content and mode — an independent, second check beyond the
  single whole-archive checksum.
- **Neither one proves who published the archive.** A party who can replace
  both the archive and its `.sha256` sidecar can produce a pair that is
  internally self-consistent and passes every check above. There is
  currently **no cryptographic publisher-identity signing** (no GPG, no
  Sigstore) anywhere in this project's release process — see
  [docs/roadmap.md](docs/roadmap.md) for this being an explicit, deliberate
  post-v1.0 scope boundary, not an oversight.

In short: integrity verification tells you the archive wasn't corrupted or
tampered with in transit relative to what you were told to trust — it does
not, on its own, tell you that the source you trusted was the real
maintainer.

## Responsible Disclosure

Please give a reasonable window to investigate and fix a genuinely
exploitable issue before any public disclosure, and avoid actions beyond
what's needed to demonstrate the vulnerability (no data destruction, no
testing against systems you don't own).

There is no bug bounty or paid disclosure program for this project.

## No Service-Level Agreement

This is a solo/portfolio project. There is no guaranteed response time for
security reports, issues, or pull requests. Reports will be reviewed on a
best-effort basis.
