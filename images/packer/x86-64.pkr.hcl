# Packer template for x86/64 Mesh Network Images
# Builds QEMU/KVM, VMware, VirtualBox images

packer {
  required_plugins {
    qemu = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/qemu"
    }
    vmware = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/vmware"
    }
    virtualbox = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/virtualbox"
    }
  }
}

variable "mesh_version" {
  type    = string
  default = "1.0.0"
}

variable "node_type" {
  type        = string
  description = "Node type: mesh-router, lan-router, gateway-wifi, gateway-wired, update-cache, monitoring"
}

variable "disk_size" {
  type    = string
  default = "8192"  # 8GB in MB
}

variable "iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.5.0-amd64-netinst.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:013f5b44670d81280b5b1bc02455842b250df2f0c6763398feb69af1a805a14f"
}

# QEMU/KVM build
source "qemu" "mesh_network" {
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum
  output_directory  = "output/qemu-${var.node_type}"
  vm_name           = "mesh-network-${var.node_type}-${var.mesh_version}"
  disk_size         = var.disk_size
  format            = "qcow2"
  accelerator       = "kvm"
  headless          = true

  # System specs
  memory            = 2048
  cpus              = 2

  # Network
  net_device        = "virtio-net"
  disk_interface    = "virtio"

  # Boot configuration
  boot_wait         = "5s"
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"
  ]

  # SSH configuration
  ssh_username      = "mesh"
  ssh_password      = "mesh"
  ssh_timeout       = "30m"

  # Serve preseed via HTTP
  http_directory    = "http"

  shutdown_command  = "echo 'mesh' | sudo -S shutdown -P now"
}

# VMware build
source "vmware-iso" "mesh_network" {
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum
  output_directory  = "output/vmware-${var.node_type}"
  vm_name           = "mesh-network-${var.node_type}-${var.mesh_version}"
  disk_size         = var.disk_size
  disk_type_id      = "0"  # Single growable virtual disk
  headless          = true

  # System specs
  memory            = 2048
  cpus              = 2

  # Guest OS
  guest_os_type     = "debian12-64"
  version           = "19"

  # Network
  network_adapter_type = "vmxnet3"

  # Boot configuration
  boot_wait         = "5s"
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"
  ]

  # SSH configuration
  ssh_username      = "mesh"
  ssh_password      = "mesh"
  ssh_timeout       = "30m"

  http_directory    = "http"
  shutdown_command  = "echo 'mesh' | sudo -S shutdown -P now"
}

# VirtualBox build
source "virtualbox-iso" "mesh_network" {
  iso_url           = var.iso_url
  iso_checksum      = var.iso_checksum
  output_directory  = "output/virtualbox-${var.node_type}"
  vm_name           = "mesh-network-${var.node_type}-${var.mesh_version}"
  disk_size         = var.disk_size
  headless          = true

  # System specs
  memory            = 2048
  cpus              = 2

  # Guest additions
  guest_additions_mode = "disable"
  guest_os_type     = "Debian_64"

  # Hardware
  hard_drive_interface = "sata"
  iso_interface     = "sata"

  # Boot configuration
  boot_wait         = "5s"
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"
  ]

  # SSH configuration
  ssh_username      = "mesh"
  ssh_password      = "mesh"
  ssh_timeout       = "30m"

  http_directory    = "http"
  shutdown_command  = "echo 'mesh' | sudo -S shutdown -P now"

  # VirtualBox settings
  vboxmanage = [
    ["modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on"],
    ["modifyvm", "{{.Name}}", "--memory", "2048"],
    ["modifyvm", "{{.Name}}", "--cpus", "2"]
  ]
}

build {
  name = "mesh-network-${var.node_type}"

  sources = [
    "source.qemu.mesh_network",
    "source.vmware-iso.mesh_network",
    "source.virtualbox-iso.mesh_network"
  ]

  # Update system
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade -y"
    ]
  }

  # Install common packages
  provisioner "shell" {
    script = "scripts/install-common.sh"
  }

  # Install node-specific packages
  provisioner "shell" {
    script = "scripts/install-${var.node_type}.sh"
  }

  # Copy mesh network files
  provisioner "file" {
    source      = "../scripts/"
    destination = "/tmp/mesh-scripts/"
  }

  provisioner "shell" {
    inline = [
      "sudo mkdir -p /opt/mesh-network",
      "sudo cp -r /tmp/mesh-scripts/* /opt/mesh-network/",
      "sudo rm -rf /tmp/mesh-scripts"
    ]
  }

  provisioner "file" {
    source      = "../configs/"
    destination = "/tmp/mesh-configs/"
  }

  provisioner "shell" {
    inline = [
      "sudo cp -r /tmp/mesh-configs /opt/mesh-network/configs",
      "sudo rm -rf /tmp/mesh-configs"
    ]
  }

  provisioner "file" {
    source      = "../systemd/"
    destination = "/tmp/mesh-systemd/"
  }

  provisioner "shell" {
    inline = [
      "sudo cp /tmp/mesh-systemd/*.service /etc/systemd/system/",
      "sudo cp /tmp/mesh-systemd/*.timer /etc/systemd/system/ 2>/dev/null || true",
      "sudo rm -rf /tmp/mesh-systemd"
    ]
  }

  # Configure system
  provisioner "shell" {
    environment_vars = [
      "NODE_TYPE=${var.node_type}",
      "MESH_VERSION=${var.mesh_version}"
    ]
    inline = [
      "echo 'MESH_NETWORK_VERSION=${var.mesh_version}' | sudo tee /etc/mesh-network-version",
      "echo 'NODE_TYPE=${var.node_type}' | sudo tee -a /etc/mesh-network-version",
      "echo 'BUILD_DATE='$(date -u +'%Y-%m-%d %H:%M:%S UTC') | sudo tee -a /etc/mesh-network-version",
      "echo 'ARCH=x86_64' | sudo tee -a /etc/mesh-network-version"
    ]
  }

  # Cleanup
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /var/lib/apt/lists/*",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*"
    ]
  }

  # Post-processors for QEMU
  post-processors {
    # Convert QCOW2 to multiple formats
    post-processor "shell-local" {
      only = ["qemu.mesh_network"]
      inline = [
        "qemu-img convert -f qcow2 -O raw output/qemu-${var.node_type}/mesh-network-${var.node_type}-${var.mesh_version} output/mesh-network-${var.node_type}-${var.mesh_version}-x86_64.img",
        "qemu-img convert -f qcow2 -O vmdk output/qemu-${var.node_type}/mesh-network-${var.node_type}-${var.mesh_version} output/mesh-network-${var.node_type}-${var.mesh_version}-x86_64.vmdk",
        "qemu-img convert -f qcow2 -O vdi output/qemu-${var.node_type}/mesh-network-${var.node_type}-${var.mesh_version} output/mesh-network-${var.node_type}-${var.mesh_version}-x86_64.vdi",
        "cp output/qemu-${var.node_type}/mesh-network-${var.node_type}-${var.mesh_version} output/mesh-network-${var.node_type}-${var.mesh_version}-x86_64.qcow2"
      ]
    }

    # Compress
    post-processor "compress" {
      output = "output/mesh-network-${var.node_type}-${var.mesh_version}-x86_64-{{.BuilderType}}.tar.xz"
    }

    # Generate checksums
    post-processor "checksum" {
      checksum_types = ["sha256"]
      output         = "output/mesh-network-${var.node_type}-${var.mesh_version}-x86_64-{{.BuilderType}}.tar.xz.sha256"
    }
  }
}
