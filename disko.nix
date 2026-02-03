# Disk Configuration with LUKS Encryption
#
# Partition layout for SD card (shared by all devices):
#   1. FIRMWARE (1GB)  - FAT32, Pi firmware partition (automount on access)
#   2. ESP (1GB)       - FAT32, EFI System Partition for bootloader (automount on access)
#   3. log (8GB)       - ext4, dedicated /var/log partition (mounted at boot)
#   4. system (rest)   - LUKS encrypted ext4, root filesystem
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

  # Ensure /var/log is mounted early for boot logging
  fileSystems."/var/log".neededForBoot = true;

  # Merge SD card config with any extra disks from hostConfig
  disko.devices = {
    disk = {sd = sdCardDisk;} // extraDisks;
  };
}
