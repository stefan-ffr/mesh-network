#!/bin/bash
# Mesh IPAM Client - Request IP from distributed IPAM
# Usage: mesh-ipam-client.sh [request|renew|release]

set -e

# Configuration
IPAM_SERVER="${MESH_IPAM_SERVER:-10.10.255.53}"  # Uses anycast DNS IP
IPAM_PORT="${MESH_IPAM_PORT:-5381}"
HOSTNAME="${MESH_HOSTNAME:-$(hostname)}"
NODE_TYPE="${MESH_NODE_TYPE:-default}"
INTERFACE="${MESH_INTERFACE:-eth0}"

# Get MAC address
get_mac() {
    cat /sys/class/net/${INTERFACE}/address 2>/dev/null || \
    ip link show ${INTERFACE} 2>/dev/null | grep -oP 'link/ether \K[0-9a-f:]+' || \
    echo ""
}

# Read node type from config
get_node_type() {
    if [ -f /boot/firmware/mesh-config.txt ]; then
        grep MESH_NODE_TYPE /boot/firmware/mesh-config.txt | cut -d= -f2 || echo "$NODE_TYPE"
    else
        echo "$NODE_TYPE"
    fi
}

# API URL
API_URL="http://${IPAM_SERVER}:${IPAM_PORT}/api/v1"

# Request new IP
cmd_request() {
    local mac=$(get_mac)
    local node_type=$(get_node_type)

    echo "Requesting IP from IPAM server ${IPAM_SERVER}..."
    echo "  Hostname: ${HOSTNAME}"
    echo "  MAC: ${mac:-unknown}"
    echo "  Type: ${node_type}"

    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"hostname\":\"${HOSTNAME}\",\"mac\":\"${mac}\",\"node_type\":\"${node_type}\"}" \
        "${API_URL}/allocate" 2>&1)

    if echo "$RESPONSE" | grep -qE '"status":\s*"(allocated|existing)"'; then
        IP=$(echo "$RESPONSE" | grep -oP '"ip":\s*"\K[^"]+')
        echo "Allocated IP: ${IP}"

        # Configure interface
        if [ -n "$IP" ] && [ "$IP" != "null" ]; then
            configure_ip "$IP"
        fi

        echo "$RESPONSE"
    else
        echo "Allocation failed: $RESPONSE"
        exit 1
    fi
}

# Configure IP on interface
configure_ip() {
    local ip="$1"

    echo "Configuring ${INTERFACE} with ${ip}/24..."

    # Check if using NetworkManager
    if systemctl is-active --quiet NetworkManager; then
        nmcli con mod "${INTERFACE}" ipv4.addresses "${ip}/24" ipv4.method manual 2>/dev/null || \
        nmcli con add con-name "mesh-${INTERFACE}" ifname "${INTERFACE}" type ethernet \
            ipv4.addresses "${ip}/24" ipv4.method manual 2>/dev/null || true
        nmcli con up "${INTERFACE}" 2>/dev/null || nmcli con up "mesh-${INTERFACE}" 2>/dev/null || true

    # Check if using systemd-networkd
    elif systemctl is-active --quiet systemd-networkd; then
        cat > /etc/systemd/network/20-mesh-${INTERFACE}.network << EOF
[Match]
Name=${INTERFACE}

[Network]
Address=${ip}/24
DNS=10.10.255.53

[Route]
Gateway=10.10.0.1
EOF
        networkctl reload

    # Fallback to ip command
    else
        ip addr flush dev "${INTERFACE}" 2>/dev/null || true
        ip addr add "${ip}/24" dev "${INTERFACE}"
        ip link set "${INTERFACE}" up
    fi

    echo "IP configured successfully"
}

# Renew lease
cmd_renew() {
    echo "Renewing IP lease for ${HOSTNAME}..."

    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"hostname\":\"${HOSTNAME}\"}" \
        "${API_URL}/renew" 2>&1)

    if echo "$RESPONSE" | grep -q '"status":"renewed"'; then
        echo "Lease renewed successfully"
        echo "$RESPONSE"
    else
        echo "Renew failed, requesting new IP..."
        cmd_request
    fi
}

# Release IP
cmd_release() {
    echo "Releasing IP for ${HOSTNAME}..."

    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"hostname\":\"${HOSTNAME}\"}" \
        "${API_URL}/release" 2>&1)

    echo "$RESPONSE"
}

# Show current allocations
cmd_status() {
    echo "Current allocations:"
    curl -s "${API_URL}/allocations" | python3 -m json.tool 2>/dev/null || \
        curl -s "${API_URL}/allocations"
}

# Show IP ranges
cmd_ranges() {
    echo "IP Ranges:"
    curl -s "${API_URL}/ranges" | python3 -m json.tool 2>/dev/null || \
        curl -s "${API_URL}/ranges"
}

# Main
case "${1:-request}" in
    request|get)
        cmd_request
        ;;
    renew)
        cmd_renew
        ;;
    release)
        cmd_release
        ;;
    status|list)
        cmd_status
        ;;
    ranges)
        cmd_ranges
        ;;
    *)
        echo "Usage: $0 {request|renew|release|status|ranges}"
        echo ""
        echo "Environment variables:"
        echo "  MESH_IPAM_SERVER  - IPAM server (default: 10.10.255.53)"
        echo "  MESH_IPAM_PORT    - API port (default: 5381)"
        echo "  MESH_HOSTNAME     - Hostname to register"
        echo "  MESH_NODE_TYPE    - Node type for IP range selection"
        echo "  MESH_INTERFACE    - Network interface (default: eth0)"
        exit 1
        ;;
esac
