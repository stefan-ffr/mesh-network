#!/bin/bash
# Mesh DNS Anycast Setup
# All DNS servers share 10.10.255.53 via OSPF
# Clients just use this one IP - OSPF routes to nearest DNS

set -e

# Anycast configuration
ANYCAST_IP="${DNS_ANYCAST_IP:-10.10.255.53}"
ANYCAST_PREFIX="${DNS_ANYCAST_PREFIX:-32}"
LOOPBACK_DEV="lo:dns"
OSPF_AREA="${OSPF_AREA:-0.0.0.0}"

# Multicast for DNS coordination
MCAST_GROUP="${DNS_MCAST_GROUP:-239.255.77.69}"
MCAST_PORT="${DNS_MCAST_PORT:-5381}"

echo "=== Mesh DNS Anycast Setup ==="
echo "Anycast IP: ${ANYCAST_IP}/${ANYCAST_PREFIX}"
echo "OSPF Area: ${OSPF_AREA}"

# Step 1: Add anycast IP to loopback
setup_anycast_ip() {
    echo "Adding anycast IP to loopback..."

    # Remove if exists
    ip addr del ${ANYCAST_IP}/${ANYCAST_PREFIX} dev lo 2>/dev/null || true

    # Add anycast IP
    ip addr add ${ANYCAST_IP}/${ANYCAST_PREFIX} dev lo label ${LOOPBACK_DEV}

    echo "  Added ${ANYCAST_IP}/${ANYCAST_PREFIX} to lo"
}

# Step 2: Configure FRR/OSPF to announce the anycast IP
configure_ospf() {
    echo "Configuring OSPF to announce anycast IP..."

    # Check if FRR is running
    if ! systemctl is-active --quiet frr; then
        echo "  FRR not running, starting..."
        systemctl start frr || return 1
    fi

    # Configure via vtysh
    vtysh << EOF
configure terminal
router ospf
  redistribute connected
  network ${ANYCAST_IP}/32 area ${OSPF_AREA}
exit
exit
write memory
EOF

    echo "  OSPF configured to announce ${ANYCAST_IP}"
}

# Step 3: Configure Unbound to listen on anycast IP
configure_unbound() {
    echo "Configuring Unbound to listen on anycast IP..."

    local UNBOUND_CONF="/etc/unbound/unbound.conf.d/anycast.conf"

    cat > ${UNBOUND_CONF} << EOF
# Anycast DNS configuration
server:
    interface: ${ANYCAST_IP}
    interface: 127.0.0.1
    interface: 0.0.0.0

    # Accept queries from anywhere (anycast)
    access-control: 0.0.0.0/0 allow
    access-control: ::/0 allow
EOF

    # Reload unbound
    systemctl reload unbound || systemctl restart unbound

    echo "  Unbound listening on ${ANYCAST_IP}"
}

# Step 4: Health check - withdraw from OSPF if unhealthy
setup_healthcheck() {
    echo "Setting up health check..."

    cat > /opt/mesh-network/dns-api/dns-healthcheck.sh << 'HEALTHCHECK'
#!/bin/bash
# DNS health check - withdraw anycast if unhealthy

ANYCAST_IP="10.10.255.53"
CHECK_DOMAIN="mesh"

# Test DNS resolution
if dig +short +time=2 +tries=1 @127.0.0.1 ${CHECK_DOMAIN} SOA > /dev/null 2>&1; then
    # Healthy - ensure anycast IP is up
    if ! ip addr show lo | grep -q "${ANYCAST_IP}"; then
        ip addr add ${ANYCAST_IP}/32 dev lo label lo:dns
        logger "DNS healthy - announcing anycast ${ANYCAST_IP}"
    fi
else
    # Unhealthy - withdraw anycast IP
    if ip addr show lo | grep -q "${ANYCAST_IP}"; then
        ip addr del ${ANYCAST_IP}/32 dev lo
        logger "DNS unhealthy - withdrawing anycast ${ANYCAST_IP}"
    fi
fi
HEALTHCHECK
    chmod +x /opt/mesh-network/dns-api/dns-healthcheck.sh

    # Create systemd timer for health check
    cat > /etc/systemd/system/mesh-dns-healthcheck.service << EOF
[Unit]
Description=DNS Anycast Health Check

[Service]
Type=oneshot
ExecStart=/opt/mesh-network/dns-api/dns-healthcheck.sh
EOF

    cat > /etc/systemd/system/mesh-dns-healthcheck.timer << EOF
[Unit]
Description=DNS Anycast Health Check Timer

[Timer]
OnBootSec=30
OnUnitActiveSec=10

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now mesh-dns-healthcheck.timer

    echo "  Health check configured (every 10s)"
}

# Step 5: Leader election via multicast (for primary duties)
setup_leader_election() {
    echo "Setting up leader election..."

    # Leader handles things like:
    # - Cleanup of stale entries
    # - External DNS updates
    # - Generating reports

    # This is handled by mesh-dns-multicast.py
    # The DNS server with lowest IP becomes leader

    echo "  Leader election via multicast ${MCAST_GROUP}:${MCAST_PORT}"
}

# Main setup
main() {
    setup_anycast_ip
    configure_ospf
    configure_unbound
    setup_healthcheck
    setup_leader_election

    echo ""
    echo "=== Anycast DNS Setup Complete ==="
    echo ""
    echo "All DNS servers now share: ${ANYCAST_IP}"
    echo "Clients should use: nameserver ${ANYCAST_IP}"
    echo ""
    echo "OSPF will route to nearest healthy DNS server."
    echo "Health check runs every 10s - unhealthy servers withdraw."
    echo ""
}

# Commands
case "${1:-setup}" in
    setup|start)
        main
        ;;
    stop)
        echo "Removing anycast IP..."
        ip addr del ${ANYCAST_IP}/${ANYCAST_PREFIX} dev lo 2>/dev/null || true
        echo "Done"
        ;;
    status)
        echo "Anycast IP status:"
        ip addr show lo | grep -E "${ANYCAST_IP}|lo:" || echo "  Not configured"
        echo ""
        echo "OSPF routes:"
        vtysh -c "show ip ospf route" 2>/dev/null | grep -E "${ANYCAST_IP}|Type" || echo "  OSPF not running"
        echo ""
        echo "DNS test:"
        dig +short @${ANYCAST_IP} mesh SOA || echo "  DNS not responding on anycast"
        ;;
    *)
        echo "Usage: $0 {setup|stop|status}"
        exit 1
        ;;
esac
