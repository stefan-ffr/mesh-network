#!/bin/bash
# Install packages for LAN router node (wired mesh + LAN clients)
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing LAN router packages ==="

# DHCP server for LAN clients
apt-get install -y \
    isc-dhcp-server

# Network tools
apt-get install -y \
    bridge-utils \
    vlan

# Enable DHCP server
systemctl enable isc-dhcp-server

echo "=== LAN router packages installed successfully ==="
