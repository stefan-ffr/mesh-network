#!/bin/bash
# Common packages for all mesh network nodes
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing common mesh network packages ==="

# Networking tools
apt-get install -y \
    network-manager \
    iptables \
    iproute2 \
    iputils-ping \
    dnsutils \
    net-tools \
    bridge-utils \
    vlan

# Routing (FRR)
apt-get install -y \
    frr \
    frr-pythontools

# Distributed storage (etcd)
apt-get install -y \
    etcd-server \
    etcd-client

# DNS
apt-get install -y \
    coredns \
    unbound

# System utilities
apt-get install -y \
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
echo "frr=yes" > /etc/frr/daemons
echo "zebra=yes" >> /etc/frr/daemons
echo "ospfd=yes" >> /etc/frr/daemons
echo "bgpd=no" >> /etc/frr/daemons
echo "ospf6d=no" >> /etc/frr/daemons
echo "ripd=no" >> /etc/frr/daemons
echo "ripngd=no" >> /etc/frr/daemons
echo "isisd=no" >> /etc/frr/daemons
echo "pimd=no" >> /etc/frr/daemons
echo "ldpd=no" >> /etc/frr/daemons
echo "nhrpd=no" >> /etc/frr/daemons
echo "eigrpd=no" >> /etc/frr/daemons
echo "babeld=no" >> /etc/frr/daemons
echo "sharpd=no" >> /etc/frr/daemons
echo "pbrd=no" >> /etc/frr/daemons
echo "bfdd=no" >> /etc/frr/daemons
echo "fabricd=no" >> /etc/frr/daemons
echo "vrrpd=no" >> /etc/frr/daemons

systemctl enable frr

# Configure etcd
systemctl enable etcd

# Create mesh network directories
mkdir -p /opt/mesh-network
mkdir -p /etc/mesh-network
mkdir -p /var/lib/mesh-network
mkdir -p /var/log/mesh-network

echo "=== Common packages installed successfully ==="
