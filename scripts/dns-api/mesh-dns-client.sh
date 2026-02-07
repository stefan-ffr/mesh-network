#!/bin/bash
# Mesh DNS Client - Register this node with the mesh DNS server
# Usage: mesh-dns-client.sh [register|heartbeat|unregister]

set -e

# Configuration
DNS_SERVER="${MESH_DNS_SERVER:-dns.mesh}"
DNS_API_PORT="${MESH_DNS_PORT:-5380}"
API_TOKEN="${MESH_DNS_TOKEN:-}"
HOSTNAME="${MESH_HOSTNAME:-$(hostname)}"
NODE_TYPE="${MESH_NODE_TYPE:-}"

# Detect IP addresses
get_ipv4() {
    ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1 || \
    hostname -I 2>/dev/null | awk '{print $1}' || \
    echo ""
}

get_ipv6() {
    ip -6 route get 2001:4860:4860::8888 2>/dev/null | grep -oP 'src \K[0-9a-f:]+' | head -1 || \
    echo ""
}

# Build API URL
API_URL="http://${DNS_SERVER}:${DNS_API_PORT}/api/v1"

# Build auth header
AUTH_HEADER=""
if [ -n "$API_TOKEN" ]; then
    AUTH_HEADER="-H X-API-Token: ${API_TOKEN}"
fi

# Detect services running on this node
detect_services() {
    services="["
    first=true

    # Check common services
    if systemctl is-active --quiet nginx 2>/dev/null || pgrep nginx >/dev/null 2>&1; then
        [ "$first" = true ] || services+=","
        services+='{"name":"http","port":80,"protocol":"tcp"}'
        first=false
    fi

    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        [ "$first" = true ] || services+=","
        services+='{"name":"ssh","port":22,"protocol":"tcp"}'
        first=false
    fi

    if systemctl is-active --quiet grafana-server 2>/dev/null || docker ps 2>/dev/null | grep -q grafana; then
        [ "$first" = true ] || services+=","
        services+='{"name":"grafana","port":3000,"protocol":"tcp"}'
        first=false
    fi

    if systemctl is-active --quiet prometheus 2>/dev/null || docker ps 2>/dev/null | grep -q prometheus; then
        [ "$first" = true ] || services+=","
        services+='{"name":"prometheus","port":9090,"protocol":"tcp"}'
        first=false
    fi

    if systemctl is-active --quiet mumble-server 2>/dev/null; then
        [ "$first" = true ] || services+=","
        services+='{"name":"mumble","port":64738,"protocol":"tcp"}'
        first=false
    fi

    if systemctl is-active --quiet matrix-synapse 2>/dev/null || docker ps 2>/dev/null | grep -q synapse; then
        [ "$first" = true ] || services+=","
        services+='{"name":"matrix","port":8008,"protocol":"tcp"}'
        first=false
    fi

    if systemctl is-active --quiet smbd 2>/dev/null; then
        [ "$first" = true ] || services+=","
        services+='{"name":"smb","port":445,"protocol":"tcp"}'
        first=false
    fi

    if systemctl is-active --quiet nfs-kernel-server 2>/dev/null; then
        [ "$first" = true ] || services+=","
        services+='{"name":"nfs","port":2049,"protocol":"tcp"}'
        first=false
    fi

    services+="]"
    echo "$services"
}

# Commands
cmd_register() {
    IPV4=$(get_ipv4)
    IPV6=$(get_ipv6)
    SERVICES=$(detect_services)

    if [ -z "$IPV4" ] && [ -z "$IPV6" ]; then
        echo "Error: Could not detect IP address"
        exit 1
    fi

    # Read node type from config if not set
    if [ -z "$NODE_TYPE" ] && [ -f /boot/firmware/mesh-config.txt ]; then
        source /boot/firmware/mesh-config.txt
        NODE_TYPE="${MESH_NODE_TYPE:-}"
    fi

    echo "Registering ${HOSTNAME} with DNS server ${DNS_SERVER}..."
    echo "  IPv4: ${IPV4:-none}"
    echo "  IPv6: ${IPV6:-none}"
    echo "  Type: ${NODE_TYPE:-unknown}"

    # Build JSON payload
    JSON=$(cat <<EOF
{
    "hostname": "${HOSTNAME}",
    "ipv4": "${IPV4}",
    "ipv6": "${IPV6}",
    "node_type": "${NODE_TYPE}",
    "services": ${SERVICES},
    "metadata": {
        "arch": "$(uname -m)",
        "os": "$(cat /etc/os-release 2>/dev/null | grep ^ID= | cut -d= -f2 | tr -d '"')"
    }
}
EOF
)

    # Send registration
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        ${AUTH_HEADER} \
        -d "${JSON}" \
        "${API_URL}/register" 2>&1) || true

    if echo "$RESPONSE" | grep -q '"status":"registered"'; then
        echo "Successfully registered as ${HOSTNAME}.mesh"
        echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
    else
        echo "Registration failed: $RESPONSE"
        exit 1
    fi
}

cmd_heartbeat() {
    curl -s -X POST \
        -H "Content-Type: application/json" \
        ${AUTH_HEADER} \
        -d "{\"hostname\": \"${HOSTNAME}\"}" \
        "${API_URL}/heartbeat" || echo "Heartbeat failed"
}

cmd_unregister() {
    echo "Unregistering ${HOSTNAME} from DNS..."
    curl -s -X POST \
        -H "Content-Type: application/json" \
        ${AUTH_HEADER} \
        -d "{\"hostname\": \"${HOSTNAME}\"}" \
        "${API_URL}/unregister"
}

cmd_list() {
    curl -s "${API_URL}/nodes" | python3 -m json.tool 2>/dev/null || \
        curl -s "${API_URL}/nodes"
}

cmd_discover() {
    SERVICE="${1:-http}"
    curl -s "${API_URL}/discover/${SERVICE}" | python3 -m json.tool 2>/dev/null || \
        curl -s "${API_URL}/discover/${SERVICE}"
}

# Main
case "${1:-register}" in
    register)
        cmd_register
        ;;
    heartbeat|ping)
        cmd_heartbeat
        ;;
    unregister|remove)
        cmd_unregister
        ;;
    list|nodes)
        cmd_list
        ;;
    discover|find)
        cmd_discover "$2"
        ;;
    *)
        echo "Usage: $0 {register|heartbeat|unregister|list|discover <service>}"
        echo ""
        echo "Environment variables:"
        echo "  MESH_DNS_SERVER  - DNS server hostname (default: dns.mesh)"
        echo "  MESH_DNS_PORT    - API port (default: 5380)"
        echo "  MESH_DNS_TOKEN   - API authentication token"
        echo "  MESH_HOSTNAME    - Override hostname"
        echo "  MESH_NODE_TYPE   - Node type (e.g., monitoring, gateway)"
        exit 1
        ;;
esac
