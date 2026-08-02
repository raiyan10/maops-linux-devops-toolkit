# Installing From a Release Archive

This walks through installing MAOps from a downloaded release tarball
instead of a Git checkout — download, verify, extract, install, and
confirm — plus exactly what each verification step does and does not
prove.

If you already have a Git checkout, [docs/quickstart.md](quickstart.md) is
the simpler path; this document is for anyone starting from a release
asset only.

## 1. Download the Tarball and Its Checksum

Each release publishes two files with a matching version number:

```text
maops-linux-devops-toolkit-X.Y.Z.tar.gz
maops-linux-devops-toolkit-X.Y.Z.tar.gz.sha256
```

Download both from this repository's **Releases** page (GitHub →
**Releases** tab) into the same directory. Substitute the actual version
number you want — for example `maops-linux-devops-toolkit-1.0.0.tar.gz`.

## 2. Verify the Checksum

This is the primary, always-available pre-extraction safety check — it
needs only `sha256sum`, not `python3`:

```bash
cd /path/to/download/directory
sha256sum -c maops-linux-devops-toolkit-X.Y.Z.tar.gz.sha256
```

Expect `maops-linux-devops-toolkit-X.Y.Z.tar.gz: OK`. **Stop here if this
fails** — do not extract an archive that fails its checksum.

## 3. Safe Extraction

```bash
tar -tzf maops-linux-devops-toolkit-X.Y.Z.tar.gz | head -20   # inspect first, optional
tar -xzf maops-linux-devops-toolkit-X.Y.Z.tar.gz
cd maops-linux-devops-toolkit-X.Y.Z
```

The archive has a single top-level directory
(`maops-linux-devops-toolkit-X.Y.Z/`) containing the runtime tree plus
`MAOPS-MANIFEST.tsv` — a `MODE<TAB>SHA256<TAB>PATH` line per distributed
file, generated from Git's own tracked content at build time.

## 4. Package Verification (Defense in Depth)

The checksum in step 2 proves the archive's *bytes* are correct. For a
second, independent layer — per-file content/mode verification, plus
rejection of any unsafe archive member type (symlink, hardlink, device,
FIFO, path traversal) — the toolkit ships its own verifier at
`scripts/release/verify-package.sh` inside the archive you just extracted.

There's a chicken-and-egg wrinkle worth understanding: `verify-package.sh`
only becomes available *after* you extract, since it's part of what's
being distributed — it cannot check the archive before you've trusted it
enough to extract it once. Running it after the fact is still meaningful
defense in depth, because it re-extracts the archive into its own private,
temporary snapshot (independent of the extraction you already did in step
3) and performs the full Python-`tarfile` member-safety and manifest
cross-check against that snapshot:

```bash
# From inside the extracted maops-linux-devops-toolkit-X.Y.Z/ directory,
# point it back at the original downloaded archive:
./scripts/release/verify-package.sh /path/to/download/directory/maops-linux-devops-toolkit-X.Y.Z.tar.gz
```

This step requires `python3` (used only for `tarfile` inspection) and is
optional — most users can safely stop after step 2's checksum check for
routine installs.

## 5. Install

```bash
./scripts/install/install.sh
# or, for a custom location:
./scripts/install/install.sh --prefix /opt/maops
```

Installing from an extracted archive is detected automatically: `install.sh`
looks for `MAOPS-MANIFEST.tsv` at the root of what you're installing from
and, when found, verifies every entry's SHA-256 against the manifest
*before* copying anything into the install prefix — a tampered file fails
the install outright rather than being silently installed. No `sudo` is
required; the default prefix is `$HOME/.local`.

## 6. Installed Integrity Check

```bash
maops --version
maops integrity
```

Once installed, `maops integrity` compares the installed tree against
`PREFIX/lib/maops/.integrity-manifest` (a copy of `MAOPS-MANIFEST.tsv`
written at install time) — ongoing local tamper detection, independent of
the one-time install-time check in step 5.

## 7. Upgrade

Download the new version's tarball and checksum, repeat steps 1–4, then:

```bash
./scripts/install/install.sh --force
```

`--force` performs an atomic upgrade: the new version is staged in a
temporary directory first, then swapped into place, with the previous
install removed only after the new one is confirmed live. Your
configuration is never part of this — see "Config Preservation" below.

## 8. Uninstall

```bash
./scripts/install/uninstall.sh --yes
```

Add `--purge-config` to also remove the configuration directory:

```bash
./scripts/install/uninstall.sh --purge-config --yes
```

`uninstall.sh` only ever removes files it can verify against the install
manifest it wrote at install time — it never runs an unrestricted `rm -rf`
against a user-supplied path.

## Config Preservation

Your configuration file lives at
`${XDG_CONFIG_HOME:-$HOME/.config}/maops/config`, structurally outside the
install prefix (`$HOME/.local` or wherever `--prefix` pointed). Neither
`install.sh` (including `--force` upgrades) nor a plain `uninstall.sh`
touches this location — only `uninstall.sh --purge-config` removes it,
explicitly and only when asked.

## The Trust Boundary: SHA-256, MAOPS-MANIFEST.tsv, and Publisher Identity

Three different, non-overlapping things are being verified across the
steps above, and it matters not to conflate them:

1. **The external `.sha256`** (step 2) proves the archive you downloaded is
   byte-for-byte what was produced by whoever ran the build.
2. **`MAOPS-MANIFEST.tsv`** (steps 4–6) proves that, once you trust the
   archive as a whole, each individual distributed file still has its
   expected content and mode — a second, independent layer beyond the
   single whole-archive checksum.
3. **Neither one proves who published the release.** There is no
   cryptographic publisher-identity signing (no GPG, no Sigstore) in this
   project today — see [SECURITY.md](../SECURITY.md) for the full
   explanation and [docs/roadmap.md](roadmap.md) for this being an
   explicit, deliberate post-v1.0 scope boundary. Only download release
   assets from this repository's own Releases page, and treat step 1
   ("where did this file come from") as the part these checksums cannot
   verify for you.
