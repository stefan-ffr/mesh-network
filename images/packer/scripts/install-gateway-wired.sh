#!/bin/bash
# Install packages for wired gateway node (wired mesh + WAN)
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing wired gateway packages ==="

# Gateway/firewall tools
sudo apt-get install -y \
    iptables-persistent \
    fail2ban \
    dnsmasq

# Network tools
sudo apt-get install -y \
    bridge-utils \
    vlan

# Enable fail2ban
sudo systemctl enable fail2ban || true

echo "=== Wired gateway packages installed successfully ==="
