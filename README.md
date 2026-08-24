# Tool Installers

Small, verified install scripts for setting up dev tools on Debian/Ubuntu-family
Linux (including derivatives like Pop!_OS).

## What's here

- **`install-vscode.sh`** — installs Visual Studio Code via Microsoft's official
  apt repository. Before trusting anything, it verifies the downloaded
  Microsoft signing key two ways:
  - **SHA256 checksum**, pinned to the hash of the key as fetched directly
    from `packages.microsoft.com` at the time this script was written
    (trust-on-first-use tamper detection — Microsoft doesn't publish an
    official checksum for this file).
  - **GPG key fingerprint**, pinned to the fingerprint Microsoft officially
    publishes at [learn.microsoft.com/en-us/linux/packages](https://learn.microsoft.com/en-us/linux/packages)
    (`BC52 8686 B50D 79E3 39D3 721C EB3E 94AD BE12 29CF`) — this is the
    authoritative identity check.

  If either check fails, the script aborts before anything is installed.

## Usage

```bash
chmod +x install-vscode.sh
./install-vscode.sh
```

Requires `wget`, `gpg`, and `apt`. Prompts for `sudo` only for the steps that
need it (installing the apt key and running `apt install`).

## PATH

The script does not modify `PATH` itself, and doesn't need to. The `code`
`.deb` package's own `postinst` maintainer script handles it:

```bash
rm -f /usr/bin/code
ln -s /usr/share/code/bin/code /usr/bin/code
```

It installs the real binary under `/usr/share/code/bin/code` and symlinks it
to `/usr/bin/code`, which is already on every user's default `PATH` on
Debian/Ubuntu-family systems (including derivatives like Pop!_OS). So once
`apt install -y code` finishes, the `code` command works immediately in any
new terminal — no `~/.bashrc` or `/etc/environment` edits required.

The package also registers `code` with `update-alternatives` as a low-priority
candidate for `/usr/bin/editor` and installs a `.desktop` launcher entry.
Neither of those affects `PATH` either.

## Troubleshooting: "does not have a Release file"

If `apt update` fails with something like:

```
E: The repository 'https://example.com/packages noble Release' does not have a Release file.
```

that's an **unrelated, broken/misconfigured apt repo already on your system**
(commonly leftover from a bad `apt-add-repository <url>` call that guessed the
wrong suite name, or a dead third-party PPA) — not the VS Code repo added by
this script. `apt update` fails the whole run if *any* configured repo errors,
which can block installs that have nothing to do with the broken one.

`install-vscode.sh` works around this by scoping its `apt-get update` call to
only `vscode.list`, so a broken repo elsewhere in
`/etc/apt/sources.list.d/` won't block it. If you still hit the error (e.g. on
the fallback full `apt update`), find and remove/fix the offending file:

```bash
for f in /etc/apt/sources.list.d/*.list; do echo "== $f =="; cat "$f"; done
sudo rm /etc/apt/sources.list.d/<bad-file>.list
sudo apt update
```
