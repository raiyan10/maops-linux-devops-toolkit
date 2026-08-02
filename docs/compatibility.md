# Compatibility

What this toolkit actually assumes about its environment, and what
evidence backs each claim below. This document distinguishes what is
*actively validated* from what is merely *expected* — do not read "expected
but not continuously validated" as a promise.

## Actively Validated Environments

These are exercised by CI or daily development, with direct evidence:

- **Ubuntu, `ubuntu-latest`** — every push and pull request to `main` runs
  `make final-check` on GitHub Actions' `ubuntu-latest` runner
  (`.github/workflows/bash-validation.yml`).
- **WSL2 Ubuntu** — the author's development environment. Several
  WSL/drvfs-specific findings (permission-bit misreporting on the drvfs
  filesystem, in particular) are documented in
  [troubleshooting.md](troubleshooting.md) and
  [best-practices.md](best-practices.md) §9, and are accounted for in the
  packaging/integrity code (Git-index-derived file modes, never raw
  filesystem `stat`).

## Expected but Not Continuously Validated

Other Debian/Ubuntu-family systemd Linux distributions (Debian, Pop!_OS,
Linux Mint, and similar) share the same GNU coreutils, procps, util-linux,
and systemd assumptions as Ubuntu and are expected to work, but are never
exercised by CI or routine development. Issues here are welcome but may
take longer to diagnose.

## Unsupported Environments

- **Alpine / BusyBox / musl-based Linux.** The toolkit's resource-report
  collectors (`scripts/common/reporting.sh`) primarily parse `free -h` and
  `uptime`'s free-text output, which assumes GNU coreutils/procps column
  layouts and phrasing. BusyBox's `free`/`uptime` implementations use
  different, incompatible layouts. As of v1.0.0, these fields validate
  their parsed shape and fall back to `/proc/loadavg`/`/proc/meminfo`
  (kernel-ABI, not implementation-dependent) when the primary command's
  output doesn't match the expected shape — this materially improves
  resilience, but has only been exercised against synthetic BusyBox-shaped
  *test fixtures*, never a real BusyBox host. Do not read this as a claim
  of tested Alpine/BusyBox support. `doctor.sh`'s required-command roster
  also includes `lscpu` (util-linux) and `getent` (glibc-shaped), neither
  guaranteed present on a musl/BusyBox system.
- **macOS / BSD.** Most modules call `require_linux` (checks `uname -s
  == Linux`) and refuse to run at all. Never tested, not a goal.

## Bash Version

**Bash ≥ 4 is required.** This is both explicitly checked
(`scripts/diagnostics/doctor.sh` tests `BASH_VERSINFO[0] >= 4` as part of
`doctor`) and structurally required: `scripts/common/config-file.sh`,
`scripts/common/integrity.sh`, `scripts/install/uninstall.sh`, and
`scripts/release/verify-package.sh` all use associative arrays
(`declare -A`/`local -A`), a Bash-4 feature. Ubuntu and WSL2 Ubuntu ship
Bash ≥ 5 by default, well above this floor.

## GNU Coreutils / procps Assumptions

The toolkit assumes GNU-flavored `awk`, `find`, `df`, `free`, `uptime`,
`sort`, and util-linux's `lscpu` — not POSIX-minimal or BusyBox
equivalents. Where this matters most:

- `scripts/common/reporting.sh` parses `free -h`'s column-7 "available"
  field and `df -hP`'s POSIX-mode single-line output — see "Unsupported
  Environments" above for how this degrades on non-GNU systems as of
  v1.0.0.
- `doctor.sh`'s required-command roster
  (`awk find sort ps getent ip ping timeout df free lscpu uptime`) assumes
  every one of these is the GNU/procps/util-linux/iproute2 build, not a
  BusyBox applet.

## systemd / Service Fallback

`scripts/service/service-status.sh` genuinely detects whether systemd is
PID 1 by checking for `/run/systemd/system` (the same probe glibc's
`sd_booted(3)` uses) rather than merely trusting `command -v systemctl`,
which can be present but non-functional (e.g. inside some containers). When
systemd is not running, it falls back to the LSB-style `service(8)` command
and interprets its exit code per the LSB init-script convention. This is a
genuine, tested fallback path — not a gap — and is what makes `maops
service status` usable inside most containers and minimal chroots as well
as a full systemd host.

## WSL2 Considerations

WSL2's `drvfs`-backed filesystem (used when the repository lives under
`/mnt/c/...` or similar) reports mode `0777` for every file via `stat`,
regardless of Git's actual tracked index mode. The toolkit's packaging and
integrity code never trusts filesystem `stat` for mode information — every
distributed file's mode comes from Git's index (`git ls-files -s`) instead,
which is unaffected by this drvfs quirk. See
[troubleshooting.md](troubleshooting.md) and
[best-practices.md](best-practices.md) §9 for the full history of this
finding. Running the repository from WSL2's native ext4 filesystem (e.g.
under `/home/...` inside the WSL2 VM, not `/mnt/c/...`) avoids the quirk
entirely and is the author's actual daily setup.

## Python 3: Dev/Release Tooling Only, Not a Runtime Dependency

**Ordinary `maops` commands never require `python3`.** The only place
`python3` is invoked is `scripts/release/verify-package.sh` (a hard
dependency there, used solely for `tarfile`-based archive member-safety
inspection) and `scripts/release/validate-documentation.sh` (release
tooling). `doctor.sh` lists `python3` among its *optional* commands
(alongside `git`, `make`, `shellcheck`, `bats`) purely for informational
reporting — its absence never fails `doctor`, and no runtime command
(`system`, `monitoring`, `filesystem`, `network`, `user`, `process`,
`service`, `config`, `report`) invokes it at all. Python 3 is only needed
if you're building or verifying a release archive, or contributing to the
project's own test/documentation tooling.
