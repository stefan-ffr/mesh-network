#!/bin/bash
# Install packages for mesh router node
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing mesh router packages ==="

# WiFi tools
sudo apt-get install -y \
    wpasupplicant \
    hostapd \
    wireless-tools \
    iw \
    crda || sudo apt-get install -y wpasupplicant hostapd wireless-tools iw

# DHCP server
sudo apt-get install -y \
    isc-dhcp-server

# Enable hostapd for WiFi AP
sudo systemctl unmask hostapd || true
sudo systemctl enable hostapd || true

# Enable DHCP server
sudo systemctl enable isc-dhcp-server || true

echo "=== Mesh router packages installed successfully ==="
