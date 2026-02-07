#!/usr/bin/env bash
# yubikey-unlock.sh -- Unlock the Pi's LUKS volume remotely using a local YubiKey
#
# This script runs on your LOCAL machine (not the Pi). It:
#   1. Reads the saved salt for the target Pi
#   2. Sends the salt as an HMAC-SHA1 challenge to the local YubiKey
#   3. SSHes to the Pi's initrd and pipes the derived key to /bin/yk-unlock
#
# Prerequisites:
#   - yubikey-personalization (provides ykchalresp)
#     Available in the flake devShell: nix develop
#   - YubiKey enrolled via yubikey-enroll.sh
#   - The Pi must be in the initrd stage (waiting for LUKS passphrase)
#
# Usage:
#   ./scripts/yubikey-unlock.sh <hostname> [pi-ip-or-hostname]
#
# Example:
#   ./scripts/yubikey-unlock.sh px5n0 10.13.12.249
#
# See docs/secure-boot-guide.md for full documentation.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

SALT_DIR="${HOME}/.config/yk-luks"
YK_SLOT=2
INITRD_SSH_PORT=42069

# ── Argument parsing ─────────────────────────────────────────────────────────

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <hostname> [pi-ip-or-hostname]"
    echo ""
    echo "  hostname            Pi hostname (px5n0, px5n1) -- used for salt lookup"
    echo "  pi-ip-or-hostname   IP or hostname to SSH to (default: same as hostname)"
    exit 1
fi

HOSTNAME="$1"
PI_HOST="${2:-$HOSTNAME}"
SALT_FILE="${SALT_DIR}/${HOSTNAME}.salt"

# ── Preflight checks ─────────────────────────────────────────────────────────

# Check for required tools
if ! command -v ykchalresp &>/dev/null; then
    echo "Error: 'ykchalresp' not found. Enter the devShell with: nix develop" >&2
    exit 1
fi

# Check salt file exists
if [ ! -f "$SALT_FILE" ]; then
    echo "Error: Salt file not found: ${SALT_FILE}" >&2
    echo "Run yubikey-enroll.sh first to set up the YubiKey for this host." >&2
    exit 1
fi

# Check YubiKey is plugged in
if ! command -v ykinfo &>/dev/null || ! ykinfo -s 2>/dev/null | grep -q "serial"; then
    echo "Error: No YubiKey detected. Plug in your YubiKey and try again." >&2
    exit 1
fi

# ── Read salt ────────────────────────────────────────────────────────────────

SALT=$(cat "$SALT_FILE")

if [ -z "$SALT" ]; then
    echo "Error: Salt file is empty: ${SALT_FILE}" >&2
    exit 1
fi

# ── Compute derived key ─────────────────────────────────────────────────────

echo "Computing YubiKey response (touch may be required)..."
DERIVED_KEY=$(printf '%s' "$SALT" | ykchalresp -${YK_SLOT} -H -i-)

if [ -z "$DERIVED_KEY" ]; then
    echo "Error: YubiKey did not return a response." >&2
    exit 1
fi

# ── Send to Pi ───────────────────────────────────────────────────────────────

echo "Sending unlock key to ${PI_HOST}:${INITRD_SSH_PORT}..."

# Pipe the derived key to the yk-unlock helper in the Pi's initrd.
# -o StrictHostKeyChecking=no: the initrd host key differs from the booted system's key.
# -o UserKnownHostsFile=/dev/null: don't pollute known_hosts with the initrd key.
printf '%s\n' "$DERIVED_KEY" | ssh \
    -p "$INITRD_SSH_PORT" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=10 \
    "root@${PI_HOST}" \
    /bin/yk-unlock

echo "Done. The Pi should continue booting if the key was accepted."
