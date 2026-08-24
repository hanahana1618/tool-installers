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
