# Tool Installers

Small, verified install scripts for setting up dev tools on Debian/Ubuntu-family
Linux (including derivatives like Pop!_OS).

Every script here fetches its vendor's signing key straight from an official
vendor URL and verifies it — by SHA256 and by GPG fingerprint — before
trusting it with anything. If a check fails, the script aborts and installs
nothing.

## What's here

- **`install-vscode.sh`** — Visual Studio Code, via Microsoft's official apt
  repository.
  - **SHA256**: pinned to the hash of the key as fetched from
    `packages.microsoft.com` at the time this script was written
    (trust-on-first-use — Microsoft doesn't publish an official checksum for
    this file).
  - **GPG fingerprint**: pinned to the fingerprint Microsoft officially
    publishes at [learn.microsoft.com/en-us/linux/packages](https://learn.microsoft.com/en-us/linux/packages)
    (`BC52 8686 B50D 79E3 39D3 721C EB3E 94AD BE12 29CF`) — the authoritative
    check.

- **`install-docker.sh`** — Docker Engine (`docker-ce`, `docker-ce-cli`,
  `containerd.io`, buildx + compose plugins), via Docker's official apt
  repository. Auto-detects Ubuntu- vs Debian-based systems from
  `/etc/os-release` and uses the matching repo.
  - **SHA256**: pinned to the hash of the key as fetched from
    `download.docker.com` at the time this script was written
    (trust-on-first-use — Docker doesn't publish an official checksum either).
  - **GPG fingerprint**: pinned to the well-known "Docker Release (CE deb)"
    key (`9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`) — the
    authoritative check.

- **`install-gh.sh`** — GitHub CLI (`gh`), via GitHub's official apt
  repository.
  - **SHA256**: `6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b`
    — GitHub officially publishes this checksum in their own
    [install docs](https://github.com/cli/cli/blob/trunk/docs/install_linux.md),
    so this is a real authoritative match, not just trust-on-first-use.
  - **GPG fingerprints**: the keyring bundles two keys (current + a
    rotation/overlap key), both documented in the same install docs. The
    script requires both to be present and rejects any undocumented
    fingerprint found in the file.

## Usage

```bash
chmod +x install-vscode.sh && ./install-vscode.sh
chmod +x install-docker.sh && ./install-docker.sh
chmod +x install-gh.sh     && ./install-gh.sh
```

Each script prompts for `sudo` only for the steps that need it (installing
the apt key and running `apt install`). If a tool is already installed, the
script asks whether to reinstall/refresh — except when run non-interactively
(e.g. piped from `curl`/`wget`, or in CI), where it skips the reinstall and
exits cleanly instead of hanging or aborting on a `read` with no stdin.

| Script              | Requires                  |
|---------------------|----------------------------|
| `install-vscode.sh` | `wget`, `gpg`, `apt`       |
| `install-docker.sh` | `curl`, `gpg`, `apt`       |
| `install-gh.sh`     | `wget`, `gpg`, `apt`, `dpkg` |

## PATH

None of these scripts touch `PATH` themselves, and none need to — each
vendor's `.deb` package handles its own binary placement via its `postinst`
maintainer script, symlinking into a directory already on the default
Debian/Ubuntu `PATH` (`/usr/bin`). So `code`, `docker`, and `gh` all work
immediately in any new terminal after install, with no `~/.bashrc` or
`/etc/environment` edits required.

For VS Code specifically: the package installs the real binary under
`/usr/share/code/bin/code` and symlinks it to `/usr/bin/code`. It also
registers `code` with `update-alternatives` as a low-priority candidate for
`/usr/bin/editor` and installs a `.desktop` launcher entry — neither of which
affects `PATH`.

For Docker: `docker-ce-cli` installs `/usr/bin/docker` directly. If you want
to run `docker` without `sudo`, add yourself to the `docker` group and
re-login (the script prints this hint if you're not already in it):

```bash
sudo usermod -aG docker $USER
```

## Troubleshooting: "does not have a Release file"

If `apt update` fails with something like:

```
E: The repository 'https://example.com/packages noble Release' does not have a Release file.
```

that's an **unrelated, broken/misconfigured apt repo already on your system**
(commonly leftover from a bad `apt-add-repository <url>` call that guessed the
wrong suite name, or a dead third-party PPA) — not a repo added by any script
here. `apt update` fails the whole run if *any* configured repo errors, which
can block installs that have nothing to do with the broken one.

Every script here works around this by scoping its own `apt-get update` call
to just the `.list` file it added (`vscode.list`, `docker.list`, or
`github-cli.list`), so a broken repo elsewhere in `/etc/apt/sources.list.d/`
won't block it. If you still hit the error (e.g. on the fallback full
`apt update`), find and remove/fix the offending file:

```bash
for f in /etc/apt/sources.list.d/*.list; do echo "== $f =="; cat "$f"; done
sudo rm /etc/apt/sources.list.d/<bad-file>.list
sudo apt update
```
