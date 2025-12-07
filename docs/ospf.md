# OSPF Configuration Guide

## Overview

This mesh network uses OSPF (Open Shortest Path First) for dynamic routing.

## Why OSPF?

- **Automatic neighbor discovery**
- **Fast convergence** (< 10 seconds)
- **Loop-free routing**
- **Metric-based path selection**
- **Multipath support**

## Configuration

### Basic OSPF Settings
```
router ospf
  network 169.254.0.0/16 area 0
```

### Interface Configuration
```
interface mesh0
  ip ospf network point-to-multipoint
  ip ospf hello-interval 10
  ip ospf dead-interval 40
  ip ospf cost 10
```

### Gateway Configuration

Gateways announce default routes:
```
router ospf
  default-information originate always metric 10
```

Lower metric = preferred gateway.

## Anycast Configuration

Update cache servers use anycast:
```
# Loopback anycast IP
interface lo
  ip ospf network point-to-point
  ip ospf cost 1
  
router ospf
  network 10.99.99.1/32 area 0
```

## Monitoring

### Show OSPF neighbors
```bash
vtysh -c "show ip ospf neighbor"
```

### Show routing table
```bash
vtysh -c "show ip route ospf"
```

### Show OSPF database
```bash
vtysh -c "show ip ospf database"
```

## Troubleshooting

See [troubleshooting.md](troubleshooting.md#ospf-issues).
