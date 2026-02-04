# Network Configuration
#
# Features:
#   - Static IP: 10.13.12.249 (same during boot and in main system)
#   - systemd-networkd for network management
#   - SSH accessible on port 22 (main system) and 42069 (initrd)
{lib, ...}: {
  networking = {
    useNetworkd = true;

    # Firewall disabled for simplicity
    firewall.enable = false;

    # Disable wpa_supplicant (not needed for wired connection)
    wireless.enable = false;
  };

  # systemd-networkd configuration with static IP
  systemd.network = {
    enable = true;

    networks."10-ethernet" = {
      matchConfig.Name = "eth* en*";
      address = ["10.13.12.249/24"];
      gateway = ["10.13.12.1"];
      dns = ["10.13.12.1"];
      networkConfig = {
        DHCP = "no";
        MulticastDNS = "yes";
      };
    };
  };

  # Network service stability during upgrades
  systemd.services = {
    systemd-networkd.stopIfChanged = false;
    systemd-resolved.stopIfChanged = false;
  };

  # Disable wait-online
  systemd.network.wait-online.enable = false;
}
