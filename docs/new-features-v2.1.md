# What's New in Version 2.1

Version 2.1 brings major enhancements to the mesh network infrastructure with full IPv6 support, advanced bridging capabilities, and improved setup experience.

## 🌟 Major Features

### 1. Full IPv6 Support (Dual-Stack)

The mesh network now fully supports IPv6 alongside IPv4:

**Key Features:**
- **OSPFv3** for IPv6 routing
- **Unique Local Addresses (ULA)**: `fd00:mesh::/48` for internal communication
- **IPv6 NAT66** (NPTv6) for Internet gateways
- **Automatic address assignment** based on node hostname
- **ICMPv6** properly configured for Neighbor Discovery

**Benefits:**
- Future-proof networking
- More IP addresses (no more exhaustion!)
- Better end-to-end connectivity
- Modern Internet protocol support

**Technical Details:**
```yaml
IPv6 Configuration:
  ULA Prefix: fd00:mesh::/48
  Node Addresses: fd00:mesh::<node-id>:1/64
  Routing: OSPFv3 (area 0.0.0.0)
  NAT66: Enabled on gateways (ULA → GUA translation)
```

### 2. WiFi-to-Wired Mesh Bridge

Seamlessly connect BATMAN-adv (WiFi mesh) with OSPF (wired mesh):

**Architecture:**
```
┌─────────────────────────────────┐
│   Gateway (Hybrid) Node         │
├─────────────────────────────────┤
│                                 │
│  wlan0 → BATMAN-adv (bat0)      │
│            ↓                    │
│       br-mesh (Bridge)          │
│            ↓                    │
│       eth0 (OSPF)               │
│            ↓                    │
│       eth1 (WAN)                │
└─────────────────────────────────┘
```

**Use Cases:**
- Connect WiFi mesh islands with Ethernet backbone
- Use Ethernet for high-bandwidth links between buildings
- Provide redundant paths (WiFi + Ethernet)
- Bridge mobile WiFi clients with wired infrastructure

**How It Works:**
1. **BATMAN-adv** handles WiFi mesh (Layer 2, ad-hoc networking)
2. **Bridge (br-mesh)** connects bat0 with Ethernet interface
3. **OSPF** handles routing across the wired segment
4. Traffic flows transparently between both segments

### 3. Interactive Setup Script

New automatic setup wizard with intelligent interface detection:

**Features:**
- ✅ **Auto-detects** all network interfaces (WiFi + Ethernet)
- ✅ **Shows details**: Link status, speed, MAC addresses
- ✅ **Interactive selection**: Choose your node type
- ✅ **Smart assignment**: Automatic interface role assignment
- ✅ **One-command setup**: No manual configuration needed

**Example Output:**
```
Detected interfaces:
  📶 wlan0 (WiFi)
     ssid: mesh-network
     channel: 6
  🔌 eth0 (Wired, 1000Mbps, up) - MAC: aa:bb:cc:dd:ee:ff
  🔌 eth1 (Wired, 1000Mbps, up) - MAC: 11:22:33:44:55:66

Node Types:
1) Mesh Router       - WiFi mesh + LAN distribution
2) LAN Router        - Wired mesh + LAN distribution
3) Gateway (WiFi)    - WiFi mesh + Internet gateway
4) Gateway (Wired)   - Wired mesh + Internet gateway
5) Gateway (Hybrid)  - WiFi + Wired mesh bridge + Internet ⭐
6) Update Cache      - LANcache node
7) Monitoring Node   - Network monitoring
```

**Usage:**
```bash
wget https://raw.githubusercontent.com/YOUR-USERNAME/mesh-network/main/scripts/setup/interactive-setup.sh
chmod +x interactive-setup.sh
sudo ./interactive-setup.sh
```

See [Interactive Setup Guide](interactive-setup.md) for full documentation.

## 🎯 New Node Type

### Gateway (Hybrid)

The new hybrid gateway bridges WiFi and wired mesh segments while providing Internet access.

**Hardware Requirements:**
- 1x WiFi adapter (802.11s or ad-hoc capable)
- 2+ Ethernet ports (1 for mesh, 1 for WAN)
- 1GB+ RAM
- 8GB+ storage

**Features:**
- BATMAN-adv ↔ OSPF bridging
- IPv4 + IPv6 NAT
- Dual-stack routing
- Automatic failover between segments

**Perfect For:**
- Multi-building deployments
- Mixed WiFi/Ethernet infrastructure
- High-availability setups
- Bandwidth-intensive applications

## 📊 IPv6 Technical Details

### Addressing

**ULA (Unique Local Addresses):**
```
Prefix:     fd00:mesh::/48
Subnets:    fd00:mesh::/64 (first subnet)
Node IDs:   Generated from hostname (MD5 hash)

Example:
  Hostname: mesh-gw-01
  Node ID:  a3c4
  Address:  fd00:mesh::a3c4:1/64
```

### Routing (OSPFv3)

OSPFv3 configuration mirrors OSPFv2:
```
Router ID:      Same as OSPFv2 (IPv4 address)
Area:           0.0.0.0 (backbone)
Hello Interval: 1 second
Dead Interval:  4 seconds
Network Type:   Point-to-point
```

### NAT66 (NPTv6)

Internet gateways use Network Prefix Translation:

**Internal → External:**
```
fd00:mesh::/48  →  2001:xxxx:xxxx::/48 (ISP prefix)
```

**Advantages:**
- Stable internal addressing
- ISP-independent numbering
- Privacy (internal structure hidden)
- Easy ISP migration

**Limitations:**
- Some applications may not support NAT66
- End-to-end principle slightly violated
- Inbound connections require configuration

### ICMPv6

Properly configured ICMPv6 types:
- **Neighbor Discovery** (ND) - Essential for IPv6
- **Router Advertisement** (RA) - Autoconfiguration
- **Path MTU Discovery** - Optimal packet sizes
- **Echo Request/Reply** - Ping6

### Firewall Rules

IPv6 firewall includes:
```
✅ Established/Related connections
✅ ICMPv6 (all types)
✅ OSPFv3 (protocol 89)
✅ DHCPv6 (ports 546-547)
✅ SSH (port 22)
✅ Link-local traffic (fe80::/10)
✅ Mesh interface traffic
❌ Invalid packets (dropped)
```

## 🔧 Bridge Configuration

### systemd-networkd

The bridge uses systemd-networkd for configuration:

**/etc/systemd/network/20-mesh-bridge.netdev:**
```ini
[NetDev]
Name=br-mesh
Kind=bridge
```

**/etc/systemd/network/20-mesh-bridge.network:**
```ini
[Match]
Name=br-mesh

[Network]
Description=Mesh Bridge (BATMAN-adv <-> OSPF)
Address=169.254.255.1/24
IPForward=yes

[Address]
Address=fd00:mesh::xxxx:1/64

[IPv6AcceptRA]
UseAutonomousPrefix=false
```

### Bridge Members

**BATMAN-adv interface (bat0):**
```ini
[Match]
Name=bat0

[Network]
Bridge=br-mesh
```

**Wired mesh interface (ethX):**
```ini
[Match]
Name=eth0

[Network]
Bridge=br-mesh
```

### Performance Tuning

Optional bridge optimizations:
```bash
# Disable STP if not needed (faster convergence)
echo 0 > /sys/class/net/br-mesh/bridge/stp_state

# Adjust ageing time (5 minutes)
echo 300 > /sys/class/net/br-mesh/bridge/ageing_time

# Forward delay (faster bridging)
echo 2 > /sys/class/net/br-mesh/bridge/forward_delay
```

## 🚀 Migration Guide

### From v2.0 to v2.1

**Existing Installations:**

IPv6 support is **opt-in** and won't break existing v2.0 installations.

**Option 1: Keep IPv4-only (default)**
- No action needed
- Everything continues to work as before

**Option 2: Enable IPv6**
1. Update to latest version:
   ```bash
   cd /opt/mesh-network
   git pull
   ```

2. Run interactive setup:
   ```bash
   sudo /opt/mesh-network/scripts/setup/interactive-setup.sh
   ```

3. Or manually enable IPv6:
   ```bash
   # In /etc/frr/daemons
   ospf6d=yes

   # Create OSPFv3 config
   sudo nano /etc/frr/ospf6d.conf

   # Enable IPv6 forwarding
   sudo sysctl -w net.ipv6.conf.all.forwarding=1
   ```

**New Installations:**

IPv6 is enabled by default on fresh installs using the interactive setup script.

### Upgrading Pre-Built Images

If you're using pre-built images, download the new v2.1 images:

**Raspberry Pi:**
```bash
wget https://github.com/YOUR-USERNAME/mesh-network/releases/download/v2.1.0/mesh-network-gateway-hybrid-2.1.0-arm64.img.xz
```

**x86/64:**
```bash
wget https://github.com/YOUR-USERNAME/mesh-network/releases/download/v2.1.0/mesh-network-gateway-hybrid-2.1.0-x86_64.qcow2.xz
```

## 📈 Performance Impact

### IPv6

**Overhead:**
- CPU: < 5% additional (OSPFv3 processing)
- Memory: ~10MB additional (routing tables)
- Bandwidth: ~2% overhead (IPv6 headers slightly larger)

**Benefits:**
- Better routing with larger address space
- Reduced NAT complexity (NAT66 is simpler than NAT44)
- Modern protocol features

### Bridging

**Overhead:**
- CPU: < 3% (bridge processing)
- Latency: < 1ms additional
- Memory: ~5MB (bridge forwarding database)

**Benefits:**
- Unified mesh topology
- Reduced routing complexity
- Better path selection

## 🛡️ Security Considerations

### IPv6 Firewall

IPv6 firewall rules are **strictly configured**:
- Default DROP policy for INPUT/FORWARD
- Explicit ACCEPT rules for needed protocols
- ICMPv6 limited to essential types
- No IPv6 forwarding to WAN without NAT66

### NAT66 Privacy

NAT66 provides:
- Internal network structure obscuration
- Stable internal addressing
- Protection from external scanning

But remember:
- Not a complete security solution
- Still need firewall rules
- End-to-end encryption still recommended

### Bridge Security

Bridge security features:
- Port isolation (if configured)
- MAC address filtering (optional)
- VLAN support (advanced)
- STP/RSTP for loop prevention

## 🐛 Known Issues

### IPv6

1. **DHCPv6 Prefix Delegation**: Not yet implemented
   - Workaround: Use static ULA prefixes

2. **Router Advertisements**: Basic implementation only
   - Workaround: Configure manually if needed

3. **NAT66 Application Support**: Some apps don't work through NAT66
   - Workaround: Use port forwarding or DMZ

### Bridging

1. **MTU Mismatch**: WiFi and Ethernet may have different MTUs
   - Workaround: Set consistent MTU on all interfaces

2. **Broadcast Storms**: Possible in complex topologies
   - Workaround: Enable STP/RSTP

3. **MAC Flapping**: Can occur with multiple paths
   - Workaround: Increase bridge ageing time

## 📚 Additional Resources

- [Interactive Setup Guide](interactive-setup.md) - Full setup documentation
- [RFC 4193](https://tools.ietf.org/html/rfc4193) - IPv6 ULA addressing
- [RFC 6296](https://tools.ietf.org/html/rfc6296) - IPv6-to-IPv6 NPT
- [RFC 5340](https://tools.ietf.org/html/rfc5340) - OSPFv3 specification
- [BATMAN-adv Wiki](https://www.open-mesh.org/projects/batman-adv/wiki) - WiFi mesh documentation

## 🎉 Feedback

We'd love to hear your feedback on these new features!

- **GitHub Issues**: [Report bugs](https://github.com/YOUR-USERNAME/mesh-network/issues)
- **GitHub Discussions**: [Share experiences](https://github.com/YOUR-USERNAME/mesh-network/discussions)
- **Pull Requests**: [Contribute improvements](https://github.com/YOUR-USERNAME/mesh-network/pulls)

---

**Happy meshing with IPv6! 🌐**
