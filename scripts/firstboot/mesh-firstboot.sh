#!/bin/bash
# Mesh Network - First Boot Setup Script
# This script runs once on first boot to install packages and configure the node
# It is triggered by the mesh-firstboot.service systemd unit

set -e

LOG_FILE="/var/log/mesh-firstboot.log"
MARKER_FILE="/opt/mesh-network/.firstboot-complete"

# Redirect output to log
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================"
echo "Mesh Network First Boot Setup"
echo "Started at: $(date)"
echo "========================================"

# Check if already run
if [ -f "$MARKER_FILE" ]; then
    echo "First boot setup already completed. Exiting."
    exit 0
fi

# Detect node type from /boot/firmware/mesh-config.txt or /etc/mesh-network-version
NODE_TYPE="monitoring"  # default
if [ -f /boot/firmware/mesh-config.txt ]; then
    source /boot/firmware/mesh-config.txt
    NODE_TYPE="${MESH_NODE_TYPE:-monitoring}"
elif [ -f /etc/mesh-network-version ]; then
    source /etc/mesh-network-version
fi

echo "Node Type: $NODE_TYPE"

# Wait for network
echo "Waiting for network..."
for i in {1..30}; do
    if ping -c1 deb.debian.org &>/dev/null; then
        echo "Network is up!"
        break
    fi
    sleep 2
done

# Update package lists
echo "Updating package lists..."
apt-get update

# Install common packages
echo "Installing common packages..."
apt-get install -y \
    git curl wget \
    python3 python3-pip python3-venv \
    network-manager \
    iptables iproute2 \
    frr frr-pythontools \
    vim nano htop tmux \
    ca-certificates gnupg

# Configure FRR
echo "Configuring FRR..."
cat > /etc/frr/daemons << 'EOF'
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
systemctl start frr

# Install node-specific packages
echo "Installing packages for node type: $NODE_TYPE"
case "$NODE_TYPE" in
    mesh-router)
        apt-get install -y wpasupplicant hostapd wireless-tools iw isc-dhcp-server || true
        systemctl unmask hostapd || true
        ;;
    lan-router)
        apt-get install -y isc-dhcp-server bridge-utils vlan || true
        ;;
    gateway-wifi)
        apt-get install -y wpasupplicant hostapd wireless-tools iw dnsmasq fail2ban iptables-persistent || true
        systemctl unmask hostapd || true
        systemctl enable fail2ban || true
        ;;
    gateway-wired)
        apt-get install -y dnsmasq fail2ban iptables-persistent bridge-utils vlan || true
        systemctl enable fail2ban || true
        ;;
    update-cache)
        echo "Installing Docker for update-cache..."
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker pi || true
        systemctl enable docker
        apt-get install -y apt-cacher-ng || true
        ;;
    monitoring)
        echo "Installing Docker for monitoring..."
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker pi || true
        systemctl enable docker
        apt-get install -y postgresql-client snmp snmpd || true
        ;;
    emergency)
        echo "Installing packages for emergency/disaster relief node..."
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker pi || true
        systemctl enable docker
        # Offline communication
        apt-get install -y samba samba-common-bin nfs-kernel-server syncthing || true
        apt-get install -y nginx sqlite3 python3-flask || true
        # LoRa/Meshtastic support
        apt-get install -y python3-serial || true
        systemctl enable smbd nmbd || true
        mkdir -p /srv/emergency/{files,messages,maps}
        ;;
    portable-gateway)
        echo "Installing packages for portable gateway (LTE/5G/Starlink)..."
        apt-get install -y modemmanager libqmi-utils libmbim-utils usb-modeswitch || true
        apt-get install -y wireguard-tools openvpn || true
        apt-get install -y hostapd dnsmasq wpasupplicant || true
        apt-get install -y gpsd gpsd-clients || true
        apt-get install -y vnstat iftop nload || true
        systemctl unmask hostapd || true
        systemctl enable ModemManager || true
        mkdir -p /etc/mesh-network/failover
        ;;
    comm-hub)
        echo "Installing packages for communication hub..."
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker pi || true
        systemctl enable docker
        # Chat and voice
        apt-get install -y mumble-server prosody || true
        apt-get install -y inspircd || apt-get install -y ngircd || true
        # Email
        apt-get install -y postfix dovecot-imapd || true
        # Service discovery
        apt-get install -y avahi-daemon avahi-utils dnsmasq || true
        systemctl enable mumble-server avahi-daemon || true
        mkdir -p /srv/comm-hub/{matrix,files,mail}
        ;;
    data-node)
        echo "Installing packages for distributed data node..."
        curl -fsSL https://get.docker.com | sh
        usermod -aG docker pi || true
        systemctl enable docker
        # Distributed storage
        apt-get install -y glusterfs-server glusterfs-client || true
        apt-get install -y syncthing restic borgbackup || true
        # File sharing
        apt-get install -y samba samba-common-bin nfs-kernel-server || true
        apt-get install -y lvm2 mdadm smartmontools || true
        systemctl enable glusterd smbd nfs-kernel-server || true
        mkdir -p /srv/data-node/{ipfs,minio,gluster,backups,shares}
        ;;
esac

# Create mesh network directories
mkdir -p /opt/mesh-network
mkdir -p /etc/mesh-network
mkdir -p /var/lib/mesh-network
mkdir -p /var/log/mesh-network

# Write version info
cat > /etc/mesh-network-version << EOF
MESH_NETWORK_VERSION=1.0.0
NODE_TYPE=$NODE_TYPE
BUILD_DATE=$(date -u +'%Y-%m-%d %H:%M:%S UTC')
ARCH=$(uname -m)
FIRSTBOOT_COMPLETED=$(date -u +'%Y-%m-%d %H:%M:%S UTC')
EOF

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/*

# Mark as complete
touch "$MARKER_FILE"

# Disable the firstboot service
systemctl disable mesh-firstboot.service || true

echo "========================================"
echo "First boot setup completed successfully!"
echo "Finished at: $(date)"
echo "========================================"
echo ""
echo "Please reboot to apply all changes:"
echo "  sudo reboot"
