# Console Appearance Configuration
#
# Configures terminal fonts and colors for better readability.
# Based on nixos-images installer module.
{
  lib,
  pkgs,
  ...
}: {
  console = {
    earlySetup = true;
    font = lib.mkDefault "${pkgs.terminus_font}/share/consolefonts/ter-u16n.psf.gz";

    # Tango color theme for better readability
    # Source: https://yayachiken.net/en/posts/tango-colors-in-terminal/
    colors = lib.mkDefault [
      "000000" # black
      "CC0000" # red
      "4E9A06" # green
      "C4A000" # yellow
      "3465A4" # blue
      "75507B" # magenta
      "06989A" # cyan
      "D3D7CF" # white
      "555753" # bright black
      "EF2929" # bright red
      "8AE234" # bright green
      "FCE94F" # bright yellow
      "739FCF" # bright blue
      "AD7FA8" # bright magenta
      "34E2E2" # bright cyan
      "EEEEEC" # bright white
    ];
  };
}
