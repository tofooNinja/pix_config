# Raspberry Pi 5 Hardware Configuration
#
# This module configures hardware-specific settings for the Raspberry Pi 5,
# including the bootloader, display drivers, and config.txt options.
{
  config,
  pkgs,
  lib,
  nixos-raspberrypi,
  ...
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
          params = {};
        };
      };
    };
  };

  # System identification tags
  system.nixos.tags = let
    cfg = config.boot.loader.raspberry-pi;
  in [
    "raspberry-pi-${cfg.variant}"
    cfg.bootloader
    config.boot.kernelPackages.kernel.version
  ];
}
