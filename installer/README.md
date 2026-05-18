# shairport-sync AP2 Installer

One-shot installer for **shairport-sync with AirPlay 2 (AP2) and multi-room support** on Linux Mint 22.x (Ubuntu 24.04 Noble base).

## What it does

1. Installs all required build dependencies via `apt`
2. Builds and installs [nqptp](https://github.com/mikebrady/nqptp) — the AirPlay 2 timing daemon
3. Builds shairport-sync from source with `--with-airplay-2`
4. Writes a baseline `/etc/shairport-sync.conf`
5. Enables and starts both `nqptp` and `shairport-sync` as systemd services

## Requirements

- Linux Mint 22.x or Ubuntu 24.04+
- `sudo` / root access
- Internet connection (fetches nqptp and build deps)

## Quick start

```bash
# Clone and run
git clone https://github.com/kuykejoe/shairport-sync.git
cd shairport-sync
sudo bash installer/install.sh

# Or pull just the script and run
wget https://raw.githubusercontent.com/kuykejoe/shairport-sync/master/installer/install.sh
sudo bash install.sh
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--name NAME` | system hostname | AirPlay receiver name visible on Apple devices |
| `--output TYPE` | `alsa` | Audio backend: `alsa`, `pulseaudio`, `pipewire` |
| `--help` | — | Show usage |

### Examples

```bash
# Custom name, PipeWire output
sudo bash installer/install.sh --name "Living Room" --output pipewire

# PulseAudio with default hostname
sudo bash installer/install.sh --output pulseaudio
```

## After installation

```bash
# Check service status
systemctl status shairport-sync
systemctl status nqptp

# Follow live logs
journalctl -u shairport-sync -f

# Edit config
sudo nano /etc/shairport-sync.conf
sudo systemctl restart shairport-sync
```

The receiver name set during install appears in the AirPlay menu on iOS/macOS. Open **Music → AirPlay** or swipe up on Control Center to find it.

## Multi-room / AirPlay 2 notes

Multi-room sync is managed by the `nqptp` daemon (runs on UDP ports 319 and 320). Make sure your firewall allows those ports if you have one configured:

```bash
sudo ufw allow 319/udp
sudo ufw allow 320/udp
```

## Updating

```bash
cd shairport-sync
git pull
sudo bash installer/install.sh
```

The installer is idempotent — re-running it rebuilds and reinstalls cleanly.

## Upstream

This repo is a fork of [mikebrady/shairport-sync](https://github.com/mikebrady/shairport-sync). To sync with upstream:

```bash
git fetch upstream
git merge upstream/master
```
