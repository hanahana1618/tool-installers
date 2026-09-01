#!/usr/bin/env bash
#
# install-docker.sh
#
# Installs Docker Engine (docker-ce, docker-ce-cli, containerd.io, the
# buildx and compose plugins) on Debian/Ubuntu-family Linux (including
# derivatives like Pop!_OS) via Docker's official apt repository, with
# integrity verification of the signing key before it's trusted.
#
# The repo URL differs by upstream base (download.docker.com/linux/ubuntu
# vs .../debian), so this script detects the base distro from
# /etc/os-release and picks the matching one. Both endpoints currently
# serve the byte-identical key file, so a single pinned SHA256 covers
# either.
#
# Two independent checks are run on the downloaded key before it's
# installed into apt's keyring:
#
#   1. SHA256 checksum - pinned below to the hash of the file as fetched
#      directly from https://download.docker.com/linux/{ubuntu,debian}/gpg
#      on 2026-09-01. Docker does not publish an official checksum for
#      this file, so this is trust-on-first-use tamper detection: it
#      confirms the file hasn't changed since this script was written,
#      not that Docker "signed" the hash itself.
#
#   2. GPG key fingerprint - pinned to the fingerprint of the well-known
#      "Docker Release (CE deb) <docker@docker.com>" key:
#      9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88
#      This is the authoritative check -- it confirms the key itself is
#      cryptographically the one Docker signs its apt packages with,
#      independent of exact file bytes/whitespace. (The key file also
#      carries one signing subkey under the same primary key -- that's
#      normal GPG structure, not a second untrusted identity.)
#
# If either check fails, or the base distro can't be determined, the
# script aborts and nothing is installed.
#
# Usage:
#   ./install-docker.sh
#
set -euo pipefail

EXPECTED_SHA256="1500c1f56fa9e26b9b8f42452a553675796ade0807cdce11975eb98170b3a570"
EXPECTED_FINGERPRINT="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "== Installing Docker Engine =="

if command -v docker >/dev/null 2>&1; then
  echo "[INFO] 'docker' is already installed: $(command -v docker) ($(docker --version))"
  ans=""
  if [[ -t 0 ]]; then
    read -r -p "Reinstall/refresh anyway? [y/N] " ans
  else
    echo "[INFO] Not an interactive terminal (e.g. piped from curl/wget) -- skipping reinstall."
  fi
  [[ "${ans,,}" == "y" ]] || { echo "Nothing to do."; exit 0; }
fi

for dep in curl gpg apt; do
  command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: required command '$dep' not found." >&2; exit 1; }
done

# ---------------------------------------------------------------------------
# 1. Determine the upstream base distro (Docker publishes separate repos
#    for Ubuntu and Debian; derivatives report which one they're built on
#    via ID / ID_LIKE in /etc/os-release).
# ---------------------------------------------------------------------------
[[ -r /etc/os-release ]] || { echo "ERROR: /etc/os-release not found -- cannot determine distro." >&2; exit 1; }
# shellcheck source=/dev/null
source /etc/os-release

DISTRO_BASE=""
case " ${ID:-} ${ID_LIKE:-} " in
  *" ubuntu "*) DISTRO_BASE="ubuntu" ;;
  *" debian "*) DISTRO_BASE="debian" ;;
esac

if [[ -z "$DISTRO_BASE" ]]; then
  echo "ERROR: could not determine whether this system is Ubuntu-based or Debian-based" >&2
  echo "  (ID='${ID:-}', ID_LIKE='${ID_LIKE:-}')." >&2
  echo "This script only supports Debian/Ubuntu-family Linux. Aborting." >&2
  exit 1
fi
echo "[INFO] Detected $DISTRO_BASE-based system (ID='${ID:-}', ID_LIKE='${ID_LIKE:-}')"

KEY_URL="https://download.docker.com/linux/${DISTRO_BASE}/gpg"
REPO_URL="https://download.docker.com/linux/${DISTRO_BASE}"

# ---------------------------------------------------------------------------
# 2. Download the signing key
# ---------------------------------------------------------------------------
echo "[STEP] Downloading Docker signing key from $KEY_URL"
curl -fsSL "$KEY_URL" -o "$WORKDIR/docker.asc"

# ---------------------------------------------------------------------------
# 3. SHA256 verification (tamper detection against the pinned hash)
# ---------------------------------------------------------------------------
echo "[STEP] Verifying SHA256 checksum"
ACTUAL_SHA256="$(sha256sum "$WORKDIR/docker.asc" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]]; then
  echo "ERROR: SHA256 mismatch!" >&2
  echo "  expected: $EXPECTED_SHA256" >&2
  echo "  actual:   $ACTUAL_SHA256" >&2
  echo "The downloaded key does not match what this script expects. Aborting -- do not proceed." >&2
  exit 1
fi
echo "[PASS] SHA256 matches pinned value ($ACTUAL_SHA256)"

# ---------------------------------------------------------------------------
# 4. GPG fingerprint verification (the authoritative identity check)
# ---------------------------------------------------------------------------
echo "[STEP] Verifying GPG key fingerprint"
ACTUAL_FINGERPRINT="$(gpg --show-keys --with-fingerprint --with-colons "$WORKDIR/docker.asc" 2>/dev/null \
  | awk -F: '/^fpr:/{print $10; exit}')"
if [[ "$ACTUAL_FINGERPRINT" != "$EXPECTED_FINGERPRINT" ]]; then
  echo "ERROR: GPG fingerprint mismatch!" >&2
  echo "  expected: $EXPECTED_FINGERPRINT" >&2
  echo "  actual:   ${ACTUAL_FINGERPRINT:-<none found>}" >&2
  echo "This key is NOT the official Docker signing key. Aborting -- do not proceed." >&2
  exit 1
fi
echo "[PASS] GPG fingerprint matches Docker's official key ($ACTUAL_FINGERPRINT)"

# ---------------------------------------------------------------------------
# 5. Install the verified key, add the repo, install the packages
# ---------------------------------------------------------------------------
echo "[STEP] Installing key to /etc/apt/keyrings/docker.asc (sudo)"
sudo install -D -o root -g root -m 644 "$WORKDIR/docker.asc" /etc/apt/keyrings/docker.asc

ARCH="$(dpkg --print-architecture)"
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
if [[ -z "$CODENAME" ]]; then
  echo "ERROR: could not determine release codename from /etc/os-release." >&2
  exit 1
fi

echo "[STEP] Adding Docker apt repository for $DISTRO_BASE/$CODENAME ($ARCH) (sudo)"
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] ${REPO_URL} ${CODENAME} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[STEP] Updating apt for the Docker repo only (sudo)"
# Scoped to just docker.list so an unrelated broken/misconfigured repo
# elsewhere in /etc/apt/sources.list.d/ can't block this install.
if ! sudo apt-get update \
      -o Dir::Etc::sourcelist="sources.list.d/docker.list" \
      -o Dir::Etc::sourceparts="-" \
      -o APT::Get::List-Cleanup="0"; then
  echo "[WARN] Scoped update failed, falling back to a full 'apt update'" >&2
  echo "[WARN] (this may fail loudly if another repo on this system is broken -- that's unrelated to Docker)" >&2
  sudo apt update
fi

echo "[STEP] Installing Docker Engine packages (sudo)"
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "== Done =="
if command -v docker >/dev/null 2>&1; then
  echo "Installed: $(docker --version)"
  if ! groups "$USER" | grep -qw docker; then
    echo ""
    echo "[INFO] To run docker without sudo, add yourself to the 'docker' group and re-login:"
    echo "  sudo usermod -aG docker \$USER"
  fi
else
  echo "WARNING: apt install finished but 'docker' was not found on PATH -- check the apt output above." >&2
  exit 1
fi
