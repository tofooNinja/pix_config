# Minimal encrypted NixOS configuration for Raspberry Pi 5
{
  config,
  lib,
  pkgs,
  nixos-raspberrypi,
  hostConfig,
  ...
}: {
  # ══════════════════════════════════════════════════════════════════════════
  # HARDWARE
  # ══════════════════════════════════════════════════════════════════════════

  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    raspberry-pi-5.display-vc4
  ];

  # Pi firmware config.txt settings
  hardware.raspberry-pi.config.all = {
    options = {
      camera_auto_detect = {
        enable = lib.mkDefault true;
        value = lib.mkDefault true;
      };
      display_auto_detect = {
        enable = lib.mkDefault true;
        value = lib.mkDefault true;
      };
      max_framebuffers = {
        enable = lib.mkDefault true;
        value = lib.mkDefault 2;
      };
      disable_fw_kms_setup = {
        enable = lib.mkDefault true;
        value = lib.mkDefault true;
      };
      disable_overscan = {
        enable = lib.mkDefault true;
        value = lib.mkDefault true;
      };
      arm_boost = {
        enable = lib.mkDefault true;
        value = lib.mkDefault true;
      };
      enable_uart = {
        enable = true;
        value = true;
      };
    };
    base-dt-params = {
      pciex1 = {
        enable = true;
        value = "on";
      };
      pciex1_gen = {
        enable = true;
        value = "3";
      };
    };
    dt-overlays.vc4-kms-v3d.enable = lib.mkDefault true;
  };

  # ══════════════════════════════════════════════════════════════════════════
  # BOOT & LUKS
  # ══════════════════════════════════════════════════════════════════════════

  boot = {
    tmp.useTmpfs = true;
    kernelPackages = pkgs.linuxPackages_latest;

    loader.raspberry-pi = {
      enable = true;
      bootloader = "kernel";
      configurationLimit = 1;
      variant = "5";
    };

    # Static IP during boot for SSH unlock: 10.13.12.249
    kernelParams = [
      "ip=10.13.12.249::10.13.12.1:255.255.255.0::eth0:off"
      "console=serial0,115200"
      "console=tty1"
    ];

    supportedFilesystems = {
      vfat = true;
      ext4 = true;
    };

    initrd = {
      kernelModules = [
        "vc4"
        "bcm2835_dma"
        "i2c_bcm2835"
        "bcm2712-rpi-5-b"
        "pcie_brcmstb"
        "reset-raspberrypi"
        "rp1"
      ];

      availableKernelModules = [
        "usbhid"
        "hid"
        "hid-generic"
        "hidraw"
        "evdev"
      ];

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

      systemd = {
        enable = true;
        network.enable = true;
      };

      luks.devices.crypted = {
        device = "/dev/disk/by-partlabel/disk-sd-system";
        allowDiscards = true;
      };
    };
  };

  fileSystems."/var/log".neededForBoot = true;

  # ══════════════════════════════════════════════════════════════════════════
  # NETWORKING
  # ══════════════════════════════════════════════════════════════════════════

  networking = {
    useNetworkd = true;
    firewall.enable = false;
    wireless.enable = false;
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;

    networks."10-ethernet" = {
      matchConfig.Name = "eth* en*";
      address = ["10.13.12.249/24"];
      gateway = ["10.13.12.1"];
      dns = ["10.13.12.1"];
      networkConfig = {
        DHCP = "no";
        MulticastDNS = "yes";
      };
    };
  };

  systemd.services = {
    systemd-networkd.stopIfChanged = false;
    systemd-resolved.stopIfChanged = false;
  };

  # ══════════════════════════════════════════════════════════════════════════
  # USERS & SSH
  # ══════════════════════════════════════════════════════════════════════════

  users.users.${hostConfig.primaryUser} = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "video"];
    initialPassword = "nix";
    openssh.authorizedKeys.keys = hostConfig.sshKeys;
  };

  users.users.root = {
    initialPassword = "nix";
    openssh.authorizedKeys.keys = hostConfig.sshKeys;
  };

  security = {
    polkit.enable = true;
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };

  services.getty.autologinUser = hostConfig.primaryUser;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  nix.settings = {
    trusted-users = ["nixos" hostConfig.primaryUser "root"];
    download-buffer-size = 500000000;
  };

  # ══════════════════════════════════════════════════════════════════════════
  # PACKAGES
  # ══════════════════════════════════════════════════════════════════════════

  environment.systemPackages = with pkgs; [
    # File management
    tree

    # Editors
    vim
    neovim

    # Version control
    git
    tig

    # Documentation
    tealdeer

    # System
    bottom
    duf
    lshw
    pciutils
    usbutils

    # Serial/terminal tools
    screen
  ];
}
