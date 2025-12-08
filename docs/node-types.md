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

## 6. Monitoring Node

### Description
Centralized network monitoring, alerting, and visualization for the entire mesh network.

### Hardware Requirements
- 2GB+ RAM (4GB for 50+ nodes)
- 20GB+ storage (historical data)
- 1 Ethernet port
- Docker support required

### Deployment
**Containerized (Recommended):**
- Runs entirely in Docker containers
- Easy updates via GitHub Container Registry
- Includes PostgreSQL database
- Optional Grafana integration
- Automatic image builds via GitHub Actions

**Components:**
- Dashboard container (Flask + WebSocket)
- Collector container (SSH-based metrics)
- PostgreSQL database
- Optional: Nginx, Grafana, Prometheus

### Features

**Monitoring:**
- Automatic node discovery via OSPF
- Real-time metrics collection (CPU, RAM, disk)
- Service health monitoring (FRR, etcd, DNS)
- OSPF topology visualization
- SSH-based agentless monitoring
- SNMP support (optional)

**Alerting:**
- Email notifications (SMTP)
- Telegram bot integration
- Discord webhooks
- Slack integration
- Custom webhooks
- Configurable thresholds

**Dashboard:**
- Web-based interface (port 8080)
- Real-time updates via WebSocket
- Interactive network topology map
- Historical graphs (24h/7d/30d)
- Alert management
- Mobile-friendly responsive design

**Data Retention:**
- Configurable metrics retention
- PostgreSQL for scalability
- Export to JSON/CSV
- Optional Grafana dashboards

### Use Cases
- Network operations center (NOC)
- Proactive issue detection
- Performance monitoring
- Capacity planning
- SLA compliance
- Audit logging

### Installation
```bash
# Docker deployment (recommended)
git clone https://github.com/YOUR-USERNAME/mesh-network.git
cd mesh-network

# Pull pre-built containers
docker pull ghcr.io/YOUR-USERNAME/mesh-network-monitor-dashboard:latest
docker pull ghcr.io/YOUR-USERNAME/mesh-network-monitor-collector:latest

# Configure and start
cp docker/monitoring/.env.example docker/monitoring/.env
# Edit .env file with your settings
docker-compose -f docker/monitoring-docker-compose.yml up -d

# Access dashboard
open http://server-ip:8080
```

### Configuration
- Config file: `/etc/mesh-monitor/config.yml`
- Environment: `docker/monitoring/.env`
- SSH keys: `/opt/mesh-monitor/.ssh/`
- Database: PostgreSQL (containerized)

### Notifications Setup

**Email (Gmail example):**
```yaml
notifications:
  email:
    enabled: true
    smtp_server: smtp.gmail.com
    smtp_port: 587
    smtp_user: your-email@gmail.com
    smtp_password: app-password
```

**Telegram:**
```yaml
notifications:
  telegram:
    enabled: true
    bot_token: YOUR_BOT_TOKEN
    chat_id: YOUR_CHAT_ID
```

### Scaling
- 1-10 nodes: 1GB RAM, 30s interval
- 10-25 nodes: 2GB RAM, 30s interval
- 25-50 nodes: 2GB RAM, 60s interval
- 50-100 nodes: 4GB RAM, 60s interval
- 100+ nodes: 8GB+ RAM, PostgreSQL, 120s interval

## Choosing the Right Type

**Small home (1-5 clients):**
- 1× Gateway Wired
- 1× Mesh Router
- Optional: 1× Monitoring Node

**Medium home (5-20 clients):**
- 1× Gateway WiFi
- 2-3× Mesh Router
- 1× Update Cache
- 1× Monitoring Node (recommended)

**Large home / Small office (20-50 clients):**
- 2× Gateway WiFi (redundant)
- 3-5× Mesh Router
- 1-2× LAN Router
- 1× Update Cache
- 1× Monitoring Node (strongly recommended)

**Multi-building:**
- Multiple gateways (different buildings)
- Multiple cache servers (with sync)
- Mesh routers per building
- LAN routers for extension
- 1× Monitoring Node (essential for visibility)
