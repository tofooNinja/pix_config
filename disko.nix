# Disk Configuration with LUKS Encryption
#
# Partition layout for SD card:
#   1. FIRMWARE (1GB)  - FAT32, Pi firmware partition
#   2. ESP (1GB)       - FAT32, EFI System Partition for bootloader
#   3. log (8GB)       - ext4, dedicated /var/log partition
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
in {
  # Required filesystem support
  boot.supportedFilesystems = {
    vfat = true;
    ext4 = true;
  };

  disko.devices = {
    disk.sd = {
      type = "disk";
      device = "/dev/mmcblk0"; # SD card
      content = {
        type = "gpt";
        partitions = {
          # Pi firmware partition
          FIRMWARE = firmwarePartition {
            label = "FIRMWARE";
            content.mountpoint = "/boot/firmware";
          };

          # EFI System Partition
          ESP = espPartition {
            label = "ESP";
            content.mountpoint = "/boot";
          };

          # Dedicated log partition (unencrypted for boot diagnostics)
          log = {
            type = "8300"; # Linux filesystem
            size = "8G";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/var/log";
              mountOptions = [
                "noatime"
                "noauto"
                "x-systemd.automount"
                "x-systemd.idle-timeout=1min"
                "umask=0077"
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
                  "noatime"
                  "noauto"
                  "x-systemd.automount"
                  "x-systemd.idle-timeout=1min"
                  "umask=0077"
                ];
              };
            };
          };
        };
      };
    };
  };
}
