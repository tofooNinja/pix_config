# Boot Configuration with LUKS Unlock via USB Key
#
# ══════════════════════════════════════════════════════════════════════════════
# FEATURES
# ══════════════════════════════════════════════════════════════════════════════
#
#   - USB key-based LUKS unlock with password fallback
#   - SSH access during initrd for remote unlock
#   - Early network boot support
#   - Systemd-based initrd for better logging and service management
#
# ══════════════════════════════════════════════════════════════════════════════
# INITRD LOGGING
# ══════════════════════════════════════════════════════════════════════════════
#
# With systemd in initrd (boot.initrd.systemd.enable = true), journald runs
# during early boot and captures all initrd activity. Combined with the
# dedicated /var/log partition (neededForBoot = true in disko.nix), this means:
#
#   1. /var/log is mounted BEFORE LUKS unlock attempt
#   2. journald can write directly to /var/log/journal
#   3. If LUKS unlock fails, logs are still preserved on the unencrypted log partition
#   4. SSH unlock attempts, network issues, and hardware detection are all logged
#
# To view initrd-specific logs after boot:
#   journalctl -b _SYSTEMD_UNIT=initrd.target
#   journalctl -b _TRANSPORT=kernel  # kernel messages only
#
# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURABLE OPTIONS (via flake.nix)
# ══════════════════════════════════════════════════════════════════════════════
#
#   - hostConfig.usbKeyUuid    - UUID of USB stick with LUKS keyfile
#   - hostConfig.initrdSshKeys - SSH public keys for remote unlock
#   - hostConfig.initrdSshPort - SSH port during initrd (default: 22)
{ config
, lib
, pkgs
, hostConfig
, ...
}: {
  # Bootloader configuration
  boot = {
    tmp.useTmpfs = true;
    kernelPackages = pkgs.linuxPackages_latest;

    loader.raspberry-pi = {
      enable = true;
      bootloader = "kernel";
      configurationLimit = 1;
      variant = "5";
    };

    # Kernel parameters for early boot
    kernelParams = [
      "ip=dhcp" # Enable DHCP during early boot (for initrd SSH)
    ];
  };

  # Initrd configuration for LUKS unlock
  boot.initrd = {
    # Kernel modules needed for USB key and display
    kernelModules = [
      # Display/graphics
      "vc4"
      "bcm2835_dma"
      "i2c_bcm2835"
      "bcm2712-rpi-5-b"
      "pcie_brcmstb"
      "reset-raspberrypi"
      # USB storage
      "usbcore"
      "usb_storage"
      "uas"
      # Filesystem support
      "vfat"
      "nls_cp437"
      "nls_iso8859_1"
      # Networking
      "rp1"
    ];

    # Additional modules for keyboard/console support
    availableKernelModules = [
      "usbhid"
      "hid"
      "hid-generic"
      "hidraw"
      "evdev"
    ];

    # Enable systemd in initrd
    systemd.enable = true;

    # Network configuration for early boot
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = hostConfig.initrdSshPort;
        hostKeys = [
          ./keys/initrd_host_rsa
          ./keys/initrd_host_ed25519
        ];
        authorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
        shell = "${pkgs.bashInteractive}/bin/bash";
      };
    };

    # For systemd initrd: create /bin/cryptsetup-askpass that sshd expects
    # This gives you a bash shell; run 'systemd-tty-ask-password-agent' to unlock LUKS
    systemd.storePaths = [ pkgs.bashInteractive ];
    systemd.users.root.shell = "${pkgs.bashInteractive}/bin/bash";
    # systemd.users.root.shell = "/bin/cryptsetup-askpass";
    # systemd.contents."bin/cryptsetup-askpass" = { source = "${pkgs.bashInteractive}/bin/bash";
    # target = "/bin/cryptsetup-askpass";
    # };

    systemd.initrdBin = [
      (pkgs.writeScriptBin "cryptsetup-askpass" ''
        #!${pkgs.bash}/bin/sh
        exec ${pkgs.bashInteractive}/bin/bash "$@"
      '')
    ];

    systemd.network.enable = true;

    # Service to mount USB key containing LUKS keyfile
    # systemd.services.mount-usb-key = {
    #   description = "Mount USB stick containing LUKS key";
    #   wantedBy = ["cryptsetup-pre.target"];
    #   before = ["cryptsetup-pre.target"];
    #   after = ["systemd-udev-settle.service"];
    #   unitConfig.DefaultDependencies = false;
    #   serviceConfig = {
    #     Type = "oneshot";
    #     RemainAfterExit = true;
    #   };
    #   script = ''
    #     mkdir -m 0755 -p /usbstick
    #     sleep 2
    #     mount -t vfat -o ro /dev/disk/by-uuid/${hostConfig.usbKeyUuid} /usbstick
    #   '';
    # };

    # Mount USB key for LUKS keyfile (runs before cryptsetup)
    systemd.mounts = [{
      what = "/dev/disk/by-uuid/${hostConfig.usbKeyUuid}";
      where = "/usbstick";
      type = "vfat";
      options = "ro";
      wantedBy = [ "cryptsetup-pre.target" ];
      before = [ "cryptsetup-pre.target" ];
      after = [ "dev-disk-by\\x2duuid-${hostConfig.usbKeyUuid}.device" ];
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/dev/disk/by-uuid/${hostConfig.usbKeyUuid}";
      };
    }];

    # LUKS device configuration
    luks.devices.crypted = {
      device = "/dev/disk/by-partlabel/disk-sd-system";
      keyFile = "/usbstick/crypto_keyfile.bin";
      allowDiscards = true;
      keyFileTimeout = 10; # Fall back to password after 10 seconds
    };
  };

  # USB key mount for runtime access (automounts on access)
  fileSystems."/mnt/usb" = {
    device = "/dev/disk/by-uuid/${hostConfig.usbKeyUuid}";
    fsType = "vfat";
    options = [
      "noauto" # Don't mount immediately at boot
      "nofail" # Don't fail boot if drive is missing
      "x-systemd.automount" # Trigger mount on access
      "x-systemd.idle-timeout=60s" # Unmount after 60s of inactivity
      "x-systemd.device-timeout=5s" # Short wait if device isn't there
      # "x-initrd.mount"             # Ensure this rule is available in initrd
    ];
  };
}
