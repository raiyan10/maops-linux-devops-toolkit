# Engineering Review — Day 5 Release-Readiness (v0.4.0)

**Reviewer role:** Senior Platform / Release Engineer
**Scope:** Full-repository release-readiness review for v0.4.0, covering the new configuration system (`scripts/common/config-file.sh`, `scripts/config/config-manager.sh`), dependency-free JSON output (`scripts/common/format.sh`), the `doctor` diagnostic (`scripts/diagnostics/doctor.sh`), the user-local installer/uninstaller (`scripts/install/install.sh`, `scripts/install/lib.sh`, `scripts/install/uninstall.sh`), release packaging and archive verification (`scripts/release/package.sh`, `scripts/release/verify-package.sh`, `scripts/common/release-files.sh`), the `bin/maops` symlink-resolution fix, the new/updated Bats suites, CI parity, and documentation accuracy — using the `bash-review`, `linux-best-practices`, `devops-review`, `github-actions`, `documentation`, `bash-test-engineer`, and `release-engineer` review capabilities.
**Method:** All commands executed live against the working tree at `/mnt/f/DevOps-Portfolio/maops-linux-devops-toolkit` (branch `feature/day-5-packaging-config`) — no network access used or required, no `sudo`, no system-wide install, no writes to the real `$HOME` configuration. Every implementation file (config, install, uninstall, package, verify-package, doctor, format, release-files, cli/bootstrap/helpers/logger) and every new/changed Bats file was read directly. Two independent specialized sub-reviews were additionally commissioned and cross-checked against direct testing: a **release-engineer** review of packaging/install/uninstall/config security, and a **bash-test-engineer** review of the Bats suite's isolation, injection-test rigor, determinism, and coverage. No implementation files were modified; only this report was added.

---

## 1. Commands Run and Results

| Command | Result |
|---|---|
| `make quality` | **Pass.** `validate` → `lint` → `check-executable` → `test` all pass; **238/238** Bats tests green (up from Day 4's 116). |
| `make package` | **Pass.** Built `dist/maops-linux-devops-toolkit-0.4.0.tar.gz` and its `.sha256`. |
| `make verify-package` | **Pass.** Checksum, member-path safety, and required-path checks all succeeded. |
| `make smoke-install` | **Pass.** Install → `--version` → `doctor` (all required checks passed) → uninstall → post-uninstall cleanup verification, against a throwaway `/tmp` prefix. |
| `bin/maops doctor --format json \| python3 -m json.tool` | **Valid JSON**, pretty-printed cleanly; `overall: "pass"`, 25 checks. |
| `bin/maops config show --format json \| python3 -m json.tool` | **Valid JSON**; `process_limit`/`ping_count`/`network_timeout` correctly emitted as unquoted JSON numbers. |
| Adversarial: `$(...)` in `process_limit` | Rejected (`invalid value for process_limit`), exit 1, **marker file never created**. |
| Adversarial: backtick command substitution in `process_limit` | Rejected, exit 1, **marker file never created**. |
| Adversarial: duplicate key (`output_format` twice) | Rejected (`duplicate key 'output_format'`), exit 1. |
| Adversarial: unknown key (`made_up_key=1`) | Rejected (`unknown key 'made_up_key'`), exit 1. |
| Adversarial: malformed line (no `=`) | Rejected (`malformed line`), exit 1. |
| Adversarial: `install.sh --prefix /` | Refused (`Refusing to install to the filesystem root`), exit 2. |
| Adversarial: `install.sh --prefix "$SCRATCH/evil-\$(touch marker)"` | Directory **literally named** `evil-$(touch ...)` created; install succeeded into it; **marker never created** — no execution. |
| Adversarial: `install.sh --prefix "$SCRATCH/evilsemi; touch marker"` | Same result — literal directory name, **marker never created**. |
| Adversarial: unrelated file at `PREFIX/bin/maops` | Refused, exit 1, **even with `--force`**; file content unchanged both times. |
| Adversarial: `uninstall.sh` against a manifest-less directory with unrelated files | `Nothing to uninstall`, exit 0, unrelated files **untouched**. |
| Adversarial: tampered archive (1 byte flipped mid-file) | `verify-package.sh` correctly failed the checksum check, exit 1. |
| Adversarial: crafted path-traversal tar member (`tar --transform` to escape via `../../`) | `verify-package.sh` refused **before extraction** (`Refusing archive with an unsafe member path`), exit 1, **canary file never created**. |
| Executable-mode sweep (`git ls-files -s`) | All new `.sh`/`bin/maops` entries tracked `100755`; new `.bats` files correctly `100644` (excluded from `check-executable`'s glob, matching the documented convention). |
| Version consistency sweep | `PROJECT_VERSION="0.4.0"` (`config.sh`) matches `CHANGELOG.md`'s `## [0.4.0]` entry, `verify-package.sh`'s `PKG_NAME`, `package.sh`'s archive name, and every `--version` assertion in `tests/*.bats` (read dynamically via `test-helper.bash`, not hardcoded). |
| Real-`$HOME` isolation check | `~/.config/maops` absent before and after the full session; `make smoke-install`'s live `doctor` run against the real `$HOME` only *read* `config_path`/`config_exists` (both read-only checks) and never wrote to it. |

---

## 2. Package Artifact Details

- **Archive:** `dist/maops-linux-devops-toolkit-0.4.0.tar.gz`, 33,796 bytes (33 KB), 57 members, single top-level directory `maops-linux-devops-toolkit-0.4.0/`.
- **Checksum:** `dist/maops-linux-devops-toolkit-0.4.0.tar.gz.sha256` — `2da4acf26adb3445ce2db0bc640d5cc79469b98685bfda1fbfa53ba7b64ee0fc`.
- **Contents:** `bin/maops`; all of `scripts/` (common, config, diagnostics, filesystem, install, monitoring, network, process, release, service, system, users); `templates/script-template.sh`; `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, `Makefile`, `.gitattributes` — exactly `scripts/common/release-files.sh`'s `RELEASE_FILE_LIST`, expanded through `git ls-files` for directory entries.
- **Excluded (confirmed absent):** `.git/`, `.github/`, `.claude/`, `dist/`, `tests/`, `docs/` — no test fixtures, no CI config, no engineering-review docs, no user configuration or secrets.
- **Reproducibility:** two successive `make package` runs on an unchanged tree produced byte-identical archives on this machine (per `tests/release/package.bats`'s dedicated test, reconfirmed) — but see Finding H1 for a cross-machine caveat.
- **Required-path manifest** (`verify-package.sh`'s `REQUIRED_ARCHIVE_PATHS`): `bin/maops`, `scripts/common/bootstrap.sh`, `scripts/config/config-manager.sh`, `scripts/diagnostics/doctor.sh`, `scripts/install/install.sh`, `scripts/install/uninstall.sh`, `scripts/release/package.sh`, `templates/script-template.sh`, `LICENSE`, `Makefile`, `README.md`, `CHANGELOG.md` — all present and verified.

---

## 3. Total Test Count

**238 Bats tests, 238 passing (0 failures).** Independently recounted by the bash-test-engineer sub-review (`grep -c '^@test' tests/*/*.bats` sums to exactly 238, matching the `make quality` summary line). Breakdown of Day 5's net-new coverage: `tests/config/config-manager.bats` (39 tests), `tests/diagnostics/doctor.bats` (28 tests), `tests/install/install.bats` (23 tests), `tests/release/package.bats` (17 tests), plus new dispatch-route assertions folded into `tests/cli/maops.bats` — up from Day 4's 116.

---

## 4. Findings

### Critical

None found.

### High

**H1 — `cp -a` propagates the working tree's filesystem-observed permission bits instead of git's tracked index mode, in both packaging and installation.**
Files: `scripts/release/package.sh:99,103` (`copy_entry`), `scripts/install/install.sh:176` (`do_install`'s `cp -a -- "$src" "$dest"`).
Independently confirmed twice (by direct testing and by the release-engineer sub-review) on this exact checkout: `git ls-files -s` records `100644` for `README.md`, `LICENSE`, `Makefile`, `.gitattributes`, `CHANGELOG.md`, `CONTRIBUTING.md` (i.e., non-executable), but `stat -c '%a'` on the working tree shows `777` for every one of them, because `git config core.fileMode` is `false` on this WSL/drvfs mount (a variant of the same filesystem gotcha `docs/roadmap.md` already documents for git's *executable-mode tracking*, but not previously identified as also affecting *packaged/installed output permissions*). Since `cp -a` preserves whatever the source filesystem reports rather than normalizing to git's tracked mode, both the release tarball and the installed `$PREFIX/lib/maops` tree built on a `core.fileMode=false` checkout ship every file — including plain documentation and the `Makefile` — as world-writable (`777`).
**Failure scenario:** a contributor builds and installs from a WSL/drvfs (or any `core.fileMode=false`) checkout; the resulting `$PREFIX/lib/maops` tree is world-writable end-to-end, so any other local principal with filesystem access to that path can silently modify installed scripts before they're next invoked. It also means the documented "byte-identical reproducible build" guarantee (`CHANGELOG.md`, `docs/architecture.md` §15) is proven only *on a single machine* by the existing test (`tests/release/package.bats`'s "building twice … produces byte-identical archives") — it does not hold *across* machines with different `core.fileMode`/umask settings, which the same test cannot detect since it never varies the source filesystem.
**Fix direction (not applied, per this review's scope):** after `cp -a`, `chmod` each staged file according to `git ls-files -s`'s recorded mode (`100755` → `755`, everything else → `644`) rather than trusting the working tree's observed bits, in both `package.sh` and `install.sh`.

### Medium

**M1 — `uninstall.sh`'s removal guard is scoped to `$PREFIX` rather than the narrower `$LIB_DIR`.**
File: `scripts/install/uninstall.sh:179` (`remove_files`).
The per-path safety check accepts any manifest entry matching `"$PREFIX"/*`, but `write_manifest` (`install.sh:158`) only ever emits paths under `$LIB_DIR` (`$PREFIX/lib/maops`) today. This is a defense-in-depth gap, not a currently-exploitable one: a corrupted or hand-edited manifest could direct `rm -f` at any file under a shared prefix such as `$HOME/.local` — a location commonly shared with `pipx`, `npm`, `cargo`, or other user-local tooling — not just MAOps's own subtree. Tightening the guard to `"$LIB_DIR"/*` would match the manifest's actual invariant and shrink the blast radius of a future manifest-format bug to exactly what MAOps itself installed.

**M2 — Archive-member safety checks in `verify-package.sh` validate member *names* only, never member *type* (symlink/hardlink) or link targets.**
Files: `scripts/release/verify-package.sh:109-141` (`is_unsafe_member`, `verify_member_paths`); no corresponding test in `tests/release/package.bats`.
Both sub-reviews independently converged on this gap. The existing path-traversal defense (rejecting `..` segments and out-of-prefix members by name) is correctly implemented and well-tested (`tests/release/package.bats`'s `--transform`-based traversal test, reconfirmed live in this review with a canary file). However, a maliciously crafted archive containing a *symlink* member (e.g., a directory-replacing symlink whose target lies outside the extraction scratch directory, followed by a member that writes "through" it) is not rejected by this script's own name-based logic. The release-engineer sub-review confirmed empirically that GNU tar 1.35 happens to refuse this specific pattern at extraction time as a side effect of its own built-in protections — but `verify-package.sh` does not itself guarantee this, and the guarantee would not necessarily hold under `bsdtar` or an older GNU tar. Package verification only ever runs locally in this project's current workflow (never on untrusted, remotely-fetched archives), which limits real-world exploitability today, but the gap is worth closing given `verify-package.sh`'s explicit stated purpose of rejecting unsafe archives *before* extraction.

### Low

**L1 — `tests/install/install.bats:67-73`** ("the installed CLI runs doctor successfully") does not shadow `PATH` the way `tests/diagnostics/doctor.bats` does everywhere else in the suite; it depends on the real host actually having `ip`/`lscpu`/`free`/`uptime`/`getent`/`systemctl` on `PATH`. This holds today on the documented CI target (`ubuntu-latest`, per `.github/workflows/bash-validation.yml`) and passed live in this review, but it is a determinism dependency the rest of the suite deliberately eliminated via `stub_shadow_path_except`.

**L2 — `verify-package.sh` reads the archive twice** (`tar -tzf` for member-path validation at line 140, then `tar -xzf` for the required-path check at line 149) without pinning both reads to a single snapshot. A concurrent writer to `dist/` between the two calls could in principle swap the archive's contents after the safety check passed but before extraction. Low impact for this project's actual usage (single-user, local, non-concurrent build tooling), but worth noting as the theoretical TOCTOU class this design otherwise carefully avoids elsewhere (the checksum-then-member-check-then-extract ordering is itself correct and intentional).

**L3 — Untested branches, none security-relevant:** `config-manager.sh`'s `cmd_path`/`cmd_validate` unexpected-argument paths (`config-manager.sh:68,172`); `install.sh`'s `check_launcher_safety` refusal when `$LAUNCHER` is a symlink to a *foreign* target rather than a plain regular file (only the regular-file case is covered, `install.bats:110-121`); `uninstall.sh`'s `remove_launcher` symlink-but-not-ours warn branch (`uninstall.sh:208-210`). Several tests are also implementation-detail assertions (grepping source for `mktemp -d -- "$PREFIX/lib`, absence of `sudo`, absence of `eval`/`source`) rather than purely behavioral — a defensible trade-off for encoding specific security invariants as regression tripwires, but worth knowing they'd need updating alongside any refactor that preserves behavior but changes implementation.

**L4 (carried over from Day 3/4, unchanged) — `scripts/network/*.sh` still stamp `Version: 0.2.0`** in header comments while `PROJECT_VERSION` correctly reads `0.4.0`. Already tracked in `docs/roadmap.md`'s Planned section as a known, deferred, cosmetic-only cleanup — `bin/maops --version` always reads the single source of truth (`config.sh`), never a per-script header.

### Future Enhancements

- Close M2 with an explicit tar member-type/link-target check in `verify-package.sh` (not relying on the extracting tar implementation's own protections) plus a dedicated Bats regression test, mirroring the rigor already applied to the by-name path-traversal case.
- Tighten M1's `remove_files` guard to `"$LIB_DIR"/*`.
- Normalize permissions to git's tracked index mode in both `package.sh` and `install.sh` (H1) — the single highest-leverage fix in this review, since it affects both packaging integrity and installation safety simultaneously.
- Extend `stub_shadow_path_except` (currently omit-only) to support forcing a *specific* fake output for a command, so `doctor.sh`'s non-Linux and Bash-`<4` branches (currently unreachable under any existing test) become testable without relying on the real host.
- `doctor` currently reports read-only diagnostics only; a natural next step (raised in the Day 3/4 reviews as a "machine-readable output" suggestion, now partially realized via `--format json`) would be a `doctor --fix` mode for safely-correctable issues (e.g., `config init` when the config is merely absent) — deliberately out of scope for this release.
- Resolve L4 (network script version-header drift) opportunistically alongside any other touch of those files.

---

## 5. Category Scores

| # | Category | Score /10 | Rationale |
|---|---|---|---|
| 1 | Architecture | 9 | `config_resolve_value` is implemented exactly once and reused identically by `config show`, `doctor`, and three leaf scripts' defaults — verified by reading every call site; `scripts/common/release-files.sh` is genuinely the single source of truth shared by both `install.sh` and `package.sh`, eliminating an entire class of install/package drift by construction. |
| 2 | Bash correctness | 9 | `set -euo pipefail` and full quoting/`--` discipline throughout every new script; `bash -n` and ShellCheck both pass clean across the entire new surface (`make validate`, `make lint`). Docked slightly for H1 (permission-propagation assumption baked into `cp -a` usage). |
| 3 | CLI usability | 9 | `config`/`doctor` subcommands follow the exact same `--help`/`--version`/usage-error conventions as every pre-existing group; `--format text\|json` is symmetric across both new JSON-emitting commands; error messages are specific (`unknown key 'X'`, `duplicate key 'X'`) rather than generic. |
| 4 | Configuration security | 10 | Independently re-verified via live adversarial testing in this review (not just reading the tests): `$(...)`, backticks, and `;`-chained commands in config values are all inert — rejected by regex/validator, never reaching anything that would expand them. No `eval`, `source`, `bash -c`, or `sh -c` anywhere in `config-file.sh` (confirmed by direct grep, matching the suite's own regression test). |
| 5 | Installation safety | 8 | Staged-then-atomically-swapped install, manifest-verified upgrades, and an unconditional (no `--force` override) refusal to overwrite an unrelated file at the launcher path were all independently confirmed live. Docked for H1 (permission propagation) and M1 (manifest-guard scoped to `$PREFIX` rather than `$LIB_DIR`). |
| 6 | Uninstall safety | 9 | Manifest-prefix-match requirement, per-file `$PREFIX`-scoped guard before every `rm -f --`, idempotent double-uninstall, and default configuration preservation (with explicit `--purge-config` opt-in) all independently confirmed live, including against a directory with no manifest and against an unrelated launcher file. Docked only for M1. |
| 7 | JSON correctness | 10 | Both `doctor --format json` and `config show --format json` independently piped through `python3 -m json.tool` and parsed cleanly; numeric fields correctly unquoted, string fields correctly escaped (backslash-first ordering verified by reading `json_escape`), exactly one document with no stray log lines before/after in either command. |
| 8 | Packaging integrity | 7 | Reproducible-build tooling, git-tracked-file-only staging (stray untracked files confirmed excluded), and pre-extraction archive-safety checks (checksum → member-path → required-path, in that order) are all real and independently verified, including against a tampered archive and a crafted traversal member. Held back by H1 (permission propagation undermines the cross-machine reproducibility claim) and M2 (symlink-member gap). |
| 9 | Automated testing | 9 | 238/238 passing, up from 116; injection tests correctly prove *non-execution* via canary/marker files rather than exit-code-only assertions (the stronger, correct pattern) across config, install, and package suites alike; isolation from real `$HOME`/`$XDG_CONFIG_HOME`/system state independently confirmed via direct reading of every `setup()`/`teardown()`. Docked for L1 and the coverage gaps in L3. |
| 10 | CI and documentation | 9 | `.github/workflows/bash-validation.yml` runs `make quality` → `make package` → `make verify-package` → `make smoke-install` in exactly that order with `HOME` redirected to a runner-temp directory for the smoke step — genuine parity with this review's required command set. `docs/architecture.md` §11–§18 and `docs/best-practices.md` §16–§18 were spot-checked line-by-line against the actual implementation with no discrepancy found; `docs/roadmap.md` is current and even pre-discloses known deferred items. Docked only for the pre-existing `actions/checkout@v4` SHA-pinning suggestion (carried over, still non-blocking) and L4. |

**Overall score: 8.9 / 10**

A strong release with the codebase's first genuinely new attack surface (user-supplied `--prefix`, user-editable config file, archive extraction) — and it holds up under adversarial testing. The score is capped below Day 4's 9.1 by one High finding (H1) that both independent reviewers converged on from different angles, plus two Medium defense-in-depth gaps (M1, M2) that are real but neither currently exploitable nor release-blocking in this project's actual (single-user, local, non-adversarial-network) usage model.

---

## 6. Strongest Three Areas

1. **Configuration security (10/10)** — the "never sourced or eval'd" guarantee is structural, not incidental: one regex both classifies and extracts each line via `BASH_REMATCH`, every value is checked against a validator (`is_one_of`/`is_positive_integer`) and never expanded, and this review's own live adversarial testing (command substitution, backticks, semicolon-chaining) against `config validate` produced zero executions and zero marker files created, matching what the Bats suite's own canary-based tests already proved.
2. **JSON correctness (10/10)** — both `--format json` commands produced valid JSON under `python3 -m json.tool` on every attempt in this review, with correct numeric/string typing and no log-output contamination; `json_escape`'s backslash-first escaping order is a small but easy-to-get-wrong detail that was implemented, documented, and tested correctly.
3. **Uninstall safety (9/10)** — the manifest-as-sole-authority design (no manifest → no-op exit 0; prefix mismatch → refuse; every removal individually checked against the prefix before `rm -f --`, never a bulk `rm -rf` on anything user-derived) was independently confirmed live against three adversarial scenarios (no manifest, mismatched prefix, unrelated launcher file) with zero unintended deletions in any case.

---

## 7. Five Highest-Priority Improvements

1. **Fix H1 — normalize permissions to git's tracked index mode in `package.sh` and `install.sh`** rather than trusting `cp -a`'s filesystem-observed bits. This is the single highest-leverage fix: it closes a real world-writable-install exposure and restores the cross-machine reproducibility guarantee the documentation already claims.
2. **Close M2 — add an explicit tar member-type/symlink check to `verify-package.sh`**, plus a dedicated regression test, so the archive-safety guarantee doesn't implicitly depend on which `tar` implementation happens to be extracting it.
3. **Tighten M1 — scope `uninstall.sh`'s removal guard to `$LIB_DIR` instead of `$PREFIX`**, matching what the manifest actually ever contains and shrinking the blast radius of any future manifest-format bug.
4. **Extend `stub_shadow_path_except` to support forced fake output, not just omission**, so `doctor.sh`'s non-Linux and Bash-`<4` branches become independently testable rather than permanently unreachable under CI.
5. **Resolve L4 (network script `Version:` header drift, carried over from Day 3/4) and the Day 3-era `actions/checkout@v4` SHA-pinning suggestion together** the next time either area is touched — both are small, well-understood, and already tracked in `docs/roadmap.md`.

---

## 8. Unresolved Release Blockers

**None that block tagging v0.4.0 as-is for this project's actual usage model** (single-user, local, `$HOME`-scoped installs on developer machines) — but **H1 is a recommended pre-tag fix, not merely a future enhancement**, given that it was independently reached by two separate review methods and directly undermines a guarantee already stated in this release's own `CHANGELOG.md` and `docs/architecture.md`. If v0.4.0 is tagged before H1 is addressed, the release notes should caveat the reproducible-build claim as "verified single-machine, same-`core.fileMode`-setting only" until fixed. M1 and M2 are real but do not, on their own or together, rise to blocking severity — see Findings for reasoning.

This review made **no code changes**, per its own scope (implementation files were not modified); all findings above are therefore unresolved pending a follow-up change.

---

## 9. Final v0.4.0 Readiness Recommendation

**Ready to tag v0.4.0, with H1 flagged as a strongly recommended fix-forward (either immediately pre-tag, or as the very first Day 6 commit).**

All four required release-gate commands (`make quality`, `make package`, `make verify-package`, `make smoke-install`) passed cleanly, 238/238 Bats tests are green, both new JSON-emitting commands produce valid JSON under `python3 -m json.tool`, and every adversarial scenario specified for this review — command substitution and shell metacharacters in config values, duplicate/unknown/malformed config keys, unsafe and metacharacter-laden install prefixes, an unrelated file at the launcher path, uninstall against an unverified directory, and a tampered/traversal-crafted release archive — was independently reproduced live and handled safely, with zero unintended executions, zero unintended deletions, and zero unintended overwrites in every case. Two independent specialized reviews (release-engineer and bash-test-engineer), run from scratch without access to each other's conclusions, converged on the same short list of non-critical gaps, which is itself a positive signal about the review's reliability. The one High finding (H1, permission propagation via `cp -a`) is well-understood, narrowly scoped, and has a clear one-line-per-callsite fix direction that does not require redesigning any of this release's genuinely new, well-tested safety architecture.
