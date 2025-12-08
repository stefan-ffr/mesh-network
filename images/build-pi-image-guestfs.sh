#!/bin/bash
# Mesh Network - Raspberry Pi Image Builder (libguestfs version)
# Creates bootable SD card images WITHOUT requiring loop devices
# This version works in GitHub Actions and containerized environments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}/output"
CACHE_DIR="${SCRIPT_DIR}/cache"

# Image configuration
BASE_IMAGE_URL="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-11-19/2024-11-19-raspios-bookworm-arm64-lite.img.xz"
BASE_IMAGE_NAME="raspios-bookworm-arm64-lite.img"
MESH_VERSION="1.0.0"

# Node types
NODE_TYPES=("mesh-router" "lan-router" "gateway-wifi" "gateway-wired" "update-cache" "monitoring")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

check_requirements() {
    log "Checking requirements..."

    local missing=()

    command -v wget >/dev/null 2>&1 || missing+=("wget")
    command -v xz >/dev/null 2>&1 || missing+=("xz-utils")
    command -v virt-customize >/dev/null 2>&1 || missing+=("libguestfs-tools")
    command -v qemu-img >/dev/null 2>&1 || missing+=("qemu-utils")

    if [ ${#missing[@]} -ne 0 ]; then
        error "Missing required packages: ${missing[*]}"
        info "Install with: sudo apt install ${missing[*]}"
        exit 1
    fi

    # Check for QEMU ARM support
    if [ ! -f /usr/bin/qemu-aarch64-static ] && [ ! -f /usr/bin/qemu-aarch64 ]; then
        missing+=("qemu-user-static")
        error "Missing qemu-user-static for ARM emulation"
        info "Install with: sudo apt install qemu-user-static"
        exit 1
    fi

    log "All requirements met"
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

    log "Base image ready"
}

create_work_image() {
    local node_type=$1
    local work_image="${BUILD_DIR}/${node_type}.img"

    log "Creating working image for ${node_type}..."

    mkdir -p "${BUILD_DIR}"

    # Copy base image
    cp "${CACHE_DIR}/${BASE_IMAGE_NAME}" "${work_image}"

    # Resize image to 8GB using qemu-img (no loop device needed)
    log "Resizing image to 8GB..."
    qemu-img resize -f raw "${work_image}" 8G

    # Resize the root partition using guestfish
    log "Expanding root partition..."
    guestfish --rw -a "${work_image}" <<EOF
run
part-resize /dev/sda 2 -1
e2fsck-f /dev/sda2
resize2fs /dev/sda2
EOF

    echo "${work_image}"
}

create_customization_script() {
    local node_type=$1
    local script_file="${BUILD_DIR}/customize-${node_type}.sh"

    cat > "${script_file}" << CUSTOMIZE_EOF
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
export NODE_TYPE="${node_type}"

echo "=== Customizing Mesh Network Node: \${NODE_TYPE} ==="

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
if [[ "\${NODE_TYPE}" == "monitoring" ]] || [[ "\${NODE_TYPE}" == "update-cache" ]]; then
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker pi || true
    systemctl enable docker
fi

# Install node-specific packages
case "\${NODE_TYPE}" in
    mesh-router|gateway-wifi)
        apt-get install -y \
            wpasupplicant \
            hostapd \
            wireless-tools \
            iw
        ;;
    gateway-*)
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

# Create mesh network directories
mkdir -p /opt/mesh-network

# Configure FRR
cat > /etc/frr/daemons << 'FRREOF'
frr=yes
zebra=yes
ospfd=yes
FRREOF
systemctl enable frr

# Configure etcd
systemctl enable etcd

# Setup first-boot configuration
cat > /etc/rc.local << 'RCEOF'
#!/bin/bash
if [ -f /boot/mesh-config.txt ]; then
    source /boot/mesh-config.txt
    if [ -n "\${MESH_HOSTNAME}" ]; then
        hostnamectl set-hostname "\${MESH_HOSTNAME}"
    fi
    if [ -f "/opt/mesh-network/setup-\${MESH_NODE_TYPE}.sh" ]; then
        bash "/opt/mesh-network/setup-\${MESH_NODE_TYPE}.sh"
    fi
    rm /boot/mesh-config.txt
fi
exit 0
RCEOF
chmod +x /etc/rc.local

# Enable SSH
systemctl enable ssh

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "=== Customization complete ==="
CUSTOMIZE_EOF

    chmod +x "${script_file}"
    echo "${script_file}"
}

customize_image() {
    local node_type=$1
    local work_image=$2

    log "Customizing image for ${node_type} using virt-customize..."

    # Create customization script
    local customize_script=$(create_customization_script "${node_type}")

    # Create version file content
    local version_content="MESH_NETWORK_VERSION=${MESH_VERSION}
NODE_TYPE=${node_type}
BUILD_DATE=$(date -u +'%Y-%m-%d %H:%M:%S UTC')
ARCH=arm64"

    # Use virt-customize to modify the image
    # This works WITHOUT loop devices!
    virt-customize -a "${work_image}" \
        --upload "${customize_script}:/tmp/customize.sh" \
        --run-command "chmod +x /tmp/customize.sh" \
        --run-command "/tmp/customize.sh" \
        --run-command "rm /tmp/customize.sh" \
        --write "/etc/mesh-network-version:${version_content}" \
        --run-command "mkdir -p /opt/mesh-network"

    # Copy mesh network files if they exist
    if [ -d "${SCRIPT_DIR}/../scripts" ]; then
        log "Copying mesh network scripts..."
        # Create a tarball and upload it
        local scripts_tar="${BUILD_DIR}/scripts.tar.gz"
        tar -czf "${scripts_tar}" -C "${SCRIPT_DIR}/.." scripts configs systemd 2>/dev/null || true

        if [ -f "${scripts_tar}" ]; then
            virt-customize -a "${work_image}" \
                --upload "${scripts_tar}:/tmp/mesh-files.tar.gz" \
                --run-command "tar -xzf /tmp/mesh-files.tar.gz -C /opt/mesh-network/ 2>/dev/null || true" \
                --run-command "rm /tmp/mesh-files.tar.gz" \
                --run-command "cp /opt/mesh-network/systemd/*.service /etc/systemd/system/ 2>/dev/null || true" \
                --run-command "cp /opt/mesh-network/systemd/*.timer /etc/systemd/system/ 2>/dev/null || true"
            rm "${scripts_tar}"
        fi
    fi

    # Clean up local script
    rm "${customize_script}"

    log "Image customization complete"
}

compress_image() {
    local image=$1
    local output_name=$2

    log "Compressing image..."

    local output="${OUTPUT_DIR}/${output_name}.xz"
    mkdir -p "${OUTPUT_DIR}"

    xz -9 -T0 "${image}" -c > "${output}"

    # Calculate checksums
    sha256sum "${output}" > "${output}.sha256"
    cd "${OUTPUT_DIR}" && sha256sum "$(basename ${output})" > "$(basename ${output}).sha256"

    log "Compression complete"
    echo "${output}"
}

build_node_image() {
    local node_type=$1

    log "========================================="
    log "Building image for: ${node_type}"
    log "========================================="

    # Create working image
    local work_image=$(create_work_image "${node_type}")

    # Customize image using virt-customize (no loop devices!)
    customize_image "${node_type}" "${work_image}"

    # Compress
    local output_name="mesh-network-${node_type}-${MESH_VERSION}-arm64.img"
    local compressed=$(compress_image "${work_image}" "${output_name}")

    # Cleanup work image
    rm "${work_image}"

    log "========================================="
    log "Image built successfully!"
    log "Output: ${compressed}"
    log "========================================="
}

show_usage() {
    cat << EOF
Mesh Network - Raspberry Pi Image Builder (libguestfs version)
This version works in GitHub Actions without loop device support.

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
  $0 monitoring
  $0 all
  $0 -v 1.1.0 mesh-router

Note: This script does NOT require root/sudo as it uses libguestfs
      instead of loop devices.

EOF
}

main() {
    local node_type=""
    local clean=false

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

    if [ "$clean" = true ]; then
        log "Cleaning build directory..."
        rm -rf "${BUILD_DIR}"
    fi

    if [ -z "${node_type}" ]; then
        show_usage
        exit 1
    fi

    check_requirements
    download_base_image

    if [ "${node_type}" = "all" ]; then
        for type in "${NODE_TYPES[@]}"; do
            build_node_image "${type}"
        done
    else
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
