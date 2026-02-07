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
    dns-server)
        echo "Installing packages for automatic DNS server..."
        # Unbound as primary recursive + authoritative DNS
        apt-get install -y unbound unbound-anchor || true
        # mDNS/Avahi for zero-config discovery
        apt-get install -y avahi-daemon avahi-utils libnss-mdns || true
        # DNS utilities and API dependencies
        apt-get install -y bind9-dnsutils python3-flask || true
        # Configure Unbound for .mesh domain
        mkdir -p /etc/unbound/unbound.conf.d
        cat > /etc/unbound/unbound.conf.d/mesh.conf << 'UNBOUNDCONF'
server:
    interface: 0.0.0.0
    access-control: 10.0.0.0/8 allow
    access-control: 172.16.0.0/12 allow
    access-control: 192.168.0.0/16 allow
    access-control: 127.0.0.0/8 allow
    local-zone: "mesh." static
    local-data: "mesh. IN SOA ns.mesh. admin.mesh. 1 3600 1200 604800 86400"
    local-data: "mesh. IN NS ns.mesh."
    local-data: "dns.mesh. 300 IN A 127.0.0.1"
    include: /etc/unbound/mesh-hosts.conf
forward-zone:
    name: "."
    forward-addr: 1.1.1.1
    forward-addr: 8.8.8.8
    forward-first: yes
UNBOUNDCONF
        touch /etc/unbound/mesh-hosts.conf
        # Enable unbound control for API
        unbound-control-setup 2>/dev/null || true
        systemctl enable unbound avahi-daemon || true
        systemctl disable dnsmasq || true
        mkdir -p /opt/mesh-network/dns-api /var/lib/mesh-dns

        # Setup Anycast IP (shared by all DNS servers)
        ANYCAST_IP="10.10.255.53"
        echo "Setting up DNS Anycast IP: ${ANYCAST_IP}"

        # Add anycast IP to loopback
        cat > /etc/networkd-dispatcher/routable.d/50-dns-anycast << ANYCASTSCRIPT
#!/bin/bash
ip addr add ${ANYCAST_IP}/32 dev lo label lo:dns 2>/dev/null || true
ANYCASTSCRIPT
        chmod +x /etc/networkd-dispatcher/routable.d/50-dns-anycast 2>/dev/null || true

        # Configure Unbound to listen on anycast IP
        cat > /etc/unbound/unbound.conf.d/anycast.conf << ANYCASTCONF
server:
    interface: ${ANYCAST_IP}
    interface: 0.0.0.0
ANYCASTCONF

        # OSPF announcement for anycast (if FRR installed)
        if [ -f /etc/frr/frr.conf ]; then
            cat >> /etc/frr/frr.conf << OSPFCONF
! DNS Anycast
router ospf
 redistribute connected route-map DNS-ANYCAST
!
route-map DNS-ANYCAST permit 10
 match ip address prefix-list DNS-ANYCAST-PREFIX
!
ip prefix-list DNS-ANYCAST-PREFIX seq 5 permit ${ANYCAST_IP}/32
OSPFCONF
        fi

        # Health check - withdraw if unhealthy
        cat > /opt/mesh-network/dns-api/dns-healthcheck.sh << 'HEALTHSCRIPT'
#!/bin/bash
ANYCAST_IP="10.10.255.53"
if dig +short +time=1 @127.0.0.1 mesh SOA >/dev/null 2>&1; then
    ip addr add ${ANYCAST_IP}/32 dev lo 2>/dev/null || true
else
    ip addr del ${ANYCAST_IP}/32 dev lo 2>/dev/null || true
    logger "DNS unhealthy - withdrawing anycast"
fi
HEALTHSCRIPT
        chmod +x /opt/mesh-network/dns-api/dns-healthcheck.sh

        # Health check timer
        cat > /etc/systemd/system/mesh-dns-healthcheck.timer << 'HCTIMER'
[Unit]
Description=DNS Health Check
[Timer]
OnBootSec=30
OnUnitActiveSec=10
[Install]
WantedBy=timers.target
HCTIMER
        cat > /etc/systemd/system/mesh-dns-healthcheck.service << 'HCSERVICE'
[Unit]
Description=DNS Health Check
[Service]
Type=oneshot
ExecStart=/opt/mesh-network/dns-api/dns-healthcheck.sh
HCSERVICE
        systemctl enable mesh-dns-healthcheck.timer || true

        # Enable DNS API if service file exists
        if [ -f /etc/systemd/system/mesh-dns-api.service ]; then
            systemctl enable mesh-dns-api || true
        fi
        ;;
esac

# Create mesh network directories
mkdir -p /opt/mesh-network
mkdir -p /etc/mesh-network
mkdir -p /var/lib/mesh-network
mkdir -p /var/log/mesh-network
mkdir -p /opt/mesh-network/dns-api
mkdir -p /opt/mesh-network/ipam

# Setup P2P IPAM (runs on EVERY node - no central server)
echo "Setting up P2P IPAM..."
cat > /opt/mesh-network/ipam/ipam-p2p.py << 'IPAMSCRIPT'
#!/usr/bin/env python3
"""Minimal P2P IPAM - runs on every node"""
import json, socket, struct, threading, time, sqlite3, random, os
from pathlib import Path

MCAST_GROUP, MCAST_PORT = '239.255.77.70', 5382
DB_PATH = '/var/lib/mesh-network/ipam.db'
HOSTNAME = os.environ.get('HOSTNAME', socket.gethostname())
NODE_TYPE = os.environ.get('MESH_NODE_TYPE', 'default')
RANGES = {'mesh-router':'10.10.1.0/24','lan-router':'10.10.2.0/24','gateway':'10.10.3.0/24',
          'monitoring':'10.10.4.0/24','dns-server':'10.10.5.0/24','emergency':'10.10.6.0/24',
          'default':'10.10.100.0/24'}
known_ips = {}
my_ip = None

def init_db():
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('CREATE TABLE IF NOT EXISTS ips(ip TEXT PRIMARY KEY,host TEXT,expires INT)')
    conn.execute('CREATE TABLE IF NOT EXISTS myip(id INT PRIMARY KEY,ip TEXT,expires INT)')
    conn.commit(); conn.close()

def send_mcast(msg):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    s.sendto(json.dumps(msg).encode(), (MCAST_GROUP, MCAST_PORT)); s.close()

def get_free_ip():
    import ipaddress
    net = ipaddress.ip_network(RANGES.get(NODE_TYPE, RANGES['default']))
    used = set(known_ips.keys())
    candidates = [str(ip) for ip in net.hosts() if not str(ip).endswith('.1')]
    random.shuffle(candidates)
    for ip in candidates:
        if ip not in used: return ip
    return None

def request_ip():
    global my_ip
    # Check existing
    conn = sqlite3.connect(DB_PATH)
    r = conn.execute('SELECT ip,expires FROM myip WHERE id=1').fetchone()
    conn.close()
    if r and r[1] > time.time(): my_ip = r[0]; return r[0]

    ip = get_free_ip()
    if not ip: return None
    send_mcast({'t':'req','ip':ip,'h':HOSTNAME,'ts':int(time.time())})
    time.sleep(2)
    if ip in known_ips and known_ips[ip] != HOSTNAME: return request_ip()

    expires = int(time.time()) + 86400
    send_mcast({'t':'claim','ip':ip,'h':HOSTNAME,'exp':expires})
    conn = sqlite3.connect(DB_PATH)
    conn.execute('INSERT OR REPLACE INTO myip VALUES(1,?,?)', (ip, expires))
    conn.execute('INSERT OR REPLACE INTO ips VALUES(?,?,?)', (ip, HOSTNAME, expires))
    conn.commit(); conn.close()
    known_ips[ip] = HOSTNAME
    my_ip = ip
    return ip

def listener():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('', MCAST_PORT))
    s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP,
                 struct.pack('4sl', socket.inet_aton(MCAST_GROUP), socket.INADDR_ANY))
    while True:
        try:
            data, _ = s.recvfrom(4096)
            m = json.loads(data.decode())
            if m.get('h') == HOSTNAME: continue
            if m.get('t') in ('claim', 'announce'):
                known_ips[m['ip']] = m['h']
                conn = sqlite3.connect(DB_PATH)
                conn.execute('INSERT OR REPLACE INTO ips VALUES(?,?,?)',
                            (m['ip'], m['h'], m.get('exp', int(time.time())+86400)))
                conn.commit(); conn.close()
        except: pass

def announcer():
    while True:
        time.sleep(60)
        if my_ip: send_mcast({'t':'announce','ip':my_ip,'h':HOSTNAME,'exp':int(time.time())+86400})

if __name__ == '__main__':
    init_db()
    threading.Thread(target=listener, daemon=True).start()
    send_mcast({'t':'query','h':HOSTNAME}); time.sleep(2)
    ip = request_ip()
    if ip:
        import subprocess
        subprocess.run(['ip','addr','add',f'{ip}/24','dev','eth0'], capture_output=True)
        subprocess.run(['ip','link','set','eth0','up'], capture_output=True)
        print(f'[IPAM] Configured: {ip}')
        threading.Thread(target=announcer, daemon=True).start()
        while True: time.sleep(3600)
IPAMSCRIPT
chmod +x /opt/mesh-network/ipam/ipam-p2p.py

# Create P2P IPAM service
cat > /etc/systemd/system/mesh-ipam.service << 'IPAMSVC'
[Unit]
Description=Mesh P2P IPAM
After=network.target
Before=mesh-dns-register.service
[Service]
Type=simple
EnvironmentFile=-/boot/firmware/mesh-config.txt
ExecStart=/usr/bin/python3 /opt/mesh-network/ipam/ipam-p2p.py
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
IPAMSVC
systemctl enable mesh-ipam.service || true

# Setup DNS with Anycast IP (shared by all DNS servers via OSPF)
# All clients just use 10.10.255.53 - OSPF routes to nearest healthy DNS
ANYCAST_DNS="10.10.255.53"
echo "Configuring DNS with Anycast IP: ${ANYCAST_DNS}"

# Configure systemd-resolved if present
if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    mkdir -p /etc/systemd/resolved.conf.d/
    cat > /etc/systemd/resolved.conf.d/mesh-anycast.conf << EOF
[Resolve]
DNS=${ANYCAST_DNS}
FallbackDNS=1.1.1.1 8.8.8.8
Domains=~mesh
EOF
    systemctl restart systemd-resolved || true
fi

# Configure /etc/resolv.conf directly (for systems without systemd-resolved)
if [ ! -L /etc/resolv.conf ] || [ ! -f /run/systemd/resolve/stub-resolv.conf ]; then
    cat > /etc/resolv.conf << EOF
# Mesh Network DNS (Anycast)
# All DNS servers share ${ANYCAST_DNS} via OSPF
search mesh local
nameserver ${ANYCAST_DNS}
nameserver 1.1.1.1
EOF
fi

echo "DNS configured: ${ANYCAST_DNS} (Anycast)"

# Setup DNS client for auto-registration (all nodes except dns-server)
if [ "$NODE_TYPE" != "dns-server" ]; then
    echo "Setting up DNS auto-registration..."
    mkdir -p /opt/mesh-network/dns-api

    # Create simple registration script (uses Anycast IP)
    cat > /opt/mesh-network/dns-api/register.sh << 'REGSCRIPT'
#!/bin/bash
# Register with mesh DNS server (Anycast)
DNS_SERVER="${MESH_DNS_SERVER:-10.10.255.53}"
HOSTNAME=$(hostname)
IPV4=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1)
NODE_TYPE=$(grep MESH_NODE_TYPE /boot/firmware/mesh-config.txt 2>/dev/null | cut -d= -f2 || echo "unknown")

[ -z "$IPV4" ] && exit 1

curl -s -X POST -H "Content-Type: application/json" \
    -d "{\"hostname\":\"$HOSTNAME\",\"ipv4\":\"$IPV4\",\"node_type\":\"$NODE_TYPE\"}" \
    "http://${DNS_SERVER}:5380/api/v1/register" 2>/dev/null || true
REGSCRIPT
    chmod +x /opt/mesh-network/dns-api/register.sh

    # Create systemd service for registration
    cat > /etc/systemd/system/mesh-dns-register.service << 'REGSVC'
[Unit]
Description=Register with Mesh DNS
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 30
ExecStart=/opt/mesh-network/dns-api/register.sh
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
REGSVC

    # Create timer for periodic heartbeat
    cat > /etc/systemd/system/mesh-dns-heartbeat.timer << 'HBTIMER'
[Unit]
Description=Mesh DNS Heartbeat

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
HBTIMER

    cat > /etc/systemd/system/mesh-dns-heartbeat.service << 'HBSVC'
[Unit]
Description=Mesh DNS Heartbeat

[Service]
Type=oneshot
ExecStart=/opt/mesh-network/dns-api/register.sh
HBSVC

    systemctl enable mesh-dns-register.service mesh-dns-heartbeat.timer || true
fi

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
