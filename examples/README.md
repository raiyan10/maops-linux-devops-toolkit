# Examples

Standalone, safe-to-run examples that demonstrate how to use the MAOps
Linux DevOps Toolkit's supported configuration and automation surface.
These are illustrative, not part of the CLI itself — nothing under
`examples/` is invoked by `bin/maops`.

## `config/maops.conf`

An example configuration file containing only supported keys
(`output_format`, `process_limit`, `ping_count`, `network_timeout`), with
comments explaining precedence (CLI argument > `MAOPS_*` environment
variable > config file > built-in default). Validate it directly:

```bash
maops config validate examples/config/maops.conf
```

To actually use it, copy it to your real config path (or start from
`maops config init` and edit from there):

```bash
cp examples/config/maops.conf "$(maops config path)"
```

## `automation/health-report.sh`

A standalone example script showing how external automation (a cron job,
a CI health check, a monitoring hook) can call `maops` to generate and save
a redacted JSON operational report. It resolves the `maops` executable via
`PATH` or the `MAOPS_BIN` environment variable — it does not assume it's
running from inside this repository.

```bash
# Using an installed maops on PATH:
./examples/automation/health-report.sh /var/tmp/maops-reports

# Or against a source-tree checkout:
MAOPS_BIN=./bin/maops ./examples/automation/health-report.sh
```

It requires no `sudo`, makes no network requests, never mutates a service
or process, and exits with the underlying report's own health verdict (`0`
for a healthy report, `1` otherwise) so it can be used directly as a
monitoring check's exit condition.
