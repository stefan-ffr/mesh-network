#!/bin/bash
# Install packages for distributed data/storage node
# Provides redundant, distributed storage across mesh network
set -e

export DEBIAN_FRONTEND=noninteractive

echo "=== Installing data node packages ==="

# Docker for containerized services
echo "Installing Docker..."
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker mesh || sudo usermod -aG docker $USER || true
sudo apt-get install -y docker-compose-plugin

# Distributed storage - IPFS
echo "Installing IPFS..."
IPFS_VERSION="v0.24.0"
wget -q "https://dist.ipfs.tech/kubo/${IPFS_VERSION}/kubo_${IPFS_VERSION}_linux-arm64.tar.gz" -O /tmp/ipfs.tar.gz || true
if [ -f /tmp/ipfs.tar.gz ]; then
    cd /tmp && tar xzf ipfs.tar.gz
    sudo mv kubo/ipfs /usr/local/bin/
    rm -rf /tmp/kubo /tmp/ipfs.tar.gz
fi

# Distributed file system - GlusterFS
sudo apt-get install -y \
    glusterfs-server \
    glusterfs-client || true

# Ceph (lightweight - for larger deployments)
# sudo apt-get install -y ceph-common ceph-fuse || true

# MinIO for S3-compatible object storage
sudo docker pull minio/minio:latest || true
sudo docker pull minio/mc:latest || true

# Syncthing for file synchronization
sudo apt-get install -y syncthing || true

# Restic for backup
sudo apt-get install -y restic || true

# BorgBackup for deduplicating backups
sudo apt-get install -y borgbackup || true

# ZFS for local storage (optional, resource heavy)
# sudo apt-get install -y zfsutils-linux || true

# LVM for flexible storage management
sudo apt-get install -y \
    lvm2 \
    mdadm

# Samba for Windows/SMB shares
sudo apt-get install -y \
    samba \
    samba-common-bin

# NFS server
sudo apt-get install -y \
    nfs-kernel-server \
    nfs-common

# iSCSI target for block storage
sudo apt-get install -y \
    tgt \
    open-iscsi || true

# SeaweedFS (lightweight distributed file system)
sudo docker pull chrislusf/seaweedfs:latest || true

# Rclone for cloud sync (offline use)
sudo apt-get install -y rclone || true

# Database for metadata
sudo apt-get install -y \
    sqlite3 \
    postgresql-client

# Monitoring and management
sudo apt-get install -y \
    smartmontools \
    hdparm \
    iotop \
    ncdu

# Enable services
sudo systemctl enable docker
sudo systemctl enable glusterd || true
sudo systemctl enable smbd || true
sudo systemctl enable nmbd || true
sudo systemctl enable nfs-kernel-server || true

# Create storage directories
sudo mkdir -p /srv/data-node/ipfs
sudo mkdir -p /srv/data-node/minio
sudo mkdir -p /srv/data-node/gluster
sudo mkdir -p /srv/data-node/backups
sudo mkdir -p /srv/data-node/shares

# Initialize IPFS if available
if command -v ipfs &> /dev/null; then
    sudo -u mesh ipfs init --profile=lowpower 2>/dev/null || true
fi

echo "=== Data node packages installed successfully ==="
