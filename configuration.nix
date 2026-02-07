# Minimal encrypted NixOS configuration for Raspberry Pi 5
{
  config,
  lib,
  pkgs,
  nixos-raspberrypi,
  hostConfig,
  ...
}:
let
  # Tang / Clevis helpers
  isTangServer = hostConfig.tangServer or false;
  tangUnlockUrl = hostConfig.tangUnlockUrl or null;
  isClevisClient = tangUnlockUrl != null;

  # Helper script for remote YubiKey challenge-response LUKS unlock.
  # Reads a passphrase from stdin and replies to the systemd ask-password
  # socket(s) via socat (DGRAM protocol). Used by scripts/yubikey-unlock.sh.
  # See docs/secure-boot-guide.md for setup instructions.
  ykUnlockScript = pkgs.writeShellScript "yk-unlock" ''
    # Read the derived key from stdin (one line, no trailing newline)
    IFS= read -r key

    if [ -z "$key" ]; then
      echo "Error: no key provided on stdin" >&2
      exit 1
    fi

    replied=0
    for f in /run/systemd/ask-password/ask.*; do
      [ -f "$f" ] || continue
      socket=""
      while IFS='=' read -r k v; do
        [ "$k" = "Socket" ] && socket="$v" && break
      done < "$f"
      [ -S "$socket" ] || continue
      printf '+%s\0' "$key" | ${pkgs.socat}/bin/socat STDIN UNIX-SENDTO:"$socket"
      replied=1
    done

    if [ "$replied" = "0" ]; then
      echo "No pending password queries found." >&2
      echo "Tip: wait for systemd-cryptsetup to request a password, then retry." >&2
      exit 1
    fi

    echo "Unlock key sent."
  '';
in
{
  # ══════════════════════════════════════════════════════════════════════════
  # HARDWARE
  # ══════════════════════════════════════════════════════════════════════════

  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    raspberry-pi-5.display-vc4
    #usb-gadget-ethernet # Configures USB Gadget/Ethernet - Ethernet emulation over USB
  ];

  # Pi firmware config.txt settings
  hardware.raspberry-pi.config.all = {
    options = {
      # https://www.raspberrypi.com/documentation/computers/config_txt.html#uart_2ndstage
      # enable debug logging to the UART, also automatically enables
      # UART logging in `start.elf`
      uart_2ndstage = {
        enable = true;
        value = true;
      };
    };
    base-dt-params = {
      # forward uart on pi5 to GPIO 14/15 instead of uart-port
      uart0_console.enable = true;
      # https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#enable-pcie
      pciex1 = {
        enable = true;
        value = "on";
      };
      # PCIe Gen 3.0
      # https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#pcie-gen-3-0
      pciex1_gen = {
        enable = true;
        value = "3";
      };
    };
    # TPM 2.0 SPI module (Infineon SLB 9670/9672)
    # Requires a Raspberry Pi-compatible TPM board connected to the GPIO SPI pins.
    # See docs/secure-boot-guide.md for compatible hardware.
    dt-overlays = {
      tpm-slb9670 = {
        enable = true;
        params = {};
      };
    };
  };

  # ══════════════════════════════════════════════════════════════════════════
  # BOOT & LUKS
  # ══════════════════════════════════════════════════════════════════════════

  # Fix for no screen out during password prompt
  # https://github.com/nvmd/nixos-raspberrypi/issues/49#issuecomment-3367765772
  boot.blacklistedKernelModules = ["vc4"];
  systemd.services.modprobe-vc4 = {
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
    before = ["multi-user.target"];
    wantedBy = ["multi-user.target"];
    script = "/run/current-system/sw/bin/modprobe vc4";
  };

  boot = {
    tmp.useTmpfs = true;
    #kernelPackages = pkgs.linuxPackages_latest;

    loader.raspberry-pi = {
      enable = true;
      bootloader = "kernel"; # or "uboot";?
      configurationLimit = 2;
      variant = "5";
    };

    # see also nixos-raspberrypi/module/raspberrypi.nix
    # Static IP during boot for SSH unlock: 10.13.12.249
    kernelParams = [
      "ip=dhcp"
      #"ip=10.13.12.249::10.13.12.1:255.255.255.0::end0:off"
    ] ++ lib.optionals isClevisClient [
      "rd.neednet=1" # Ensure network is up before Clevis contacts Tang
    ];

    supportedFilesystems = ["ext4" "vfat"];

    initrd = {
      # Kernel modules needed for mounting USB VFAT devices in initrd stage
      # https://github.com/nvmd/nixos-raspberrypi/issues/14
      # (warning: nothing is printed after preDeviceCommands in HDMI outputs (but appears in journalctl
      # if boot succeeds), making it harder to debug)
      # Debug tips: kernel options boot.debug1* drops you in a shell (see stage-1.sh for various options),
      # boot.trace shows all typed commands.
      kernelModules = [
        "uas"
        "usbcore"
        "usb_storage"
        "vfat"
        "nls_cp437"
        "nls_iso8859_1"
        "ext4" # in case ext4 is not configured as builtin
        # TPM 2.0 SPI module support (Infineon SLB 9670/9672)
        "tpm_tis_spi"
        "tpm_tis_core"
        # USB HID for YubiKey FIDO2 (optional, see docs/secure-boot-guide.md)
        "hid_generic"
        "usbhid"
      ];
      #kernelModules = [ "rp1" "bcm2712-rpi-5-b" ];

      availableKernelModules = ["hid" "evdev"];

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
          # leave uncommented for debug purposes
          # shell = "/usr/bin/systemd-tty-ask-password-agent";
        };
      };

      systemd = {
        enable = true;
        network.enable = true;
        # socat is needed by yk-unlock for DGRAM socket communication
        storePaths = ["${pkgs.socat}/bin/socat"];
        # Remote YubiKey challenge-response unlock helper (see docs/secure-boot-guide.md)
        extraBin.yk-unlock = "${ykUnlockScript}";
      };

      luks.devices.crypted = {
        device = "/dev/disk/by-partlabel/disk-sd-system";
        allowDiscards = true;
        # TPM2 auto-unlock: systemd-cryptsetup unseals the LUKS key from the TPM.
        # Passphrase fallback is automatic if TPM is absent or PCR mismatch.
        # Enroll with: sudo systemd-cryptenroll --tpm2-device=auto /dev/disk/by-partlabel/disk-sd-system
        # or: sudo systemd-cryptenroll \ --fido2-device=auto \ --fido2-with-client-pin=no \ --fido2-with-user-presence=no \ /dev/disk/by-partlabel/disk-sd-system
        # Optional: add "fido2-device=auto" for YubiKey FIDO2 as alternative unlock method.
        crypttabExtraOpts = ["fido2-device=auto" "tpm2-device=auto"];
      };
    };
  };

  # ══════════════════════════════════════════════════════════════════════════
  # TANG / CLEVIS (Network-Bound Disk Encryption)
  # ══════════════════════════════════════════════════════════════════════════

  # Tang server: provides key escrow for Clevis clients on the local network.
  # Other Pis contact this server during boot to unlock their LUKS volumes.
  # Keys are auto-generated on first request and stored in /var/lib/tang.
  # See docs/secure-boot-guide.md Part 2.6 for setup details.
  services.tang = lib.mkIf isTangServer {
    enable = true;
    listenStream = [ "7654" ];
    ipAddressAllow = hostConfig.tangIpAllowList or [
      "10.0.0.0/8"
      "172.16.0.0/12"
      "192.168.0.0/16"
    ];
  };

  # Open Tang port if firewall is enabled (currently disabled, but future-proofing).
  networking.firewall.allowedTCPPorts = lib.mkIf isTangServer [ 7654 ];

  # Clevis client: unlocks LUKS volume by contacting a Tang server at boot.
  # Enrollment: see docs/secure-boot-guide.md Part 2.6 for step-by-step instructions.
  # The JWE secret file is created during enrollment and stored at ./keys/clevis-tang.jwe.
  #
  # Known limitation: the JWE file is copied to the Nix store (world-readable).
  # See: https://github.com/NixOS/nixpkgs/issues/335105
  # Mitigation: the JWE can only be decrypted by contacting the Tang server.
  # Keep the Tang server on a trusted private network.
  boot.initrd.clevis = lib.mkIf isClevisClient {
    enable = true;
    useTang = true;
    devices.crypted.secretFile = ./keys/clevis-tang.jwe;
  };

  # ══════════════════════════════════════════════════════════════════════════
  # NETWORKING
  # ══════════════════════════════════════════════════════════════════════════

  networking = {
    useNetworkd = true;
    firewall.enable = false;
    wireless = {
      enable = false;
      iwd = {
        enable = true;
        settings = {
          Network = {
            EnableIPv6 = true;
            RoutePriorityOffset = 300;
          };
          Settings.AutoConnect = true;
        };
      };
    };
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;

    networks = {
      "99-ethernet-default-dhcp".networkConfig.MulticastDNS = "yes";
      "99-wireless-client-dhcp".networkConfig.MulticastDNS = "yes";
    };
    #networks."10-ethernet" = {
    #  matchConfig.Name = "end* eth* en*";
    #  address = [ "10.13.12.249/24" ];
    #  gateway = [ "10.13.12.1" ];
    #  dns = [ "10.13.12.1" ];
    #  networkConfig = {
    #    DHCP = "no";
    #    MulticastDNS = "yes";
    #  };
    #};
  };

  # This comment was lifted from `srvos`
  # Do not take down the network for too long when upgrading,
  # This also prevents failures of services that are restarted instead of stopped.
  # It will use `systemctl restart` rather than stopping it with `systemctl stop`
  # followed by a delayed `systemctl start`.
  systemd.services = {
    systemd-networkd.stopIfChanged = false;
    systemd-resolved.stopIfChanged = false;
  };

  # ══════════════════════════════════════════════════════════════════════════
  # USERS & SSH
  # ══════════════════════════════════════════════════════════════════════════

  users.users.${hostConfig.primaryUser} = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager" "video" "tss"];
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
    # TPM 2.0 support: exposes /dev/tpmrm0 and sets up tpm2-abrmd resource manager
    tpm2 = {
      enable = true;
      pkcs11.enable = true;
      tctiEnvironment.enable = true;
    };
  };

  services.getty.autologinUser = hostConfig.primaryUser;

  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
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
    btop
    duf
    lshw
    pciutils
    usbutils

    # Serial/terminal tools
    screen
    minicom

    # Security / TPM2
    tpm2-tools # TPM2 CLI tools (tpm2_*)
    tpm2-tss # TPM2 software stack

    # Security / YubiKey (optional, for FIDO2 LUKS unlock)
    libfido2 # FIDO2 library and fido2-token CLI
    yubikey-manager # ykman CLI for YubiKey management

    raspberrypi-eeprom
  ] ++ lib.optionals (isTangServer || isClevisClient) [
    # Security / Clevis (network-bound disk encryption)
    clevis # Automated LUKS decryption framework (Tang/Clevis)
  ];
}
