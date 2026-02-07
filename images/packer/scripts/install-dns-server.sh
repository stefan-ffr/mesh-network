#!/bin/bash
# Install packages for automatic DNS server node
# Provides automatic .mesh domain resolution and service discovery
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing DNS server packages ==="

# Docker for containerized services
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker mesh || sudo usermod -aG docker $USER || true
sudo apt-get install -y docker-compose-plugin

# Primary DNS - Unbound (recursive resolver + authoritative for .mesh)
sudo apt-get install -y \
    unbound \
    unbound-anchor

# Secondary/fallback DNS - dnsmasq (DHCP + DNS + TFTP)
sudo apt-get install -y \
    dnsmasq

# mDNS/DNS-SD for zero-config discovery
sudo apt-get install -y \
    avahi-daemon \
    avahi-utils \
    avahi-autoipd \
    libnss-mdns

# DNS utilities
sudo apt-get install -y \
    bind9-dnsutils \
    ldnsutils \
    whois

# Pi-hole for ad blocking (optional, via Docker)
sudo docker pull pihole/pihole:latest || true

# CoreDNS for advanced mesh DNS (Kubernetes-style)
COREDNS_VERSION="1.11.1"
wget -q "https://github.com/coredns/coredns/releases/download/v${COREDNS_VERSION}/coredns_${COREDNS_VERSION}_linux_arm64.tgz" -O /tmp/coredns.tgz || true
if [ -f /tmp/coredns.tgz ]; then
    cd /tmp && tar xzf coredns.tgz
    sudo mv coredns /usr/local/bin/
    rm -f /tmp/coredns.tgz
fi

# Create Unbound config for .mesh domain
sudo mkdir -p /etc/unbound/unbound.conf.d
sudo cat > /etc/unbound/unbound.conf.d/mesh-network.conf << 'UNBOUND_CONF'
# Mesh Network DNS Configuration
server:
    # Listen on all interfaces
    interface: 0.0.0.0
    interface: ::0
    port: 53

    # Access control - allow mesh networks
    access-control: 10.0.0.0/8 allow
    access-control: 172.16.0.0/12 allow
    access-control: 192.168.0.0/16 allow
    access-control: fd00::/8 allow
    access-control: 127.0.0.0/8 allow
    access-control: ::1/128 allow

    # Performance tuning
    num-threads: 2
    msg-cache-size: 50m
    rrset-cache-size: 100m
    cache-max-ttl: 86400
    cache-min-ttl: 300
    prefetch: yes
    prefetch-key: yes

    # Privacy
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes

    # Local .mesh zone
    local-zone: "mesh." static
    local-data: "mesh. 86400 IN SOA ns.mesh. admin.mesh. 1 3600 1200 604800 86400"
    local-data: "mesh. 86400 IN NS ns.mesh."

    # Include dynamic hosts file
    include: /etc/unbound/mesh-hosts.conf

# Forward non-.mesh queries to upstream (when internet available)
forward-zone:
    name: "."
    forward-addr: 1.1.1.1
    forward-addr: 8.8.8.8
    forward-addr: 9.9.9.9
    forward-first: yes
UNBOUND_CONF

# Create empty mesh hosts file
sudo touch /etc/unbound/mesh-hosts.conf
sudo chmod 644 /etc/unbound/mesh-hosts.conf

# Create DNS registration script for nodes
sudo mkdir -p /opt/mesh-network/dns
sudo cat > /opt/mesh-network/dns/register-node.sh << 'REGISTER_SCRIPT'
#!/bin/bash
# Register a node in the mesh DNS
# Usage: register-node.sh <hostname> <ip>

HOSTNAME="${1:-$(hostname)}"
IP="${2:-$(hostname -I | awk '{print $1}')}"
DNS_SERVER="${3:-dns.mesh}"
HOSTS_FILE="/etc/unbound/mesh-hosts.conf"

if [ -z "$IP" ]; then
    echo "Error: Could not determine IP address"
    exit 1
fi

# Add to local hosts file if we're the DNS server
if [ -f "$HOSTS_FILE" ]; then
    # Remove old entry
    sudo sed -i "/local-data: \"${HOSTNAME}.mesh/d" "$HOSTS_FILE"
    # Add new entry
    echo "local-data: \"${HOSTNAME}.mesh. 300 IN A ${IP}\"" | sudo tee -a "$HOSTS_FILE"
    # Reload unbound
    sudo unbound-control reload 2>/dev/null || sudo systemctl reload unbound
    echo "Registered ${HOSTNAME}.mesh -> ${IP}"
fi
REGISTER_SCRIPT
sudo chmod +x /opt/mesh-network/dns/register-node.sh

# Create DNS update service that runs periodically
sudo cat > /opt/mesh-network/dns/update-mesh-dns.sh << 'UPDATE_SCRIPT'
#!/bin/bash
# Auto-discover and register mesh nodes via mDNS/Avahi

HOSTS_FILE="/etc/unbound/mesh-hosts.conf"
TEMP_FILE="/tmp/mesh-hosts.tmp"

echo "# Auto-generated mesh DNS entries - $(date)" > "$TEMP_FILE"
echo "# Manual entries below this line will be preserved" >> "$TEMP_FILE"

# Discover nodes via avahi
avahi-browse -apt 2>/dev/null | grep -E "IPv4|IPv6" | while read line; do
    hostname=$(echo "$line" | awk -F';' '{print $4}')
    ip=$(echo "$line" | awk -F';' '{print $8}')
    if [ -n "$hostname" ] && [ -n "$ip" ]; then
        # Skip link-local addresses
        if [[ ! "$ip" =~ ^fe80 ]] && [[ ! "$ip" =~ ^169\.254 ]]; then
            if [[ "$ip" =~ \. ]]; then
                echo "local-data: \"${hostname}.mesh. 300 IN A ${ip}\""
            else
                echo "local-data: \"${hostname}.mesh. 300 IN AAAA ${ip}\""
            fi
        fi
    fi
done >> "$TEMP_FILE"

# Preserve manual entries
if [ -f "$HOSTS_FILE" ]; then
    grep -A1000 "# Manual entries" "$HOSTS_FILE" 2>/dev/null >> "$TEMP_FILE" || true
fi

# Update and reload
sudo mv "$TEMP_FILE" "$HOSTS_FILE"
sudo unbound-control reload 2>/dev/null || sudo systemctl reload unbound || true

echo "Mesh DNS updated at $(date)"
UPDATE_SCRIPT
sudo chmod +x /opt/mesh-network/dns/update-mesh-dns.sh

# Create systemd timer for auto-update
sudo cat > /etc/systemd/system/mesh-dns-update.service << 'SERVICE'
[Unit]
Description=Update Mesh DNS from discovered nodes
After=network.target unbound.service avahi-daemon.service

[Service]
Type=oneshot
ExecStart=/opt/mesh-network/dns/update-mesh-dns.sh
SERVICE

sudo cat > /etc/systemd/system/mesh-dns-update.timer << 'TIMER'
[Unit]
Description=Periodically update mesh DNS

[Timer]
OnBootSec=60
OnUnitActiveSec=5min
AccuracySec=1min

[Install]
WantedBy=timers.target
TIMER

# Configure dnsmasq as DHCP server with DNS forwarding
sudo cat > /etc/dnsmasq.d/mesh-network.conf << 'DNSMASQ_CONF'
# Mesh Network DHCP and DNS
# Forward .mesh to local Unbound
server=/mesh/127.0.0.1#53

# DHCP range (adjust per deployment)
# dhcp-range=10.10.0.100,10.10.0.200,12h

# Set this server as DNS for DHCP clients
dhcp-option=6,0.0.0.0

# Enable DNS
port=5353
listen-address=127.0.0.1

# Log queries for debugging
log-queries
log-facility=/var/log/dnsmasq.log
DNSMASQ_CONF

# Enable services
sudo systemctl enable docker
sudo systemctl enable unbound
sudo systemctl enable avahi-daemon
sudo systemctl enable mesh-dns-update.timer
# Disable dnsmasq by default (conflicts with unbound on port 53)
sudo systemctl disable dnsmasq || true

# Create DNS directories
sudo mkdir -p /var/lib/mesh-dns
sudo mkdir -p /var/log/mesh-dns
sudo mkdir -p /opt/mesh-network/dns-api

# Initialize unbound-anchor for DNSSEC
sudo unbound-anchor -a /var/lib/unbound/root.key || true

# Install Python Flask for DNS API
echo "Installing DNS API dependencies..."
sudo apt-get install -y python3-flask python3-requests python3-pip || true

# Note: The API scripts are deployed via firstboot or manually
# They should be copied to /opt/mesh-network/dns-api/

echo "=== DNS server packages installed successfully ==="
echo ""
echo "Services:"
echo "  - Unbound: Primary DNS with .mesh zone (port 53)"
echo "  - Avahi: mDNS/DNS-SD discovery"
echo "  - DNS API: REST API on port 5380"
echo "  - Multicast: Discovery on 239.255.77.69:5381"
echo "  - Auto-sync: Between DNS servers"
echo ""
echo "API Endpoints:"
echo "  POST /api/v1/register   - Register a node"
echo "  POST /api/v1/heartbeat  - Send heartbeat"
echo "  GET  /api/v1/nodes      - List all nodes"
echo "  GET  /api/v1/peers      - List DNS peers"
echo "  GET  /api/v1/discover/X - Find service X"
echo "  POST /api/v1/sync       - Force sync with peers"
echo ""
echo "Multicast Group: 239.255.77.69:5381"
echo "Register nodes: /opt/mesh-network/dns-api/mesh-dns-client.sh register"
