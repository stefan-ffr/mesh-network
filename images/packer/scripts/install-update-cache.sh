#!/bin/bash
# Install packages for update cache server
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing update cache packages ==="

# Docker (for LANcache)
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sh
usermod -aG docker pi

# Docker Compose
apt-get install -y docker-compose-plugin

# APT caching
apt-get install -y \
    apt-cacher-ng

# Squid proxy
apt-get install -y \
    squid

# Enable services
systemctl enable docker
systemctl enable apt-cacher-ng
systemctl enable squid

# Pull LANcache containers
docker pull lancachenet/lancache-dns:latest
docker pull lancachenet/monolithic:latest
docker pull lancachenet/sniproxy:latest

echo "=== Update cache packages installed successfully ==="
