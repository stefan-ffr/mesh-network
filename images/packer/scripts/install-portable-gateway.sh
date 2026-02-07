#!/bin/bash
# Install packages for portable gateway node
# Mobile internet via LTE/5G/Starlink with automatic failover
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing portable gateway packages ==="

# ModemManager for LTE/5G modems
sudo apt-get install -y \
    modemmanager \
    libmbim-utils \
    libqmi-utils \
    usb-modeswitch \
    usb-modeswitch-data

# NetworkManager with ModemManager integration
sudo apt-get install -y \
    network-manager-gnome \
    network-manager-openvpn

# PPP for legacy modems
sudo apt-get install -y \
    ppp \
    wvdial

# Gateway/NAT tools
sudo apt-get install -y \
    iptables-persistent \
    fail2ban \
    dnsmasq \
    nftables

# Traffic shaping and QoS
sudo apt-get install -y \
    wondershaper \
    tc \
    sqm-scripts || true

# Failover and load balancing
sudo apt-get install -y \
    ifupdown \
    ifenslave \
    mwan3 || true

# VPN clients for secure backhaul
sudo apt-get install -y \
    wireguard-tools \
    openvpn \
    openconnect

# Bandwidth monitoring
sudo apt-get install -y \
    vnstat \
    iftop \
    nethogs \
    bmon

# Starlink support (USB ethernet)
sudo apt-get install -y \
    ethtool

# GPS support for location tracking
sudo apt-get install -y \
    gpsd \
    gpsd-clients

# Power management for mobile use
sudo apt-get install -y \
    tlp \
    powertop

# Enable services
sudo systemctl enable ModemManager
sudo systemctl enable NetworkManager
sudo systemctl enable fail2ban || true
sudo systemctl enable vnstat || true

# Create failover script directory
sudo mkdir -p /opt/mesh-network/failover
sudo mkdir -p /etc/NetworkManager/dispatcher.d

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-gateway.conf
echo "net.ipv6.conf.all.forwarding=1" | sudo tee -a /etc/sysctl.d/99-gateway.conf

echo "=== Portable gateway packages installed successfully ==="
