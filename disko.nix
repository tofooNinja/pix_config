# Disk Configuration with LUKS Encryption
#
# ══════════════════════════════════════════════════════════════════════════════
# PARTITION LAYOUT for SD card (shared by all devices):
# ══════════════════════════════════════════════════════════════════════════════
#
#   1. FIRMWARE (1GB)  - FAT32, Pi firmware partition (automount on access)
#   2. ESP (1GB)       - FAT32, EFI System Partition for bootloader (automount on access)
#   3. log (8GB)       - ext4, dedicated /var/log partition (mounted at boot)
#   4. system (rest)   - LUKS encrypted ext4, root filesystem
#
# ══════════════════════════════════════════════════════════════════════════════
# WHY SEPARATE FIRMWARE AND ESP (BOOT) PARTITIONS?
# ══════════════════════════════════════════════════════════════════════════════
#
# The Raspberry Pi has a unique multi-stage boot process:
#
#   Stage 1: GPU ROM → reads bootcode.bin from SD card (must be on first FAT partition)
#   Stage 2: bootcode.bin → loads start4.elf (GPU firmware)
#   Stage 3: start4.elf → reads config.txt, loads kernel/device tree
#   Stage 4: Kernel → normal Linux boot
#
# The FIRMWARE partition contains Pi-specific GPU firmware files:
#   - start4.elf, fixup4.dat (GPU firmware)
#   - config.txt (Pi boot configuration)
#   - Device tree blobs (.dtb files)
#   - Overlays for hardware configuration
#
# The ESP partition contains standard bootloader files:
#   - Linux kernel (Image)
#   - initramfs
#   - NixOS boot generations
#   - U-Boot or systemd-boot configuration
#
# Benefits of separation:
#   - Different update cycles: firmware rarely changes, kernel updates are frequent
#   - Independent failure domains: corrupted ESP won't brick firmware boot
#   - Follows UEFI conventions on ESP while accommodating Pi-specific requirements
#   - Cleaner organization with single responsibility per partition
#
# ══════════════════════════════════════════════════════════════════════════════
# WHY A DEDICATED /var/log PARTITION?
# ══════════════════════════════════════════════════════════════════════════════
#
# The log partition is UNENCRYPTED and mounted EARLY (neededForBoot = true) to:
#
#   1. Capture boot logs before LUKS unlock (debugging failed unlocks)
#   2. Preserve logs across failed boots and system crashes
#   3. Allow log access for forensics even if encrypted root won't unlock
#   4. Reduce writes to the encrypted root partition (SD card wear leveling)
#
# Note: /var/log can be mounted directly without /var being a separate partition.
# The mount point directory (/var/log) is created on the root filesystem, and
# this partition is mounted on top of it. Linux handles this transparently.
#
# ══════════════════════════════════════════════════════════════════════════════
#
# Additional disks can be configured per-device via hostConfig.extraDisks
# See flake.nix for examples.
{
  lib,
  hostConfig,
  ...
}: let
  # Reusable partition definitions
  firmwarePartition = lib.recursiveUpdate {
    priority = 1;
    type = "0700"; # Microsoft basic data
    attributes = [0]; # Required Partition
    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      mountOptions = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
  };

  espPartition = lib.recursiveUpdate {
    type = "EF00"; # EFI System Partition
    attributes = [2]; # Legacy BIOS Bootable (for U-Boot)
    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      mountOptions = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
        "umask=0077"
      ];
    };
  };

  # Shared SD card configuration (used by all devices)
  sdCardDisk = {
    type = "disk";
    device = "/dev/mmcblk0"; # SD card
    content = {
      type = "gpt";
      partitions = {
        # Pi firmware partition - automount on access
        FIRMWARE = firmwarePartition {
          label = "FIRMWARE";
          content.mountpoint = "/boot/firmware";
        };

        # EFI System Partition - automount on access
        ESP = espPartition {
          label = "ESP";
          content.mountpoint = "/boot";
        };

        # Dedicated log partition - always mounted for boot diagnostics
        log = {
          type = "8300"; # Linux filesystem
          size = "8G";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/var/log";
            mountOptions = [
              "noatime" # Reduce writes
              "commit=60" # Sync every 60s (balance between safety and SD wear)
            ];
          };
        };

        # Encrypted root partition
        system = {
          size = "100%"; # Remaining space
          content = {
            type = "luks";
            name = "crypted";
            # Password file provided by nixos-anywhere during installation
            passwordFile = "/tmp/disk.key";
            settings = {
              allowDiscards = true;
            };
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
              mountOptions = [
                "noatime" # Reduce writes
                "commit=60" # Sync every 60s
              ];
            };
          };
        };
      };
    };
  };

  # Get extra disks from hostConfig, default to empty
  extraDisks = hostConfig.extraDisks or {};
in {
  # Required filesystem support
  boot.supportedFilesystems = {
    vfat = true;
    ext4 = true;
  };

  # ══════════════════════════════════════════════════════════════════════════
  # EARLY BOOT LOGGING CONFIGURATION
  # ══════════════════════════════════════════════════════════════════════════
  #
  # neededForBoot = true ensures /var/log is mounted during initrd (Stage 1).
  # This is BEFORE the LUKS partition is unlocked, capturing:
  #   - initrd startup messages
  #   - Network initialization (for remote unlock)
  #   - LUKS unlock attempts and errors
  #   - Any early boot failures
  #
  # Boot logging timeline:
  #   1. Kernel starts → logs to kernel ring buffer (volatile, in RAM)
  #   2. initrd starts → /var/log mounted (neededForBoot = true)
  #   3. journald starts in initrd → can write to /var/log/journal
  #   4. LUKS unlock → root filesystem available
  #   5. Switch to real root → journald restarts, flushes early logs
  #
  # The journal "flush" step copies any logs from volatile storage
  # (/run/log/journal) to persistent storage (/var/log/journal).
  #
  fileSystems."/var/log".neededForBoot = true;

  # Configure journald for persistent storage
  # This ensures boot logs are written to /var/log/journal and not lost
  services.journald = {
    storage = "persistent"; # Always use /var/log/journal (not /run/log/journal)
    extraConfig = ''
      # Compress logs to save space on SD card
      Compress=yes
      # Sync to disk every 5 minutes (balance between safety and SD wear)
      SyncIntervalSec=5m
      # Limit total journal size to prevent filling the log partition
      SystemMaxUse=4G
      # Keep at least 1GB free on the log partition
      SystemKeepFree=1G
      # Maximum size of individual journal files
      SystemMaxFileSize=128M
      # Forward to console for debugging (useful with serial console)
      ForwardToConsole=no
      # Rate limiting to prevent log floods
      RateLimitIntervalSec=30s
      RateLimitBurst=10000
    '';
  };

  # Merge SD card config with any extra disks from hostConfig
  disko.devices = {
    disk = {sd = sdCardDisk;} // extraDisks;
  };
}
