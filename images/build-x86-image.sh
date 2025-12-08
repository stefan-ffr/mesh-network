#!/bin/bash
# Mesh Network - x86/64 Image Builder
# Creates bootable disk images for PCs, VMs, and mini-PCs

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build-x86"
OUTPUT_DIR="${SCRIPT_DIR}/output"
CACHE_DIR="${SCRIPT_DIR}/cache"

# Image configuration
BASE_IMAGE_URL="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
MESH_VERSION="1.0.0"
IMAGE_SIZE="8G"  # Can be resized by user

# Node types
NODE_TYPES=("mesh-router" "lan-router" "gateway-wifi" "gateway-wired" "update-cache" "monitoring")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

check_requirements() {
    log "Checking requirements..."

    local missing=()

    command -v wget >/dev/null 2>&1 || missing+=("wget")
    command -v qemu-img >/dev/null 2>&1 || missing+=("qemu-utils")
    command -v virt-install >/dev/null 2>&1 || missing+=("virtinst")
    command -v virt-customize >/dev/null 2>&1 || missing+=("libguestfs-tools")
    command -v genisoimage >/dev/null 2>&1 || missing+=("genisoimage")

    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required packages: ${missing[*]}"
        info "Install with: sudo apt install ${missing[*]}"
        exit 1
    fi

    if [ "$EUID" -ne 0 ]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi

    log "All requirements met ✓"
}

download_base_iso() {
    log "Downloading base Debian ISO..."

    mkdir -p "${CACHE_DIR}"

    local iso_file="${CACHE_DIR}/debian-12-amd64-netinst.iso"

    if [ -f "${iso_file}" ]; then
        info "Base ISO already downloaded, skipping..."
    else
        wget -O "${iso_file}" "${BASE_IMAGE_URL}"
    fi

    log "Base ISO ready ✓"
}

create_preseed() {
    local node_type=$1
    local preseed_file="${BUILD_DIR}/preseed-${node_type}.cfg"

    log "Creating preseed configuration..."

    mkdir -p "${BUILD_DIR}"

    cat > "${preseed_file}" << 'PRESEED_EOF'
#### Debian 12 Preseed for Mesh Network

### Localization
d-i debian-installer/language string en
d-i debian-installer/country string DE
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

### Network configuration
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string mesh-node
d-i netcfg/get_domain string mesh.local
d-i netcfg/wireless_wep string

### Mirror settings
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

### Account setup
d-i passwd/root-login boolean true
d-i passwd/root-password password mesh
d-i passwd/root-password-again password mesh
d-i passwd/user-fullname string Mesh User
d-i passwd/username string mesh
d-i passwd/user-password password mesh
d-i passwd/user-password-again password mesh

### Clock and time zone
d-i clock-setup/utc boolean true
d-i time/zone string Europe/Berlin
d-i clock-setup/ntp boolean true

### Partitioning
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

### Base system installation
d-i base-installer/install-recommends boolean false
d-i base-installer/kernel/image string linux-image-amd64

### Package selection
tasksel tasksel/first multiselect standard, ssh-server
d-i pkgsel/include string sudo curl wget git vim htop tmux python3 python3-pip network-manager
d-i pkgsel/upgrade select full-upgrade
popularity-contest popularity-contest/participate boolean false

### Boot loader installation
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string default

### Finishing up
d-i finish-install/reboot_in_progress note

### Late commands
d-i preseed/late_command string \
    in-target sed -i 's/PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config; \
    in-target systemctl enable ssh; \
    echo "mesh ALL=(ALL) NOPASSWD: ALL" > /target/etc/sudoers.d/mesh; \
    chmod 0440 /target/etc/sudoers.d/mesh;
PRESEED_EOF

    echo "${preseed_file}"
}

create_disk_image() {
    local node_type=$1
    local disk_image="${BUILD_DIR}/${node_type}.qcow2"

    log "Creating disk image (${IMAGE_SIZE})..."

    mkdir -p "${BUILD_DIR}"

    # Create qcow2 image
    qemu-img create -f qcow2 "${disk_image}" "${IMAGE_SIZE}"

    echo "${disk_image}"
}

install_base_system() {
    local node_type=$1
    local disk_image=$2
    local preseed_file=$3

    log "Installing base Debian system via virt-install..."

    local iso_file="${CACHE_DIR}/debian-12-amd64-netinst.iso"

    # Create custom ISO with preseed
    local custom_iso="${BUILD_DIR}/debian-custom-${node_type}.iso"

    info "Creating custom installation ISO..."
    mkdir -p "${BUILD_DIR}/iso-mount"
    mkdir -p "${BUILD_DIR}/iso-new"

    # Mount original ISO
    mount -o loop "${iso_file}" "${BUILD_DIR}/iso-mount"

    # Copy contents
    rsync -a "${BUILD_DIR}/iso-mount/" "${BUILD_DIR}/iso-new/"

    # Unmount
    umount "${BUILD_DIR}/iso-mount"

    # Add preseed
    cp "${preseed_file}" "${BUILD_DIR}/iso-new/preseed.cfg"

    # Modify boot parameters
    sed -i 's/append  /append auto=true priority=critical preseed\/file=\/cdrom\/preseed.cfg /' \
        "${BUILD_DIR}/iso-new/isolinux/txt.cfg" || true

    # Create new ISO
    genisoimage -r -J -b isolinux/isolinux.bin -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -o "${custom_iso}" "${BUILD_DIR}/iso-new"

    # Install via virt-install (headless)
    virt-install \
        --name "mesh-${node_type}-build" \
        --ram 2048 \
        --vcpus 2 \
        --disk path="${disk_image}",format=qcow2 \
        --cdrom "${custom_iso}" \
        --os-variant debian12 \
        --graphics none \
        --console pty,target_type=serial \
        --extra-args 'console=ttyS0,115200n8 serial auto=true priority=critical preseed/file=/cdrom/preseed.cfg' \
        --wait 30 \
        --noreboot

    # Cleanup
    rm -rf "${BUILD_DIR}/iso-mount" "${BUILD_DIR}/iso-new"
    virsh undefine "mesh-${node_type}-build" || true

    log "Base system installed ✓"
}

customize_image() {
    local node_type=$1
    local disk_image=$2

    log "Customizing image for ${node_type}..."

    # Prepare customization scripts
    local custom_script="${BUILD_DIR}/customize-${node_type}.sh"

    cat > "${custom_script}" << 'CUSTOM_EOF'
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NODE_TYPE="__NODE_TYPE__"

echo "=== Customizing Mesh Network Node: ${NODE_TYPE} ==="

# Update system
apt-get update
apt-get upgrade -y

# Install common packages
apt-get install -y \
    git curl wget \
    python3 python3-pip python3-venv \
    network-manager \
    iptables iproute2 iputils-ping \
    dnsutils net-tools bridge-utils \
    frr frr-pythontools \
    etcd-server etcd-client \
    vim nano htop tmux \
    openssh-server

# Install Docker (for monitoring and cache nodes)
if [[ "${NODE_TYPE}" == "monitoring" ]] || [[ "${NODE_TYPE}" == "update-cache" ]]; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
fi

# Install node-specific packages
case "${NODE_TYPE}" in
    mesh-router|gateway-wifi)
        apt-get install -y \
            wpasupplicant hostapd \
            wireless-tools iw
        systemctl enable hostapd
        ;;
    gateway-*)
        apt-get install -y \
            dnsmasq fail2ban ufw
        ;;
    update-cache)
        apt-get install -y \
            apt-cacher-ng squid
        systemctl enable apt-cacher-ng squid
        ;;
    monitoring)
        apt-get install -y \
            postgresql-client snmp
        ;;
esac

# Configure FRR
cat > /etc/frr/daemons << EOF
frr=yes
zebra=yes
ospfd=yes
bgpd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
EOF

systemctl enable frr
systemctl enable etcd

# Create mesh network directories
mkdir -p /opt/mesh-network
mkdir -p /etc/mesh-network
mkdir -p /var/lib/mesh-network
mkdir -p /var/log/mesh-network

# Create version file
cat > /etc/mesh-network-version << EOF
MESH_NETWORK_VERSION=__VERSION__
NODE_TYPE=${NODE_TYPE}
BUILD_DATE=$(date -u +'%Y-%m-%d %H:%M:%S UTC')
ARCH=x86_64
EOF

# Enable NetworkManager
systemctl enable NetworkManager

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*

echo "=== Customization complete ==="
CUSTOM_EOF

    # Replace placeholders
    sed -i "s/__NODE_TYPE__/${node_type}/g" "${custom_script}"
    sed -i "s/__VERSION__/${MESH_VERSION}/g" "${custom_script}"

    # Run customization using virt-customize
    virt-customize -a "${disk_image}" \
        --run "${custom_script}" \
        --copy-in "${SCRIPT_DIR}/../scripts:/opt/mesh-network/" \
        --copy-in "${SCRIPT_DIR}/../configs:/opt/mesh-network/" \
        --copy-in "${SCRIPT_DIR}/../systemd:/etc/systemd/system/" \
        --hostname "mesh-${node_type}" \
        --timezone "Europe/Berlin" \
        --root-password password:mesh \
        --ssh-inject root:file:/root/.ssh/id_rsa.pub \
        --selinux-relabel

    log "Image customization complete ✓"
}

convert_to_formats() {
    local node_type=$1
    local source_image="${BUILD_DIR}/${node_type}.qcow2"
    local output_base="${OUTPUT_DIR}/mesh-network-${node_type}-${MESH_VERSION}-x86_64"

    log "Converting to multiple formats..."

    mkdir -p "${OUTPUT_DIR}"

    # QCOW2 (for QEMU/KVM)
    log "  - QCOW2 (QEMU/KVM)"
    cp "${source_image}" "${output_base}.qcow2"

    # RAW (for dd, VirtualBox)
    log "  - RAW (dd, VirtualBox)"
    qemu-img convert -f qcow2 -O raw "${source_image}" "${output_base}.img"

    # VMDK (for VMware)
    log "  - VMDK (VMware)"
    qemu-img convert -f qcow2 -O vmdk "${source_image}" "${output_base}.vmdk"

    # VDI (for VirtualBox)
    log "  - VDI (VirtualBox)"
    qemu-img convert -f qcow2 -O vdi "${source_image}" "${output_base}.vdi"

    # VHD (for Hyper-V)
    log "  - VHD (Hyper-V)"
    qemu-img convert -f qcow2 -O vpc "${source_image}" "${output_base}.vhd"

    log "Format conversion complete ✓"
}

compress_images() {
    local node_type=$1
    local output_base="${OUTPUT_DIR}/mesh-network-${node_type}-${MESH_VERSION}-x86_64"

    log "Compressing images..."

    # Compress each format
    for format in qcow2 img vmdk vdi vhd; do
        local file="${output_base}.${format}"
        if [ -f "${file}" ]; then
            log "  - Compressing ${format}..."
            xz -9 -T0 "${file}"
            sha256sum "${file}.xz" > "${file}.xz.sha256"
        fi
    done

    log "Compression complete ✓"
}

build_node_image() {
    local node_type=$1

    log "========================================="
    log "Building x86/64 image for: ${node_type}"
    log "========================================="

    # Create preseed
    local preseed_file=$(create_preseed "${node_type}")

    # Create disk image
    local disk_image=$(create_disk_image "${node_type}")

    # Install base system
    install_base_system "${node_type}" "${disk_image}" "${preseed_file}"

    # Customize image
    customize_image "${node_type}" "${disk_image}"

    # Convert to multiple formats
    convert_to_formats "${node_type}"

    # Compress
    compress_images "${node_type}"

    log "========================================="
    log "Image built successfully!"
    log "Output directory: ${OUTPUT_DIR}"
    log "========================================="
}

show_usage() {
    cat << EOF
Mesh Network - x86/64 Image Builder

Usage: $0 [OPTIONS] [NODE_TYPE]

Node Types:
  mesh-router      - WiFi mesh router + LAN clients
  lan-router       - Wired mesh router + LAN clients
  gateway-wifi     - WiFi mesh + WAN gateway
  gateway-wired    - Wired mesh + WAN gateway
  update-cache     - Update cache server (LANcache)
  monitoring       - Monitoring node
  all              - Build all node types

Options:
  -h, --help       - Show this help message
  -c, --clean      - Clean build directory
  -v, --version V  - Set version (default: ${MESH_VERSION})
  -s, --size SIZE  - Disk size (default: ${IMAGE_SIZE})

Output Formats:
  - QCOW2 (QEMU/KVM)
  - RAW (dd, bare metal)
  - VMDK (VMware)
  - VDI (VirtualBox)
  - VHD (Hyper-V)

Examples:
  sudo $0 monitoring
  sudo $0 -s 16G mesh-router
  sudo $0 -v 1.1.0 all

EOF
}

# Main script
main() {
    local node_type=""
    local clean=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--clean)
                clean=true
                shift
                ;;
            -v|--version)
                MESH_VERSION="$2"
                shift 2
                ;;
            -s|--size)
                IMAGE_SIZE="$2"
                shift 2
                ;;
            *)
                node_type="$1"
                shift
                ;;
        esac
    done

    # Clean if requested
    if [ "$clean" = true ]; then
        log "Cleaning build directory..."
        rm -rf "${BUILD_DIR}"
    fi

    # Show usage if no node type
    if [ -z "${node_type}" ]; then
        show_usage
        exit 1
    fi

    # Check requirements
    check_requirements

    # Download base ISO
    download_base_iso

    # Build images
    if [ "${node_type}" = "all" ]; then
        for type in "${NODE_TYPES[@]}"; do
            build_node_image "${type}"
        done
    else
        # Validate node type
        if [[ ! " ${NODE_TYPES[@]} " =~ " ${node_type} " ]]; then
            error "Invalid node type: ${node_type}"
            show_usage
            exit 1
        fi

        build_node_image "${node_type}"
    fi

    log "========================================="
    log "All images built successfully!"
    log "Output directory: ${OUTPUT_DIR}"
    log ""
    log "Available formats:"
    log "  - .qcow2.xz (QEMU/KVM)"
    log "  - .img.xz (RAW/dd)"
    log "  - .vmdk.xz (VMware)"
    log "  - .vdi.xz (VirtualBox)"
    log "  - .vhd.xz (Hyper-V)"
    log "========================================="
}

main "$@"
