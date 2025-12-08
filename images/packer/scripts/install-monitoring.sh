#!/bin/bash
# Install packages for monitoring node
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing monitoring node packages ==="

# Docker (for containerized monitoring)
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker mesh || sudo usermod -aG docker $USER || true

# Docker Compose
sudo apt-get install -y docker-compose-plugin

# Monitoring tools
sudo apt-get install -y \
    postgresql-client \
    snmp \
    snmpd \
    openssh-client \
    python3-paramiko

# System monitoring
sudo apt-get install -y \
    sysstat \
    iotop \
    iftop \
    nload

# Enable services
sudo systemctl enable docker
sudo systemctl enable ssh

# Pull monitoring containers (optional, may timeout)
sudo docker pull postgres:16-alpine || true
sudo docker pull nginx:alpine || true
sudo docker pull grafana/grafana:latest || true
sudo docker pull prom/prometheus:latest || true

echo "=== Monitoring packages installed successfully ==="
