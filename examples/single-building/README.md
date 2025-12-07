# Single Building Setup Example

## Topology
```
Internet → [Gateway] → [Mesh Router 1] ←WiFi→ [Mesh Router 2]
                            ↓                       ↓
                        [Cache]                 Clients
                            ↓
                        Clients
```

## Hardware

- 1× Gateway (Raspberry Pi 4 with ethernet)
- 2× Mesh Router (Raspberry Pi 4 with WiFi)
- 1× Cache Server (old PC with 500GB HDD)

## Installation Steps

### 1. Gateway
```bash
sudo ./install.sh
# Select: 4) Gateway Wired
# WAN interface: eth0
# Mesh interface: eth1
```

### 2. Mesh Routers
```bash
sudo ./install.sh
# Select: 1) Mesh Router
# WiFi: wlan0
# LAN: eth1
# SSID: home-mesh
```

### 3. Cache Server
```bash
sudo ./install.sh
# Select: 5) Update Cache
# Type: 2) LANcache
# Size: 500GB
```

## Expected Results

- All nodes discover each other automatically
- Clients get internet access
- Updates cached transparently
- 85%+ bandwidth savings
