#!/bin/bash
# Install packages for communication hub node
# Local communication services without internet dependency
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing communication hub packages ==="

# Docker for containerized services
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker mesh || sudo usermod -aG docker $USER || true
sudo apt-get install -y docker-compose-plugin

# Matrix Synapse (federated chat)
echo "Pulling Matrix Synapse..."
sudo docker pull matrixdotorg/synapse:latest || true
sudo docker pull vectorim/element-web:latest || true

# Mumble (low-latency voice chat)
sudo apt-get install -y mumble-server
sudo systemctl enable mumble-server || true

# Jitsi Meet for video (optional, resource heavy)
# sudo docker pull jitsi/web:latest || true

# XMPP Server (Prosody) as Matrix alternative
sudo apt-get install -y \
    prosody \
    lua-sec \
    lua-bitop

# IRC Server for simple text chat
sudo apt-get install -y \
    inspircd || sudo apt-get install -y ngircd || true

# Email server for local mesh mail
sudo apt-get install -y \
    postfix \
    dovecot-imapd \
    dovecot-pop3d

# mDNS/DNS-SD for service discovery
sudo apt-get install -y \
    avahi-daemon \
    avahi-utils \
    libnss-mdns

# Local DNS with .mesh domain
sudo apt-get install -y \
    dnsmasq \
    bind9-dnsutils

# WebRTC gateway for browser-based comms
sudo docker pull pion/ion-sfu:latest || true

# Collaborative tools
sudo docker pull nextcloud:latest || true
sudo docker pull etherpad/etherpad:latest || true

# Bulletin board / forum
sudo docker pull discourse/discourse:latest || true

# Enable services
sudo systemctl enable docker
sudo systemctl enable avahi-daemon
sudo systemctl enable postfix || true
sudo systemctl enable dovecot || true

# Create communication directories
sudo mkdir -p /srv/comm-hub/matrix
sudo mkdir -p /srv/comm-hub/files
sudo mkdir -p /srv/comm-hub/mail

echo "=== Communication hub packages installed successfully ==="
