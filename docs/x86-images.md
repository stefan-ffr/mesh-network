# x86/64 Images

## Overview

Pre-built x86/64 images for PCs, servers, and virtual machines. Available in multiple formats for different hypervisors and bare metal deployment.

## Supported Platforms

### Virtualization
- ✅ **QEMU/KVM** - Linux virtualization (`.qcow2`)
- ✅ **VMware** - Workstation/ESXi (`.vmdk`)
- ✅ **VirtualBox** - Cross-platform (`.vdi`)
- ✅ **Hyper-V** - Microsoft (`.vhd`)
- ✅ **Proxmox VE** - Uses QCOW2 format

### Bare Metal
- ✅ **Physical servers** - Via dd (`.img`)
- ✅ **Mini PCs** - Intel NUC, Lenovo ThinkCentre, etc.
- ✅ **Industrial PCs** - x86 embedded systems

## Available Images

| Image | Size (compressed) | Use Case | Min RAM |
|-------|------------------|----------|---------|
| **mesh-router** | ~1.5GB | WiFi mesh (USB WiFi required) | 1GB |
| **lan-router** | ~1.2GB | Wired mesh router | 512MB |
| **gateway-wifi** | ~1.5GB | WiFi mesh + WAN | 1GB |
| **gateway-wired** | ~1.2GB | Wired mesh + WAN | 512MB |
| **update-cache** | ~2.0GB | LANcache server | 2GB |
| **monitoring** | ~1.8GB | Network monitoring | 2GB |

## Download Images

### From GitHub Releases

```bash
# Download (choose your format and node type)
wget https://github.com/YOUR-USERNAME/mesh-network/releases/latest/download/mesh-network-monitoring-1.0.0-x86_64.qcow2.xz

# Verify checksum
wget https://github.com/YOUR-USERNAME/mesh-network/releases/latest/download/mesh-network-monitoring-1.0.0-x86_64.qcow2.xz.sha256
sha256sum -c mesh-network-monitoring-1.0.0-x86_64.qcow2.xz.sha256

# Extract
xz -d mesh-network-monitoring-1.0.0-x86_64.qcow2.xz
```

### Available Formats

Replace `qcow2` with your preferred format:
- `qcow2` - QEMU/KVM
- `img` - RAW/dd
- `vmdk` - VMware
- `vdi` - VirtualBox
- `vhd` - Hyper-V

## Usage by Platform

### QEMU/KVM (Linux)

```bash
# Extract image
xz -d mesh-network-monitoring-1.0.0-x86_64.qcow2.xz

# Run directly
qemu-system-x86_64 \
  -m 2048 \
  -hda mesh-network-monitoring-1.0.0-x86_64.qcow2 \
  -net nic -net user

# Or import into virt-manager
virt-install \
  --name mesh-monitoring \
  --ram 2048 \
  --vcpus 2 \
  --disk path=mesh-network-monitoring-1.0.0-x86_64.qcow2,format=qcow2 \
  --import \
  --os-variant debian12
```

### Proxmox VE

```bash
# Upload QCOW2 to Proxmox
scp mesh-network-monitoring-1.0.0-x86_64.qcow2 root@proxmox:/var/lib/vz/images/

# On Proxmox host
qm create 100 --name mesh-monitoring --memory 2048 --net0 virtio,bridge=vmbr0
qm importdisk 100 /var/lib/vz/images/mesh-network-monitoring-1.0.0-x86_64.qcow2 local-lvm
qm set 100 --scsihw virtio-scsi-pci --scsi0 local-lvm:vm-100-disk-0
qm set 100 --boot c --bootdisk scsi0
qm start 100
```

### VMware Workstation

1. Extract: `xz -d mesh-network-monitoring-1.0.0-x86_64.vmdk.xz`
2. Open VMware Workstation
3. File → New Virtual Machine → Custom
4. Select "I will install the operating system later"
5. Guest OS: Linux → Debian 12 64-bit
6. Remove default disk
7. Add → Hard Disk → Use existing virtual disk
8. Select the `.vmdk` file
9. Finish and start VM

### VMware ESXi

```bash
# Upload via SCP
scp mesh-network-monitoring-1.0.0-x86_64.vmdk root@esxi-host:/vmfs/volumes/datastore1/

# Create VM via ESXi web interface
# 1. Create new VM
# 2. Select "Debian 12 (64-bit)"
# 3. Delete default disk
# 4. Add existing hard disk → select uploaded VMDK
```

### VirtualBox

```bash
# Extract
xz -d mesh-network-monitoring-1.0.0-x86_64.vdi.xz

# Import
VBoxManage createvm --name "Mesh Monitoring" --ostype "Debian_64" --register
VBoxManage storagectl "Mesh Monitoring" --name "SATA Controller" --add sata --bootable on
VBoxManage storageattach "Mesh Monitoring" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium mesh-network-monitoring-1.0.0-x86_64.vdi
VBoxManage modifyvm "Mesh Monitoring" --memory 2048 --vram 16 --cpus 2
VBoxManage modifyvm "Mesh Monitoring" --nic1 bridged --bridgeadapter1 eth0
VBoxManage startvm "Mesh Monitoring"
```

Or use VirtualBox GUI:
1. Machine → New
2. Name: Mesh Monitoring, Type: Linux, Version: Debian (64-bit)
3. Use existing virtual hard disk → select `.vdi` file
4. Settings → Network → Bridged Adapter
5. Start

### Hyper-V (Windows)

```powershell
# Extract (use 7-Zip or similar)
# In PowerShell:

# Convert VHD to VHDX (optional, for better performance)
Convert-VHD -Path "mesh-network-monitoring-1.0.0-x86_64.vhd" -DestinationPath "mesh-monitoring.vhdx"

# Create VM
New-VM -Name "Mesh Monitoring" -MemoryStartupBytes 2GB -VHDPath "mesh-monitoring.vhdx" -Generation 1
Set-VMProcessor "Mesh Monitoring" -Count 2
Add-VMNetworkAdapter -VMName "Mesh Monitoring" -SwitchName "External Switch"
Start-VM "Mesh Monitoring"
```

### Bare Metal (Physical Hardware)

```bash
# Extract
xz -d mesh-network-monitoring-1.0.0-x86_64.img.xz

# Find target disk
lsblk

# Flash to disk (WARNING: This will erase the target disk!)
sudo dd if=mesh-network-monitoring-1.0.0-x86_64.img of=/dev/sdX bs=4M status=progress conv=fsync

# Or use USB boot disk
sudo dd if=mesh-network-monitoring-1.0.0-x86_64.img of=/dev/sdX bs=4M status=progress
# Boot from USB, then install to internal disk
```

## First Boot Configuration

### Default Credentials
- **Username:** `mesh`
- **Password:** `mesh`
- **Root password:** `mesh`

**⚠️ IMPORTANT:** Change passwords immediately after first login!

### Initial Setup

```bash
# SSH into the machine
ssh mesh@<ip-address>

# Change password
passwd

# Change root password
sudo passwd root

# Run setup wizard
sudo /opt/mesh-network/setup.sh
```

The setup wizard will configure:
- Hostname
- Node type (pre-configured but can be changed)
- Network interfaces
- OSPF settings
- Node-specific configuration

### For Monitoring Node

```bash
cd /opt/mesh-network

# Configure monitoring
cp docker/monitoring/.env.example docker/monitoring/.env
nano docker/monitoring/.env

# Generate secure passwords
echo "DB_PASSWORD=$(openssl rand -hex 32)" >> docker/monitoring/.env
echo "SECRET_KEY=$(openssl rand -hex 32)" >> docker/monitoring/.env

# Start monitoring
docker-compose -f docker/monitoring-docker-compose.yml up -d
```

Access: `http://<ip>:8080`

### For Update Cache Node

```bash
cd /opt/mesh-network

# Start LANcache
docker-compose -f docker/lancache-docker-compose.yml up -d
```

## Network Configuration

### Bridge Adapter (Recommended for Testing)

Connects VM directly to your local network.

**QEMU/KVM:**
```bash
qemu-system-x86_64 -m 2048 -hda image.qcow2 -net nic -net bridge,br=br0
```

**VirtualBox:** Settings → Network → Bridged Adapter

**VMware:** Settings → Network Adapter → Bridged

### NAT (Default)

VM shares host's IP address.

### Host-Only (Isolated Network)

Creates isolated network between VMs and host.

## Resizing Disk

Images come with 8GB disk. To resize:

### QCOW2 (QEMU/KVM)

```bash
# Add 8GB (total 16GB)
qemu-img resize image.qcow2 +8G

# Boot VM and resize partition
sudo parted /dev/sda
  resizepart 2 100%
  quit
sudo resize2fs /dev/sda2
```

### VMDK (VMware)

```bash
# In VMware
vmware-vdiskmanager -x 16GB image.vmdk

# Or in VM settings
# Edit → Virtual Disk → Expand

# Then resize partition inside VM
sudo parted /dev/sda
  resizepart 2 100%
  quit
sudo resize2fs /dev/sda2
```

### VDI (VirtualBox)

```bash
VBoxManage modifymedium disk image.vdi --resize 16384

# Then resize partition inside VM
```

## Performance Tuning

### QEMU/KVM

```bash
# Use KVM acceleration
qemu-system-x86_64 -enable-kvm -m 2048 -cpu host -smp 2 -hda image.qcow2

# Use virtio drivers for better performance
-net nic,model=virtio -net bridge,br=br0
-drive file=image.qcow2,if=virtio
```

### VMware

- Enable 3D acceleration
- Install VMware Tools: `sudo apt install open-vm-tools`
- Allocate at least 2 CPU cores

### VirtualBox

- Enable VT-x/AMD-V
- Allocate at least 2 CPU cores
- Install Guest Additions: `sudo apt install virtualbox-guest-utils`

## Building Custom Images

### Using Packer (Recommended)

```bash
cd images/packer

# Install Packer
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt install packer

# Initialize
packer init x86-64.pkr.hcl

# Build for specific platform
packer build -var="node_type=monitoring" -only=qemu.mesh_network x86-64.pkr.hcl

# Build all formats
packer build -var="node_type=monitoring" x86-64.pkr.hcl
```

### Using Build Script

```bash
cd images

# Build single image
sudo ./build-x86-image.sh monitoring

# Build all images
sudo ./build-x86-image.sh all

# Custom size
sudo ./build-x86-image.sh -s 16G monitoring
```

### Via GitHub Actions

1. Go to Actions → Build x86/64 Images
2. Click "Run workflow"
3. Select node type, version, and build method
4. Download from Artifacts or Release

## Troubleshooting

### VM Won't Boot

**Symptoms:** Black screen, no boot menu

**Solutions:**
- Verify image checksum before use
- Check virtualization is enabled in BIOS
- Try different disk controller (IDE vs SATA vs virtio)
- Increase boot timeout in BIOS/VM settings

### No Network Connectivity

**Solutions:**
```bash
# Check interface
ip addr show

# Restart NetworkManager
sudo systemctl restart NetworkManager

# Check network adapter in VM settings
# Try bridged adapter instead of NAT
```

### Slow Performance

**Solutions:**
- Enable hardware virtualization (VT-x/AMD-V)
- Allocate more RAM (minimum 2GB)
- Use virtio drivers (QEMU/KVM)
- Install guest tools
- Use SSD for VM storage
- Enable KVM acceleration

### Docker Not Starting (Monitoring/Cache)

**Solutions:**
```bash
# Check status
sudo systemctl status docker

# Enable and start
sudo systemctl enable --now docker

# Check logs
sudo journalctl -u docker -f

# Verify KVM is available (for QEMU)
lsmod | grep kvm
```

## Security Hardening

### Change Default Passwords

```bash
# User password
passwd

# Root password
sudo passwd root
```

### SSH Key Authentication

```bash
# On your computer
ssh-keygen -t ed25519
ssh-copy-id mesh@<vm-ip>

# Disable password auth
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
sudo systemctl restart ssh
```

### Firewall

```bash
sudo apt install ufw
sudo ufw allow 22/tcp
sudo ufw allow proto ospf
sudo ufw enable
```

## Comparison: VM vs Bare Metal

### Virtual Machine
**Pros:**
- Easy testing and development
- Snapshots and cloning
- Resource isolation
- Quick deployment

**Cons:**
- Performance overhead
- USB WiFi adapters tricky to pass through
- Extra layer of complexity

### Bare Metal
**Pros:**
- Maximum performance
- Direct hardware access
- Better for WiFi mesh nodes
- Lower latency

**Cons:**
- Harder to test
- No snapshots
- Dedicated hardware required

## Use Cases

### Development/Testing
- VirtualBox or QEMU/KVM
- Snapshots before changes
- Easy rollback

### Production (Server)
- Proxmox VE or VMware ESXi
- HA and clustering
- Resource efficiency

### Production (Appliance)
- Mini PC with bare metal
- Intel NUC, ThinkCentre
- Dedicated monitoring or cache server

### Home Lab
- Mix of VMs and bare metal
- Test upgrades in VMs first
- Deploy to production bare metal

## Image Changelog

### Version 1.0.0 (2024-03-15)
- Initial x86/64 release
- Based on Debian 12 Bookworm
- All 6 node types
- 5 image formats
- FRR 8.5, etcd 3.5, Docker 24.0
