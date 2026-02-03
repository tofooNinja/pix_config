{
  description = "Minimal encrypted NixOS configuration for Raspberry Pi 5 (px5n0)";

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

    nixosConfigurations.pix5n0 = nixos-raspberrypi.lib.nixosSystemFull {
      specialArgs = inputs;
      modules = [
        # Core configuration modules
        ./hardware.nix
        ./disko.nix
        ./boot.nix
        ./networking.nix
        ./users.nix
        ./packages.nix
        # ./console.nix

        # Disko module for disk management
        disko.nixosModules.disko

        # System identity and state
        {
          networking.hostName = "px5n0";
          time.timeZone = "UTC";
          system.stateVersion = "24.05";
        }
      ];
    };
  };
}
