#!/bin/bash
# Install packages for WiFi gateway node (WiFi mesh + WAN)
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing WiFi gateway packages ==="

# WiFi tools
apt-get install -y \
    wpasupplicant \
    hostapd \
    wireless-tools \
    iw \
    crda

# Gateway/firewall tools
apt-get install -y \
    iptables-persistent \
    fail2ban \
    dnsmasq

# Enable hostapd for WiFi AP
systemctl unmask hostapd
systemctl enable hostapd

# Enable fail2ban
systemctl enable fail2ban

echo "=== WiFi gateway packages installed successfully ==="
