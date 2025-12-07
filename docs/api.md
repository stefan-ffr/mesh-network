# API Reference

## Management Commands

### mesh-health
System health check

**Usage**: `mesh-health`

**Output**: Status of all services

### mesh-dns
DNS management

**Commands**:
- `mesh-dns add <fqdn> <ip> [ttl]` - Add DNS entry
- `mesh-dns del <fqdn>` - Delete entry
- `mesh-dns list [filter]` - List entries
- `mesh-dns test <fqdn>` - Test resolution
- `mesh-dns cache-stats` - Cache statistics

### mesh-update-cache
Cache management

**Commands**:
- `mesh-update-cache stats` - Show statistics
- `mesh-update-cache health` - Health check
- `mesh-update-cache clients` - Connected clients
- `mesh-update-cache clear-apt` - Clear APT cache
- `mesh-update-cache clear-squid` - Clear Squid cache

### mesh-lancache-stats
LANcache statistics

**Usage**: `mesh-lancache-stats`

### mesh-anycast-status
Anycast routing status

**Usage**: `mesh-anycast-status`

### mesh-backup
Create backup

**Usage**: `mesh-backup`

**Output**: Backup file location

### mesh-restore
Restore from backup

**Usage**: `mesh-restore <file>`

**List backups**: `mesh-restore` (no arguments)

## Configuration Files

### FRR
- Location: `/etc/frr/frr.conf`
- Reload: `systemctl reload frr`

### DNS
- CoreDNS: `/etc/coredns/Corefile`
- Unbound: `/etc/unbound/unbound.conf`
- Reload: `systemctl reload coredns unbound`

### DHCP
- Location: `/etc/dhcp/dhcpd.conf`
- Reload: `systemctl reload isc-dhcp-server`

### Network
- Location: `/etc/network/interfaces`
- Reload: `systemctl restart networking`

## Logs

- FRR: `/var/log/frr/frr.log`
- etcd: `journalctl -u etcd`
- CoreDNS: `journalctl -u coredns`
- System: `journalctl -xe`
