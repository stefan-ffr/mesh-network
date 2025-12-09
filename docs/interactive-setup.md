# Interactive Setup Script

Das interaktive Setup-Script bietet eine benutzerfreundliche Konfiguration für Mesh-Network-Nodes mit automatischer Interface-Erkennung und fortgeschrittenen Features.

## Features

### 1. Automatische Interface-Erkennung
- Erkennt alle physischen Netzwerk-Interfaces automatisch
- Unterscheidet zwischen WiFi und Ethernet-Interfaces
- Zeigt Link-Status, Geschwindigkeit und MAC-Adressen
- Intelligente Zuordnung basierend auf Node-Typ

### 2. WiFi-to-Wired Mesh Bridge
- Verbindet BATMAN-adv (WiFi-Mesh) mit OSPF (Wired-Mesh)
- Transparent Bridging zwischen beiden Mesh-Technologien
- Optimiert für Gateway-Nodes (Hybrid-Modus)
- Ermöglicht nahtlose Kommunikation zwischen WiFi- und Ethernet-Mesh-Teilnehmern

### 3. Vollständiger IPv6-Support
- **Dual-Stack**: IPv4 und IPv6 parallel
- **OSPFv3**: IPv6-Routing über OSPFv3
- **ULA-Adressen**: Unique Local Addresses (fd00::/8) für interne Kommunikation
- **IPv6 NAT66**: Network Prefix Translation für Internet-Gateways
- **ICMPv6**: Essential für IPv6-Funktionalität (Neighbor Discovery, etc.)

## Installation

```bash
# Download und ausführen
wget https://raw.githubusercontent.com/YOUR-USERNAME/mesh-network/main/scripts/setup/interactive-setup.sh
chmod +x interactive-setup.sh
sudo ./interactive-setup.sh
```

## Node-Typen

### 1. Mesh Router
- WiFi-Mesh (BATMAN-adv) + LAN-Distribution
- Für WiFi-Mesh-Erweiterung mit lokalem LAN
- Benötigt: 1x WiFi, 1+ Ethernet

### 2. LAN Router
- Wired-Mesh (OSPF) + LAN-Distribution
- Für Ethernet-basiertes Mesh mit lokalem LAN
- Benötigt: 2+ Ethernet

### 3. Gateway (WiFi)
- WiFi-Mesh + Internet-Gateway
- NAT für Mesh-Netzwerk
- Benötigt: 1x WiFi (Mesh), 1x Ethernet (WAN)

### 4. Gateway (Wired)
- Wired-Mesh + Internet-Gateway
- NAT für Mesh-Netzwerk
- Benötigt: 2+ Ethernet (1x Mesh, 1x WAN)

### 5. Gateway (Hybrid) ⭐ NEU
- WiFi-Mesh + Wired-Mesh Bridge + Internet
- Verbindet BATMAN-adv (WiFi) mit OSPF (Ethernet)
- NAT für beide Mesh-Segmente
- Benötigt: 1x WiFi, 2+ Ethernet (1x Mesh, 1x WAN)

### 6. Update Cache
- LANcache für Gaming-Updates
- Docker-basiert
- Benötigt: 1+ Ethernet

### 7. Monitoring Node
- Network Monitoring & Visualization
- Dashboard auf Port 8080
- Benötigt: 1+ Ethernet

## Setup-Ablauf

### 1. Interface-Erkennung

Das Script erkennt automatisch alle Interfaces:

```
Detected interfaces:
  📶 wlan0 (WiFi)
     ssid: mesh-network
     channel: 6
  🔌 eth0 (Wired, 1000Mbps, up) - MAC: aa:bb:cc:dd:ee:ff
  🔌 eth1 (Wired, down) - MAC: 11:22:33:44:55:66
```

### 2. Node-Typ Auswahl

Wählen Sie den passenden Node-Typ für Ihre Anforderungen.

### 3. Interface-Zuordnung

Das Script führt Sie durch die Zuordnung:
- **Mesh-Interface**: WiFi oder Ethernet für Mesh-Kommunikation
- **WAN-Interface**: Für Internet-Gateways
- **LAN-Interfaces**: Alle verbleibenden Interfaces

### 4. Automatische Konfiguration

Das Script konfiguriert automatisch:
- BATMAN-adv (WiFi-Mesh)
- OSPF/OSPFv3 (IPv4/IPv6-Routing)
- Bridge (WiFi ↔ Wired)
- NAT/NAT66 (für Gateways)
- Firewall-Regeln
- systemd-Services

## WiFi-to-Wired Bridge Details

### Architektur

```
┌─────────────────────────────────────────────┐
│         Gateway (Hybrid) Node               │
├─────────────────────────────────────────────┤
│                                             │
│  wlan0 (WiFi Mesh)                          │
│    │                                        │
│    └──> BATMAN-adv (bat0)                   │
│           │                                  │
│           └──> br-mesh (Bridge)             │
│                  │                           │
│           ┌──────┴──────┐                   │
│           │             │                    │
│     eth0 (Wired)   OSPF Routing             │
│     (Mesh)              │                    │
│                         │                    │
│                    eth1 (WAN)                │
│                         │                    │
└─────────────────────────┼───────────────────┘
                          │
                     Internet
```

### Funktionsweise

1. **BATMAN-adv Layer**: WiFi-Geräte kommunizieren über BATMAN-adv (bat0)
2. **Bridge Layer**: `br-mesh` verbindet bat0 mit Ethernet-Interface
3. **OSPF Layer**: Wired-Mesh nutzt OSPF für Routing
4. **Transparenz**: Beide Mesh-Segmente können nahtlos kommunizieren

### Vorteile

- **Flexibilität**: WiFi- und Ethernet-Clients in einem Mesh
- **Redundanz**: Mehrere Pfade zwischen Segmenten
- **Performance**: Ethernet-Backbone für Hochgeschwindigkeitsverbindungen
- **Reichweite**: WiFi für mobile/entfernte Nodes

## IPv6-Konfiguration

### ULA-Adressierung

Das Mesh verwendet Unique Local Addresses (ULA):

```
Prefix: fd00:mesh::/48

Node-Adressen:
  fd00:mesh::<node-id>:1/64
```

Node-ID wird aus Hostname generiert (MD5-Hash).

### OSPFv3 (IPv6)

- **Protokoll**: OSPFv3 für IPv6-Routing
- **Area**: 0.0.0.0 (Backbone)
- **Hello-Intervall**: 1 Sekunde
- **Dead-Intervall**: 4 Sekunden

### IPv6 NAT66 (für Gateways)

Internet-Gateways nutzen NAT66 (Network Prefix Translation):

```
Interne ULA: fd00:mesh::/48
    ↓ NPTv6
Externe GUA: 2001:xxxx:xxxx::/48 (von ISP)
```

**Vorteile von NAT66**:
- Stabile interne Adressen (unabhängig vom ISP)
- Privacy (interne Struktur nicht sichtbar)
- ISP-Wechsel ohne Renumbering

### IPv6-Firewall

Das Script konfiguriert automatisch:
- **ICMPv6**: Neighbor Discovery, Path MTU, etc.
- **OSPFv3**: Protocol 89
- **DHCPv6**: Ports 546-547
- **Link-Local**: fe80::/10 Traffic

### RA (Router Advertisement)

Gateway-Nodes können optional RAs senden:

```bash
# In /etc/radvd.conf
interface br-mesh {
    AdvSendAdvert on;
    prefix fd00:mesh::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
};
```

## Konfigurationsdateien

Das Script erstellt folgende Konfigurationen:

### 1. FRR (Routing)
```
/etc/frr/ospfd.conf       # OSPFv2 (IPv4)
/etc/frr/ospf6d.conf      # OSPFv3 (IPv6)
/etc/frr/daemons          # Enabled daemons
```

### 2. Firewall
```
/etc/iptables/rules.v4    # IPv4 NAT + Filter
/etc/iptables/rules.v6    # IPv6 NAT66 + Filter
```

### 3. Networking
```
/etc/systemd/network/20-mesh-bridge.netdev    # Bridge netdev
/etc/systemd/network/20-mesh-bridge.network   # Bridge config
/etc/systemd/network/21-batman-bridge.network # bat0 → bridge
/etc/systemd/network/22-*.network             # Interface configs
```

### 4. BATMAN-adv
```
/etc/systemd/system/batman-mesh.service       # systemd service
/usr/local/bin/batman-setup.sh                # Setup script
```

### 5. System
```
/etc/sysctl.d/99-mesh-forwarding.conf         # IP forwarding
/etc/mesh-network/config.yaml                 # Node configuration
/etc/mesh-network/gateway                     # Gateway marker
```

## Status-Befehle

### BATMAN-adv (WiFi Mesh)

```bash
# Originators (mesh nodes)
batctl o

# Neighbors (direct WiFi connections)
batctl n

# Throughput estimation
batctl tp wlan0

# Gateway status
batctl gw
```

### OSPF (IPv4 Routing)

```bash
# Enter FRR shell
vtysh

# Show neighbors
show ip ospf neighbor

# Show routes
show ip route

# Show OSPF database
show ip ospf database
```

### OSPFv3 (IPv6 Routing)

```bash
vtysh

# Show IPv6 neighbors
show ipv6 ospf6 neighbor

# Show IPv6 routes
show ipv6 route

# Show OSPFv3 database
show ipv6 ospf6 database
```

### Bridge

```bash
# Show bridge members
bridge link

# Show bridge FDB
bridge fdb show

# Show bridge info
ip link show br-mesh
```

### IPv6

```bash
# Show IPv6 addresses
ip -6 addr show

# Show IPv6 routes
ip -6 route show

# Show IPv6 neighbors
ip -6 neigh show

# Ping IPv6
ping6 fd00:mesh::1234:1
```

### NAT

```bash
# IPv4 NAT
iptables -t nat -L -n -v

# IPv6 NAT66
ip6tables -t nat -L -n -v

# Connection tracking
conntrack -L
```

## Fehlersuche

### Bridge funktioniert nicht

```bash
# Check bridge status
brctl show br-mesh

# Check bridge members
bridge link show

# Restart batman
systemctl restart batman-mesh
```

### OSPF keine Neighbors

```bash
# Check OSPF is running
systemctl status frr

# Check interface configuration
vtysh -c "show ip ospf interface"

# Check firewall
iptables -L -n -v | grep -i ospf
```

### IPv6 nicht erreichbar

```bash
# Check IPv6 is enabled
sysctl net.ipv6.conf.all.forwarding

# Check addresses
ip -6 addr show

# Check routes
ip -6 route show

# Check ICMPv6
ip6tables -L -n -v | grep icmpv6

# Test connectivity
ping6 -c 3 fd00:mesh::1
```

### NAT66 funktioniert nicht

```bash
# Check NAT66 rules
ip6tables -t nat -L POSTROUTING -n -v

# Check IPv6 forwarding
sysctl net.ipv6.conf.all.forwarding

# Check conntrack
conntrack -L -f ipv6
```

## Performance-Optimierung

### BATMAN-adv

```bash
# Increase throughput meter accuracy
echo 10000 > /sys/class/net/bat0/mesh/throughput_override

# Enable multicast optimization
echo 1 > /sys/class/net/bat0/mesh/multicast_mode
```

### OSPF

In `/etc/frr/ospfd.conf`:

```
router ospf
 # Fast convergence
 timers throttle spf 200 400 10000

 # BFD for sub-second failure detection
 bfd
```

### Bridge

```bash
# Disable STP if not needed (faster convergence)
echo 0 > /sys/class/net/br-mesh/bridge/stp_state

# Set ageing time
echo 300 > /sys/class/net/br-mesh/bridge/ageing_time
```

## Sicherheitshinweise

1. **Firewall**: Script konfiguriert restriktive Firewall-Regeln
2. **SSH**: Standardmäßig erlaubt, verwenden Sie Key-based Auth
3. **OSPF Auth**: Fügen Sie OSPF-Authentication hinzu:
   ```
   interface eth0
    ip ospf authentication message-digest
    ip ospf message-digest-key 1 md5 SECRET
   ```
4. **WPA3**: Verwenden Sie WPA3 für WiFi-Mesh wenn verfügbar

## Bekannte Einschränkungen

1. **NAT66**: Nicht alle Anwendungen unterstützen NAT66 perfekt
2. **BATMAN-adv**: Funktioniert nur mit Ad-hoc oder Mesh WiFi-Modi
3. **OSPFv3**: Benötigt Link-Local Adressen auf allen Interfaces
4. **systemd-networkd**: Script setzt voraus, dass systemd-networkd verwendet wird

## Weiterführende Links

- [FRR Documentation](https://docs.frrouting.org/)
- [BATMAN-adv Wiki](https://www.open-mesh.org/projects/batman-adv/wiki)
- [RFC 7084 - IPv6 CE Router Requirements](https://tools.ietf.org/html/rfc7084)
- [RFC 4193 - Unique Local IPv6 Unicast Addresses](https://tools.ietf.org/html/rfc4193)
- [RFC 6296 - IPv6-to-IPv6 Network Prefix Translation](https://tools.ietf.org/html/rfc6296)
