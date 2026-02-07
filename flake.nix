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

  outputs =
    { self
    , nixpkgs
    , nixos-raspberrypi
    , disko
    , nixos-anywhere
    , ...
    } @ inputs:
    let
      allSystems = nixpkgs.lib.systems.flakeExposed;
      forSystems = systems: f: nixpkgs.lib.genAttrs systems (system: f system);

      # Shared settings
      primaryUser = "tofoo";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBI4vdV8fwBFrtVGxWWmEQ5qZFV/vcM9ExyHZsn0uai0 tofoo@hole"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCYOfQXuaY9TxgYgUPLfZw6GDI3fvkpu3Q0xj2AsgdK tofoo@nixos"
      ];
      initrdSshPort = 42069;

      # Per-device disk configurations (empty for both - SD card only)
      px5n0Disks = { };
      px5n1Disks = { };

      mkHostConfig = extraDisks: {
        inherit primaryUser sshKeys initrdSshPort extraDisks;
      };

      mkPi5System =
        { hostname
        , extraDisks ? { }
        ,
        }:
        nixos-raspberrypi.lib.nixosSystemFull {
          specialArgs = inputs // { hostConfig = mkHostConfig extraDisks; };
          modules = [
            ./configuration.nix
            ./disko.nix
            disko.nixosModules.disko
            {
              networking.hostName = hostname;
              time.timeZone = "UTC";
              system.stateVersion = "24.05";
            }
          ];
        };
    in
    {
      # Development shell with useful tools
      devShells = forSystems allSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              nil
              nixpkgs-fmt
              nix-output-monitor
              nixos-anywhere.packages.${system}.default
              # YubiKey tools for HMAC-SHA1 challenge-response LUKS unlock
              # Provides: ykpersonalize (program slots), ykchalresp (challenge-response)
              yubikey-personalization
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
