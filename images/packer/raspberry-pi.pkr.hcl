# Packer template for Raspberry Pi Mesh Network Images
# Builds images using packer-builder-arm plugin

packer {
  required_plugins {
    arm-image = {
      version = ">= 0.2.7"
      source  = "github.com/solo-io/arm-image"
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

variable "base_image_url" {
  type    = string
  default = "https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2024-03-15/2024-03-15-raspios-bookworm-arm64-lite.img.xz"
}

source "arm-image" "raspberry_pi" {
  iso_url           = var.base_image_url
  iso_checksum      = "none"
  output_filename   = "output/mesh-network-${var.node_type}-${var.mesh_version}-arm64.img"
  qemu_binary       = "qemu-aarch64-static"
  target_image_size = 8589934592 # 8GB
}

build {
  sources = ["source.arm-image.raspberry_pi"]

  # Enable SSH
  provisioner "shell" {
    inline = [
      "touch /boot/ssh"
    ]
  }

  # Update system
  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get update",
      "apt-get upgrade -y",
      "apt-get install -y git curl wget python3 python3-pip python3-venv"
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
    destination = "/opt/mesh-network/scripts/"
  }

  provisioner "file" {
    source      = "../configs/"
    destination = "/opt/mesh-network/configs/"
  }

  provisioner "file" {
    source      = "../systemd/"
    destination = "/etc/systemd/system/"
  }

  # Configure system
  provisioner "shell" {
    script = "scripts/configure-system.sh"
    environment_vars = [
      "NODE_TYPE=${var.node_type}",
      "MESH_VERSION=${var.mesh_version}"
    ]
  }

  # Cleanup
  provisioner "shell" {
    inline = [
      "apt-get clean",
      "rm -rf /var/lib/apt/lists/*",
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*"
    ]
  }

  # Compress output
  post-processor "compress" {
    output = "output/mesh-network-${var.node_type}-${var.mesh_version}-arm64.img.xz"
  }

  # Generate checksums
  post-processor "checksum" {
    checksum_types = ["sha256"]
    output         = "output/mesh-network-${var.node_type}-${var.mesh_version}-arm64.img.xz.sha256"
  }
}
