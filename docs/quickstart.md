# Quickstart

The fastest path from a fresh clone to a working, verified installation.
Every command below is copy/paste-ready and requires no `sudo` and no
network access beyond the initial `git clone`.

## 1. Run Directly From the Source Tree

No installation is required to try the toolkit — `bin/maops` works straight
out of a checkout:

```bash
git clone https://github.com/raiyan10/maops-linux-devops-toolkit.git
cd maops-linux-devops-toolkit

./bin/maops --version
./bin/maops --help
```

## 2. Install It User-Locally

```bash
make install
```

This runs `scripts/install/install.sh --prefix "$HOME/.local"` — no
`sudo`, no system-wide changes. It stages the runtime tree in a temporary
location first and only replaces anything once staging succeeds, so a
failed install never leaves a half-installed toolkit behind.

Confirm `$HOME/.local/bin` is on your `PATH`, then:

```bash
maops --version
```

To install to a custom location instead:

```bash
./scripts/install/install.sh --prefix /opt/maops
```

## 3. Initialize Configuration

```bash
maops config init
maops config path
maops config show
```

`config init` writes a default config file at
`${XDG_CONFIG_HOME:-$HOME/.config}/maops/config`. It is never required —
every setting has a built-in default — but it's the place to override
`output_format`, `process_limit`, `ping_count`, or `network_timeout`.

## 4. Run Doctor

```bash
maops doctor
maops doctor --format json
```

`doctor` checks that every command the toolkit depends on
(`awk`, `find`, `ps`, `ip`, `df`, `free`, `lscpu`, etc.) is actually present
and reports pass/fail per dependency. It never installs or repairs
anything — it's diagnostic only.

## 5. Run Integrity

```bash
maops integrity
maops integrity --format json
```

In a source-tree checkout, `integrity` compares your working tree against
Git's own tracked index — a modified or corrupted tracked file is reported
by path. In an installed tree, it compares against the manifest recorded at
install time. See [docs/install-from-release.md](install-from-release.md)
for the full integrity model.

## 6. Generate an Operational Report

```bash
maops report summary
```

This prints toolkit version, execution mode, system/resource facts,
configuration state, and the `doctor`/`integrity` verdicts in one
human-readable document.

## 7. Generate a JSON Report

```bash
maops report summary --format json | python3 -m json.tool
```

Every field name and shape is identical between the text and JSON forms —
JSON is meant for scripting, text for reading.

## 8. Generate a Redacted Report

```bash
maops report summary --format json --redact
```

`--redact` overwrites the hostname and configuration-path fields with
`<redacted>` before the report is ever rendered — useful when pasting a
report into a bug report or sharing it outside your own machine.

## 9. Save a Report to a File

```bash
maops report save --output /tmp/maops-report.json --format json --redact
stat -c '%a' /tmp/maops-report.json   # 600
```

`report save` writes atomically (temp file in the same directory, then a
same-filesystem rename) and always sets the file to mode `0600`,
independent of your shell's `umask`.

## 10. Uninstall

```bash
./scripts/install/uninstall.sh --yes
```

Add `--purge-config` if you also want the config directory removed. Your
config is never touched by a plain uninstall.

## What's Next

- [docs/demo-workflow.md](demo-workflow.md) — the same walkthrough, but
  fully sandboxed in a temporary `$HOME` for a safe, disposable demo.
- [docs/install-from-release.md](install-from-release.md) — installing
  from a downloaded release tarball instead of a Git checkout.
- [docs/compatibility.md](compatibility.md) — which environments are
  actually supported.
- [docs/architecture.md](architecture.md) — how the CLI, bootstrap, and
  common libraries fit together.
