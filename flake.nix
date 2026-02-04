{
  description = "Minimal encrypted NixOS configuration for Raspberry Pi 5";

  nixConfig = {
    bash-prompt = "[pix5-minimal-encrypted] ➜ ";
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
    connect-timeout = 5;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixos-raspberrypi,
    disko,
    nixos-anywhere,
    ...
  } @ inputs: let
    allSystems = nixpkgs.lib.systems.flakeExposed;
    forSystems = systems: f: nixpkgs.lib.genAttrs systems (system: f system);

    #
    # ══════════════════════════════════════════════════════════════════════════
    # SHARED SETTINGS - Common to all devices
    # ══════════════════════════════════════════════════════════════════════════
    #

    # Primary user account name
    primaryUser = "tofoo";

    # SSH public keys for authorized access (both initrd and main system)
    sshKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBI4vdV8fwBFrtVGxWWmEQ5qZFV/vcM9ExyHZsn0uai0 tofoo@hole"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCYOfQXuaY9TxgYgUPLfZw6GDI3fvkpu3Q0xj2AsgdK tofoo@nixos"
    ];

    # Initrd SSH port for remote LUKS unlock (main system uses port 22)
    initrdSshPort = 42069;

    #
    # ══════════════════════════════════════════════════════════════════════════
    # PER-DEVICE DISK CONFIGURATIONS
    # ══════════════════════════════════════════════════════════════════════════
    # Define additional disks for each device here.
    # The SD card configuration is shared and defined in disko.nix.
    #
    # Example NVMe data disk:
    #   nvme0 = {
    #     type = "disk";
    #     device = "/dev/nvme0n1";
    #     content = {
    #       type = "gpt";
    #       partitions = {
    #         data = {
    #           size = "100%";
    #           content = {
    #             type = "filesystem";
    #             format = "ext4";
    #             mountpoint = "/data";
    #             mountOptions = ["noatime"];
    #           };
    #         };
    #       };
    #     };
    #   };
    #

    # px5n0: No additional disks (SD card only)
    px5n0Disks = {};

    # px5n1: No additional disks (SD card only)
    # Uncomment and modify to add an NVMe drive:
    # px5n1Disks = {
    #   nvme0 = {
    #     type = "disk";
    #     device = "/dev/nvme0n1";
    #     content = {
    #       type = "gpt";
    #       partitions = {
    #         data = {
    #           size = "100%";
    #           content = {
    #             type = "filesystem";
    #             format = "ext4";
    #             mountpoint = "/data";
    #             mountOptions = ["noatime"];
    #           };
    #         };
    #       };
    #     };
    #   };
    # };
    px5n1Disks = {};

    #
    # ══════════════════════════════════════════════════════════════════════════
    #

    # Helper to create hostConfig with device-specific settings
    mkHostConfig = extraDisks: {
      inherit primaryUser sshKeys initrdSshPort extraDisks;
    };

    # Helper function to create a Pi 5 configuration
    mkPi5System = {
      hostname,
      extraDisks ? {},
    }:
      nixos-raspberrypi.lib.nixosSystemFull {
        specialArgs = inputs // {hostConfig = mkHostConfig extraDisks;};
        modules = [
          # Core configuration modules
          ./hardware.nix
          ./disko.nix
          ./boot.nix
          ./networking.nix
          ./users.nix
          ./packages.nix
          ./console.nix

          # Disko module for disk management
          disko.nixosModules.disko

          # System identity and state
          {
            networking.hostName = hostname;
            time.timeZone = "UTC";
            system.stateVersion = "24.05";
          }
        ];
      };
  in {
    # Development shell with useful tools
    devShells = forSystems allSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          nil
          nixpkgs-fmt
          nix-output-monitor
          nixos-anywhere.packages.${system}.default
        ];
      };
    });

    # Expose nixos-anywhere for deployment
    packages.x86_64-linux.default = nixos-anywhere.packages.x86_64-linux.default;
    packages.aarch64-linux.default = nixos-anywhere.packages.aarch64-linux.default;

    nixosConfigurations = {
      px5n0 = mkPi5System {
        hostname = "px5n0";
        extraDisks = px5n0Disks;
      };
      px5n1 = mkPi5System {
        hostname = "px5n1";
        extraDisks = px5n1Disks;
      };
    };
  };
}
