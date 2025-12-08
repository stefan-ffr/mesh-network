#!/bin/bash
# Install packages for mesh router node
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing mesh router packages ==="

# WiFi tools
apt-get install -y \
    wpasupplicant \
    hostapd \
    wireless-tools \
    iw \
    crda

# DHCP server
apt-get install -y \
    isc-dhcp-server

# Enable hostapd for WiFi AP
systemctl unmask hostapd
systemctl enable hostapd

# Enable DHCP server
systemctl enable isc-dhcp-server

echo "=== Mesh router packages installed successfully ==="
