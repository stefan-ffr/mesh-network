#!/bin/bash
# Install packages for emergency node (offline communication hub)
# Designed for disaster relief / field communication without internet
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing emergency node packages ==="

# Docker for containerized services
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker mesh || sudo usermod -aG docker $USER || true
sudo apt-get install -y docker-compose-plugin

# Matrix Synapse (offline chat server)
echo "Setting up Matrix Synapse..."
sudo docker pull matrixdotorg/synapse:latest || true

# File sharing
echo "Installing file sharing tools..."
sudo apt-get install -y \
    samba \
    nfs-kernel-server \
    vsftpd

# Syncthing for P2P file sync
sudo docker pull syncthing/syncthing:latest || true

# Offline web server for emergency info
sudo apt-get install -y \
    nginx \
    php-fpm \
    php-sqlite3

# Offline maps support (tile server)
sudo docker pull maptiler/tileserver-gl:latest || true

# LoRa/Meshtastic bridge support
sudo apt-get install -y \
    python3-serial \
    python3-protobuf \
    screen

# Emergency broadcast tools
sudo apt-get install -y \
    espeak-ng \
    sox \
    mpg123

# QR code generation for sharing network info
sudo apt-get install -y qrencode

# Enable services
sudo systemctl enable docker
sudo systemctl enable nginx
sudo systemctl enable smbd || true
sudo systemctl enable nfs-server || true

# Create emergency data directories
sudo mkdir -p /srv/emergency/files
sudo mkdir -p /srv/emergency/maps
sudo mkdir -p /srv/emergency/docs
sudo chmod 777 /srv/emergency/files

echo "=== Emergency node packages installed successfully ==="
