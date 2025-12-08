# Raspberry Pi Setup - Alternative Methods

This document describes alternative methods to set up Raspberry Pi nodes without building custom images.

## Method 1: One-Line Installer (Recommended)

The simplest method - run one command on a fresh Raspberry Pi OS installation:

```bash
curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/mesh-network/main/scripts/setup/raspberry-pi-setup.sh | sudo bash -s -- monitoring
```

Replace `monitoring` with your desired node type:
- `mesh-router` - WiFi mesh router
- `lan-router` - Wired mesh router
- `gateway-wifi` - WiFi mesh with WAN uplink
- `gateway-wired` - Wired mesh with WAN uplink
- `update-cache` - LANcache server
- `monitoring` - Network monitoring node

### What it does:
1. Updates system packages
2. Installs FRR, etcd, and required dependencies
3. Clones the mesh-network repository
4. Configures services based on node type
5. Installs Docker (for monitoring/cache nodes)
6. Sets up systemd services

### Manual Installation:

```bash
# Download script
wget https://raw.githubusercontent.com/YOUR-USERNAME/mesh-network/main/scripts/setup/raspberry-pi-setup.sh

# Make executable
chmod +x raspberry-pi-setup.sh

# Run with node type
sudo ./raspberry-pi-setup.sh monitoring
```

## Method 2: Raspberry Pi Imager with Cloud-Init

Use the official Raspberry Pi Imager with custom cloud-init configuration for fully automated setup.

### Steps:

1. **Download Raspberry Pi Imager**
   - [Download from raspberrypi.com](https://www.raspberrypi.com/software/)

2. **Prepare cloud-init configuration**

Create `user-data` file:

```yaml
#cloud-config

# Hostname
hostname: mesh-node-01

# Users
users:
  - name: mesh
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3... your-ssh-key

# Package updates
package_update: true
package_upgrade: true

# Install packages
packages:
  - git
  - curl
  - wget
  - python3-pip
  - docker.io

# Run setup script on first boot
runcmd:
  - curl -sSL https://raw.githubusercontent.com/YOUR-USERNAME/mesh-network/main/scripts/setup/raspberry-pi-setup.sh | bash -s -- monitoring
  - reboot

# Auto-reboot after setup
power_state:
  mode: reboot
  delay: now
  message: Rebooting after mesh network setup
```

3. **Flash SD card with Imager**
   - Select "Raspberry Pi OS Lite (64-bit)"
   - Click gear icon ⚙️ for Advanced Options
   - Enable SSH
   - Set username/password
   - (Optional) Configure WiFi
   - In "User data" section, paste your cloud-init config

4. **Boot and wait**
   - Insert SD card into Pi
   - Power on
   - Wait 5-10 minutes for setup to complete
   - Pi will reboot automatically

## Method 3: Ansible Playbook

For managing multiple Raspberry Pis at once.

### Prerequisites:

```bash
pip install ansible
```

### Playbook (`ansible/raspberry-pi.yml`):

```yaml
---
- name: Setup Mesh Network Nodes
  hosts: mesh_nodes
  become: yes

  vars:
    github_repo: "YOUR-USERNAME/mesh-network"
    github_branch: "main"
    install_dir: "/opt/mesh-network"

  tasks:
    - name: Update system
      apt:
        update_cache: yes
        upgrade: dist

    - name: Install common packages
      apt:
        name:
          - git
          - curl
          - python3-pip
          - network-manager
          - iptables
          - vim
        state: present

    - name: Clone repository
      git:
        repo: "https://github.com/{{ github_repo }}.git"
        dest: "{{ install_dir }}"
        version: "{{ github_branch }}"

    - name: Run setup script
      shell: "{{ install_dir }}/scripts/setup/raspberry-pi-setup.sh {{ node_type }}"
      args:
        creates: /etc/mesh-network-version
```

### Inventory (`ansible/inventory.ini`):

```ini
[mesh_nodes]
pi1.local ansible_user=pi node_type=monitoring
pi2.local ansible_user=pi node_type=mesh-router
pi3.local ansible_user=pi node_type=gateway-wifi
```

### Run:

```bash
ansible-playbook -i ansible/inventory.ini ansible/raspberry-pi.yml
```

## Method 4: Existing Image + Post-Install Script

If you already have Raspberry Pi OS running:

### Via SSH:

```bash
# From your computer
scp scripts/setup/raspberry-pi-setup.sh pi@raspberrypi.local:~/
ssh pi@raspberrypi.local 'sudo ~/raspberry-pi-setup.sh monitoring'
```

### Via USB drive:

1. Copy `raspberry-pi-setup.sh` to USB drive
2. Insert USB into Pi
3. Mount and run:
   ```bash
   sudo mount /dev/sda1 /mnt
   sudo /mnt/raspberry-pi-setup.sh monitoring
   ```

## Comparison

| Method | Complexity | Automation | Multiple Pis | Best For |
|--------|-----------|------------|--------------|----------|
| One-line installer | ⭐ Easy | Manual | No | Quick single setup |
| Cloud-Init | ⭐⭐ Medium | Full | No | Unattended install |
| Ansible | ⭐⭐⭐ Advanced | Full | Yes | Fleet management |
| Post-install | ⭐ Easy | Manual | No | Existing installs |

## Troubleshooting

### Script fails with "command not found"

Check internet connection:
```bash
ping -c 4 github.com
```

### Docker not starting (monitoring node)

Enable and start Docker:
```bash
sudo systemctl enable docker
sudo systemctl start docker
sudo systemctl status docker
```

### FRR not routing

Check FRR status:
```bash
sudo systemctl status frr
sudo vtysh -c "show ip route"
sudo vtysh -c "show ip ospf neighbor"
```

### etcd connection refused

Check etcd status:
```bash
sudo systemctl status etcd
etcdctl endpoint health
```

## Security Notes

1. **Change default passwords** after setup
2. **Use SSH keys** instead of passwords for authentication
3. **Enable firewall** for production use:
   ```bash
   sudo apt install ufw
   sudo ufw allow 22/tcp  # SSH
   sudo ufw allow 89/tcp  # OSPF
   sudo ufw enable
   ```

## Next Steps

After setup:
1. **Reboot** the Raspberry Pi
2. **Verify services** are running
3. **Check OSPF** neighbors
4. **Test connectivity** to other mesh nodes
5. **(Monitoring node)** Access dashboard at `http://<pi-ip>:8080`

## Advantages vs Image Building

✅ **No GitHub Actions limitations** - No loop device issues
✅ **Always up-to-date** - Pulls latest code from repository
✅ **Flexible** - Easy to customize per-node
✅ **Transparent** - All steps visible in script
✅ **Maintainable** - Script easier to update than image builds
✅ **Size** - No need to distribute large image files
✅ **Official base** - Uses official Raspberry Pi OS as base
