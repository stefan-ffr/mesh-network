#!/bin/bash
# Mesh Network - Interactive Setup Script with Auto-Detection
#
# Features:
# - Automatic detection and assignment of physical interfaces
# - WiFi-to-Wired mesh bridging for gateway nodes
# - BATMAN-adv (WiFi mesh) <-> OSPF (wired mesh) integration
# - Interactive configuration wizard

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

VERSION="2.1.0"

# Configuration
NODE_TYPE=""
HOSTNAME=""
MESH_INTERFACES=()
LAN_INTERFACES=()
WAN_INTERFACES=()
BRIDGE_WIFI_WIRED=false
OSPF_AREA="0.0.0.0"
ROUTER_ID=""
ENABLE_IPV6=true
IPV6_ULA_PREFIX="fd00:mesh"  # Unique Local Address for mesh

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
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

header() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║   🌐  Mesh Network Interactive Setup v${VERSION}        ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Check root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

# Detect all network interfaces
detect_interfaces() {
    log "Detecting network interfaces..."

    # Get all interfaces (excluding lo, docker, veth, etc.)
    ALL_INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep -v -E '^(lo|docker|veth|br-|virbr)')

    if [ -z "$ALL_INTERFACES" ]; then
        error "No network interfaces found!"
        exit 1
    fi

    echo ""
    info "Detected interfaces:"

    # Categorize interfaces
    WIRED_IFACES=()
    WIRELESS_IFACES=()

    for iface in $ALL_INTERFACES; do
        # Check if wireless
        if [ -d "/sys/class/net/$iface/wireless" ]; then
            WIRELESS_IFACES+=("$iface")

            # Get WiFi info
            if command -v iw &> /dev/null; then
                WIFI_INFO=$(iw dev "$iface" info 2>/dev/null | grep -E "ssid|channel|txpower" | head -3)
                echo -e "  ${CYAN}📶 $iface${NC} (WiFi)"
                if [ -n "$WIFI_INFO" ]; then
                    echo "$WIFI_INFO" | sed 's/^/     /'
                fi
            else
                echo -e "  ${CYAN}📶 $iface${NC} (WiFi)"
            fi
        else
            WIRED_IFACES+=("$iface")

            # Get link status and speed
            LINK_STATE=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo "unknown")
            SPEED=$(cat "/sys/class/net/$iface/speed" 2>/dev/null || echo "?")
            MAC=$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo "?")

            if [ "$LINK_STATE" = "up" ]; then
                echo -e "  ${GREEN}🔌 $iface${NC} (Wired, ${SPEED}Mbps, $LINK_STATE) - MAC: $MAC"
            else
                echo -e "  ${YELLOW}🔌 $iface${NC} (Wired, $LINK_STATE) - MAC: $MAC"
            fi
        fi
    done

    echo ""
    info "Summary: ${#WIRELESS_IFACES[@]} wireless, ${#WIRED_IFACES[@]} wired interfaces"
}

# Select node type
select_node_type() {
    echo ""
    echo -e "${CYAN}═══ Node Type Selection ═══${NC}"
    echo ""
    echo "1) Mesh Router       - WiFi mesh + LAN distribution"
    echo "2) LAN Router        - Wired mesh + LAN distribution"
    echo "3) Gateway (WiFi)    - WiFi mesh + Internet gateway"
    echo "4) Gateway (Wired)   - Wired mesh + Internet gateway"
    echo "5) Gateway (Hybrid)  - WiFi + Wired mesh bridge + Internet"
    echo "6) Update Cache      - LANcache node"
    echo "7) Monitoring Node   - Network monitoring and visualization"
    echo ""

    while true; do
        read -p "Select node type [1-7]: " choice
        case $choice in
            1) NODE_TYPE="mesh-router"; break ;;
            2) NODE_TYPE="lan-router"; break ;;
            3) NODE_TYPE="gateway-wifi"; break ;;
            4) NODE_TYPE="gateway-wired"; break ;;
            5) NODE_TYPE="gateway-hybrid"; BRIDGE_WIFI_WIRED=true; break ;;
            6) NODE_TYPE="update-cache"; break ;;
            7) NODE_TYPE="monitoring"; break ;;
            *) error "Invalid choice" ;;
        esac
    done

    log "Selected: $NODE_TYPE"
}

# Assign interfaces based on node type
assign_interfaces() {
    echo ""
    echo -e "${CYAN}═══ Interface Assignment ═══${NC}"
    echo ""

    case $NODE_TYPE in
        mesh-router|gateway-wifi|gateway-hybrid)
            # Need WiFi for mesh
            if [ ${#WIRELESS_IFACES[@]} -eq 0 ]; then
                error "No wireless interfaces found! This node type requires WiFi."
                exit 1
            fi

            echo "Available WiFi interfaces:"
            for i in "${!WIRELESS_IFACES[@]}"; do
                echo "  $((i+1))) ${WIRELESS_IFACES[$i]}"
            done

            if [ ${#WIRELESS_IFACES[@]} -eq 1 ]; then
                MESH_INTERFACES+=("${WIRELESS_IFACES[0]}")
                log "Auto-selected: ${WIRELESS_IFACES[0]} for mesh"
            else
                read -p "Select WiFi interface for mesh [1-${#WIRELESS_IFACES[@]}]: " wifi_choice
                MESH_INTERFACES+=("${WIRELESS_IFACES[$((wifi_choice-1))]}")
            fi
            ;;
    esac

    case $NODE_TYPE in
        lan-router|gateway-wired|gateway-hybrid)
            # Need wired for mesh uplink
            if [ ${#WIRED_IFACES[@]} -eq 0 ]; then
                error "No wired interfaces found!"
                exit 1
            fi

            echo ""
            echo "Available wired interfaces:"
            for i in "${!WIRED_IFACES[@]}"; do
                echo "  $((i+1))) ${WIRED_IFACES[$i]}"
            done

            read -p "Select wired mesh/uplink interface [1-${#WIRED_IFACES[@]}]: " uplink_choice
            selected="${WIRED_IFACES[$((uplink_choice-1))]}"
            MESH_INTERFACES+=("$selected")

            # Remove from available wired interfaces
            WIRED_IFACES=("${WIRED_IFACES[@]/$selected}")
            ;;
    esac

    # WAN assignment for gateways
    if [[ $NODE_TYPE == gateway-* ]]; then
        echo ""
        if [ ${#WIRED_IFACES[@]} -gt 0 ]; then
            echo "Available interfaces for WAN:"
            for i in "${!WIRED_IFACES[@]}"; do
                echo "  $((i+1))) ${WIRED_IFACES[$i]}"
            done

            read -p "Select WAN interface [1-${#WIRED_IFACES[@]}]: " wan_choice
            selected="${WIRED_IFACES[$((wan_choice-1))]}"
            WAN_INTERFACES+=("$selected")
            WIRED_IFACES=("${WIRED_IFACES[@]/$selected}")
        fi
    fi

    # Remaining interfaces for LAN
    if [ ${#WIRED_IFACES[@]} -gt 0 ]; then
        echo ""
        info "Remaining interfaces will be used for LAN"
        LAN_INTERFACES=("${WIRED_IFACES[@]}")
    fi

    # Summary
    echo ""
    log "Interface assignment complete:"
    echo "  Mesh:  ${MESH_INTERFACES[*]:-none}"
    echo "  WAN:   ${WAN_INTERFACES[*]:-none}"
    echo "  LAN:   ${LAN_INTERFACES[*]:-none}"
}

# Configure WiFi-to-Wired bridge
configure_mesh_bridge() {
    if [ "$BRIDGE_WIFI_WIRED" != "true" ]; then
        return
    fi

    log "Configuring WiFi-to-Wired mesh bridge..."

    # Create bridge interface for mesh interconnection
    cat > /etc/systemd/network/20-mesh-bridge.netdev <<EOF
[NetDev]
Name=br-mesh
Kind=bridge
EOF

    cat > /etc/systemd/network/20-mesh-bridge.network <<EOF
[Match]
Name=br-mesh

[Network]
Description=Mesh Bridge (BATMAN-adv <-> OSPF)
Address=169.254.255.1/24
IPForward=yes

[Link]
RequiredForOnline=no
EOF

    # Bridge BATMAN-adv (bat0) with wired mesh
    cat > /etc/systemd/network/21-batman-bridge.network <<EOF
[Match]
Name=bat0

[Network]
Bridge=br-mesh
EOF

    # Bridge wired mesh interface
    for iface in "${MESH_INTERFACES[@]}"; do
        if [[ ! " ${WIRELESS_IFACES[@]} " =~ " ${iface} " ]]; then
            cat > "/etc/systemd/network/22-${iface}-bridge.network" <<EOF
[Match]
Name=$iface

[Network]
Bridge=br-mesh
EOF
        fi
    done

    # Configure IPv6 on bridge if enabled
    if [ "$ENABLE_IPV6" = "true" ]; then
        # Generate unique IPv6 ULA based on node
        NODE_ID=$(hostname | md5sum | cut -c1-4)
        IPV6_ADDR="${IPV6_ULA_PREFIX}::${NODE_ID}:1/64"

        cat >> /etc/systemd/network/20-mesh-bridge.network <<EOF

[Address]
Address=$IPV6_ADDR

[IPv6AcceptRA]
UseAutonomousPrefix=false
EOF
        info "IPv6 configured on br-mesh: $IPV6_ADDR"
    fi

    info "Mesh bridge configured: bat0 <-> br-mesh <-> ${MESH_INTERFACES[*]}"
}

# Configure OSPF routing (IPv4 and IPv6)
configure_ospf() {
    log "Configuring OSPF routing (OSPFv2 and OSPFv3)..."

    # Generate Router ID from hostname or first IP
    ROUTER_ID=$(hostname -I | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || echo "1.1.1.1")

    # Enable OSPFv3 in daemons file
    sed -i 's/ospf6d=no/ospf6d=yes/' /etc/frr/daemons

    # Create FRR OSPF config (IPv4)
    cat > /etc/frr/ospfd.conf <<EOF
! OSPFv2 Configuration for Mesh Network (IPv4)
hostname $(hostname)
log syslog informational

! Router ID
router ospf
 ospf router-id $ROUTER_ID

 ! Redistribute connected routes
 redistribute connected

 ! Mesh interfaces
$(for iface in "${MESH_INTERFACES[@]}"; do
    echo " network 0.0.0.0/0 area $OSPF_AREA"
done)

 ! Fast convergence
 timers throttle spf 200 400 10000

! OSPF interface settings
$(for iface in "${MESH_INTERFACES[@]}"; do
    echo "interface $iface"
    echo " ip ospf hello-interval 1"
    echo " ip ospf dead-interval 4"
    echo " ip ospf priority 1"
    echo " ip ospf network point-to-point"
    echo "!"
done)

EOF

    if [ "$ENABLE_IPV6" = "true" ]; then
        # Create FRR OSPFv3 config (IPv6)
        cat > /etc/frr/ospf6d.conf <<EOF
! OSPFv3 Configuration for Mesh Network (IPv6)
hostname $(hostname)
log syslog informational

! OSPFv3 router
router ospf6
 ospf6 router-id $ROUTER_ID
 redistribute connected

! OSPFv3 interface settings
$(for iface in "${MESH_INTERFACES[@]}"; do
    echo "interface $iface"
    echo " ipv6 ospf6 area $OSPF_AREA"
    echo " ipv6 ospf6 hello-interval 1"
    echo " ipv6 ospf6 dead-interval 4"
    echo " ipv6 ospf6 priority 1"
    echo " ipv6 ospf6 network point-to-point"
    echo "!"
done)

EOF
        chmod 640 /etc/frr/ospf6d.conf
        chown frr:frr /etc/frr/ospf6d.conf
        info "OSPFv3 (IPv6) configured"
    fi

    chmod 640 /etc/frr/ospfd.conf
    chown frr:frr /etc/frr/ospfd.conf

    info "OSPFv2 (IPv4) configured with Router-ID: $ROUTER_ID"
}

# Configure BATMAN-adv
configure_batman() {
    if [ ${#WIRELESS_IFACES[@]} -eq 0 ]; then
        return
    fi

    log "Configuring BATMAN-adv WiFi mesh..."

    # Load batman-adv module
    modprobe batman-adv || true
    echo "batman-adv" >> /etc/modules-load.d/mesh.conf

    # Create systemd service for batman setup
    cat > /etc/systemd/system/batman-mesh.service <<EOF
[Unit]
Description=BATMAN-adv Mesh Network
After=network.target
Wants=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/batman-setup.sh
ExecStop=/usr/sbin/ip link set bat0 down

[Install]
WantedBy=multi-user.target
EOF

    # Create batman setup script
    cat > /usr/local/bin/batman-setup.sh <<'EOFBAT'
#!/bin/bash
set -e

# Load batman module
modprobe batman-adv

# Create bat0 if not exists
if ! ip link show bat0 &> /dev/null; then
    ip link add name bat0 type batadv
fi

# Add mesh interfaces to batman
EOFBAT

    for iface in "${MESH_INTERFACES[@]}"; do
        if [[ " ${WIRELESS_IFACES[@]} " =~ " ${iface} " ]]; then
            cat >> /usr/local/bin/batman-setup.sh <<EOFBAT
# Add $iface to batman mesh
ip link set $iface down
ip addr flush dev $iface
ip link set $iface up
echo bat0 > /sys/class/net/$iface/batman_adv/mesh_iface

EOFBAT
        fi
    done

    cat >> /usr/local/bin/batman-setup.sh <<'EOFBAT'

# Bring up bat0
ip link set bat0 up

# Enable bridge loop avoidance and distributed ARP table
echo 1 > /sys/class/net/bat0/mesh/bridge_loop_avoidance
echo 1 > /sys/class/net/bat0/mesh/distributed_arp_table

# Set gateway mode if needed
if [ -f /etc/mesh-network/gateway ]; then
    echo server > /sys/class/net/bat0/mesh/gw_mode
else
    echo client > /sys/class/net/bat0/mesh/gw_mode
fi

exit 0
EOFBAT

    chmod +x /usr/local/bin/batman-setup.sh

    systemctl daemon-reload
    systemctl enable batman-mesh.service

    info "BATMAN-adv configured for: ${WIRELESS_IFACES[*]}"
}

# Configure NAT for gateways (IPv4 and IPv6)
configure_nat() {
    if [[ ! $NODE_TYPE == gateway-* ]]; then
        return
    fi

    if [ ${#WAN_INTERFACES[@]} -eq 0 ]; then
        warn "No WAN interface configured, skipping NAT"
        return
    fi

    log "Configuring NAT and firewall (IPv4 + IPv6)..."

    WAN_IFACE="${WAN_INTERFACES[0]}"

    # Enable IP forwarding
    cat > /etc/sysctl.d/99-mesh-forwarding.conf <<EOF
# IPv4 forwarding
net.ipv4.ip_forward=1

# IPv6 forwarding
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.${WAN_IFACE}.forwarding=1

# IPv6 accept RA even with forwarding enabled
net.ipv6.conf.${WAN_IFACE}.accept_ra=2

# Disable IPv6 privacy extensions on WAN (for stable addressing)
net.ipv6.conf.${WAN_IFACE}.use_tempaddr=0
EOF

    sysctl -p /etc/sysctl.d/99-mesh-forwarding.conf

    # Configure iptables NAT (IPv4)
    cat > /etc/iptables/rules.v4 <<EOF
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]

# IPv4 NAT for mesh network
-A POSTROUTING -o $WAN_IFACE -j MASQUERADE

COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# Allow established connections
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
-A INPUT -i lo -j ACCEPT

# Allow mesh traffic
$(for iface in "${MESH_INTERFACES[@]}"; do
    echo "-A INPUT -i $iface -j ACCEPT"
    echo "-A FORWARD -i $iface -j ACCEPT"
done)

# Allow LAN traffic
$(for iface in "${LAN_INTERFACES[@]}"; do
    echo "-A INPUT -i $iface -j ACCEPT"
    echo "-A FORWARD -i $iface -j ACCEPT"
done)

# Drop invalid packets
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A FORWARD -m conntrack --ctstate INVALID -j DROP

# Allow SSH
-A INPUT -p tcp --dport 22 -j ACCEPT

# Allow OSPF
-A INPUT -p ospf -j ACCEPT

# Allow DHCP
-A INPUT -p udp --dport 67:68 -j ACCEPT

# Allow ICMPv4
-A INPUT -p icmp -j ACCEPT

COMMIT
EOF

    # Apply IPv4 rules
    iptables-restore < /etc/iptables/rules.v4

    if [ "$ENABLE_IPV6" = "true" ]; then
        # Configure ip6tables NAT (IPv6) using NPTv6
        cat > /etc/iptables/rules.v6 <<EOF
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]

# IPv6 NAT66 (Network Prefix Translation)
# Translates ULA addresses to global IPv6
-A POSTROUTING -s ${IPV6_ULA_PREFIX}::/48 -o $WAN_IFACE -j MASQUERADE

COMMIT

*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# Allow established connections
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
-A INPUT -i lo -j ACCEPT

# Allow mesh traffic
$(for iface in "${MESH_INTERFACES[@]}"; do
    echo "-A INPUT -i $iface -j ACCEPT"
    echo "-A FORWARD -i $iface -j ACCEPT"
done)

# Allow LAN traffic
$(for iface in "${LAN_INTERFACES[@]}"; do
    echo "-A INPUT -i $iface -j ACCEPT"
    echo "-A FORWARD -i $iface -j ACCEPT"
done)

# Drop invalid packets
-A INPUT -m conntrack --ctstate INVALID -j DROP
-A FORWARD -m conntrack --ctstate INVALID -j DROP

# Allow SSH
-A INPUT -p tcp --dport 22 -j ACCEPT

# Allow OSPFv3
-A INPUT -p 89 -j ACCEPT

# Allow DHCPv6
-A INPUT -p udp --dport 546:547 -j ACCEPT

# Allow ICMPv6 (essential for IPv6)
-A INPUT -p ipv6-icmp -j ACCEPT
-A FORWARD -p ipv6-icmp -j ACCEPT

# Allow link-local
-A INPUT -s fe80::/10 -j ACCEPT
-A FORWARD -s fe80::/10 -j ACCEPT

COMMIT
EOF

        # Apply IPv6 rules
        ip6tables-restore < /etc/iptables/rules.v6
        info "IPv6 NAT66 configured (${IPV6_ULA_PREFIX}::/48 -> $WAN_IFACE)"
    fi

    # Mark as gateway
    mkdir -p /etc/mesh-network
    touch /etc/mesh-network/gateway

    info "NAT configured on $WAN_IFACE (IPv4 + IPv6)"
}

# Create configuration summary
create_config_summary() {
    mkdir -p /etc/mesh-network

    cat > /etc/mesh-network/config.yaml <<EOF
# Mesh Network Configuration
# Generated: $(date -u +'%Y-%m-%d %H:%M:%S UTC')

version: "$VERSION"
node_type: "$NODE_TYPE"
hostname: "$(hostname)"

interfaces:
  mesh:
$(for iface in "${MESH_INTERFACES[@]}"; do
    echo "    - $iface"
done)
  wan:
$(for iface in "${WAN_INTERFACES[@]}"; do
    echo "    - $iface"
done)
  lan:
$(for iface in "${LAN_INTERFACES[@]}"; do
    echo "    - $iface"
done)

features:
  wifi_wired_bridge: $BRIDGE_WIFI_WIRED
  batman_adv: $([ ${#WIRELESS_IFACES[@]} -gt 0 ] && echo "true" || echo "false")
  ospf: true
  ospfv3: $ENABLE_IPV6
  nat: $([ "$NODE_TYPE" == gateway-* ] && echo "true" || echo "false")
  nat66: $([ "$NODE_TYPE" == gateway-* ] && [ "$ENABLE_IPV6" = "true" ] && echo "true" || echo "false")

routing:
  ospf_router_id: "$ROUTER_ID"
  ospf_area: "$OSPF_AREA"

ipv6:
  enabled: $ENABLE_IPV6
  ula_prefix: "$IPV6_ULA_PREFIX::/48"
  node_address: "$([ "$ENABLE_IPV6" = "true" ] && echo "${IPV6_ULA_PREFIX}::$(hostname | md5sum | cut -c1-4):1/64" || echo "disabled")"
EOF

    info "Configuration saved to /etc/mesh-network/config.yaml"
}

# Main installation
main() {
    header

    detect_interfaces
    select_node_type
    assign_interfaces

    echo ""
    read -p "Continue with installation? [Y/n]: " confirm
    if [[ $confirm == "n" || $confirm == "N" ]]; then
        warn "Installation cancelled"
        exit 0
    fi

    log "Starting installation..."

    # Install packages
    log "Installing required packages..."
    apt-get update
    apt-get install -y \
        frr frr-pythontools \
        batman-adv batctl \
        bridge-utils \
        iptables iptables-persistent \
        etcd-server etcd-client \
        hostapd iw wireless-tools \
        || true

    # Configure components
    configure_batman
    configure_ospf
    configure_mesh_bridge
    configure_nat
    create_config_summary

    # Enable services
    systemctl daemon-reload
    systemctl enable frr
    systemctl enable etcd

    echo ""
    log "Installation complete!"
    echo ""
    info "Configuration Summary:"
    info "  Node Type:    $NODE_TYPE"
    info "  Mesh IFs:     ${MESH_INTERFACES[*]}"
    info "  WAN IFs:      ${WAN_INTERFACES[*]:-none}"
    info "  LAN IFs:      ${LAN_INTERFACES[*]:-none}"
    info "  OSPF Router:  $ROUTER_ID"
    info "  WiFi↔Wired:   $BRIDGE_WIFI_WIRED"
    info "  IPv6:         $ENABLE_IPV6 (${IPV6_ULA_PREFIX}::/48)"
    echo ""
    warn "IMPORTANT: Reboot required to apply all changes"
    warn "  sudo reboot"
    echo ""
    info "After reboot, check status:"
    info "  # BATMAN-adv (WiFi mesh)"
    info "  batctl o                              # Show originators"
    info "  batctl n                              # Show neighbors"
    echo ""
    info "  # OSPF (Wired/WiFi routing)"
    info "  vtysh -c 'show ip ospf neighbor'      # OSPFv2 neighbors"
    if [ "$ENABLE_IPV6" = "true" ]; then
        info "  vtysh -c 'show ipv6 ospf6 neighbor'   # OSPFv3 neighbors (IPv6)"
    fi
    echo ""
    info "  # Bridge and interfaces"
    info "  bridge link                           # Show bridge members"
    info "  ip -6 addr show                       # Show IPv6 addresses"
    echo ""
    if [[ "$NODE_TYPE" == gateway-* ]]; then
        info "  # NAT status"
        info "  iptables -t nat -L -n -v             # IPv4 NAT"
        if [ "$ENABLE_IPV6" = "true" ]; then
            info "  ip6tables -t nat -L -n -v            # IPv6 NAT66"
        fi
        echo ""
    fi
}

main "$@"
