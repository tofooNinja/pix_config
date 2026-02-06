# Disk Configuration with LUKS Encryption
# Partitions: FIRMWARE (1GB), ESP (1GB), log (5GB), system (rest, encrypted)
{ hostConfig, ... }: {
  disko.devices.disk =
    {
      sd = {
        type = "disk";
        device = "/dev/mmcblk0";
        content = {
          type = "gpt";
          partitions = {
            FIRMWARE = {
              priority = 1;
              type = "0700";
              attributes = [ 0 ];
              size = "1024M";
              label = "FIRMWARE";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/firmware";
                mountOptions = [ "noatime" "noauto" "x-systemd.automount" "x-systemd.idle-timeout=1min" ];
              };
            };

            ESP = {
              type = "EF00";
              attributes = [ 2 ];
              size = "1024M";
              label = "ESP";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "noatime" "noauto" "x-systemd.automount" "x-systemd.idle-timeout=1min" "umask=0077" ];
              };
            };

            encrypted_swap = {
              size = "8G";
              content = {
                type = "swap";
                randomEncryption = true;
              };
            };

            system = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted";
                passwordFile = "/tmp/disk.key";
                settings.allowDiscards = true;
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                  mountOptions = [ "noatime" "commit=60" ];
                };
              };
            };
          };
        };
      };
    }
    // (hostConfig.extraDisks or { });
}
