# Boot Configuration with LUKS Unlock
#
# Features:
#   - Password-based LUKS unlock via keyboard or SSH
#   - SSH access during initrd for remote unlock on 10.13.12.249:42069
#   - Static IP: 10.13.12.249 during early boot
#
# Configurable via flake.nix:
#   - hostConfig.initrdSshPort
{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
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
    # Static IP: ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>
    kernelParams = [
      "ip=10.13.12.249::10.13.12.1:255.255.255.0::eth0:off"
    ];
  };

  # Initrd configuration for LUKS unlock
  boot.initrd = {
    # Kernel modules needed for display, keyboard and networking
    kernelModules = [
      # Display/graphics (for password prompt on screen)
      "vc4"
      "bcm2835_dma"
      "i2c_bcm2835"
      "bcm2712-rpi-5-b"
      "pcie_brcmstb"
      "reset-raspberrypi"
      # Networking (for SSH access during boot)
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

    # Network configuration for early boot SSH access
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
      };
    };

    # Enable systemd in initrd for network and password prompts
    systemd = {
      enable = true;
      network.enable = true;
    };

    # LUKS device configuration - password only (bare minimum)
    luks.devices.crypted = {
      device = "/dev/disk/by-partlabel/disk-sd-system";
      allowDiscards = true;
      # No keyFile = prompts for password via keyboard or SSH
    };
  };
}
