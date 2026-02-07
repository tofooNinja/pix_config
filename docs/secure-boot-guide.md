# Raspberry Pi 5 -- Secure Boot and LUKS Unlock Guide

This guide covers three layers of boot security for the Raspberry Pi 5 running
NixOS with LUKS-encrypted root:

1. **TPM2 for LUKS auto-unlock** (recommended, primary)
2. **YubiKey FIDO2 for LUKS unlock** (optional, alternative)
3. **RPi5 hardware secure boot** (advanced, optional, irreversible)

---

## Table of Contents

- [Threat Model](#threat-model)
- [Compatible TPM2 Hardware](#compatible-tpm2-hardware)
- [Part 1: TPM2 LUKS Auto-Unlock](#part-1-tpm2-luks-auto-unlock)
  - [How It Works](#how-it-works)
  - [Why PCR Binding Matters](#why-pcr-binding-matters)
  - [Prerequisites](#prerequisites)
  - [Step 1: Install the TPM Module](#step-1-install-the-tpm-module)
  - [Step 2: Verify TPM Detection](#step-2-verify-tpm-detection)
  - [Step 3: Back Up the LUKS Header](#step-3-back-up-the-luks-header)
  - [Step 4: Enroll the TPM](#step-4-enroll-the-tpm)
  - [Step 5: Reboot and Verify](#step-5-reboot-and-verify)
  - [Re-Enrollment After Kernel Updates](#re-enrollment-after-kernel-updates)
  - [Managing Enrollments](#managing-enrollments)
  - [Fallback: Passphrase Unlock](#fallback-passphrase-unlock)
- [Part 2: YubiKey FIDO2 LUKS Unlock (Optional)](#part-2-yubikey-fido2-luks-unlock-optional)
  - [How It Works](#how-it-works-1)
  - [Prerequisites](#prerequisites-1)
  - [Enabling FIDO2 in the NixOS Configuration](#enabling-fido2-in-the-nixos-configuration)
  - [Step 1: Verify Your YubiKey](#step-1-verify-your-yubikey)
  - [Step 2: Enroll the YubiKey](#step-2-enroll-the-yubikey)
  - [Step 3: Reboot and Verify](#step-3-reboot-and-verify)
  - [Enrolling a Backup YubiKey](#enrolling-a-backup-yubikey)
  - [Re-Enrolling a Previously Enrolled YubiKey](#re-enrolling-a-previously-enrolled-yubikey)
- [Part 3: RPi5 Hardware Secure Boot (Advanced)](#part-3-rpi5-hardware-secure-boot-advanced)
  - [Overview](#overview)
  - [Warnings](#warnings)
  - [How RPi5 Secure Boot Works](#how-rpi5-secure-boot-works)
  - [Testing Signed Boot (Non-Destructive)](#testing-signed-boot-non-destructive)
  - [Full Secure Boot Provisioning](#full-secure-boot-provisioning)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Threat Model

Understanding what each layer protects against:

| Threat | LUKS Encryption | TPM2 Auto-Unlock | YubiKey FIDO2 | RPi5 Secure Boot |
|--------|:-:|:-:|:-:|:-:|
| Stolen SD card / disk read | Yes | Yes | Yes | No |
| Brute-force passphrase | Partial | Yes (no passphrase needed) | Yes (hardware-bound) | No |
| Tampered kernel/initramfs | No | Yes (PCR-bound) | No | Yes |
| Evil maid (boot modification) | No | Yes (PCR-bound) | No | Yes |
| Physical device theft (powered off) | Yes | Yes | Yes | Yes |
| Unattended reboot (headless) | No (needs passphrase) | Yes (automatic) | No (needs touch) | N/A |

**Recommendation**: TPM2 is the best choice for headless Raspberry Pi servers --
it provides automatic LUKS unlock on trusted boots and refuses to unseal the key
if the boot chain has been tampered with (via PCR binding). The passphrase
remains as a fallback for recovery.

---

## Compatible TPM2 Hardware

The Raspberry Pi 5 does not have a built-in TPM. You need an external TPM 2.0
module that connects via **SPI on the 40-pin GPIO header**.

> **WARNING: Do NOT buy PC motherboard TPM modules.** Modules designed for
> desktop motherboards (e.g., ASUS, MSI, Gigabyte) use a different pin header
> (typically 12-1 pin or 14-1 pin) that is **physically and electrically
> incompatible** with the Raspberry Pi GPIO. Even if the chip is identical
> (e.g., Infineon SLB 9672), the board will not fit. Only buy modules
> explicitly designed for the Raspberry Pi.

### Compatible Modules

| Module | Chip | Connector | Status | Price (approx.) | Where to Buy |
|--------|------|-----------|--------|-----------------|--------------|
| **LetsTrust TPM** | Infineon SLB 9670 | 2x5 pin GPIO | Available | ~30-42 EUR | [pi3g.com](https://pi3g.com/products/industrial/letstrust-tpm/), [ThePiHut](https://thepihut.com/products/letstrust-tpm-for-raspberry-pi), [Cytron](https://www.cytron.io/p-letstrust-tpm-for-raspberry-pi) |
| **Joy-it TPM Module** | Infineon SLB 9670 | 2x5 pin GPIO | Available | ~30-37 EUR | [Rapid Online](https://www.rapidonline.com/joy-it-raspberry-pi-tpm-module-with-infineon-optiga-slb-9670-00-0808) |
| **Infineon OPTIGA TPM Eval Board** | Infineon SLB 9672 | RPi HAT (40-pin) | Available | ~20-30 EUR | [Mouser](https://eu.mouser.com/new/infineon/infineon-optiga-tpm-slb-9672-raspberry-pi-board/) |
| **Reichelt TPM Module** | Infineon SLB 9670 | 2x5 pin GPIO | Available | ~25 EUR | [reichelt.com](https://www.reichelt.com/de/en/shop/product/raspberry_pi_-_trusted_platform_module_tpm_slb9670-253834) |
| **ANAVI TPM 2.0** | Infineon SLB 9672 | 2x5 pin GPIO | Coming soon (open-source HW) | TBD | [Crowd Supply](https://crowdsupply.com/anavi-technology/anavi-tpm-2-0-for-raspberry-pi) |

All modules use Infineon chips with mainline Linux kernel driver support
(`tpm_tis_spi`). They are functionally identical from a software perspective --
choose based on availability and price.

The **LetsTrust TPM** and **Infineon OPTIGA Eval Board** have the most
community documentation and are the safest choices.

---

## Part 1: TPM2 LUKS Auto-Unlock

### How It Works

```
Boot sequence with TPM2:

  RPi5 firmware
      |
      v
  kernel + initramfs
      |
      v
  systemd-cryptsetup
      |
      +-- TPM2 present?
      |       |
      |   yes |            no
      |       v             v
      |   Unseal key    Ask passphrase
      |   from TPM      via console/SSH
      |       |             |
      |   PCR match?        |
      |    yes / no         |
      |     /     \         |
      |    v       v        |
      |  Unlock  Ask        |
      |  LUKS    passphrase |
      |    |        \       |
      |    v         v      v
      +------- LUKS volume unlocked
                    |
              root filesystem mounted
                    |
              normal boot continues
```

When `tpm2-device=auto` is set in the crypttab, `systemd-cryptsetup` will:

1. Detect the TPM2 device at `/dev/tpmrm0`
2. Attempt to unseal the LUKS key using stored TPM2 policy
3. Verify PCR (Platform Configuration Register) values match the expected state
4. If PCRs match (firmware/kernel untampered), unlock the volume automatically
5. If PCRs mismatch or TPM is absent, fall back to passphrase prompt

The existing passphrase is **never removed** -- it remains as a fallback.

### Why PCR Binding Matters

PCRs are hash measurements of the boot chain stored in the TPM. By binding the
LUKS key to specific PCR values, the TPM will only release the key if:

- The firmware has not been modified
- The kernel has not been replaced
- The boot configuration has not changed

If an attacker swaps the SD card into another Pi or modifies the kernel, the PCR
values will differ and the TPM will refuse to unseal the key.

### Prerequisites

- A **Raspberry Pi-compatible TPM2 module** (see [Compatible Modules](#compatible-modules))
- **LUKS2** volume (the disko configuration enforces this via `--type luks2`)
- **NixOS configuration** already applied with TPM2 support (see `configuration.nix`)
- The Pi must be booted and accessible (SSH or local console)

### Step 1: Install the TPM Module

1. **Power off** the Raspberry Pi completely
2. **Attach the TPM module** to the GPIO header:
   - For 2x5 pin modules (LetsTrust, Joy-it): connect to GPIO pins 17-26
     (SPI0 CE1 by default)
   - For HAT modules (Infineon Eval Board): attach to the full 40-pin header
3. Ensure the module sits flat and pins are aligned correctly
4. **Power on** the Pi

### Step 2: Verify TPM Detection

After booting with the TPM module attached and the NixOS configuration applied:

```bash
# Check if TPM device exists
ls -la /dev/tpm*
# Expected: /dev/tpm0 and /dev/tpmrm0

# Verify TPM is recognized by systemd
systemd-cryptenroll --tpm2-device=list
# Expected: shows the TPM device path

# Check kernel module is loaded
lsmod | grep tpm
# Expected: tpm_tis_spi, tpm_tis_core, tpm

# Detailed TPM info
tpm2_getcap properties-fixed
```

If `/dev/tpm0` does not appear, see [Troubleshooting: TPM not detected](#tpm-not-detected-devtpm0-missing).

### Step 3: Back Up the LUKS Header

**Critical safety step** -- always back up before modifying LUKS key slots:

```bash
sudo cryptsetup luksHeaderBackup /dev/disk/by-partlabel/disk-sd-system \
  --header-backup-file /tmp/luks-header-backup.img

# Copy to a safe off-device location immediately!
scp /tmp/luks-header-backup.img user@other-machine:~/backups/

# Remove local copy after confirming the backup
rm /tmp/luks-header-backup.img
```

### Step 4: Enroll the TPM

Enroll the TPM2 device into the LUKS2 volume:

```bash
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  /dev/disk/by-partlabel/disk-sd-system
```

This will:
1. Ask for the existing LUKS passphrase (to authorize the enrollment)
2. Seal a new LUKS key into the TPM, bound to current PCR values
3. Store the TPM2 token metadata in the LUKS2 header

**Expected output:**

```
Please enter current passphrase for disk /dev/disk/by-partlabel/disk-sd-system: ****
New TPM2 token enrolled as key slot 1.
```

#### Optional: Bind to Specific PCRs

By default, `systemd-cryptenroll` binds to PCR 7 (Secure Boot state). For
stronger binding on the Raspberry Pi, you can specify additional PCRs:

```bash
sudo systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs=0+2+4+7 \
  /dev/disk/by-partlabel/disk-sd-system
```

PCR meanings:
- **PCR 0**: Firmware (EEPROM/bootloader)
- **PCR 2**: Kernel and boot configuration
- **PCR 4**: Boot manager code
- **PCR 7**: Secure Boot state

> **Note**: Binding to more PCRs increases security but requires re-enrollment
> more frequently (after any firmware or kernel update). For the RPi5 where
> kernel updates happen with `nixos-rebuild`, **PCR 7 alone (default) is
> recommended** to reduce re-enrollment frequency.

### Step 5: Reboot and Verify

```bash
sudo reboot
```

If everything is configured correctly:
1. The system boots and reaches `systemd-cryptsetup`
2. The TPM automatically unseals the LUKS key (no interaction required)
3. The root filesystem mounts and boot continues

Check the journal after boot to confirm:

```bash
journalctl -b -u systemd-cryptsetup@crypted.service
```

Look for messages indicating successful TPM2 unlock.

### Re-Enrollment After Kernel Updates

When the kernel or firmware changes (e.g., after `nixos-rebuild switch` with a
new kernel), the PCR values change. The TPM will refuse to unseal the key and
the system will fall back to passphrase unlock.

To re-enroll after an update:

```bash
# Wipe the old TPM enrollment and re-enroll in one step
sudo systemd-cryptenroll \
  --wipe-slot=tpm2 \
  --tpm2-device=auto \
  /dev/disk/by-partlabel/disk-sd-system
```

> **Tip**: You can create a helper script for this and run it after each
> `nixos-rebuild switch` that updates the kernel.

### Managing Enrollments

**List enrolled tokens:**

```bash
sudo cryptsetup luksDump /dev/disk/by-partlabel/disk-sd-system
```

Look for the `Tokens:` section:

```
Tokens:
  0: systemd-tpm2
        tpm2-pcrs: 7
        ...
Keyslots:
  0: luks2       <-- your passphrase
  1: luks2       <-- TPM2 key
```

**Remove TPM2 enrollment:**

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/disk-sd-system
```

**Remove a specific key slot by number:**

```bash
sudo systemd-cryptenroll --wipe-slot=1 /dev/disk/by-partlabel/disk-sd-system
```

### Fallback: Passphrase Unlock

The original LUKS passphrase (key slot 0) is **always preserved**. If the TPM
fails to unseal (PCR mismatch, TPM removed, hardware failure):

- **Local**: The passphrase prompt appears on the connected display
- **Remote**: SSH into the initrd on port 42069 and enter the passphrase:

```bash
ssh -p 42069 root@<pi-ip>
# Then enter passphrase when prompted, or run:
systemd-tty-ask-password-agent
```

---

## Part 2: YubiKey FIDO2 LUKS Unlock (Optional)

This section describes an alternative (or additional) unlock method using a
YubiKey FIDO2 token. This can be used instead of or alongside the TPM2 method.

### How It Works

When `fido2-device=auto` is set in the crypttab, `systemd-cryptsetup` will:

1. Scan USB for any FIDO2 token with an enrolled `hmac-secret`
2. Depending on the enrollment mode:
   - **PIN + touch**: prompt for both (most secure)
   - **Touch only**: prompt for physical touch
   - **Plugged-in only**: unlock automatically if the key is present (headless)
3. Derive the LUKS key using the FIDO2 `hmac-secret` extension
4. If no token is found or authentication fails, fall back to passphrase

### Prerequisites

- **YubiKey 5 series** or any FIDO2 key supporting the `hmac-secret` extension
- **LUKS2** volume (already configured)
- The Pi must be booted and accessible

### Enabling FIDO2 in the NixOS Configuration

The default `configuration.nix` uses `tpm2-device=auto`. To use FIDO2 instead
(or in addition), edit the `crypttabExtraOpts` in `configuration.nix`:

```nix
# For FIDO2 only:
crypttabExtraOpts = [ "fido2-device=auto" ];

# For TPM2 + FIDO2 (either can unlock):
crypttabExtraOpts = [ "tpm2-device=auto" "fido2-device=auto" ];
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake .#<hostname>
```

### Step 1: Verify Your YubiKey

Plug the YubiKey into the Pi and verify it is detected:

```bash
# Check USB devices
lsusb | grep -i yubico

# Verify FIDO2 support
fido2-token -L
```

You should see output like:

```
/dev/hidraw0: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO+CCID)
```

### Step 2: Enroll the YubiKey

Back up the LUKS header first (if not already done):

```bash
sudo cryptsetup luksHeaderBackup /dev/disk/by-partlabel/disk-sd-system \
  --header-backup-file /tmp/luks-header-backup.img
```

Choose an enrollment mode:

**Option A: Plugged-in only (headless, no interaction needed)**

The YubiKey just needs to be present in a USB port. No PIN, no touch.

```bash
sudo systemd-cryptenroll \
  --fido2-device=auto \
  --fido2-with-client-pin=no \
  --fido2-with-user-presence=no \
  /dev/disk/by-partlabel/disk-sd-system
```

**Option B: Touch required (moderate security)**

Requires physical touch of the YubiKey at each boot, but no PIN.

```bash
sudo systemd-cryptenroll \
  --fido2-device=auto \
  --fido2-with-client-pin=no \
  /dev/disk/by-partlabel/disk-sd-system
```

**Option C: PIN + touch (most secure)**

Requires both a FIDO2 PIN and physical touch. Set a PIN first with
`ykman fido access change-pin`.

```bash
sudo systemd-cryptenroll \
  --fido2-device=auto \
  /dev/disk/by-partlabel/disk-sd-system
```

All options will ask for the current LUKS passphrase to authorize enrollment.

### Step 3: Reboot and Verify

```bash
sudo reboot
```

Behavior depends on the enrollment mode chosen:
- **Plugged-in only**: boots automatically if YubiKey is present
- **Touch**: the YubiKey blinks, touch it to unlock
- **PIN + touch**: enter PIN, then touch

Without the YubiKey, the system falls back to the passphrase prompt.

### Enrolling a Backup YubiKey

Enroll a second YubiKey as backup (uses the same flags as the primary):

```bash
sudo systemd-cryptenroll \
  --fido2-device=auto \
  --fido2-with-client-pin=no \
  --fido2-with-user-presence=no \
  /dev/disk/by-partlabel/disk-sd-system
```

Store the backup key in a secure off-site location.

### Re-Enrolling a Previously Enrolled YubiKey

The PIN/touch policy is baked into the FIDO2 credential at enrollment time.
To change the policy (e.g., switch from PIN+touch to plugged-in only), you
must wipe the old enrollment and re-enroll:

```bash
# 1. Wipe old FIDO2 enrollment
sudo systemd-cryptenroll \
  --wipe-slot=fido2 \
  /dev/disk/by-partlabel/disk-sd-system

# 2. Re-enroll with new settings
sudo systemd-cryptenroll \
  --fido2-device=auto \
  --fido2-with-client-pin=no \
  --fido2-with-user-presence=no \
  /dev/disk/by-partlabel/disk-sd-system
```

Both steps will ask for the LUKS passphrase to authorize the operation.

---

## Part 3: RPi5 Hardware Secure Boot (Advanced)

### Overview

The Raspberry Pi 5 (BCM2712) supports hardware-enforced secure boot through:

1. **Signed EEPROM firmware** -- the boot ROM verifies the second-stage firmware
2. **Signed boot images** -- the bootloader verifies `boot.img` + `boot.sig`
3. **OTP fuse programming** -- public key hash burned into one-time-programmable memory

### Warnings

> **OTP fuse programming is IRREVERSIBLE.**
>
> Once you burn the public key hash into the BCM2712 OTP fuses:
> - The device will **only** boot signed firmware and signed boot images
> - If the private key is **lost**, the device is **permanently bricked**
> - There is **no way to undo** this operation
> - This is fundamentally different from x86 secure boot (which can be disabled in BIOS)
>
> **There is no existing NixOS module for RPi5 secure boot.** The integration
> described below requires manual work and must be redone after every
> `nixos-rebuild switch`.

### How RPi5 Secure Boot Works

```
Boot chain (with secure boot enabled):

  BCM2712 Boot ROM
      |
      | verifies signature using OTP public key hash
      v
  EEPROM Firmware (recovery.bin / bootcode5.bin)
      |   - counter-signed with customer private key
      |   - signed with Raspberry Pi key
      |
      | verifies boot.sig against boot.img
      v
  boot.img (ramdisk containing boot partition)
      |   - kernel, initramfs, device trees, config.txt
      |   - packed into a FAT filesystem image
      |   - signed with customer private key -> boot.sig
      |
      v
  Linux kernel + initramfs
      |
      v
  LUKS unlock (TPM2 / passphrase / YubiKey)
      |
      v
  Root filesystem
```

### Testing Signed Boot (Non-Destructive)

You can test the `boot.img` mechanism **without** burning OTP fuses. This
verifies the boot image format works but does **not** enforce signature
verification.

**1. Generate a signing key pair:**

```bash
# On your workstation (not the Pi)
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -pubout -out public.pem
```

**2. Create boot.img from the boot partition:**

```bash
# On the Pi, after a successful nixos-rebuild switch
# Package the boot partition contents into a FAT image
BOOT_SIZE=$(du -sb /boot | cut -f1)
# Add 10% padding
IMG_SIZE=$(( BOOT_SIZE * 110 / 100 ))

dd if=/dev/zero of=/tmp/boot.img bs=1 count=0 seek=$IMG_SIZE
mkfs.vfat /tmp/boot.img
mcopy -i /tmp/boot.img -s /boot/* ::/
```

**3. Sign the boot image:**

```bash
# On your workstation
openssl dgst -sha256 -sign private.pem -out boot.sig boot.img
```

**4. Place on the FIRMWARE partition:**

```bash
sudo cp /tmp/boot.img /boot/firmware/boot.img
sudo cp boot.sig /boot/firmware/boot.sig
```

**5. Enable boot_ramdisk in config.txt:**

Add `boot_ramdisk=1` to the config.txt on the firmware partition. The Pi
firmware will then unpack `boot.img` into memory and boot from it.

> **Note**: This test only proves the boot.img format works. Without OTP fuses
> programmed, signature verification is **not enforced** -- the Pi will boot
> even with an invalid signature.

### Full Secure Boot Provisioning

For production deployment where boot chain integrity must be enforced.

**Requirements:**

- A **separate host machine** running Raspberry Pi OS (Debian, 64-bit)
- USB cable connecting host to the Pi
- The `rpi-sb-provisioner` tool
- The private key generated above

**1. Install rpi-sb-provisioner on the host:**

```bash
# On the provisioning host (NOT the Pi)
git clone https://github.com/raspberrypi/rpi-sb-provisioner.git
cd rpi-sb-provisioner
# Follow the README for installation
```

**2. Prepare the Pi for provisioning:**

- Power off the Pi
- Set the nRPIBOOT jumper (or hold power button before power on)
- Remove EEPROM write protection
- Connect USB from the host to the Pi

**3. Sign the EEPROM firmware:**

```bash
# Using the usbboot tools
cd secure-boot-recovery5
../tools/update-pieeprom.sh -f -k "${KEY_FILE}"
```

The `-f` flag enables firmware counter-signing with your private key.

**4. Flash the signed EEPROM:**

```bash
mkdir -p metadata
../rpiboot -d . -j metadata
```

**5. Verify (before locking):**

Boot the Pi and confirm it works correctly with the signed EEPROM. Check UART
output for signature verification messages.

**6. Lock secure boot (IRREVERSIBLE):**

> **FINAL WARNING**: This step permanently burns the public key hash into OTP
> fuses. The device will never boot unsigned firmware again. If the private key
> is lost, the device becomes e-waste.

Edit `config.txt` in the `secure-boot-recovery5` directory:

```
program_pubkey=1
```

Then re-flash the EEPROM as in step 4.

**7. NixOS integration (ongoing maintenance):**

After every `nixos-rebuild switch`, you must:

1. Rebuild `boot.img` from `/boot` contents
2. Sign it with the private key
3. Place `boot.img` and `boot.sig` on the firmware partition

This can be partially automated with an activation script, but there is no
official NixOS module for this workflow.

---

## Troubleshooting

### TPM not detected (`/dev/tpm0` missing)

**Symptom**: No `/dev/tpm0` or `/dev/tpmrm0` after boot.

**Solutions**:

1. Verify the module is physically connected and properly seated
2. Check kernel messages for TPM errors:
   ```bash
   dmesg | grep -i tpm
   ```
3. Verify the device tree overlay is active:
   ```bash
   ls /proc/device-tree/soc/spi*/tpm*
   ```
4. Ensure SPI is enabled (should be via dtoverlay):
   ```bash
   ls /dev/spi*
   ```
5. Check that kernel modules are loaded:
   ```bash
   lsmod | grep tpm_tis_spi
   ```

### TPM2 unlock fails after kernel update

**Symptom**: System falls back to passphrase after `nixos-rebuild switch`.

This is expected behavior -- PCR values change when the kernel changes. Re-enroll
the TPM key:

```bash
sudo systemd-cryptenroll --wipe-slot=tpm2 --tpm2-device=auto /dev/disk/by-partlabel/disk-sd-system
```

### YubiKey not detected during boot

**Symptom**: System falls back to passphrase even with YubiKey plugged in.

**Solutions**:

1. Ensure the YubiKey is plugged in **before** powering on the Pi
2. Try a different USB port (USB 2.0 ports may be more reliable in early boot)
3. Check that kernel modules are loaded:
   ```bash
   lsmod | grep -E "hid|fido"
   ```
4. Verify the enrollment is intact:
   ```bash
   sudo cryptsetup luksDump /dev/disk/by-partlabel/disk-sd-system
   ```

### FIDO2 unlock fails with library error

**Symptom**: `loading "libpcsclite_real.so.1" failed` in journal.

This is a known NixOS issue ([nixpkgs#329135](https://github.com/NixOS/nixpkgs/issues/329135))
affecting PKCS#11 mode. FIDO2 mode (which uses `libfido2` directly) may not be
affected. If you encounter this:

1. The system will fall back to passphrase unlock automatically
2. Check if the issue has been resolved in a newer nixpkgs revision
3. As a workaround, you may need to add `libfido2` to initrd store paths:
   ```nix
   boot.initrd.systemd.storePaths = [ pkgs.libfido2 ];
   ```

### LUKS header corrupted

If the LUKS header becomes corrupted and no unlock method works:

```bash
# Boot from a live USB/SD and restore the header backup
sudo cryptsetup luksHeaderRestore /dev/disk/by-partlabel/disk-sd-system \
  --header-backup-file luks-header-backup.img
```

This is why the header backup step is critical before any enrollment.

### TPM or YubiKey lost/broken

1. Boot with the passphrase (fallback always available)
2. Remove the old enrollment:
   ```bash
   # For TPM2:
   sudo systemd-cryptenroll --wipe-slot=tpm2 /dev/disk/by-partlabel/disk-sd-system
   # For FIDO2:
   sudo systemd-cryptenroll --wipe-slot=fido2 /dev/disk/by-partlabel/disk-sd-system
   ```
3. Enroll the replacement device

---

## References

- [NixOS Wiki: TPM](https://wiki.nixos.org/wiki/TPM) -- NixOS TPM2 configuration
- [systemd-cryptenroll(1)](https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html) -- official man page
- [NixOS Secure Boot + TPM FDE Guide](https://jnsgr.uk/2024/04/nixos-secure-boot-tpm-fde/) -- comprehensive NixOS + TPM2 guide
- [LetsTrust TPM Documentation](https://letstrust.de/) -- LetsTrust TPM setup instructions
- [Infineon OPTIGA TPM Eval Board](https://www.infineon.com/cms/cn/product/evaluation-boards/optiga-tpm-9672-rpi-eval/) -- official Infineon eval board
- [NixOS Wiki: YubiKey FDE](https://wiki.nixos.org/wiki/Yubikey_based_Full_Disk_Encryption_(FDE)_on_NixOS) -- NixOS-specific YubiKey guide
- [RPi5 Secure Boot (usbboot)](https://github.com/raspberrypi/usbboot/tree/master/secure-boot-recovery5) -- official RPi5 secure boot tooling
- [rpi-sb-provisioner](https://github.com/raspberrypi/rpi-sb-provisioner) -- automated secure boot provisioning
- [RPi Bootloader Configuration](https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#raspberry-pi-bootloader-configuration) -- firmware config.txt options
- [nixpkgs#329135](https://github.com/NixOS/nixpkgs/issues/329135) -- known FIDO2 boot issue tracker
