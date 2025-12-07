# Installation Guide

## Prerequisites

- Debian 13 (Trixie) or Ubuntu 24.04+
- Root access
- Supported hardware (see README.md)
- Internet connection during installation

## Quick Install
```bash
curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/mesh-network/main/install.sh | sudo bash
```

## Manual Installation

### 1. Clone Repository
```bash
git clone https://github.com/YOUR-USERNAME/mesh-network.git
cd mesh-network
```

### 2. Run Installer
```bash
sudo ./install.sh
```

### 3. Follow Interactive Setup

The installer will:
1. Detect your system
2. Ask for node type
3. Configure interfaces
4. Install packages
5. Set up services
6. Create backups

### 4. Verify Installation
```bash
mesh-health
```

## Node Type Selection

See [node-types.md](node-types.md) for detailed explanations.

## Post-Installation

### Add Additional Nodes

Simply run the installer on new machines - they will automatically discover and join the mesh.

### Configure Clients

Clients need **zero configuration**! They will automatically:
- Get DHCP
- Use local DNS
- Route through mesh
- Use update cache (if available)

## Troubleshooting

See [troubleshooting.md](troubleshooting.md) for common issues.
