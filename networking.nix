# Network Configuration
#
# Features:
#   - systemd-networkd for network management
#   - iwd for WiFi (user-friendly CLI)
#   - mDNS support for local discovery
{lib, ...}: {
  networking = {
    useNetworkd = true;

    # Firewall settings
    firewall = {
      enable = false;
      # allowedUDPPorts = [5353]; # mDNS
      # logRefusedConnections = lib.mkDefault false;
    };

    # Disable wpa_supplicant, use iwd instead
    wireless.enable = false;
    # wireless.iwd = {
    #   enable = true;
    #   settings = {
    #     Network = {
    #       EnableIPv6 = true;
    #       RoutePriorityOffset = 300;
    #     };
    #     Settings.AutoConnect = true;
    #   };
    # };
  };

  # systemd-networkd configuration
  systemd.network.networks = {
    "99-ethernet-default-dhcp".networkConfig.MulticastDNS = "yes";
    # "99-wireless-client-dhcp".networkConfig.MulticastDNS = "yes";
  };

  # Network service stability during upgrades
  systemd.services = {
    # Don't take down networking during upgrades
    systemd-networkd.stopIfChanged = false;
    systemd-resolved.stopIfChanged = false;
  };

  # Disable wait-online (the concept of "online" is problematic)
  # See: https://github.com/systemd/systemd/blob/e1b45a756f71deac8c1aa9a008bd0dab47f64777/NEWS#L13
  systemd.services.NetworkManager-wait-online.enable = false;
  systemd.network.wait-online.enable = false;
}
