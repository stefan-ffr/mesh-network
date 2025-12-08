#!/bin/bash
# Install packages for WiFi gateway node (WiFi mesh + WAN)
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing WiFi gateway packages ==="

# WiFi tools
sudo apt-get install -y \
    wpasupplicant \
    hostapd \
    wireless-tools \
    iw \
    crda || sudo apt-get install -y wpasupplicant hostapd wireless-tools iw

# Gateway/firewall tools
sudo apt-get install -y \
    iptables-persistent \
    fail2ban \
    dnsmasq

# Enable hostapd for WiFi AP
sudo systemctl unmask hostapd || true
sudo systemctl enable hostapd || true

# Enable fail2ban
sudo systemctl enable fail2ban || true

echo "=== WiFi gateway packages installed successfully ==="
