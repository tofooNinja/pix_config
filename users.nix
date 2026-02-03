# User Configuration
{
  config,
  lib,
  ...
}: let
  # SSH public keys for authorized access
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBI4vdV8fwBFrtVGxWWmEQ5qZFV/vcM9ExyHZsn0uai0 tofoo@hole"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJCYOfQXuaY9TxgYgUPLfZw6GDI3fvkpu3Q0xj2AsgdK tofoo@nixos"
  ];
in {
  # Primary user account
  users.users.tofoo = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
    initialHashedPassword = "nix";
    openssh.authorizedKeys.keys = sshKeys;
  };

  # Root user configuration
  users.users.root = {
    initialHashedPassword = "nix";
    openssh.authorizedKeys.keys = sshKeys;
  };

  # Initrd SSH authorized keys (for remote LUKS unlock)
  boot.initrd.users.users.root.openssh.authorizedKeys.keys = sshKeys;

  # Security settings
  security = {
    polkit.enable = true;
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };

  # Auto-login for console
  services.getty.autologinUser = "tofoo";

  # SSH server configuration
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Nix trusted users for remote operations
  nix.settings = {
    trusted-users = ["nixos" "tofoo" "root"];
    download-buffer-size = 500000000;
  };
}
