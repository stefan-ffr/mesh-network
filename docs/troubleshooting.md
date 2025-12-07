# Troubleshooting Guide

## Common Issues

### No OSPF Neighbors

**Symptom**: `vtysh -c "show ip ospf neighbor"` shows nothing

**Solutions**:
1. Check FRR service: `systemctl status frr`
2. Verify interface up: `ip link show mesh0`
3. Check link-local IP: `ip addr show mesh0`
4. Firewall rules: `iptables -L`
5. Check OSPF config: `vtysh -c "show running-config"`

### DNS Not Resolving

**Symptom**: `dig test.mesh.test` fails

**Solutions**:
1. Check CoreDNS: `systemctl status coredns`
2. Check etcd: `etcdctl endpoint health --cluster`
3. Check Unbound: `systemctl status unbound`
4. Verify DNS entry exists: `etcdctl get /skydns/test/mesh/test`

### No Internet Access

**Symptom**: Clients can't reach internet

**Solutions**:
1. Check gateway OSPF default route: `vtysh -c "show ip route"`
2. Verify NAT rules: `iptables -t nat -L`
3. Check WAN interface: `ip addr show eth0`
4. Test from gateway: `ping 8.8.8.8`

### Cache Not Working

**Symptom**: Updates download from internet

**Solutions**:
1. Check anycast route: `ip route get 10.99.99.1`
2. Verify cache services: `systemctl status apt-cacher-ng squid`
3. Check DNS redirect: `dig deb.debian.org` (should be 10.99.99.1)
4. Test cache ports: `nc -zv 10.99.99.1 3142`

### Mesh WiFi Not Working

**Symptom**: mesh0 interface down

**Solutions**:
1. Check WiFi driver supports 802.11s
2. Verify mesh interface config: `iw dev mesh0 info`
3. Check frequency: `iw dev mesh0 scan`
4. Restart interface: `ifdown mesh0 && ifup mesh0`

### etcd Cluster Unhealthy

**Symptom**: `etcdctl endpoint health` shows errors

**Solutions**:
1. Check all etcd services: `systemctl status etcd`
2. Verify cluster members: `etcdctl member list`
3. Check network connectivity between nodes
4. Review logs: `journalctl -u etcd`

### High CPU Usage

**Symptom**: Load average high

**Solutions**:
1. Check OSPF: `vtysh -c "show ip ospf"`
2. Reduce OSPF hello interval if many neighbors
3. Check cache server load
4. Review running processes: `top`

### Slow Performance

**Symptom**: Network slow

**Solutions**:
1. Check mesh WiFi signal: `iw dev mesh0 station dump`
2. Verify OSPF routes optimal: `vtysh -c "show ip route"`
3. Check cache hit rate: `mesh-update-cache stats`
4. Review bandwidth usage: `vnstat`

## Getting Help

1. Run `mesh-health` and save output
2. Collect logs: `journalctl -xe > logs.txt`
3. Check GitHub Issues
4. Open new issue with logs

## Debug Mode

Enable verbose logging:
```bash
# FRR
echo "log file /var/log/frr/frr.log debugging" | vtysh

# etcd
systemctl edit etcd
# Add: Environment="ETCD_DEBUG=true"

# CoreDNS
# Edit Corefile, add: debug
```
