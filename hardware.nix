# Raspberry Pi 5 Hardware Configuration
#
# This module configures hardware-specific settings for the Raspberry Pi 5,
# including the bootloader, display drivers, config.txt options, and GPIO UART debugging.
{ config
, pkgs
, lib
, nixos-raspberrypi
, ...
}: {
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    raspberry-pi-5.display-vc4
  ];

  # config.txt settings for Raspberry Pi firmware
  hardware.raspberry-pi.config = {
    # Compute Module 4 settings
    cm4.options = {
      otg_mode = {
        enable = lib.mkDefault true;
        value = lib.mkDefault true;
      };
    };

    # Compute Module 5 settings
    cm5.dt-overlays = {
      dwc2 = {
        enable = lib.mkDefault true;
        params.dr_mode = {
          enable = true;
          value = "host";
        };
      };
    };

    # Global settings (applies to all Pi variants)
    all = {
      options = {
        # Auto-detect cameras
        camera_auto_detect = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };

        # Auto-detect DSI displays
        display_auto_detect = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };

        # For DRM VC4 V3D driver
        max_framebuffers = {
          enable = lib.mkDefault true;
          value = lib.mkDefault 2;
        };

        # Use kernel's default video settings
        disable_fw_kms_setup = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };

        # Disable overscan compensation
        disable_overscan = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };

        # Enable CPU boost
        arm_boost = {
          enable = lib.mkDefault true;
          value = lib.mkDefault true;
        };

        #
        # ══════════════════════════════════════════════════════════════════════
        # GPIO UART DEBUG OUTPUT
        # ══════════════════════════════════════════════════════════════════════
        # Enables serial console on GPIO pins 14 (TX) and 15 (RX)
        # Physical pins 8 (TX) and 10 (RX) on the 40-pin header
        # Connect with: screen /dev/ttyUSB0 115200
        #

        # Enable primary UART on GPIO 14/15
        # https://www.raspberrypi.com/documentation/computers/config_txt.html#enable_uart
        enable_uart = {
          enable = true;
          value = true;
        };

        # Enable debug logging to UART during boot (bootloader/start.elf)
        # https://www.raspberrypi.com/documentation/computers/config_txt.html#uart_2ndstage
        uart_2ndstage = {
          enable = true;
          value = true;
        };
      };

      # Device tree parameters
      base-dt-params = {
        # Enable PCIe (for NVMe drives, etc.)
        pciex1 = {
          enable = true;
          value = "on";
        };
        # PCIe Gen 3.0 for better performance
        pciex1_gen = {
          enable = true;
          value = "3";
        };
      };

      # Device tree overlays
      dt-overlays = {
        vc4-kms-v3d = {
          enable = lib.mkDefault true;
          params = { };
        };
      };
    };
  };

  # Kernel parameters for serial console debugging
  boot.kernelParams = [
    # Enable serial console on GPIO UART (primary console for boot messages)
    "console=serial0,115200"
    # Also keep tty1 as fallback console for HDMI
    "console=tty1"
  ];

  # System identification tags
  system.nixos.tags =
    let
      cfg = config.boot.loader.raspberry-pi;
    in
    [
      "raspberry-pi-${cfg.variant}"
      cfg.bootloader
      config.boot.kernelPackages.kernel.version
    ];
}
