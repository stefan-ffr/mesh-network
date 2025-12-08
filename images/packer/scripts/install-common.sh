#!/bin/bash
# Common packages for all mesh network nodes
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing common mesh network packages ==="

# Networking tools
sudo apt-get install -y \
    network-manager \
    iptables \
    iproute2 \
    iputils-ping \
    dnsutils \
    net-tools \
    bridge-utils \
    vlan

# Routing (FRR)
sudo apt-get install -y \
    frr \
    frr-pythontools

# Distributed storage (etcd)
sudo apt-get install -y \
    etcd-server \
    etcd-client

# DNS
sudo apt-get install -y \
    coredns || true
sudo apt-get install -y \
    unbound || true

# System utilities
sudo apt-get install -y \
    vim \
    nano \
    htop \
    tmux \
    screen \
    rsync \
    ca-certificates \
    gnupg \
    lsb-release

# Enable and configure FRR
sudo tee /etc/frr/daemons > /dev/null << 'EOF'
frr=yes
zebra=yes
ospfd=yes
bgpd=no
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=no
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
EOF

sudo systemctl enable frr

# Configure etcd
sudo systemctl enable etcd

# Create mesh network directories
sudo mkdir -p /opt/mesh-network
sudo mkdir -p /etc/mesh-network
sudo mkdir -p /var/lib/mesh-network
sudo mkdir -p /var/log/mesh-network

echo "=== Common packages installed successfully ==="
