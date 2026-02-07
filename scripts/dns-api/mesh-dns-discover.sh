#!/bin/bash
# Mesh DNS Resolver Setup
# Discovers DNS servers via multicast and configures local resolver
# Should run on all mesh nodes (not just DNS servers)

set -e

MCAST_GROUP="${DNS_MCAST_GROUP:-239.255.77.69}"
MCAST_PORT="${DNS_MCAST_PORT:-5381}"
DISCOVERY_TIMEOUT="${DNS_DISCOVERY_TIMEOUT:-5}"
CONFIG_FILE="/etc/mesh-network/dns-servers.conf"
RESOLV_CONF="/etc/resolv.conf"

# Discover DNS servers via multicast
discover_dns_servers() {
    echo "Discovering DNS servers on ${MCAST_GROUP}:${MCAST_PORT}..."

    # Use Python for multicast listening (more reliable than socat)
    python3 << 'PYTHON_SCRIPT'
import socket
import struct
import json
import sys
import time

MCAST_GROUP = '239.255.77.69'
MCAST_PORT = 5381
TIMEOUT = 5

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
except:
    pass

sock.bind(('', MCAST_PORT))
sock.settimeout(TIMEOUT)

mreq = struct.pack('4sl', socket.inet_aton(MCAST_GROUP), socket.INADDR_ANY)
sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)

dns_servers = {}
start = time.time()

print(f"Listening for DNS announcements ({TIMEOUT}s)...", file=sys.stderr)

while time.time() - start < TIMEOUT:
    try:
        data, addr = sock.recvfrom(4096)
        msg = json.loads(data.decode('utf-8'))
        if msg.get('type') == 'dns-announce':
            ip = addr[0]
            dns_servers[ip] = {
                'hostname': msg.get('hostname'),
                'ip': ip,
                'api_port': msg.get('api_port', 5380),
                'node_count': msg.get('node_count', 0)
            }
            print(f"Found: {msg.get('hostname')} ({ip})", file=sys.stderr)
    except socket.timeout:
        break
    except:
        continue

# Output discovered servers
for ip, info in dns_servers.items():
    print(f"{ip}:{info['api_port']}:{info['hostname']}")

sock.close()
PYTHON_SCRIPT
}

# Configure resolv.conf with discovered DNS servers
configure_resolver() {
    local servers="$1"

    if [ -z "$servers" ]; then
        echo "No DNS servers discovered, keeping current config"
        return 1
    fi

    # Backup current resolv.conf
    cp "$RESOLV_CONF" "${RESOLV_CONF}.backup" 2>/dev/null || true

    # Create new resolv.conf
    {
        echo "# Mesh Network DNS - Auto-configured"
        echo "# Generated: $(date)"
        echo "search mesh local"
        echo ""

        # Add discovered DNS servers
        echo "$servers" | while IFS=: read -r ip port hostname; do
            echo "nameserver $ip  # $hostname"
        done

        # Add fallback public DNS
        echo ""
        echo "# Fallback"
        echo "nameserver 1.1.1.1"
        echo "nameserver 8.8.8.8"
    } > "${RESOLV_CONF}.new"

    # Apply if using resolvconf
    if command -v resolvconf &> /dev/null; then
        cat "${RESOLV_CONF}.new" | resolvconf -a mesh0
    else
        # Direct overwrite (may be overwritten by DHCP)
        mv "${RESOLV_CONF}.new" "$RESOLV_CONF"
    fi

    echo "DNS resolver configured"
}

# Save discovered servers to config
save_config() {
    local servers="$1"
    mkdir -p "$(dirname "$CONFIG_FILE")"

    {
        echo "# Mesh DNS Servers - Auto-discovered"
        echo "# Generated: $(date)"
        echo ""
        echo "$servers" | while IFS=: read -r ip port hostname; do
            echo "DNS_SERVER_${hostname}=${ip}:${port}"
        done
    } > "$CONFIG_FILE"
}

# Configure systemd-resolved if available
configure_systemd_resolved() {
    local servers="$1"

    if ! systemctl is-active --quiet systemd-resolved; then
        return 0
    fi

    # Extract IPs
    local dns_ips=$(echo "$servers" | cut -d: -f1 | tr '\n' ' ')

    # Create drop-in config
    mkdir -p /etc/systemd/resolved.conf.d/
    cat > /etc/systemd/resolved.conf.d/mesh-dns.conf << EOF
[Resolve]
DNS=${dns_ips}
Domains=~mesh ~local
EOF

    systemctl restart systemd-resolved
    echo "systemd-resolved configured"
}

# Configure NetworkManager if available
configure_networkmanager() {
    local servers="$1"

    if ! systemctl is-active --quiet NetworkManager; then
        return 0
    fi

    # Extract first DNS IP
    local primary_dns=$(echo "$servers" | head -1 | cut -d: -f1)

    # Create dnsmasq config for NetworkManager
    mkdir -p /etc/NetworkManager/dnsmasq.d/
    cat > /etc/NetworkManager/dnsmasq.d/mesh-dns.conf << EOF
# Forward .mesh queries to mesh DNS
server=/mesh/${primary_dns}
EOF

    # Reload NetworkManager
    nmcli general reload dns-full 2>/dev/null || true
    echo "NetworkManager configured"
}

# Main
main() {
    echo "=== Mesh DNS Discovery ==="

    # Discover DNS servers
    servers=$(discover_dns_servers)

    if [ -z "$servers" ]; then
        echo "No DNS servers found on multicast"

        # Try Avahi/mDNS fallback
        if command -v avahi-browse &> /dev/null; then
            echo "Trying Avahi discovery..."
            servers=$(avahi-browse -trp _dns._udp 2>/dev/null | \
                grep "=;" | \
                awk -F';' '{print $8":"53":"$4}' | \
                head -3)
        fi
    fi

    if [ -z "$servers" ]; then
        echo "No DNS servers discovered"
        exit 1
    fi

    echo ""
    echo "Discovered DNS servers:"
    echo "$servers" | while IFS=: read -r ip port hostname; do
        echo "  - $hostname ($ip:$port)"
    done
    echo ""

    # Save config
    save_config "$servers"

    # Configure resolver
    configure_resolver "$servers"
    configure_systemd_resolved "$servers" 2>/dev/null || true
    configure_networkmanager "$servers" 2>/dev/null || true

    echo ""
    echo "DNS configuration complete!"
    echo "Test with: dig monitoring.mesh"
}

case "${1:-discover}" in
    discover|setup)
        main
        ;;
    show)
        cat "$CONFIG_FILE" 2>/dev/null || echo "No DNS servers configured"
        ;;
    *)
        echo "Usage: $0 {discover|setup|show}"
        exit 1
        ;;
esac
