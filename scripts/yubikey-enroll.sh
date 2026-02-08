#!/usr/bin/env bash
# yubikey-enroll.sh -- One-time setup for YubiKey challenge-response LUKS unlock
#
# This script runs on your LOCAL machine (not the Pi). It:
#   1. Optionally programs YubiKey slot 2 for HMAC-SHA1 challenge-response
#   2. Generates a random salt (challenge)
#   3. Computes the derived key using the local YubiKey
#   4. SSHes to the Pi and enrolls the derived key as a LUKS key slot
#   5. Saves the salt locally for use by yubikey-unlock.sh
#
# Prerequisites:
#   - yubikey-personalization (provides ykchalresp, ykpersonalize)
#     Available in the flake devShell: nix develop
#   - YubiKey 5 series (or any YubiKey with HMAC-SHA1 challenge-response)
#   - The Pi must be fully booted (not in initrd) and reachable via SSH on port 22
#
# Usage:
#   ./scripts/yubikey-enroll.sh <hostname> [pi-ip-or-hostname]
#
# Example:
#   ./scripts/yubikey-enroll.sh px5n0 10.13.12.249
#
# See docs/secure-boot-guide.md for full documentation.

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

LUKS_DEVICE="/dev/disk/by-partlabel/disk-sd-system"
SALT_DIR="${HOME}/.config/yk-luks"
SALT_LENGTH=64  # bytes of randomness for the challenge (128 hex chars)
YK_SLOT=2       # YubiKey slot for HMAC-SHA1 challenge-response

# ── Argument parsing ─────────────────────────────────────────────────────────

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <hostname> [pi-ip-or-hostname]"
    echo ""
    echo "  hostname            Pi hostname (px5n0, px5n1) -- used for salt filename"
    echo "  pi-ip-or-hostname   IP or hostname to SSH to (default: same as hostname)"
    exit 1
fi

HOSTNAME="$1"
PI_HOST="${2:-$HOSTNAME}"
SALT_FILE="${SALT_DIR}/${HOSTNAME}.salt"

# ── Preflight checks ─────────────────────────────────────────────────────────

echo "=== YubiKey Challenge-Response LUKS Enrollment ==="
echo ""
echo "  Pi hostname:   ${HOSTNAME}"
echo "  Pi SSH target: ${PI_HOST} (port 22)"
echo "  LUKS device:   ${LUKS_DEVICE}"
echo "  Salt file:     ${SALT_FILE}"
echo "  YubiKey slot:  ${YK_SLOT}"
echo ""

# Check for required tools
for cmd in ykchalresp ykinfo ssh openssl; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: '$cmd' not found. Enter the devShell with: nix develop" >&2
        exit 1
    fi
done

# Check YubiKey is plugged in
if ! ykinfo -s 2>/dev/null | grep -q "serial"; then
    echo "Error: No YubiKey detected. Plug in your YubiKey and try again." >&2
    exit 1
fi

echo "YubiKey detected: $(ykinfo -s 2>/dev/null | tr -d '\n')"
echo ""

# ── Step 1: Program YubiKey slot (optional) ──────────────────────────────────

# Check if slot 2 is already configured for challenge-response
if ykinfo -2 2>/dev/null | grep -q "Slot 2"; then
    echo "YubiKey slot ${YK_SLOT} is already programmed."
    read -rp "Reprogram slot ${YK_SLOT} for HMAC-SHA1 challenge-response? (y/N): " reprogram
    if [[ "${reprogram,,}" == "y" ]]; then
        echo ""
        echo "WARNING: This will overwrite the existing slot ${YK_SLOT} configuration."
        echo "If another service uses this slot, it will stop working."
        read -rp "Type 'yes' to confirm: " confirm
        if [ "$confirm" != "yes" ]; then
            echo "Aborted." >&2
            exit 1
        fi
        echo "Programming YubiKey slot ${YK_SLOT} for HMAC-SHA1 challenge-response..."
        ykpersonalize -${YK_SLOT} -ochal-resp -ochal-hmac -ohmac-lt64 -oserial-api-visible
        echo "Slot ${YK_SLOT} programmed successfully."
    else
        echo "Keeping existing slot ${YK_SLOT} configuration."
    fi
else
    echo "YubiKey slot ${YK_SLOT} is not configured."
    read -rp "Program slot ${YK_SLOT} for HMAC-SHA1 challenge-response? (Y/n): " program
    if [[ "${program,,}" != "n" ]]; then
        echo "Programming YubiKey slot ${YK_SLOT} for HMAC-SHA1 challenge-response..."
        ykpersonalize -${YK_SLOT} -ochal-resp -ochal-hmac -ohmac-lt64 -oserial-api-visible
        echo "Slot ${YK_SLOT} programmed successfully."
    else
        echo "Skipping slot programming. Make sure slot ${YK_SLOT} is set up for HMAC-SHA1."
    fi
fi

echo ""

# ── Step 2: Generate salt ────────────────────────────────────────────────────

if [ -f "$SALT_FILE" ]; then
    echo "Existing salt found at: ${SALT_FILE}"
    read -rp "Generate a new salt? This will invalidate the old enrollment. (y/N): " newsalt
    if [[ "${newsalt,,}" == "y" ]]; then
        # Back up old salt
        cp "$SALT_FILE" "${SALT_FILE}.bak.$(date +%Y%m%d%H%M%S)"
        SALT=$(openssl rand -hex "$SALT_LENGTH")
        echo "New salt generated."
    else
        SALT=$(cat "$SALT_FILE")
        echo "Using existing salt."
    fi
else
    SALT=$(openssl rand -hex "$SALT_LENGTH")
    echo "Generated new salt (${SALT_LENGTH} bytes / $((SALT_LENGTH * 2)) hex chars)."
fi

echo ""

# ── Step 3: Compute derived key ──────────────────────────────────────────────

echo "Computing HMAC-SHA1 response from YubiKey (touch may be required)..."
DERIVED_KEY=$(printf '%s' "$SALT" | ykchalresp -${YK_SLOT} -H -i-)

if [ -z "$DERIVED_KEY" ]; then
    echo "Error: YubiKey did not return a response." >&2
    exit 1
fi

echo "Derived key computed (${#DERIVED_KEY} hex chars)."
echo ""

# ── Step 4: Enroll in LUKS on the Pi ─────────────────────────────────────────

echo "Enrolling derived key in LUKS on ${PI_HOST}..."
echo ""
echo "You will be prompted for the Pi's CURRENT LUKS passphrase to authorize"
echo "adding the new key slot."
echo ""

# Write derived key to a temp file on the Pi, enroll it, then clean up.
# The -t flag ensures we get an interactive terminal for the passphrase prompt.
ssh -t "root@${PI_HOST}" bash -c "'
    set -euo pipefail
    tmpkey=\$(mktemp /tmp/yk-luks-key.XXXXXX)
    trap \"rm -f \$tmpkey\" EXIT
    printf \"%s\" \"${DERIVED_KEY}\" > \"\$tmpkey\"
    echo \"Adding new LUKS key slot...\"
    cryptsetup luksAddKey ${LUKS_DEVICE} \"\$tmpkey\"
    echo \"\"
    echo \"LUKS key slot enrolled successfully.\"
'"

echo ""

# ── Step 5: Save salt locally ────────────────────────────────────────────────

mkdir -p "$SALT_DIR"
chmod 700 "$SALT_DIR"
printf '%s' "$SALT" > "$SALT_FILE"
chmod 600 "$SALT_FILE"

echo "Salt saved to: ${SALT_FILE}"
echo ""

# ── Done ─────────────────────────────────────────────────────────────────────

echo "=== Enrollment complete ==="
echo ""
echo "To unlock the Pi remotely after reboot:"
echo "  ./scripts/yubikey-unlock.sh ${HOSTNAME} ${PI_HOST}"
echo ""
echo "IMPORTANT:"
echo "  - Keep your YubiKey safe. Without it, you cannot compute the derived key."
echo "  - The original LUKS passphrase still works as a fallback."
echo "  - The salt at ${SALT_FILE} is needed for unlock. Back it up securely."
echo "  - To remove this enrollment, use: cryptsetup luksKillSlot on the Pi."
