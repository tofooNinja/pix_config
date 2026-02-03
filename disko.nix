# Disk Configuration with LUKS Encryption
#
# Partition layout for SD card:
#   1. FIRMWARE (1GB)  - FAT32, Pi firmware partition (automount on access)
#   2. ESP (1GB)       - FAT32, EFI System Partition for bootloader (automount on access)
#   3. log (8GB)       - ext4, dedicated /var/log partition (mounted at boot)
#   4. system (rest)   - LUKS encrypted ext4, root filesystem
{lib, ...}: let
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
        "noatime" # Don't update access times (reduces writes)
        # "noauto" # Don't mount at boot
        "x-systemd.automount" # Mount on first access
        # "x-systemd.idle-timeout=1min" # Unmount after 1 minute idle
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
        "noatime" # Don't update access times
        # "noauto" # Don't mount at boot
        "x-systemd.automount" # Mount on first access
        # "x-systemd.idle-timeout=1min" # Unmount after idle
        "umask=0077" # Restrictive permissions (owner only)
      ];
    };
  };
in {
  # Required filesystem support
  boot.supportedFilesystems = {
    vfat = true;
    ext4 = true;
  };

  # Ensure /var/log is mounted early for boot logging
  fileSystems."/var/log".neededForBoot = true;

  disko.devices = {
    disk.sd = {
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
  };
}
