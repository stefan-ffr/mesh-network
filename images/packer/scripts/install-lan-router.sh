#!/bin/bash
# Install packages for LAN router node (wired mesh + LAN clients)
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing LAN router packages ==="

# DHCP server for LAN clients
sudo apt-get install -y \
    isc-dhcp-server

# Network tools
sudo apt-get install -y \
    bridge-utils \
    vlan

# Enable DHCP server
sudo systemctl enable isc-dhcp-server || true

echo "=== LAN router packages installed successfully ==="
