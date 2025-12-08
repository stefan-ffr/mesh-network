# Raspberry Pi Images

## Overview

Pre-built Raspberry Pi images are available for all mesh network node types. These images come with all necessary software pre-installed and are ready to use after basic configuration.

## Supported Hardware

### Raspberry Pi 4 Model B
- ✅ 2GB RAM (suitable for all node types except large monitoring)
- ✅ 4GB RAM (recommended for monitoring and cache nodes)
- ✅ 8GB RAM (ideal for monitoring nodes with 50+ nodes)

### Raspberry Pi 5
- ✅ 4GB RAM (recommended)
- ✅ 8GB RAM (ideal for monitoring and cache)

### Raspberry Pi 3 Model B+
- ⚠️ Limited support (2.4GHz WiFi only, less RAM)
- Only recommended for small deployments

## Available Images

| Image | Size | Use Case | Min RAM |
|-------|------|----------|---------|
| **mesh-router** | ~2.5GB | WiFi mesh + LAN clients | 1GB |
| **lan-router** | ~2.0GB | Wired mesh + LAN clients | 512MB |
| **gateway-wifi** | ~2.5GB | WiFi mesh + WAN | 1GB |
| **gateway-wired** | ~2.0GB | Wired mesh + WAN | 512MB |
| **update-cache** | ~4.0GB | LANcache + apt-cacher-ng | 2GB |
| **monitoring** | ~3.5GB | Network monitoring | 2GB |

## Download Images

### From GitHub Releases

```bash
# Download latest release
wget https://github.com/YOUR-USERNAME/mesh-network/releases/latest/download/mesh-network-monitoring-1.0.0-arm64.img.xz

# Verify checksum
wget https://github.com/YOUR-USERNAME/mesh-network/releases/latest/download/mesh-network-monitoring-1.0.0-arm64.img.xz.sha256
sha256sum -c mesh-network-monitoring-1.0.0-arm64.img.xz.sha256

# Extract
xz -d mesh-network-monitoring-1.0.0-arm64.img.xz
```

### All Available Images

Replace `monitoring` with your desired node type:
- `mesh-router`
- `lan-router`
- `gateway-wifi`
- `gateway-wired`
- `update-cache`
- `monitoring`

## Flashing to SD Card

### Linux

```bash
# Find SD card device
lsblk

# Flash image (replace /dev/sdX with your SD card)
sudo dd if=mesh-network-monitoring-1.0.0-arm64.img of=/dev/sdX bs=4M status=progress conv=fsync

# Safely eject
sudo sync
sudo eject /dev/sdX
```

### macOS

```bash
# Find SD card device
diskutil list

# Unmount (replace diskX with your SD card)
diskutil unmountDisk /dev/diskX

# Flash image
sudo dd if=mesh-network-monitoring-1.0.0-arm64.img of=/dev/rdiskX bs=4m

# Eject
sudo diskutil eject /dev/diskX
```

### Windows

Use **Etcher**, **Raspberry Pi Imager**, or **Win32DiskImager**:

1. Download and install [balenaEtcher](https://www.balena.io/etcher/)
2. Extract the `.img.xz` file (or Etcher can do this automatically)
3. Select the image file
4. Select your SD card
5. Click "Flash!"

## First Boot Configuration

### 1. Insert SD Card and Boot

- Insert SD card into Raspberry Pi
- Connect Ethernet cable (for initial setup)
- Connect power
- Wait 2-3 minutes for first boot

### 2. SSH Access

Default credentials:
- **Username:** `pi`
- **Password:** `raspberry`

```bash
# Find Pi on network
ping raspberrypi.local

# SSH in
ssh pi@raspberrypi.local
```

**IMPORTANT:** Change the default password immediately:
```bash
passwd
```

### 3. Run Initial Setup

```bash
# Run mesh network setup wizard
sudo /opt/mesh-network/setup.sh
```

The setup wizard will ask for:
- Node hostname (e.g., `mesh-router-1`)
- Node type (pre-selected based on image)
- Network interfaces configuration
- OSPF area ID
- Anycast IP (for cache/gateway nodes)
- WiFi settings (for mesh routers)

### 4. Configure Node-Specific Settings

#### Monitoring Node

```bash
cd /opt/mesh-network

# Configure environment
cp docker/monitoring/.env.example docker/monitoring/.env
nano docker/monitoring/.env

# Generate secure passwords
echo "DB_PASSWORD=$(openssl rand -hex 32)" >> docker/monitoring/.env
echo "SECRET_KEY=$(openssl rand -hex 32)" >> docker/monitoring/.env

# Start monitoring stack
docker-compose -f docker/monitoring-docker-compose.yml up -d

# Check status
docker-compose -f docker/monitoring-docker-compose.yml ps
```

Access dashboard: `http://raspberry-pi-ip:8080`

#### Update Cache Node

```bash
cd /opt/mesh-network

# Start LANcache
docker-compose -f docker/lancache-docker-compose.yml up -d

# Check status
docker ps
```

#### Mesh Router / Gateway

WiFi mesh is automatically configured during setup wizard.

Manual configuration:
```bash
sudo nano /etc/hostapd/hostapd.conf
sudo systemctl restart hostapd
```

## Post-Installation

### Update Mesh Software

```bash
# Pull latest changes
cd /opt/mesh-network
git pull

# Restart services
sudo systemctl restart frr etcd coredns
```

### Update System

```bash
# Update OS
sudo apt update && sudo apt upgrade -y

# Update Docker images (for monitoring/cache nodes)
docker-compose pull
docker-compose up -d
```

### Backup Configuration

```bash
# Create backup
mesh-backup

# List backups
ls -lh /var/backups/mesh-network/

# Restore from backup
mesh-restore /var/backups/mesh-network/backup-20240315.tar.gz
```

## Building Custom Images

### Prerequisites

```bash
# On Ubuntu/Debian build machine
sudo apt-get install -y \
    wget xz-utils parted kpartx \
    qemu-user-static qemu-utils \
    fdisk gdisk dosfstools \
    libguestfs-tools git
```

### Build Single Image

```bash
git clone https://github.com/YOUR-USERNAME/mesh-network.git
cd mesh-network/images

# Build monitoring node image
sudo ./build-pi-image.sh monitoring

# Output will be in: images/output/
```

### Build All Images

```bash
cd mesh-network/images
sudo ./build-pi-image.sh all
```

### Build Specific Version

```bash
sudo ./build-pi-image.sh -v 1.1.0 monitoring
```

### Build via GitHub Actions

Images are automatically built on release:

1. Go to GitHub repository
2. Actions → Build Raspberry Pi Images
3. Click "Run workflow"
4. Select node type and version
5. Download from Artifacts or Release page

## Troubleshooting

### Image Won't Boot

**Symptoms:** Red LED only, no green LED activity

**Solutions:**
1. Re-flash SD card
2. Verify SHA256 checksum before flashing
3. Try different SD card (Class 10 or better)
4. Check power supply (5V 3A recommended for Pi 4/5)

### Can't SSH to Pi

**Solutions:**
```bash
# Check if Pi is on network
nmap -sn 192.168.1.0/24

# Try IP address instead of hostname
ssh pi@192.168.1.X

# Enable SSH on SD card (before first boot)
# Mount boot partition and create empty file:
touch /media/boot/ssh
```

### WiFi Not Working

**Solutions:**
```bash
# Check WiFi interface
ip link show

# Check hostapd status
sudo systemctl status hostapd

# Check hostapd logs
sudo journalctl -u hostapd -f

# Verify WiFi regulatory domain
sudo iw reg get

# Set regulatory domain (if needed)
sudo iw reg set DE  # For Germany, adjust for your country
```

### Docker Not Starting (Monitoring/Cache Nodes)

**Solutions:**
```bash
# Check Docker status
sudo systemctl status docker

# Check logs
sudo journalctl -u docker -f

# Restart Docker
sudo systemctl restart docker

# Free up space if needed
docker system prune -a
```

### OSPF Neighbors Not Appearing

**Solutions:**
```bash
# Check FRR status
sudo systemctl status frr

# Check OSPF configuration
sudo vtysh -c "show running-config"

# Check OSPF neighbors
sudo vtysh -c "show ip ospf neighbor"

# Check network interfaces
ip addr show

# Verify mesh interface is up
ip link show mesh0
```

### etcd Connection Issues

**Solutions:**
```bash
# Check etcd status
sudo systemctl status etcd

# Check etcd members
etcdctl member list

# Check etcd health
etcdctl endpoint health

# Reset etcd data (WARNING: deletes all DNS entries)
sudo systemctl stop etcd
sudo rm -rf /var/lib/etcd/*
sudo systemctl start etcd
```

## Image Customization

### Adding Custom Scripts

Before building:
```bash
# Add custom scripts to
images/packer/scripts/custom/

# They will be copied to /opt/mesh-network/custom/
```

### Changing Default Settings

Edit configuration templates in:
```
configs/frr.conf.template
configs/coredns.conf.template
configs/unbound.conf.template
```

### Pre-installing Additional Packages

Edit:
```bash
images/packer/scripts/install-common.sh
```

Add packages to `apt-get install` line.

## Performance Tuning

### Raspberry Pi 4/5 Optimizations

Add to `/boot/config.txt`:
```ini
# Overclock (Pi 4)
over_voltage=2
arm_freq=1750

# Overclock (Pi 5)
over_voltage=4
arm_freq=2400

# GPU memory (for headless)
gpu_mem=16

# USB boot
dtoverlay=dwc2

# Network performance
dtparam=sd_overclock=100
```

### Network Performance

```bash
# Increase network buffers
cat >> /etc/sysctl.conf << EOF
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_rmem=4096 87380 67108864
net.ipv4.tcp_wmem=4096 65536 67108864
EOF

sudo sysctl -p
```

### Storage Performance

```bash
# Use f2fs for SD card
# WARNING: Destroys data, do during image build

# Format
sudo mkfs.f2fs /dev/mmcblk0p2

# Update /etc/fstab
/dev/mmcblk0p2  /  f2fs  defaults,noatime  0  1
```

## Security Hardening

### Change Default Passwords

```bash
# Change pi user password
passwd

# Change root password
sudo passwd root
```

### SSH Key Authentication

```bash
# On your computer
ssh-keygen -t ed25519

# Copy to Pi
ssh-copy-id pi@raspberrypi.local

# Disable password authentication
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart ssh
```

### Firewall

```bash
# Install UFW
sudo apt install -y ufw

# Allow SSH
sudo ufw allow 22/tcp

# Allow OSPF
sudo ufw allow proto ospf

# Allow etcd (from mesh network only)
sudo ufw allow from 169.254.0.0/16 to any port 2379,2380 proto tcp

# Enable firewall
sudo ufw enable
```

### Automatic Security Updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

## Support

- **Documentation:** [GitHub Wiki](https://github.com/YOUR-USERNAME/mesh-network/wiki)
- **Issues:** [GitHub Issues](https://github.com/YOUR-USERNAME/mesh-network/issues)
- **Discussions:** [GitHub Discussions](https://github.com/YOUR-USERNAME/mesh-network/discussions)

## Image Changelog

### Version 1.0.0 (2024-03-15)
- Initial release
- Based on Raspberry Pi OS Bookworm (Debian 12)
- FRR 8.5
- etcd 3.5
- Docker 24.0 (for monitoring/cache nodes)
- All 6 node types available
