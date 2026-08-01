# Troubleshooting

Symptom-first reference for the failures most likely to show up while
developing in this repository, particularly under WSL/Windows. Each entry
gives the symptom, the cause, and the fix.

---

## 1. Readonly-Variable Errors from Duplicate Sourcing

**Symptom:**

```text
scripts/common/colors.sh: line 6: MAOPS_COLORS_LOADED: readonly variable
```

**Cause:** A `scripts/common/*.sh` file was sourced twice in the same shell,
and the second `readonly MAOPS_..._LOADED=1` line ran again. This normally
can't happen here — every common-library file starts with a guard:

```bash
[[ -n "${MAOPS_COLORS_LOADED:-}" ]] && return
readonly MAOPS_COLORS_LOADED=1
```

If you see this error, the guard is either missing from a file you added, or
was removed/edited by accident. It typically surfaces when writing a new
script that sources an individual common file directly (e.g. `source
scripts/common/colors.sh`) *and* also sources `bootstrap.sh`, but the new
file was copied from an older version of the library without the guard line.

**Fix:** Ensure every file under `scripts/common/` starts with the
load-guard pattern shown above, using a unique `MAOPS_<FILE>_LOADED` name per
file. Prefer sourcing `scripts/common/bootstrap.sh` alone rather than
individual common files — see
[architecture.md](architecture.md#3-bootstrap-dependency-loading-order).

---

## 2. Permission-Denied Messages Under `/tmp`

**Symptom:**

```text
find: '/tmp/systemd-private-.../tmp': Permission denied
```

or a script exits early instead of completing its scan.

**Cause:** `/tmp` on a typical Linux system contains directories owned by
other users or services — `systemd-private-*` sandboxes, `snap-private-tmp`,
another user's session temp files. Any `find` invocation that walks into one
of those without sufficient privilege gets `Permission denied` on stderr and
a non-zero exit from `find`.

**Fix:** This is already handled in `scripts/filesystem/cleanup-temp.sh` two
ways:

1. Known-unreadable directories are pruned instead of descended into:

   ```bash
   find "$TARGET" \
       \( -type d \( -name 'systemd-private-*' -o -name 'snap-private-tmp' \) -prune \) \
       -o \
       \( -type f -readable -print \) \
       2>/dev/null || true
   ```

2. `-type f -readable` filters to files the current user can actually read,
   `2>/dev/null` discards the permission-denied noise for anything not
   pruned, and `|| true` stops a non-zero `find` exit status from tripping
   `set -e` on the whole script.

If you're extending this script or writing a new one that walks `/tmp`,
reuse the same prune list rather than only relying on `2>/dev/null` — silently
discarding stderr without pruning still lets `find`'s exit code cause
problems if you remove the `|| true`.

---

## 3. CRLF versus LF Line Endings

**Symptom:**

```text
scripts/system/system-info.sh: line 1: $'\r': command not found
```

or `bash -n` / ShellCheck fail on a script that looks correct when opened in
an editor.

**Cause:** The file has Windows-style `\r\n` line endings. Bash treats the
trailing `\r` as part of the line — on the shebang line specifically, `#!/usr/bin/env bash\r`
fails to resolve, and elsewhere a stray `\r` can break comparisons, heredocs,
and `case` patterns.

**Fix:** `.gitattributes` in this repository already forces LF for the file
types that need it:

```text
*.sh       text eol=lf
*.md       text eol=lf
*.yml      text eol=lf
```

This normalizes line endings *on checkout/commit through git*, but it can't
fix a file that already has CRLF endings in your working tree from before
`.gitattributes` was in effect, or one edited by a tool that ignores git's
normalization. Check a suspect file with:

```bash
file scripts/system/system-info.sh
# "... with CRLF line terminators" means it needs fixing
```

Fix it in place with:

```bash
sed -i 's/\r$//' scripts/system/system-info.sh
```

then re-add it so git records the corrected content. If this keeps
recurring for the same file, check whether your editor is configured to save
with Windows line endings for that file type and override it locally rather
than fighting `.gitattributes` on every commit.

---

## 4. WSL and Windows Git Executable-Mode Behavior

**Symptom:** A script runs fine locally (`./scripts/system/system-info.sh`
works from your WSL shell) but CI fails with:

```text
The following tracked shell files are not executable:
scripts/system/system-info.sh
```

**Cause:** Git tracks a file's executable bit as part of its mode
(`100755` vs `100644`) independently of what the underlying filesystem
reports. On a Windows-backed mount inside WSL (`/mnt/c/...`, `/mnt/f/...` —
`drvfs`), **`ls -l` reports every file as `rwxrwxrwx` regardless of the mode
git has recorded**, because `drvfs` doesn't support real Unix permission
bits and fakes them. That means a file committed as `100644` from a Windows
tool (or from `git add` before a `chmod +x` was ever run) will look and
behave as executable locally, while a real Linux checkout — including
GitHub Actions' `ubuntu-latest` runner — honors the tracked `100644` mode and
refuses to execute it directly.

**Fix:** Check the mode git actually recorded, not what the filesystem shows:

```bash
git ls-files -s scripts/system/system-info.sh
# 100755 ... scripts/system/system-info.sh   <- correct
# 100644 ... scripts/system/system-info.sh   <- needs fixing
```

Fix a wrong mode directly through git (works even from a `drvfs` mount,
since it edits the index rather than relying on the filesystem's reported
permissions):

```bash
git update-index --chmod=+x scripts/system/system-info.sh
git commit -m "fix: mark system-info.sh executable"
```

Run `make check-executable` before pushing to catch every mis-tracked script
at once — it's the same check CI runs. For ongoing development, prefer
cloning the repository onto the native Linux filesystem inside WSL (e.g.
`~/code/...`) rather than working directly against a `/mnt/c/...` or
`/mnt/f/...` path, so `chmod` and git's recorded mode never drift apart in
the first place. See
[best-practices.md](best-practices.md#9-git-executable-modes-under-wsl) for
the underlying convention.

**This used to affect packaged/installed output too, not just CI.** Before
Day 6, `package.sh`/`install.sh` staged files with `cp -a`, which copied
whatever mode the *source* filesystem reported — `0777` on `drvfs`,
regardless of what git had recorded. If you built a release or ran
`install.sh` directly from a `/mnt/c/...`/`/mnt/f/...` checkout, the
packaged/installed files could end up world-writable even though `git
ls-files -s` showed the correct mode all along. This is fixed: staging now
derives every mode from `git ls-files -s` exclusively and never consults
`stat` on the source tree. If you still see an unexpected mode in a
freshly-built `dist/*.tar.gz` or freshly-installed tree, run `maops
integrity` (§17 below) against it — it will name the exact file and the
expected-vs-actual mode, and if it's clean, the problem is likely in a
custom fork of `package.sh`/`install.sh` that reintroduced `cp -a`
somewhere, not in the filesystem mounting behavior itself.

**This also affects the Bats tests that simulate drvfs.** If a
`build_drvfs_clone_fixture`-based test passes locally but fails only in CI,
that's a different, test-only manifestation of the same `core.fileMode`
sensitivity — see [§18](#18-build_drvfs_clone_fixture-bats-tests-pass-on-wsl-but-fail-on-a-real-ci-runner).

---

## 5. SC1091

**Symptom:** ShellCheck reports:

```text
In scripts/filesystem/largest-files.sh line 9:
source "$SCRIPT_DIR/../common/bootstrap.sh"
       ^-- SC1091 (info): Not following: ... was not specified as input (see shellcheck -x)
```

**Cause:** ShellCheck analyzes one file at a time and can't resolve a
dynamically constructed path like `"$SCRIPT_DIR/../common/bootstrap.sh"` on
its own — `$SCRIPT_DIR` is only known at runtime.

**Fix:** Point ShellCheck at the real file with a `source=` directive
immediately above the `source` line:

```bash
# shellcheck source=scripts/common/bootstrap.sh
source "$SCRIPT_DIR/../common/bootstrap.sh"
```

For files where the target genuinely can't be resolved to a fixed repo path
(dynamically resolved dependencies documented as such), the codebase instead
uses `# shellcheck source=/dev/null` with a comment explaining why, e.g. in
`scripts/filesystem/largest-files.sh`:

```bash
# The dynamically resolved dependency is linted independently.
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../common/bootstrap.sh"
```

This is an informational-severity notice (`SC1091` is `info`, not
`warning`/`error`), so it won't fail `make lint` or CI on its own — but
resolving it properly means ShellCheck can actually check that the sourced
file's functions are used correctly, instead of treating them as unknown.

---

## 6. SC2317

**Symptom:** ShellCheck reports:

```text
SC2317 (info): Command appears to be unreachable. Check usage (or ignore if invoked indirectly).
```

**Cause:** This fires on code ShellCheck's static analysis can't prove is
ever called — most commonly a function defined but never referenced by name
in the same file, because it's invoked indirectly (dispatched by variable,
called from another sourced file, or simply not yet wired up). It's an
`info`-severity notice, not an error.

**Fix:** First confirm whether the code is genuinely dead or just invoked
indirectly:

- If it's dead code (a leftover function nothing calls), delete it — don't
  suppress the warning.
- If it's invoked indirectly (e.g. a function called only from a file that
  sources this one), either restructure so ShellCheck can see the call, or
  suppress the specific line with a reason:

  ```bash
  # shellcheck disable=SC2317 # invoked indirectly via <mechanism>
  ```

Do not blanket-disable `SC2317` at the top of a file — that hides genuinely
unreachable code the next time someone edits the function.

---

## 7. Exit 141 Caused by SIGPIPE

**Symptom:** A script that pipes several commands together exits with no
error message and a status of `141`:

```bash
$ bash scripts/filesystem/largest-files.sh /usr 5
--------------------------------------------------------------------------------
Largest Files
--------------------------------------------------------------------------------
[INFO] Scanning /usr
EXIT:141
```

**Cause:** `141 = 128 + 13`, where `13` is `SIGPIPE`. This happens when a
pipeline under `set -o pipefail` has a downstream stage that exits before
reading all of its input — classically `... | head -n N`. Once `head` reads
its `N` lines, it exits and closes the read end of the pipe; the upstream
command (e.g. `sort`) gets `SIGPIPE` on its next write and dies. `pipefail`
then reports that signal-based exit as the pipeline's status, which trips
`set -e` and kills the whole script silently — no message, because the
failure is a signal, not a printed error.

**Fix:** Don't terminate a `pipefail`-sensitive pipeline with `head`.
`scripts/filesystem/largest-files.sh` avoids the issue entirely by letting
the full pipeline run to completion and doing the row-limiting inside `awk`
(`NR <= limit`) instead of truncating the stream with `head`:

```bash
find "$TARGET" -type f -printf '%s\t%p\n' 2>/dev/null |
    sort -nr -k1,1 |
    awk -F '\t' -v limit="$LIMIT" 'NR <= limit { ... }'
```

If a `head`-terminated pipeline is unavoidable elsewhere, two other valid
fixes: temporarily disable `pipefail` around just that pipeline
(`set +o pipefail` ... `set -o pipefail`), or wrap the pipeline in a subshell
with `trap '' PIPE` so `SIGPIPE` is ignored there. See
[best-practices.md](best-practices.md#7-sigpipe-and-pipefail) for the full
explanation and additional options.

---

## 8. GitHub Actions Failures

`.github/workflows/bash-validation.yml` has four checks that can fail
independently. Reproduce each one locally before re-pushing:

| CI step | Local reproduction | Typical cause |
|---|---|---|
| Validate Bash syntax | `make validate` | A real syntax error — unclosed quote/brace, bad `case` statement |
| Run ShellCheck | `make lint` | A ShellCheck warning/error at default severity; see [SC1091](#5-sc1091) / [SC2317](#6-sc2317) above for the two info-level notices this project has already reasoned about |
| Verify executable modes | `make check-executable` | A script committed as `100644` instead of `100755` — see [§4](#4-wsl-and-windows-git-executable-mode-behavior) above, most commonly caused by committing from a WSL `drvfs` mount |
| Run the Bats suite | `make test` | A genuine test regression, or — if the failing test passes locally on WSL but fails only in CI and involves `build_drvfs_clone_fixture` — see [§18](#18-build_drvfs_clone_fixture-bats-tests-pass-on-wsl-but-fail-on-a-real-ci-runner) |
| Install ShellCheck | — | Runner-side `apt-get` failure (transient); re-run the job |

`make quality` runs the first three in sequence and is the fastest way to
confirm a branch will pass CI before pushing. If a workflow run fails and
none of the above explains it, open the failed step's log in the Actions tab
— each step name in the table matches the step name shown there — and check
whether the failure is in a step's own command (a genuine repo problem) or
in GitHub-hosted runner setup (transient, safe to re-run).

---

## 9. `bin/maops: Permission denied`

**Symptom:**

```text
$ ./bin/maops --help
bash: ./bin/maops: Permission denied
```

**Cause:** Same class of issue as [§4](#4-wsl-and-windows-git-executable-mode-behavior)
— `bin/maops` has no `.sh` extension, so it's easy to forget it needs the
same `100755` git mode as every script under `scripts/`.

**Fix:**

```bash
git ls-files -s bin/maops   # 100644 means it needs fixing
git update-index --chmod=+x bin/maops
```

`make check-executable` covers `bin/maops` explicitly (not just `*.sh`
files), so this is caught locally before it reaches CI.

---

## 10. `bats: command not found`

**Symptom:** `make test` or `make quality` exits with `Bats is not
installed.`

**Cause:** [Bats](https://github.com/bats-core/bats-core) isn't installed
locally. It's a separate tool from ShellCheck.

**Fix:** Install it via your distro's package manager (`sudo apt-get install
bats` on Ubuntu/Debian) or the
[bats-core installation guide](https://bats-core.readthedocs.io/en/stable/installation.html).
CI installs it automatically as part of the "Install ShellCheck and Bats"
workflow step.

---

## 11. `ping-check.sh` fails with "Operation not permitted"

**Symptom:** `./scripts/network/ping-check.sh <host>` (or `maops network
ping <host>`) fails immediately, even against a genuinely reachable host, in
a container or CI-style sandbox.

**Cause:** Sending an ICMP echo request requires either `CAP_NET_RAW` or an
allowed `ping_group_range` (`iputils-ping` uses an unprivileged ICMP socket
on modern Linux, but the group range still has to include the running
user). Minimal containers and some sandboxed environments deny both.

**Fix:** This is an environment limitation, not a script bug — there's
nothing in `ping-check.sh` to fix. This is also why the Bats suite
(`tests/network/network-tools.bats`) never exercises a real, live ping: it
only tests `--help` and invalid-`COUNT` rejection, both of which run before
any ICMP socket is opened. If you need to confirm real reachability in a
restricted environment, use `maops network port HOST PORT` instead — TCP
connect doesn't require raw-socket privileges.

---

## 12. Why `port-check.sh` Uses `bash -c` with `$1`/`$2`, Instead of `$HOST` Directly

**Symptom:** None currently — this documents a fixed vulnerability so it
isn't reintroduced. If you're reading this while modifying `port-check.sh`
(or writing a similar script that hands a shell a piece of external input
inside a nested `bash -c`), read this first.

**Cause (historical):** An earlier version of `scripts/network/port-check.sh`
built its TCP-connect check like this:

```bash
timeout "$TIMEOUT" bash -c "exec 3<>/dev/tcp/$HOST/$PORT" 2>/dev/null
```

`$HOST` is user-supplied and was never validated (unlike `$PORT`/`$TIMEOUT`,
which go through `validate_tcp_port`/`validate_positive_integer`). Because
the double-quoted string is expanded by the *outer* shell before being
handed to `bash -c` as a single argument, and the *inner* `bash` then
re-parses that whole string as a shell command, any shell metacharacter in
`$HOST` became code the inner shell executed:

```bash
$ ./scripts/network/port-check.sh '127.0.0.1;touch /tmp/pwned;' 80 1
...
$ ls /tmp/pwned
/tmp/pwned   # arbitrary command executed via a crafted HOST argument
```

This was found and fixed during the Day 3 release-readiness review, before
any tag was cut — see `docs/engineering-reviews/` for the review that caught
it and the follow-up that verified the fix.

**Fix:** `port-check.sh` now passes `$HOST`/`$PORT` as the inner `bash -c`'s
own positional parameters instead of interpolating them into the script
text:

```bash
timeout "$TIMEOUT" bash -c 'exec 3<>"/dev/tcp/$1/$2"' bash "$HOST" "$PORT" 2>/dev/null
```

The script argument (`'exec 3<>"/dev/tcp/$1/$2"'`) is single-quoted, so the
outer shell performs no expansion on it — `$1`/`$2` reach the inner `bash`
completely literally. `$HOST`/`$PORT` are then bound to the inner shell's own
`$1`/`$2` via the extra arguments after the script. The inner shell only ever
*substitutes* those values into the redirection target; a substituted value
in a redirection operand is never re-tokenized as command syntax, so a
`HOST` full of shell metacharacters just becomes (and fails as) a malformed
`/dev/tcp/...` path instead of executing anything. See
[best-practices.md §11](best-practices.md#11-parameterized-bash--c-instead-of-string-interpolation)
for the general rule this establishes, and
`tests/network/network-tools.bats`'s `"port-check.sh does not execute shell
metacharacters embedded in HOST"` test for the regression coverage that now
guards against this reappearing.

---

## 13. `maops: command not found` After `make install`

**Symptom:** `make install` reports success, but a new shell session (or a
non-interactive script) can't find `maops`:

```text
$ maops --version
bash: maops: command not found
```

**Cause:** The default install prefix is `$HOME/.local`, so the launcher
lands at `$HOME/.local/bin/maops`. Most distributions only add
`~/.local/bin` to `$PATH` for *interactive login* shells (via
`~/.profile`/`~/.bash_profile`), so a fresh non-login shell, a cron job, or a
CI step may not have it on `$PATH` yet.

**Fix:** Either add `export PATH="$HOME/.local/bin:$PATH"` to your shell's
startup file and start a new shell, or invoke the launcher by its full path
(`"$HOME/.local/bin/maops" --version`) — which always works regardless of
`$PATH`, since the installed launcher resolves its own location through the
symlink correctly (see
[architecture.md §7](architecture.md#7-unified-maops-cli)). `make
smoke-install` deliberately invokes the installed CLI by full path rather
than relying on `$PATH`, for exactly this reason.

---

## 14. `maops config validate` Rejects a Config File as Malformed or Unknown-Key

**Symptom:** `maops config validate` (or `doctor`) reports a config file as
invalid, even though it "looks right" when opened in an editor.

**Cause:** The parser in `scripts/common/config-file.sh` is intentionally
strict (see
[architecture.md §12](architecture.md#12-configuration-system)) — every line
must be blank, a `#`-prefixed comment, or match `KEY=VALUE` exactly, where
`KEY` is one of the four supported keys (`output_format`, `process_limit`,
`ping_count`, `network_timeout`). Common causes:

- A typo'd key name (`output-format` instead of `output_format`, or any key
  not in the fixed list) — reported as "unknown key."
- The same key listed twice — reported as "duplicate key," even if both
  occurrences have the same value.
- A line that isn't a comment, blank, or `KEY=VALUE` at all (e.g. a stray
  fragment left from a merge) — reported as "malformed line."
- A value that doesn't match its key's expected shape — `output_format` must
  be exactly `text` or `json`; the other three keys must be positive
  integers (`0`, a negative number, a leading zero like `007`, or non-numeric
  text all fail).

**Fix:** Run `maops config validate` directly — its error messages name the
specific line number and problem. This strictness is deliberate, not a bug:
the parser never sources or evaluates the file, so a rejected value (even
one containing `$(...)` or `;`) is always inert text, never executed — see
[best-practices.md §17](best-practices.md#17-config-file-parsing-without-eval-or-source).
To start over, `maops config init --force` regenerates a known-valid default
file.

---

## 15. Interpreting a `maops doctor` Failure in a Minimal Environment

**Symptom:** `maops doctor` exits `1` inside a minimal container or a fresh
CI image, listing several `command_*` checks as `fail`.

**Cause:** This is doctor working as intended, not a bug — a minimal base
image commonly lacks one or more of the required runtime commands
(`bash awk find sort ps getent ip ping timeout df free lscpu uptime`, plus a
`systemctl`-or-`service` service manager). Doctor reports each missing
required command by name so the gap is actionable rather than a generic
failure.

**Fix:** Install the missing package(s) for your distribution (commonly
`iproute2` for `ip`, `iputils-ping` for `ping`, `procps` for `ps`/`free`/
`uptime`, `util-linux` for `lscpu`). A missing **optional** development tool
(`git make shellcheck bats python3`) is only ever a warning — doctor still
exits `0` in that case, since those tools aren't needed to *run* the
toolkit, only to develop it. See
[architecture.md §14](architecture.md#14-doctor-command) for the full
required-vs-optional check list.

---

## 16. `verify-package.sh` Fails After Manually Editing an Archive

**Symptom:** `make verify-package` (or `scripts/release/verify-package.sh`)
fails with a checksum mismatch after the `dist/*.tar.gz` file was edited,
re-compressed, or copied through a tool that altered it in any way.

**Cause:** This is the intended behavior, not a bug — checksum verification
exists precisely to detect any modification, however small, between when
`package.sh` built the archive and when it's verified or installed from.
Re-compressing an archive (even with identical file contents) generally
changes its bytes, since gzip's own reproducibility depends on the exact
flags used (see
[architecture.md §15](architecture.md#15-packaging-and-release-verification)).

**Fix:** Rebuild the archive from source with `make package` rather than
editing an existing one — the checksum file is regenerated alongside it, so
the two always match a freshly built pair. If you need to confirm two builds
from the same source tree are identical, compare their SHA-256 sums directly
rather than editing either archive in place.

**A second, independent check can also fail even when the checksum passes.**
Since Day 6, `verify-package.sh` also validates the archive's internal
`MAOPS-MANIFEST.tsv` — every distributed file's mode, SHA-256 content, and
presence — *after* the external `.sha256` check. If you see a failure
naming a specific file (`Content mismatch for manifest entry: ...`, `Mode
mismatch for manifest entry: ...`, or `Extra distributed file not listed in
manifest: ...`) rather than a generic checksum-mismatch message, the archive
passed the whole-file checksum but a file inside it doesn't match what the
manifest says it should be — this can only happen if the archive was
rebuilt or edited by hand after the fact (e.g. re-tarring an extracted copy
with a stale `MAOPS-MANIFEST.tsv`, or editing a file post-extraction and
re-packing). The fix is the same: rebuild from source with `make package`,
never hand-edit an archive's contents.

**A crafted or corrupted archive can also fail before extraction even
runs**, with a message like `Refusing archive with an unsafe member path`,
`disallowed member type for: ...`, or `multiple top-level roots in
archive`. This means the archive contains a member `verify-package.sh`
refuses to trust on principle — an absolute path, a `..` traversal
component, a symlink/hardlink/device/FIFO member, or more than one
top-level directory — and is refusing to extract it at all rather than
attempting to sanitize it. A legitimately-built archive from `make package`
never produces any of these; seeing one means the archive did not come from
this project's own build, or was tampered with after the fact.

---

## 17. Interpreting a `maops integrity` Failure

**Symptom:** `maops integrity` exits `1` and reports one or more entries
with a `category` of `missing`, `modified`, `unexpected-mode`, or
`malformed-manifest`.

**What each category means:**

- **`missing`** — a file the manifest expects is not present. In an
  installed tree, something deleted a file under `PREFIX/lib/maops` after
  install; reinstall (`make install` / `install.sh --force`) to restore it.
  In a source-tree checkout, a Git-tracked release file is missing from the
  working tree — `git status`/`git checkout -- <path>` will show and fix it.
- **`modified`** — the file exists but its content doesn't match. In an
  installed tree, this means something edited an installed file directly
  (installed files are meant to be treated as read-only; edit the source and
  reinstall instead). In a source-tree checkout, it means uncommitted local
  changes to a tracked release file — expected during development, worth a
  second look if unexpected.
- **`unexpected-mode`** — content matches, but the permission bits don't.
  In an installed tree, something ran `chmod` on an installed file directly.
  In a source-tree checkout, it means Git's *index* mode itself is wrong for
  that path (see §4 above) — `unexpected-mode` here is about what Git has
  recorded, never about working-tree `stat`, so fixing the working tree's
  permissions alone will not clear it; use `git update-index --chmod`.
- **`malformed-manifest`** — the manifest file itself couldn't be parsed
  (wrong field count, invalid mode, non-hex/wrong-length checksum, an unsafe
  path, or a duplicate entry). In an installed tree, this generally means
  `.integrity-manifest` was hand-edited or corrupted — reinstall to
  regenerate it. `maops integrity` never repairs anything itself, in any
  category — it only reports.

**Fix, in general:** `maops integrity` is diagnostic-only by design (see
[architecture.md §16](architecture.md#16-integrity-verification-maops-integrity)) —
there is no `--repair` flag and there will not be one; the fix for every
category above is either to reinstall from a trusted source (installed
mode) or to reconcile the working tree with Git directly (source-tree
mode), never to have the tool silently patch files it doesn't fully trust.

---

## 18. `build_drvfs_clone_fixture` Bats Tests Pass on WSL but Fail on a Real CI Runner

**Symptom:** `tests/release/package.bats`, `tests/diagnostics/integrity-check.bats`,
and `tests/install/install.bats`'s "drvfs simulation" / "observed permissions
are 0777" tests all pass in a local WSL/drvfs checkout, but the same tests
fail on GitHub Actions' `ubuntu-latest` runner with output like:

```text
not ok 101 manifest and archived file modes are correct even from a drvfs-simulated (0777) source tree
#   `[[ "$output" == -rw-r--r--* ]]' failed
not ok 144 healthy source tree passes with exit 0, even when observed permissions are 0777
#   `[ "$status" -eq 0 ]' failed
```

`make test`'s failure itself is reported generically as
`make: *** [Makefile:64: test] Error 123` regardless of which test actually
failed — that line number is just where `xargs` (which runs `bats`) sits in
the `test` recipe, not the failing test's location. Always scroll up to the
first `not ok` line for the real cause; the `# (in test file ...)` and
`# ... failed` lines immediately below it name the actual assertion.

**Cause:** `build_drvfs_clone_fixture` (`tests/test-helper.bash`) simulates
the drvfs symptom described in [§4](#4-wsl-and-windows-git-executable-mode-behavior)
by copying the repository (including `.git`) into a scratch directory and
force-`chmod`-ing every file to `0777`. Every consuming test then runs `git
add -A` inside that fixture. Whether that `git add -A` actually re-records
the fake `0777` executable bit into the fixture's Git index depends on the
fixture's own `core.fileMode` setting — and until this was fixed, the
fixture never set that explicitly, so it inherited whatever `core.fileMode`
the *host* repository happened to have:

- On a WSL/drvfs checkout, Git commonly auto-detects the mount's unreliable
  permission bits and sets `core.fileMode=false` locally. `git add -A`
  is then a genuine no-op for modes, so the fixture's index stays correct
  and the test reproduces the intended symptom: `stat` reports `0777`, but
  Git's index (the only thing `git ls-files -s` and `git diff --quiet`
  actually consult) still has the real `100644`/`100755` mode.
- On a fresh GitHub Actions checkout (real ext4), `core.fileMode` defaults
  to `true`. `git add -A` then genuinely re-stages the forced `0777` as
  `100755` on every file, corrupting the fixture's index for real — so the
  code under test (correctly) reports the corruption it's designed to
  catch, and the test fails.

The production code (`scripts/common/integrity.sh`, `package.sh`,
`install.sh`, `integrity-check.sh`) was never the problem here — this was a
test-fixture bug, not a mode-normalization bug.

**Fix:** `build_drvfs_clone_fixture` now pins the fixture's own
`core.fileMode` explicitly instead of relying on inheritance:

```bash
git -C "$dest" config core.fileMode false
```

This makes the fixture reproduce the *observed symptom* deterministically
on any host — including a normal ext4 CI runner — without needing an actual
drvfs mount, which was always the fixture's stated intent.

**If you're debugging a similar "passes locally, fails in CI" Bats
failure:** check whether the failing test touches Git mode at all, and if
so, compare `git config --get core.fileMode` between your local checkout
and a fresh clone (`git config --get core.fileMode` prints nothing at all
if it's unset, which behaves as `true`). A test or fixture that assumes a
particular `core.fileMode` value without setting it explicitly will drift
by environment exactly like this one did.
