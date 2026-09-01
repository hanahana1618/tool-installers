#!/usr/bin/env bash
#
# install-gh.sh
#
# Installs the GitHub CLI (gh) on Debian/Ubuntu-family Linux (including
# derivatives like Pop!_OS) via GitHub's official apt repository, with
# integrity verification of the signing keyring before it's trusted.
#
# Two independent checks are run on the downloaded keyring before it's
# installed into apt's keyring directory:
#
#   1. SHA256 checksum - GitHub officially publishes this checksum for
#      the keyring file in their own install docs
#      (https://github.com/cli/cli/blob/trunk/docs/install_linux.md),
#      so unlike a trust-on-first-use pin, a match here is an authoritative
#      guarantee the bytes are exactly what GitHub shipped, not just that
#      they haven't changed since this script was written:
#      6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b
#
#   2. GPG key fingerprints - the keyring bundles two key pairs (current +
#      a rotation/overlap key), both published in GitHub's install docs
#      above. This script requires *both* documented fingerprints to be
#      present and rejects the key if any *other*, undocumented fingerprint
#      shows up in the file:
#        2C6106201985B60E6C7AC87323F3D4EA75716059
#        7F38BBB59D064DBCB3D84D725612B36462313325
#
# If either check fails, the script aborts and nothing is installed.
#
# Usage:
#   ./install-gh.sh
#
set -euo pipefail

KEY_URL="https://cli.github.com/packages/githubcli-archive-keyring.gpg"
EXPECTED_SHA256="6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b"
EXPECTED_FINGERPRINTS=(
  "2C6106201985B60E6C7AC87323F3D4EA75716059"
  "7F38BBB59D064DBCB3D84D725612B36462313325"
)

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "== Installing GitHub CLI (gh) =="

if command -v gh >/dev/null 2>&1; then
  echo "[INFO] 'gh' is already installed: $(command -v gh) ($(gh --version | head -n1))"
  ans=""
  if [[ -t 0 ]]; then
    read -r -p "Reinstall/refresh anyway? [y/N] " ans
  else
    echo "[INFO] Not an interactive terminal (e.g. piped from curl/wget) -- skipping reinstall."
  fi
  [[ "${ans,,}" == "y" ]] || { echo "Nothing to do."; exit 0; }
fi

for dep in wget gpg apt dpkg; do
  command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: required command '$dep' not found." >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# 1. Download the signing keyring (already a binary/dearmored keyring, not
#    ASCII-armored, per GitHub's own instructions -- no `gpg --dearmor`
#    step needed).
# ---------------------------------------------------------------------------
echo "[STEP] Downloading GitHub CLI keyring from $KEY_URL"
wget -q "$KEY_URL" -O "$WORKDIR/githubcli-archive-keyring.gpg"

# ---------------------------------------------------------------------------
# 2. SHA256 verification against GitHub's officially published checksum
# ---------------------------------------------------------------------------
echo "[STEP] Verifying SHA256 checksum"
ACTUAL_SHA256="$(sha256sum "$WORKDIR/githubcli-archive-keyring.gpg" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "ERROR: SHA256 mismatch!" >&2
  echo "  expected: $EXPECTED_SHA256" >&2
  echo "  actual:   $ACTUAL_SHA256" >&2
  echo "The downloaded keyring does not match GitHub's published checksum. Aborting -- do not proceed." >&2
  exit 1
fi
echo "[PASS] SHA256 matches GitHub's officially published value ($ACTUAL_SHA256)"

# ---------------------------------------------------------------------------
# 3. GPG fingerprint verification: every fingerprint in the file must be one
#    of the documented ones, and both documented ones must be present.
# ---------------------------------------------------------------------------
echo "[STEP] Verifying GPG key fingerprints"
mapfile -t ACTUAL_FINGERPRINTS < <(
  gpg --show-keys --with-fingerprint --with-colons "$WORKDIR/githubcli-archive-keyring.gpg" 2>/dev/null \
    | awk -F: '/^fpr:/{print $10}' | sort -u
)

if [[ ${#ACTUAL_FINGERPRINTS[@]} -eq 0 ]]; then
  echo "ERROR: no GPG fingerprints found in the downloaded keyring." >&2
  exit 1
fi

for fp in "${ACTUAL_FINGERPRINTS[@]}"; do
  known=false
  for expected in "${EXPECTED_FINGERPRINTS[@]}"; do
    [[ "$fp" == "$expected" ]] && { known=true; break; }
  done
  if ! $known; then
    echo "ERROR: unexpected GPG fingerprint in keyring: $fp" >&2
    echo "This key is NOT one of GitHub's documented signing keys. Aborting -- do not proceed." >&2
    exit 1
  fi
done

for expected in "${EXPECTED_FINGERPRINTS[@]}"; do
  found=false
  for fp in "${ACTUAL_FINGERPRINTS[@]}"; do
    [[ "$fp" == "$expected" ]] && { found=true; break; }
  done
  if ! $found; then
    echo "ERROR: expected GitHub CLI signing key not found in keyring: $expected" >&2
    exit 1
  fi
done
echo "[PASS] Keyring contains exactly GitHub's documented signing keys (${ACTUAL_FINGERPRINTS[*]})"

# ---------------------------------------------------------------------------
# 4. Install the verified keyring, add the repo, install the package
# ---------------------------------------------------------------------------
echo "[STEP] Installing keyring to /etc/apt/keyrings/githubcli-archive-keyring.gpg (sudo)"
sudo install -D -o root -g root -m 644 "$WORKDIR/githubcli-archive-keyring.gpg" /etc/apt/keyrings/githubcli-archive-keyring.gpg

echo "[STEP] Adding GitHub CLI apt repository (sudo)"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

echo "[STEP] Updating apt for the GitHub CLI repo only (sudo)"
# Scoped to just github-cli.list so an unrelated broken/misconfigured repo
# elsewhere in /etc/apt/sources.list.d/ can't block this install.
if ! sudo apt-get update \
      -o Dir::Etc::sourcelist="sources.list.d/github-cli.list" \
      -o Dir::Etc::sourceparts="-" \
      -o APT::Get::List-Cleanup="0"; then
  echo "[WARN] Scoped update failed, falling back to a full 'apt update'" >&2
  echo "[WARN] (this may fail loudly if another repo on this system is broken -- that's unrelated to GitHub CLI)" >&2
  sudo apt update
fi

echo "[STEP] Installing 'gh' (sudo)"
sudo apt install -y gh

echo "== Done =="
if command -v gh >/dev/null 2>&1; then
  echo "Installed: $(gh --version | head -n1)"
else
  echo "WARNING: apt install finished but 'gh' was not found on PATH -- check the apt output above." >&2
  exit 1
fi
