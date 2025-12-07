# DNS Architecture

## Overview

Distributed DNS using etcd + CoreDNS + Unbound.

## Architecture Layers

### 1. Client Request
Client queries: `webserver.mesh.test`

### 2. Unbound (Router)
- Local recursive resolver
- Aggressive caching (1-24h)
- Cluster-wide cache sync

### 3. CoreDNS (Port 5353)
- Reads from local etcd
- Serves .mesh.test zone
- Low latency (< 1ms)

### 4. etcd Cluster
- Distributed key-value store
- Automatic replication
- Raft consensus
- Survives node failures

## DNS Record Format

Reverse domain notation:
```
Domain: webserver.mesh.test
etcd key: /skydns/test/mesh/webserver
Value: {"host":"192.168.1.100","ttl":600}
```

## Management

### Add Record
```bash
mesh-dns add webserver.mesh.test 192.168.1.100
```

### Delete Record
```bash
mesh-dns del webserver.mesh.test
```

### List Records
```bash
mesh-dns list
```

### Test Resolution
```bash
mesh-dns test webserver.mesh.test
```

## Advanced Features

### Multiple IPs (Load Balancing)
```bash
etcdctl put /skydns/test/mesh/web \
  '{"host":"192.168.1.100"}'
etcdctl put /skydns/test/mesh/web \
  '{"host":"192.168.1.101"}'
```

DNS returns both IPs (round-robin).

### SRV Records
```bash
etcdctl put /skydns/test/mesh/services/http/myapp \
  '{"host":"192.168.1.100","port":8080}'
```

Query: `dig SRV _http._tcp.services.mesh.test`

### Wildcard
```bash
etcdctl put /skydns/test/mesh/dev/* \
  '{"host":"192.168.1.200"}'
```

All `*.dev.mesh.test` → 192.168.1.200

## Performance

- **Lookup time**: < 1ms (cached)
- **Replication time**: < 100ms
- **Cache hit rate**: 90%+
- **Failover time**: < 5s

## Troubleshooting

See [troubleshooting.md](troubleshooting.md#dns-issues).
