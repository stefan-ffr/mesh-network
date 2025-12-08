#!/bin/bash
# Install packages for update cache server
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing update cache packages ==="

# Docker (for LANcache)
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker mesh || sudo usermod -aG docker $USER || true

# Docker Compose
sudo apt-get install -y docker-compose-plugin

# APT caching
sudo apt-get install -y \
    apt-cacher-ng

# Squid proxy
sudo apt-get install -y \
    squid

# Enable services
sudo systemctl enable docker
sudo systemctl enable apt-cacher-ng || true
sudo systemctl enable squid || true

# Pull LANcache containers (optional, may timeout)
sudo docker pull lancachenet/lancache-dns:latest || true
sudo docker pull lancachenet/monolithic:latest || true
sudo docker pull lancachenet/sniproxy:latest || true

echo "=== Update cache packages installed successfully ==="
