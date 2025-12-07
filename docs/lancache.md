# LANcache Integration Guide

## What is LANcache?

Transparent caching proxy for:
- **Windows Updates** (HTTPS transparent!)
- **Gaming** (Steam, Epic, Origin, etc.)
- **Linux Updates** (APT, YUM)
- **Software** (Docker, apps)

## How It Works

### 1. DNS Hijacking
```
Client: "Where is windowsupdate.com?"
DNS: "It's at 10.99.99.1" (anycast cache)
```

### 2. SNI Proxy
```
Client: HTTPS to 10.99.99.1
SNI Proxy reads hostname from TLS handshake
Proxy: "I have that file!" → serves from cache
OR: "Don't have it" → fetches, caches, returns
```

### 3. Anycast Routing
```
OSPF routes client to NEAREST cache server
Automatic failover if cache server down
```

## Installation

Automatically installed when selecting "Update Cache Server" node type.

## Cached Services

### Gaming
- ✅ Steam
- ✅ Epic Games
- ✅ Origin (EA)
- ✅ Battle.net (Blizzard)
- ✅ Riot Games
- ✅ Xbox Live
- ✅ PlayStation Network

### Updates
- ✅ Windows Updates
- ✅ Windows Store
- ✅ Linux (Debian/Ubuntu/etc.)
- ✅ macOS updates

### Software
- ✅ Docker Hub (partial)
- ✅ Linux ISOs
- ✅ Adobe Creative Cloud

## Performance

### Bandwidth Savings
- Linux: 90-95%
- Windows: 85-90%
- Gaming: 95%+
- Overall: 85-95%

### Speed Improvement
- First download: Internet speed
- Subsequent: LAN speed (1Gbps!)
- Example: 50GB game in 2 minutes vs 2 hours

## Multi-Server Sync

Cache servers automatically sync with each other:
```
Server A caches Game-1 (50GB)
  ↓ (5 minutes)
Server B automatically gets Game-1
  ↓
Client uses Server B → instant cache hit!
```

## Monitoring
```bash
mesh-lancache-stats
```

Shows:
- Cache size
- Hit rate
- Cached domains
- Bandwidth saved

## Client Configuration

**Zero configuration required!**

Clients automatically use cache via:
1. DNS redirect
2. DHCP WPAD (Windows)
3. OSPF anycast routing

## Troubleshooting

### Cache Miss Rate High

Check DNS redirects:
```bash
dig deb.debian.org
# Should show: 10.99.99.1
```

### Docker Not Running
```bash
docker ps
systemctl status docker
docker-compose up -d
```

### No Disk Space
```bash
du -sh /data/lancache/cache
# Clear cache if needed
docker-compose down
rm -rf /data/lancache/cache/*
docker-compose up -d
```

## Advanced Configuration

See LANcache documentation: https://lancache.net/
