# System Packages
{ pkgs, ... }: {
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
