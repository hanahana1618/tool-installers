#!/usr/bin/env bash
#
# install-vscode.sh
#
# Installs Visual Studio Code on Debian/Ubuntu-family Linux (including
# derivatives like Pop!_OS) via Microsoft's official apt repository,
# with integrity verification of the signing key before it's trusted.
#
# Two independent checks are run on the downloaded key before it's
# installed into apt's keyring:
#
#   1. SHA256 checksum - pinned below to the hash of the file as fetched
#      directly from https://packages.microsoft.com/keys/microsoft.asc
#      on 2026-08-24. Microsoft does not publish an official checksum
#      for this file, so this is trust-on-first-use tamper detection:
#      it confirms the file hasn't changed since this script was
#      written, not that Microsoft "signed" the hash itself.
#
#   2. GPG key fingerprint - pinned to the fingerprint Microsoft
#      officially publishes in their docs:
#      https://learn.microsoft.com/en-us/linux/packages
#      "Microsoft (Release signing) <gpgsecurity@microsoft.com>"
#      BC52 8686 B50D 79E3 39D3 721C EB3E 94AD BE12 29CF
#      This is the authoritative check -- it confirms the key itself is
#      cryptographically the one Microsoft says it is, independent of
#      exact file bytes/whitespace.
#
# If either check fails, the script aborts and nothing is installed.
#
# Usage:
#   ./install-vscode.sh
#
set -euo pipefail

KEY_URL="https://packages.microsoft.com/keys/microsoft.asc"
EXPECTED_SHA256="2fa9c05d591a1582a9aba276272478c262e95ad00acf60eaee1644d93941e3c6"
EXPECTED_FINGERPRINT="BC528686B50D79E339D3721CEB3E94ADBE1229CF"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "== Installing Visual Studio Code =="

if command -v code >/dev/null 2>&1; then
  echo "[INFO] 'code' is already installed: $(command -v code) ($(code --version | head -n1))"
  ans=""
  if [[ -t 0 ]]; then
    read -r -p "Reinstall/refresh anyway? [y/N] " ans
  else
    echo "[INFO] Not an interactive terminal (e.g. piped from curl/wget) -- skipping reinstall."
  fi
  [[ "${ans,,}" == "y" ]] || { echo "Nothing to do."; exit 0; }
fi

for dep in wget gpg apt; do
  command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: required command '$dep' not found." >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# 1. Download the signing key
# ---------------------------------------------------------------------------
echo "[STEP] Downloading Microsoft signing key from $KEY_URL"
wget -q "$KEY_URL" -O "$WORKDIR/microsoft.asc"

# ---------------------------------------------------------------------------
# 2. SHA256 verification (tamper detection against the pinned hash)
# ---------------------------------------------------------------------------
echo "[STEP] Verifying SHA256 checksum"
ACTUAL_SHA256="$(sha256sum "$WORKDIR/microsoft.asc" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "ERROR: SHA256 mismatch!" >&2
  echo "  expected: $EXPECTED_SHA256" >&2
  echo "  actual:   $ACTUAL_SHA256" >&2
  echo "The downloaded key does not match what this script expects. Aborting -- do not proceed." >&2
  exit 1
fi
echo "[PASS] SHA256 matches pinned value ($ACTUAL_SHA256)"

# ---------------------------------------------------------------------------
# 3. GPG fingerprint verification (the authoritative identity check)
# ---------------------------------------------------------------------------
echo "[STEP] Verifying GPG key fingerprint"
ACTUAL_FINGERPRINT="$(gpg --show-keys --with-fingerprint --with-colons "$WORKDIR/microsoft.asc" 2>/dev/null \
  | awk -F: '/^fpr:/{print $10; exit}')"
if [[ "$ACTUAL_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]]; then
  echo "ERROR: GPG fingerprint mismatch!" >&2
  echo "  expected: $EXPECTED_FINGERPRINT" >&2
  echo "  actual:   ${ACTUAL_FINGERPRINT:-<none found>}" >&2
  echo "This key is NOT the official Microsoft signing key. Aborting -- do not proceed." >&2
  exit 1
fi
echo "[PASS] GPG fingerprint matches Microsoft's published key ($ACTUAL_FINGERPRINT)"

# ---------------------------------------------------------------------------
# 4. Install the verified key, add the repo, install the package
# ---------------------------------------------------------------------------
echo "[STEP] Dearmoring key"
gpg --dearmor < "$WORKDIR/microsoft.asc" > "$WORKDIR/packages.microsoft.gpg"

echo "[STEP] Installing key to /etc/apt/keyrings/packages.microsoft.gpg (sudo)"
sudo install -D -o root -g root -m 644 "$WORKDIR/packages.microsoft.gpg" /etc/apt/keyrings/packages.microsoft.gpg

echo "[STEP] Adding VS Code apt repository (sudo)"
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
  | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

echo "[STEP] Updating apt for the VS Code repo only (sudo)"
# Scoped to just vscode.list so an unrelated broken/misconfigured repo
# elsewhere in /etc/apt/sources.list.d/ (e.g. a bad third-party PPA) can't
# block this install. Falls back to a full 'apt update' if that ever fails.
if ! sudo apt-get update \
      -o Dir::Etc::sourcelist="sources.list.d/vscode.list" \
      -o Dir::Etc::sourceparts="-" \
      -o APT::Get::List-Cleanup="0"; then
  echo "[WARN] Scoped update failed, falling back to a full 'apt update'" >&2
  echo "[WARN] (this may fail loudly if another repo on this system is broken -- that's unrelated to VS Code)" >&2
  sudo apt update
fi

echo "[STEP] Installing 'code' (sudo)"
sudo apt install -y code

echo "== Done =="
if command -v code >/dev/null 2>&1; then
  echo "Installed: $(code --version | head -n1)"
else
  echo "WARNING: apt install finished but 'code' was not found on PATH -- check the apt output above." >&2
  exit 1
fi
