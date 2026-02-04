# System Packages - Bare Minimum
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    vim       # Editor
    git       # Version control
    htop      # Process monitoring
  ];
}
