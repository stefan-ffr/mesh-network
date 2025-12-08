#!/bin/bash
# Install packages for monitoring node
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing monitoring node packages ==="

# Docker (for containerized monitoring)
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sh
usermod -aG docker pi

# Docker Compose
apt-get install -y docker-compose-plugin

# Monitoring tools
apt-get install -y \
    postgresql-client \
    snmp \
    snmpd \
    openssh-client \
    python3-paramiko

# System monitoring
apt-get install -y \
    sysstat \
    iotop \
    iftop \
    nload

# Enable services
systemctl enable docker
systemctl enable ssh

# Pull monitoring containers
docker pull postgres:16-alpine
docker pull nginx:alpine
docker pull grafana/grafana:latest || true
docker pull prom/prometheus:latest || true

echo "=== Monitoring packages installed successfully ==="
