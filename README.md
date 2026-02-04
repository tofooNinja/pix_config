# Raspberry Pi 5 Encrypted System - Bare Minimum

NixOS configuration for Raspberry Pi 5 with LUKS-encrypted root partition.

## Features

- **Encrypted root partition** using LUKS
- **Password unlock** via keyboard (local) or SSH (remote)
- **Static IP**: `10.13.12.249` during boot and in main system
- **SSH access**:
  - During boot (initrd): port `42069`
  - Main system: port `22`

## Network Configuration

| Phase | IP Address | SSH Port |
|-------|------------|----------|
| Boot (initrd) | 10.13.12.249 | 42069 |
| Main system | 10.13.12.249 | 22 |

Gateway: `10.13.12.1`

## Unlocking the System

### Option 1: Local Keyboard

1. Connect a keyboard and monitor to the Pi
2. Wait for the LUKS password prompt
3. Enter your encryption password

### Option 2: Remote SSH

1. SSH into the Pi during boot:
   ```bash
   ssh -p 42069 root@10.13.12.249
   ```

2. Enter the LUKS password when prompted, or run:
   ```bash
   systemd-tty-ask-password-agent
   ```

3. After unlock, the system boots and SSH is available on port 22:
   ```bash
   ssh tofoo@10.13.12.249
   ```

## Installation

### Prerequisites

- Raspberry Pi 5 with SD card
- Another Linux machine with Nix installed
- Network access to the Pi

### Steps

1. **Boot the Pi with a live NixOS image** (or any Linux with SSH)

2. **Set up disk encryption password**:
   ```bash
   # On your local machine, create the password file
   echo -n "your-encryption-password" > /tmp/disk.key
   ```

3. **Deploy with nixos-anywhere**:
   ```bash
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#px5n0 \
     --disk-encryption-keys /tmp/disk.key /tmp/disk.key \
     root@<pi-ip-address>
   ```

4. **Reboot** - the Pi will prompt for the encryption password

## Configuration Files

| File | Purpose |
|------|---------|
| `flake.nix` | Main entry point with shared settings |
| `configuration.nix` | Complete system configuration |
| `disko.nix` | Disk partitioning and encryption |

## Customization

### Change SSH Keys

Edit `flake.nix` and update the `sshKeys` list:

```nix
sshKeys = [
  "ssh-ed25519 AAAA... your-key-here"
];
```

### Change Static IP

Edit `configuration.nix` and update both:

1. Boot kernel params (line ~69):
   ```nix
   kernelParams = [
     "ip=YOUR.IP.HERE::GATEWAY.IP:NETMASK::eth0:off"
   ];
   ```

2. Network configuration (line ~142):
   ```nix
   address = ["YOUR.IP.HERE/24"];
   gateway = ["GATEWAY.IP"];
   ```

### Change Initrd SSH Port

Edit `flake.nix`:
```nix
initrdSshPort = 42069;  # Change this
```

## Partition Layout

| Partition | Size | Type | Mount Point |
|-----------|------|------|-------------|
| FIRMWARE | 1GB | FAT32 | /boot/firmware |
| ESP | 1GB | FAT32 | /boot |
| log | 5GB | ext4 | /var/log |
| system | Remaining | LUKS/ext4 | / |

## Troubleshooting

### Can't reach Pi during boot

- Verify network cable is connected
- Check that Pi is on the same network (10.13.12.0/24)
- Wait ~30 seconds after power-on for initrd network

### SSH host key changed warning

The initrd uses different host keys than the main system. Add both to your `~/.ssh/known_hosts` or use:

```bash
ssh -o StrictHostKeyChecking=no -p 42069 root@10.13.12.249
```

### Password prompt not appearing on screen

- Ensure monitor is connected before power-on
- Try a different HDMI port
- Check serial console output (GPIO pins 8/10)
