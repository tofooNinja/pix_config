# User Configuration
#
# Configurable via flake.nix:
#   - hostConfig.primaryUser
#   - hostConfig.sshKeys
#   - hostConfig.initrdSshKeys
{
  config,
  lib,
  hostConfig,
  ...
}: {
  # Primary user account
  users.users.${hostConfig.primaryUser} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
    ];
    initialHashedPassword = "nix";
    openssh.authorizedKeys.keys = hostConfig.sshKeys;
  };

  # Root user configuration
  users.users.root = {
    initialHashedPassword = "nix";
    openssh.authorizedKeys.keys = hostConfig.sshKeys;
  };

  # Security settings
  security = {
    polkit.enable = true;
    sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };
  };

  # Auto-login for console
  services.getty.autologinUser = hostConfig.primaryUser;

  # SSH server configuration
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
  };

  # Nix trusted users for remote operations
  nix.settings = {
    trusted-users = ["nixos" hostConfig.primaryUser "root"];
    download-buffer-size = 500000000;
  };
}
