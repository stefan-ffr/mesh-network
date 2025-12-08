#!/bin/bash
# Mesh Network - Raspberry Pi Setup Script
#
# This script configures a Raspberry Pi OS installation as a mesh network node.
# Can be run on a fresh Raspberry Pi OS installation.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/mesh-network/main/scripts/setup/raspberry-pi-setup.sh | sudo bash -s -- monitoring
#
# Or manually:
#   wget https://raw.githubusercontent.com/YOUR-USERNAME/mesh-network/main/scripts/setup/raspberry-pi-setup.sh
#   chmod +x raspberry-pi-setup.sh
#   sudo ./raspberry-pi-setup.sh monitoring

set -e

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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

# Get node type
NODE_TYPE=${1:-""}
VALID_TYPES=("mesh-router" "lan-router" "gateway-wifi" "gateway-wired" "update-cache" "monitoring")

if [ -z "$NODE_TYPE" ]; then
    echo "Available node types:"
    for type in "${VALID_TYPES[@]}"; do
        echo "  - $type"
    done
    read -p "Enter node type: " NODE_TYPE
fi

# Validate node type
if [[ ! " ${VALID_TYPES[@]} " =~ " ${NODE_TYPE} " ]]; then
    error "Invalid node type: $NODE_TYPE"
    info "Valid types: ${VALID_TYPES[*]}"
    exit 1
fi

log "Setting up Raspberry Pi as: ${NODE_TYPE}"

# Configuration
GITHUB_REPO="YOUR-USERNAME/mesh-network"
GITHUB_BRANCH="main"
INSTALL_DIR="/opt/mesh-network"
MESH_VERSION="1.0.0"

# Detect architecture
ARCH=$(dpkg --print-architecture)
log "Detected architecture: $ARCH"

# Update system
log "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install common packages
log "Installing common packages..."
apt-get install -y \
    git curl wget \
    python3 python3-pip python3-venv \
    network-manager \
    iptables iproute2 \
    vim nano \
    htop tmux

# Install FRR (routing daemon)
log "Installing FRR..."
curl -s https://deb.frrouting.org/frr/keys.asc | apt-key add -
echo deb https://deb.frrouting.org/frr $(lsb_release -s -c) frr-stable | tee -a /etc/apt/sources.list.d/frr.list
apt-get update
apt-get install -y frr frr-pythontools

# Install etcd
log "Installing etcd..."
ETCD_VERSION="v3.5.9"
ETCD_URL="https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"
wget -q "$ETCD_URL" -O /tmp/etcd.tar.gz
tar -xzf /tmp/etcd.tar.gz -C /tmp/
mv /tmp/etcd-*/etcd* /usr/local/bin/
rm -rf /tmp/etcd*

# Clone mesh network repository
log "Cloning mesh network repository..."
rm -rf "$INSTALL_DIR"
git clone --depth 1 --branch "$GITHUB_BRANCH" "https://github.com/${GITHUB_REPO}.git" "$INSTALL_DIR"

# Copy systemd services
log "Installing systemd services..."
cp "$INSTALL_DIR"/systemd/*.service /etc/systemd/system/ 2>/dev/null || true
cp "$INSTALL_DIR"/systemd/*.timer /etc/systemd/system/ 2>/dev/null || true

# Node-specific setup
case $NODE_TYPE in
    mesh-router|gateway-wifi)
        log "Setting up WiFi mesh configuration..."
        apt-get install -y hostapd batman-adv
        ;;

    monitoring)
        log "Setting up monitoring node..."

        # Install Docker
        if ! command -v docker &> /dev/null; then
            log "Installing Docker..."
            curl -fsSL https://get.docker.com | sh
            usermod -aG docker $SUDO_USER 2>/dev/null || true
            systemctl enable docker
            systemctl start docker
        fi

        # Setup monitoring
        cd "$INSTALL_DIR"
        if [ -f "docker/monitoring-docker-compose.yml" ]; then
            log "Configuring monitoring stack..."
            cp docker/monitoring/.env.example docker/monitoring/.env 2>/dev/null || true

            # Generate secure passwords
            DB_PASSWORD=$(openssl rand -hex 32)
            SECRET_KEY=$(openssl rand -hex 32)

            cat >> docker/monitoring/.env <<EOF

# Auto-generated secure passwords
DB_PASSWORD=${DB_PASSWORD}
SECRET_KEY=${SECRET_KEY}
EOF

            log "Starting monitoring containers..."
            docker-compose -f docker/monitoring-docker-compose.yml up -d

            info "Monitoring dashboard will be available at: http://$(hostname -I | awk '{print $1}'):8080"
        fi
        ;;

    update-cache)
        log "Setting up LANcache..."

        # Install Docker
        if ! command -v docker &> /dev/null; then
            log "Installing Docker..."
            curl -fsSL https://get.docker.com | sh
            usermod -aG docker $SUDO_USER 2>/dev/null || true
            systemctl enable docker
            systemctl start docker
        fi

        cd "$INSTALL_DIR"
        if [ -f "docker/lancache-docker-compose.yml" ]; then
            log "Starting LANcache containers..."
            docker-compose -f docker/lancache-docker-compose.yml up -d
        fi
        ;;
esac

# Configure FRR
log "Configuring FRR for OSPF..."
if [ -d "$INSTALL_DIR/configs/frr" ]; then
    cp "$INSTALL_DIR"/configs/frr/* /etc/frr/ 2>/dev/null || true
    systemctl enable frr
    systemctl start frr
fi

# Configure etcd
log "Configuring etcd..."
mkdir -p /var/lib/etcd
cat > /etc/systemd/system/etcd.service <<EOF
[Unit]
Description=etcd key-value store
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name \$(hostname) \\
  --data-dir /var/lib/etcd \\
  --listen-client-urls http://0.0.0.0:2379 \\
  --advertise-client-urls http://\$(hostname -I | awk '{print \$1}'):2379 \\
  --listen-peer-urls http://0.0.0.0:2380 \\
  --initial-advertise-peer-urls http://\$(hostname -I | awk '{print \$1}'):2380
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable etcd
systemctl start etcd

# Write version file
log "Writing version information..."
cat > /etc/mesh-network-version <<EOF
MESH_NETWORK_VERSION=${MESH_VERSION}
NODE_TYPE=${NODE_TYPE}
BUILD_DATE=$(date -u +'%Y-%m-%d %H:%M:%S UTC')
ARCH=${ARCH}
SETUP_METHOD=script
EOF

# Final message
log "Setup complete!"
echo ""
info "Node Type: ${NODE_TYPE}"
info "Version: ${MESH_VERSION}"
info "Installation: ${INSTALL_DIR}"
echo ""
warn "IMPORTANT: Please reboot the system to apply all changes"
warn "  sudo reboot"
echo ""

if [ "$NODE_TYPE" == "monitoring" ]; then
    info "After reboot, access monitoring dashboard at:"
    info "  http://$(hostname -I | awk '{print $1}'):8080"
fi

echo ""
info "To view logs:"
info "  sudo journalctl -u frr -f"
info "  sudo journalctl -u etcd -f"

if [[ "$NODE_TYPE" == "monitoring" ]] || [[ "$NODE_TYPE" == "update-cache" ]]; then
    info "  docker-compose -f ${INSTALL_DIR}/docker/*-docker-compose.yml logs -f"
fi
