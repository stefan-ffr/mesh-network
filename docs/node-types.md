# Node Types Explained

## 1. Mesh Router (WiFi + LAN clients)

### Description
Primary network nodes that participate in the WiFi mesh and serve local clients.

### Hardware Requirements
- 1+ WiFi adapter (802.11s support)
- 1+ Ethernet port for clients
- 1GB+ RAM
- 8GB+ storage

### Use Cases
- Main coverage nodes
- Room/floor routers
- Building distribution points

### Features
- WiFi mesh (802.11s)
- DHCP server for clients
- DNS server (local)
- NAT to internet
- OSPF routing

## 2. LAN Router (Wired uplink + LAN clients)

### Description
Extends network via ethernet without WiFi mesh participation.

### Hardware Requirements
- 2+ Ethernet ports
- 512MB+ RAM
- 4GB+ storage

### Use Cases
- Port expansion in covered areas
- Wired clients in mesh-covered rooms
- Low-cost network extension

### Features
- Wired uplink to mesh
- DHCP for local clients
- DNS server
- NAT enabled
- OSPF routing

## 3. Internet Gateway (WiFi)

### Description
Provides internet access while participating in WiFi mesh.

### Hardware Requirements
- 1 WiFi adapter
- 1 WAN ethernet port
- 1GB+ RAM

### Use Cases
- Primary internet connection
- Backup gateway
- Mobile WAN (LTE/5G)

### Features
- WiFi mesh participation
- WAN connection
- Default route distribution (OSPF)
- Automatic failover
- Health monitoring

## 4. Internet Gateway (Wired)

### Description
Internet access via wired mesh connection.

### Hardware Requirements
- 2 Ethernet ports
- 512MB+ RAM

### Use Cases
- Gateway in different location
- Cheapest gateway option
- ISP in remote building

### Features
- Wired to mesh
- WAN connection
- No WiFi required
- OSPF route distribution

## 5. Update Cache Server

### Description
Transparent caching for updates and downloads.

### Hardware Requirements
- 2GB+ RAM (4GB recommended)
- 50-500GB storage
- Gigabit ethernet

### Cached Content
- Linux packages (apt/yum)
- Windows Updates
- Gaming (Steam, Epic, Origin, etc.)
- Docker images
- Software downloads

### Features
- LANcache (transparent HTTPS)
- apt-cacher-ng
- Squid proxy
- OSPF Anycast (10.99.99.1)
- Multi-server sync
- 85-95% bandwidth savings

## Choosing the Right Type

**Small home (1-5 clients):**
- 1× Gateway Wired
- 1× Mesh Router

**Medium home (5-20 clients):**
- 1× Gateway WiFi
- 2-3× Mesh Router
- 1× Update Cache

**Large home / Small office (20-50 clients):**
- 2× Gateway WiFi (redundant)
- 3-5× Mesh Router
- 1-2× LAN Router
- 1× Update Cache

**Multi-building:**
- Multiple gateways (different buildings)
- Multiple cache servers (with sync)
- Mesh routers per building
- LAN routers for extension
