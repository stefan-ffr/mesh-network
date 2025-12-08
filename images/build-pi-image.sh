#!/bin/bash
# Mesh Network - Raspberry Pi Image Builder
# Creates bootable SD card images for different node types

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/output"
CACHE_DIR="${SCRIPT_DIR}/cache"

# Image configuration
BASE_IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2024-03-15/2024-03-15-raspios-bookworm-arm64-lite.img.xz"
BASE_IMAGE_NAME="raspios-bookworm-arm64-lite.img"
MESH_VERSION="1.0.0"

# Node types
NODE_TYPES=("mesh-router" "lan-router" "gateway-wifi" "gateway-wired" "update-cache" "monitoring")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    command -v xz >/dev/null 2>&1 || missing+=("xz-utils")
    command -v parted >/dev/null 2>&1 || missing+=("parted")
    command -v kpartx >/dev/null 2>&1 || missing+=("kpartx")
    command -v qemu-arm-static >/dev/null 2>&1 || missing+=("qemu-user-static")

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

download_base_image() {
    log "Downloading base Raspberry Pi OS image..."

    mkdir -p "${CACHE_DIR}"

    local image_file="${CACHE_DIR}/$(basename ${BASE_IMAGE_URL})"

    if [ -f "${image_file}" ]; then
        info "Base image already downloaded, skipping..."
    else
        wget -O "${image_file}" "${BASE_IMAGE_URL}"
    fi

    if [ ! -f "${CACHE_DIR}/${BASE_IMAGE_NAME}" ]; then
        log "Extracting base image..."
        xz -d -k "${image_file}" -c > "${CACHE_DIR}/${BASE_IMAGE_NAME}"
    fi

    log "Base image ready ✓"
}

create_work_image() {
    local node_type=$1
    local work_image="${BUILD_DIR}/${node_type}.img"

    log "Creating working image for ${node_type}..."

    mkdir -p "${BUILD_DIR}"

    # Copy base image
    cp "${CACHE_DIR}/${BASE_IMAGE_NAME}" "${work_image}"

    # Resize image to 8GB
    log "Resizing image to 8GB..."
    dd if=/dev/zero bs=1M count=4096 >> "${work_image}"

    # Resize partition
    parted "${work_image}" resizepart 2 100%

    echo "${work_image}"
}

mount_image() {
    local image=$1

    log "Mounting image..."

    # Setup loop device without partition scanning
    local loop_device=$(losetup -f --show "${image}")

    # Use kpartx to create device mappings (works better in GitHub Actions)
    kpartx -av "${loop_device}"

    # Wait for device mappings
    sleep 2

    # Get mapper device name (e.g., loop0 -> /dev/mapper/loop0p1)
    local mapper_base=$(basename "${loop_device}")
    local boot_dev="/dev/mapper/${mapper_base}p1"
    local root_dev="/dev/mapper/${mapper_base}p2"

    # Create mount points
    local boot_mount="${BUILD_DIR}/mnt/boot"
    local root_mount="${BUILD_DIR}/mnt/root"

    mkdir -p "${boot_mount}" "${root_mount}"

    # Resize root filesystem BEFORE mounting
    e2fsck -f -y "${root_dev}" || true
    resize2fs "${root_dev}"

    # Mount partitions
    mount "${boot_dev}" "${boot_mount}"
    mount "${root_dev}" "${root_mount}"

    echo "${loop_device}:${boot_mount}:${root_mount}"
}

unmount_image() {
    local mount_info=$1
    IFS=':' read -r loop_device boot_mount root_mount <<< "${mount_info}"

    log "Unmounting image..."

    # Unmount filesystems
    umount "${root_mount}" || true
    umount "${boot_mount}" || true

    # Remove kpartx device mappings
    kpartx -dv "${loop_device}" || true

    # Detach loop device
    losetup -d "${loop_device}" || true

    # Cleanup mount points
    rm -rf "${BUILD_DIR}/mnt"
}

customize_image() {
    local node_type=$1
    local root_mount=$2

    log "Customizing image for ${node_type}..."

    # Copy customization scripts
    cp -r "${SCRIPT_DIR}/../scripts" "${root_mount}/tmp/"
    cp -r "${SCRIPT_DIR}/../configs" "${root_mount}/tmp/"
    cp -r "${SCRIPT_DIR}/../systemd" "${root_mount}/tmp/"

    # Copy QEMU binary for chroot
    cp /usr/bin/qemu-aarch64-static "${root_mount}/usr/bin/"

    # Create customization script
    cat > "${root_mount}/tmp/customize.sh" << 'CUSTOMIZE_EOF'
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
    iptables iproute2 \
    frr \
    etcd-server etcd-client \
    vim nano \
    htop tmux

# Install Docker (for monitoring and cache nodes)
if [[ "${NODE_TYPE}" == "monitoring" ]] || [[ "${NODE_TYPE}" == "update-cache" ]]; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker pi
    systemctl enable docker
fi

# Install node-specific packages
case "${NODE_TYPE}" in
    mesh-router|gateway-wifi)
        apt-get install -y \
            wpasupplicant \
            hostapd \
            wireless-tools \
            iw
        ;;
    gateway-*)
        # Additional packages for gateways
        apt-get install -y \
            dnsmasq \
            fail2ban
        ;;
    update-cache)
        apt-get install -y \
            apt-cacher-ng \
            squid
        ;;
    monitoring)
        apt-get install -y \
            postgresql-client \
            openssh-client \
            snmp
        ;;
esac

# Install mesh network scripts
mkdir -p /opt/mesh-network
cp -r /tmp/scripts/* /opt/mesh-network/ || true
cp -r /tmp/configs /opt/mesh-network/ || true

# Install systemd services
cp /tmp/systemd/*.service /etc/systemd/system/ || true
cp /tmp/systemd/*.timer /etc/systemd/system/ || true

# Configure FRR
echo "frr=yes" > /etc/frr/daemons
echo "zebra=yes" >> /etc/frr/daemons
echo "ospfd=yes" >> /etc/frr/daemons
systemctl enable frr

# Configure etcd
systemctl enable etcd

# Setup first-boot configuration
cat > /etc/rc.local << 'EOF'
#!/bin/bash
# First boot setup

if [ -f /boot/mesh-config.txt ]; then
    # Load configuration
    source /boot/mesh-config.txt

    # Set hostname
    if [ -n "${MESH_HOSTNAME}" ]; then
        hostnamectl set-hostname "${MESH_HOSTNAME}"
    fi

    # Run node-specific setup
    if [ -f "/opt/mesh-network/setup-${MESH_NODE_TYPE}.sh" ]; then
        bash "/opt/mesh-network/setup-${MESH_NODE_TYPE}.sh"
    fi

    # Remove first-boot flag
    rm /boot/mesh-config.txt
fi

exit 0
EOF
chmod +x /etc/rc.local

# Enable SSH
systemctl enable ssh

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*

echo "=== Customization complete ==="
CUSTOMIZE_EOF

    # Replace placeholder
    sed -i "s/__NODE_TYPE__/${node_type}/g" "${root_mount}/tmp/customize.sh"
    chmod +x "${root_mount}/tmp/customize.sh"

    # Run customization in chroot
    log "Running customization script in chroot..."
    chroot "${root_mount}" /tmp/customize.sh

    # Cleanup
    rm "${root_mount}/usr/bin/qemu-aarch64-static"
    rm -rf "${root_mount}/tmp/scripts"
    rm -rf "${root_mount}/tmp/configs"
    rm -rf "${root_mount}/tmp/systemd"
    rm "${root_mount}/tmp/customize.sh"

    # Create version file
    echo "MESH_NETWORK_VERSION=${MESH_VERSION}" > "${root_mount}/etc/mesh-network-version"
    echo "NODE_TYPE=${node_type}" >> "${root_mount}/etc/mesh-network-version"
    echo "BUILD_DATE=$(date -u +'%Y-%m-%d %H:%M:%S UTC')" >> "${root_mount}/etc/mesh-network-version"

    log "Image customization complete ✓"
}

shrink_image() {
    local image=$1
    local output=$2

    log "Shrinking image..."

    # Get used space
    local mount_info=$(mount_image "${image}")
    IFS=':' read -r loop_device boot_mount root_mount <<< "${mount_info}"

    local used_space=$(df -B1M "${root_mount}" | tail -1 | awk '{print $3}')
    unmount_image "${mount_info}"

    # Add 500MB buffer
    local target_size=$((used_space + 500))

    log "Shrinking to ${target_size}MB..."

    # Use pishrink if available
    if command -v pishrink.sh >/dev/null 2>&1; then
        pishrink.sh "${image}" "${output}"
    else
        # Manual shrink
        truncate -s "${target_size}M" "${output}"
        cp "${image}" "${output}"
    fi
}

compress_image() {
    local image=$1
    local output="${image}.xz"

    log "Compressing image..."
    xz -9 -T0 "${image}" -c > "${output}"

    # Calculate checksums
    sha256sum "${output}" > "${output}.sha256"

    log "Compression complete ✓"
    echo "${output}"
}

build_node_image() {
    local node_type=$1

    log "========================================="
    log "Building image for: ${node_type}"
    log "========================================="

    # Create working image
    local work_image=$(create_work_image "${node_type}")

    # Mount image
    local mount_info=$(mount_image "${work_image}")
    IFS=':' read -r loop_device boot_mount root_mount <<< "${mount_info}"

    # Customize image
    customize_image "${node_type}" "${root_mount}"

    # Unmount
    unmount_image "${mount_info}"

    # Compress and move to output
    mkdir -p "${OUTPUT_DIR}"
    local output_name="mesh-network-${node_type}-${MESH_VERSION}-arm64.img"
    local final_image="${OUTPUT_DIR}/${output_name}"

    # Compress
    local compressed=$(compress_image "${work_image}")
    mv "${compressed}" "${final_image}.xz"
    mv "${compressed}.sha256" "${final_image}.xz.sha256"

    # Cleanup
    rm "${work_image}"

    log "========================================="
    log "Image built successfully!"
    log "Output: ${final_image}.xz"
    log "========================================="
}

show_usage() {
    cat << EOF
Mesh Network - Raspberry Pi Image Builder

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

Examples:
  sudo $0 monitoring
  sudo $0 all
  sudo $0 -v 1.1.0 mesh-router

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

    # Download base image
    download_base_image

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
    log "========================================="
}

main "$@"
