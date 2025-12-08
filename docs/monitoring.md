# Monitoring Node

## Overview

The Monitoring Node provides centralized network visibility, health monitoring, and alerting for your mesh network. It collects metrics from all nodes, displays real-time network topology, and sends notifications when issues are detected.

## Features

### Network Visualization
- **Real-time Topology Map** - Visual representation of mesh network
- **OSPF Neighbor Status** - See all routing relationships
- **Node Health Dashboard** - CPU, memory, disk, uptime for all nodes
- **Traffic Statistics** - Bandwidth usage per node and link
- **Service Status** - FRR, etcd, DNS, DHCP status across network

### Alerting & Notifications
- **Email Notifications** - Via SMTP
- **Telegram Bot** - Instant messaging alerts
- **Discord Webhooks** - Server notifications
- **Slack Integration** - Team channel alerts
- **Custom Webhooks** - POST to any URL

### Alert Types
- Node offline/unreachable
- OSPF neighbor down
- Service failures (FRR, etcd, DNS)
- High CPU/memory/disk usage
- Gateway internet connectivity loss
- Cache server failures
- DNS resolution issues

### Metrics Collection
- **Node Discovery** - Automatic via OSPF
- **SNMP Polling** - Standard metrics (optional)
- **SSH-based Collection** - Agentless monitoring
- **Health Check API** - Custom endpoint on each node
- **Log Aggregation** - Centralized syslog

### Web Dashboard
- **Responsive Design** - Mobile-friendly
- **Live Updates** - WebSocket-based real-time data
- **Historical Graphs** - 24h/7d/30d views
- **Network Map** - Interactive topology visualization
- **Alert History** - View past incidents
- **Export Data** - JSON/CSV downloads

## Hardware Requirements

### Minimal Setup
- 1GB RAM
- 10GB storage
- 1 Ethernet port
- Any CPU (even Raspberry Pi)

### Recommended Setup
- 2GB RAM
- 20GB storage (for historical data)
- Gigabit Ethernet
- Multi-core CPU

### Large Deployment (50+ nodes)
- 4GB RAM
- 50GB storage
- Dedicated server
- SSD storage recommended

## Installation

### Docker Installation (Recommended)

The monitoring node runs entirely in Docker containers for easy deployment and updates.

**Prerequisites:**
```bash
# Install Docker and Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt-get update
sudo apt-get install -y docker-compose-plugin
```

**Quick Start:**
```bash
# Clone repository
git clone https://github.com/YOUR-USERNAME/mesh-network.git
cd mesh-network

# Copy and configure environment
cp docker/monitoring/.env.example docker/monitoring/.env
nano docker/monitoring/.env  # Edit configuration

# Generate secure passwords
echo "DB_PASSWORD=$(openssl rand -hex 32)" >> docker/monitoring/.env
echo "SECRET_KEY=$(openssl rand -hex 32)" >> docker/monitoring/.env

# Create SSH key for node monitoring
mkdir -p /opt/mesh-monitor/.ssh
ssh-keygen -t ed25519 -f /opt/mesh-monitor/.ssh/id_ed25519 -N ""

# Pull pre-built images from GitHub Container Registry
docker pull ghcr.io/YOUR-USERNAME/mesh-network-monitor-dashboard:latest
docker pull ghcr.io/YOUR-USERNAME/mesh-network-monitor-collector:latest

# Or build locally
docker-compose -f docker/monitoring-docker-compose.yml build

# Start monitoring stack
docker-compose -f docker/monitoring-docker-compose.yml up -d

# Check status
docker-compose -f docker/monitoring-docker-compose.yml ps

# View logs
docker-compose -f docker/monitoring-docker-compose.yml logs -f
```

**Access Dashboard:**
- URL: `http://your-server-ip:8080`
- Default login: `admin` / `changeme` (change in `.env` file!)

**Optional: Start with Grafana**
```bash
docker-compose -f docker/monitoring-docker-compose.yml --profile grafana up -d
# Access Grafana at http://your-server-ip:3000
```

### Native Installation (Advanced)

For users who prefer non-containerized deployment:

```bash
# Install dependencies
sudo apt update
sudo apt install -y python3 python3-pip python3-venv nginx snmp postgresql

# Create monitoring user
sudo useradd -r -s /bin/bash -d /opt/mesh-monitor mesh-monitor

# Install monitoring software
sudo mkdir -p /opt/mesh-monitor
sudo cp -r scripts/monitoring/* /opt/mesh-monitor/
cd /opt/mesh-monitor
sudo python3 -m venv venv
sudo venv/bin/pip install -r requirements.txt

# Setup PostgreSQL
sudo -u postgres createuser mesh_monitor
sudo -u postgres createdb mesh_monitor
sudo -u postgres psql -c "ALTER USER mesh_monitor WITH PASSWORD 'your_password';"

# Install systemd services
sudo cp systemd/mesh-monitor.service /etc/systemd/system/
sudo cp systemd/mesh-monitor-collector.service /etc/systemd/system/
sudo cp systemd/mesh-monitor-collector.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now mesh-monitor
sudo systemctl enable --now mesh-monitor-collector.timer

# Setup nginx reverse proxy
sudo cp configs/nginx-monitor.conf /etc/nginx/sites-available/mesh-monitor
sudo ln -s /etc/nginx/sites-available/mesh-monitor /etc/nginx/sites-enabled/
sudo systemctl reload nginx
```

## Configuration

### Main Config: `/etc/mesh-monitor/config.yml`

```yaml
# Network Discovery
network:
  # Auto-discover via OSPF
  auto_discovery: true
  # Or specify nodes manually
  nodes:
    - hostname: gateway1
      ip: 169.254.1.1
      type: gateway
    - hostname: router1
      ip: 169.254.1.2
      type: mesh-router

# Monitoring Settings
monitoring:
  # Collection interval (seconds)
  interval: 30

  # Timeout for health checks
  timeout: 5

  # Enable SNMP monitoring
  snmp_enabled: true
  snmp_community: public

  # SSH monitoring (agentless)
  ssh_enabled: true
  ssh_user: mesh-monitor
  ssh_key: /opt/mesh-monitor/.ssh/id_ed25519

# Alert Thresholds
thresholds:
  cpu_warning: 70
  cpu_critical: 90
  memory_warning: 80
  memory_critical: 95
  disk_warning: 80
  disk_critical: 90

# Notifications
notifications:
  # Email via SMTP
  email:
    enabled: true
    smtp_server: smtp.gmail.com
    smtp_port: 587
    smtp_user: your-email@gmail.com
    smtp_password: your-app-password
    from: mesh-monitor@yourdomain.com
    to:
      - admin@yourdomain.com
      - ops@yourdomain.com

  # Telegram Bot
  telegram:
    enabled: false
    bot_token: YOUR_BOT_TOKEN
    chat_id: YOUR_CHAT_ID

  # Discord Webhook
  discord:
    enabled: false
    webhook_url: https://discord.com/api/webhooks/...

  # Slack Webhook
  slack:
    enabled: false
    webhook_url: https://hooks.slack.com/services/...

  # Custom Webhook
  webhook:
    enabled: false
    url: https://your-webhook-endpoint.com/alerts
    method: POST
    headers:
      Authorization: Bearer YOUR_TOKEN

# Web Dashboard
dashboard:
  # Listen address
  listen: 0.0.0.0
  port: 8080

  # Authentication
  auth_enabled: true
  username: admin
  password: changeme  # CHANGE THIS!

  # Session secret (generate with: openssl rand -hex 32)
  secret_key: YOUR_SECRET_KEY_HERE

# Data Retention
retention:
  # Keep metrics for
  metrics_days: 30

  # Keep alerts for
  alerts_days: 90

  # Database location
  database: /var/lib/mesh-monitor/metrics.db
```

### Notification Setup

#### Email (Gmail Example)
```bash
# Edit config
sudo nano /etc/mesh-monitor/config.yml

# Set:
notifications:
  email:
    enabled: true
    smtp_server: smtp.gmail.com
    smtp_port: 587
    smtp_user: your-email@gmail.com
    smtp_password: YOUR_APP_PASSWORD  # Not your regular password!
    from: mesh-alerts@yourdomain.com
    to:
      - admin@yourdomain.com

# Test
mesh-monitor test-notification email
```

**Gmail App Password:**
1. Go to https://myaccount.google.com/security
2. Enable 2-Step Verification
3. Generate App Password
4. Use that password in config

#### Telegram Bot
```bash
# 1. Create bot via @BotFather on Telegram
# 2. Get bot token
# 3. Get your chat_id via @userinfobot

# Edit config
sudo nano /etc/mesh-monitor/config.yml

notifications:
  telegram:
    enabled: true
    bot_token: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
    chat_id: 123456789

# Test
mesh-monitor test-notification telegram
```

#### Discord Webhook
```bash
# 1. In Discord: Server Settings → Integrations → Webhooks
# 2. Create webhook, copy URL

sudo nano /etc/mesh-monitor/config.yml

notifications:
  discord:
    enabled: true
    webhook_url: https://discord.com/api/webhooks/1234.../abc...

# Test
mesh-monitor test-notification discord
```

## Usage

### Web Dashboard

Access: `http://monitoring-node-ip:8080`

**Default Login:**
- Username: `admin`
- Password: `changeme` (CHANGE THIS!)

**Features:**
- **Overview** - Network summary, active alerts
- **Topology** - Interactive network map
- **Nodes** - Detailed node status and metrics
- **Services** - Service health across network
- **Alerts** - Current and historical alerts
- **Graphs** - Performance trends
- **Settings** - Configuration and notifications

### CLI Tools

#### mesh-monitor
Main monitoring command
```bash
# Show network overview
mesh-monitor status

# List all nodes
mesh-monitor nodes

# Show node details
mesh-monitor node <hostname>

# Show alerts
mesh-monitor alerts

# Show OSPF topology
mesh-monitor topology

# Test notifications
mesh-monitor test-notification <type>
# Types: email, telegram, discord, slack, webhook

# Force discovery
mesh-monitor discover

# Export metrics
mesh-monitor export --format json --days 7 > metrics.json
mesh-monitor export --format csv --output metrics.csv
```

#### mesh-monitor-check
Health check specific services
```bash
# Check specific node
mesh-monitor-check node gateway1

# Check service across all nodes
mesh-monitor-check service frr
mesh-monitor-check service etcd
mesh-monitor-check service dns

# Check connectivity
mesh-monitor-check connectivity

# Check OSPF status
mesh-monitor-check ospf
```

## Alert Examples

### Email Alert
```
Subject: [CRITICAL] Node router2 is DOWN

Mesh Network Alert

Severity: CRITICAL
Node: router2 (169.254.1.5)
Issue: Node unreachable
Time: 2025-01-15 14:23:45

Details:
- Last seen: 2 minutes ago
- OSPF neighbors affected: 3
- Services down: All

Actions taken:
- OSPF reconverged
- Traffic rerouted via router1

--
Mesh Network Monitor
http://monitor.mesh.local:8080
```

### Telegram Alert
```
🔴 CRITICAL

Node: router2
Status: DOWN
Time: 14:23:45

OSPF neighbors affected: 3
Traffic rerouted automatically

View details: http://monitor.mesh.local:8080/nodes/router2
```

### Discord Alert
```json
{
  "embeds": [{
    "title": "🔴 Node Down",
    "description": "router2 is unreachable",
    "color": 15158332,
    "fields": [
      {"name": "Node", "value": "router2", "inline": true},
      {"name": "IP", "value": "169.254.1.5", "inline": true},
      {"name": "Status", "value": "DOWN", "inline": true},
      {"name": "OSPF Neighbors", "value": "3 affected", "inline": false}
    ],
    "timestamp": "2025-01-15T14:23:45Z"
  }]
}
```

## SSH Key Setup (Agentless Monitoring)

For monitoring nodes without installing agents:

### On Monitoring Node
```bash
# Generate SSH key
sudo -u mesh-monitor ssh-keygen -t ed25519 -f /opt/mesh-monitor/.ssh/id_ed25519 -N ""

# Show public key
sudo cat /opt/mesh-monitor/.ssh/id_ed25519.pub
```

### On Each Monitored Node
```bash
# Create monitoring user
sudo useradd -r -s /bin/bash mesh-monitor

# Add SSH key
sudo mkdir -p /home/mesh-monitor/.ssh
sudo nano /home/mesh-monitor/.ssh/authorized_keys
# Paste public key

sudo chown -R mesh-monitor:mesh-monitor /home/mesh-monitor
sudo chmod 700 /home/mesh-monitor/.ssh
sudo chmod 600 /home/mesh-monitor/.ssh/authorized_keys

# Grant sudo for monitoring commands (no password)
sudo nano /etc/sudoers.d/mesh-monitor
```

Add:
```
mesh-monitor ALL=(ALL) NOPASSWD: /usr/bin/vtysh, /usr/bin/systemctl status *, /usr/bin/etcdctl
```

### Test
```bash
# From monitoring node
sudo -u mesh-monitor ssh mesh-monitor@router1 'vtysh -c "show ip ospf neighbor"'
```

## API Endpoints

The monitoring node exposes a REST API:

### Authentication
```bash
# Get token
curl -X POST http://monitor.mesh.local:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"changeme"}'

# Returns: {"token": "eyJ..."}
```

### Endpoints

**GET /api/nodes**
```bash
curl -H "Authorization: Bearer TOKEN" \
  http://monitor.mesh.local:8080/api/nodes
```

**GET /api/nodes/{hostname}**
```bash
curl -H "Authorization: Bearer TOKEN" \
  http://monitor.mesh.local:8080/api/nodes/router1
```

**GET /api/topology**
```bash
curl -H "Authorization: Bearer TOKEN" \
  http://monitor.mesh.local:8080/api/topology
```

**GET /api/alerts**
```bash
curl -H "Authorization: Bearer TOKEN" \
  http://monitor.mesh.local:8080/api/alerts
```

**GET /api/metrics/{hostname}**
```bash
# Last 24 hours
curl -H "Authorization: Bearer TOKEN" \
  http://monitor.mesh.local:8080/api/metrics/router1?hours=24
```

## Integrations

### Prometheus Export

Enable Prometheus metrics:
```yaml
# In /etc/mesh-monitor/config.yml
prometheus:
  enabled: true
  port: 9090
```

Scrape endpoint: `http://monitor.mesh.local:9090/metrics`

### Grafana Dashboard

Import dashboard: `grafana/mesh-network-dashboard.json`

Data source: Prometheus (http://monitor.mesh.local:9090)

### Syslog Collection

Forward logs to monitoring node:
```bash
# On each node
sudo nano /etc/rsyslog.d/mesh-monitor.conf
```

Add:
```
*.* @@monitor-ip:514
```

## Troubleshooting

### Monitoring service not starting
```bash
# Check status
sudo systemctl status mesh-monitor

# Check logs
sudo journalctl -u mesh-monitor -f

# Verify config
sudo mesh-monitor validate-config
```

### Nodes not discovered
```bash
# Check OSPF
vtysh -c "show ip ospf neighbor"

# Manual discovery
sudo mesh-monitor discover --force

# Check SSH access
sudo -u mesh-monitor ssh mesh-monitor@node-ip 'hostname'
```

### Notifications not working
```bash
# Test each type
mesh-monitor test-notification email
mesh-monitor test-notification telegram

# Check config
sudo mesh-monitor validate-config notifications

# Check logs
sudo journalctl -u mesh-monitor | grep notification
```

### Dashboard not accessible
```bash
# Check nginx
sudo systemctl status nginx
sudo nginx -t

# Check firewall
sudo ufw allow 8080/tcp

# Check dashboard service
sudo systemctl status mesh-monitor
```

## Security Considerations

1. **Change default password** immediately after installation
2. **Use HTTPS** for production (configure nginx with SSL)
3. **Restrict access** via firewall to admin IPs only
4. **Rotate SSH keys** periodically
5. **Use read-only monitoring** (don't grant write access)
6. **Secure notification credentials** (use app passwords, not main passwords)
7. **Enable authentication** for all API access

### Enable HTTPS
```bash
# Generate SSL certificate
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d monitor.yourdomain.com

# Or self-signed
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/mesh-monitor.key \
  -out /etc/ssl/certs/mesh-monitor.crt

# Update nginx config
sudo nano /etc/nginx/sites-available/mesh-monitor
# Add SSL configuration
```

## Performance

### Scaling Guidelines

| Nodes | CPU | RAM | Disk | Interval |
|-------|-----|-----|------|----------|
| 1-10 | 1 core | 512MB | 5GB | 30s |
| 10-25 | 2 cores | 1GB | 10GB | 30s |
| 25-50 | 2 cores | 2GB | 20GB | 60s |
| 50-100 | 4 cores | 4GB | 50GB | 60s |
| 100+ | 8+ cores | 8GB+ | 100GB+ | 120s |

### Optimization

**For large networks:**
- Increase polling interval
- Disable SNMP, use SSH only
- Use dedicated database server (PostgreSQL instead of SQLite)
- Enable metrics aggregation
- Reduce retention period

## Example Deployments

### Home Network (5 nodes)
```yaml
monitoring:
  interval: 30
  ssh_enabled: true
  snmp_enabled: false

notifications:
  email:
    enabled: true

retention:
  metrics_days: 30
```

### Small Business (25 nodes)
```yaml
monitoring:
  interval: 60
  ssh_enabled: true
  snmp_enabled: true

notifications:
  email:
    enabled: true
  telegram:
    enabled: true

retention:
  metrics_days: 90
```

### Campus Network (100+ nodes)
```yaml
monitoring:
  interval: 120
  ssh_enabled: true
  snmp_enabled: true

database:
  type: postgresql
  host: db.mesh.local

notifications:
  email:
    enabled: true
  slack:
    enabled: true
  webhook:
    enabled: true

retention:
  metrics_days: 365
```
