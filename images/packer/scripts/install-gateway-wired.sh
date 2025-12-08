#!/bin/bash
# Install packages for wired gateway node (wired mesh + WAN)
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing wired gateway packages ==="

# Gateway/firewall tools
apt-get install -y \
    iptables-persistent \
    fail2ban \
    dnsmasq

# Network tools
apt-get install -y \
    bridge-utils \
    vlan

# Enable fail2ban
systemctl enable fail2ban

echo "=== Wired gateway packages installed successfully ==="
