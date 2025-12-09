## Raspberry Pi Image Builder

This directory contains scripts and templates for building custom Raspberry Pi images for mesh network nodes.

## Quick Start

### Build Single Image

```bash
cd images
sudo ./build-pi-image.sh monitoring
```

### Build All Images

```bash
sudo ./build-pi-image.sh all
```

### Build Specific Version

```bash
sudo ./build-pi-image.sh -v 1.1.0 mesh-router
```

## Available Node Types

- `mesh-router` - WiFi mesh router (BATMAN-adv) + LAN clients
- `lan-router` - Wired mesh router (OSPF) + LAN clients
- `gateway-wifi` - WiFi mesh + WAN gateway + NAT/NAT66
- `gateway-wired` - Wired mesh + WAN gateway + NAT/NAT66
- `gateway-hybrid` ⭐ - WiFi + Wired bridge (BATMAN-adv ↔ OSPF) + WAN
- `update-cache` - Update cache server (LANcache)
- `monitoring` - Monitoring node (Docker-based)

All node types include:
- IPv4 + IPv6 dual-stack support
- OSPFv2 and OSPFv3 routing
- Automatic interface detection support
- Interactive setup script included

## Requirements

```bash
sudo apt-get install -y \
    wget xz-utils parted kpartx \
    qemu-user-static qemu-utils \
    fdisk gdisk dosfstools \
    libguestfs-tools
```

## Directory Structure

```
images/
├── build-pi-image.sh       # Main build script
├── packer/                 # Packer templates (alternative method)
│   ├── raspberry-pi.pkr.hcl
│   └── scripts/
│       ├── install-common.sh
│       ├── install-monitoring.sh
│       ├── install-mesh-router.sh
│       └── install-update-cache.sh
├── build/                  # Temporary build directory
├── cache/                  # Downloaded base images
└── output/                 # Final compressed images
```

## Build Process

1. **Download Base Image** - Raspberry Pi OS Lite (arm64)
2. **Create Working Copy** - Resize to 8GB
3. **Mount Image** - Loop mount for modification
4. **Customize** - Install packages, configure services
5. **Unmount** - Clean unmount
6. **Compress** - XZ compression
7. **Checksum** - SHA256 hash

## Output

Images are created in `images/output/`:

```
mesh-network-monitoring-1.0.0-arm64.img.xz
mesh-network-monitoring-1.0.0-arm64.img.xz.sha256
```

## GitHub Actions

Images can be built automatically via GitHub Actions:

1. Go to Actions → Build Raspberry Pi Images
2. Click "Run workflow"
3. Select node type and version
4. Download from Artifacts or Releases

## Using Packer (Alternative)

```bash
cd images/packer

# Build with Packer
packer init raspberry-pi.pkr.hcl
packer build -var="node_type=monitoring" raspberry-pi.pkr.hcl
```

## Customization

### Add Custom Scripts

Place scripts in `packer/scripts/custom/` - they will be copied to `/opt/mesh-network/custom/` in the image.

### Modify Packages

Edit `packer/scripts/install-<node-type>.sh` to add/remove packages.

### Change Base Image

Edit `build-pi-image.sh`:
```bash
BASE_IMAGE_URL="https://downloads.raspberrypi.org/..."
```

## Troubleshooting

### Build Fails at Mount Stage

- Ensure running as root: `sudo ./build-pi-image.sh`
- Check loop devices: `losetup -a`
- Detach stuck loops: `sudo losetup -D`

### Out of Disk Space

- Check available space: `df -h`
- Clean build directory: `sudo rm -rf build/`
- Clean Docker: `docker system prune -a`

### QEMU Issues

```bash
# Ensure QEMU is installed
sudo apt install qemu-user-static

# Re-register QEMU
sudo update-binfmts --enable qemu-aarch64
```

## Documentation

See [docs/raspberry-pi-images.md](../docs/raspberry-pi-images.md) for:
- Flashing instructions
- First boot configuration
- Node-specific setup
- Troubleshooting
- Performance tuning
