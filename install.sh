#!/bin/bash
# Mesh Network - Quick Installer

set -e

REPO_URL="https://raw.githubusercontent.com/YOUR-USERNAME/mesh-network/main"
VERSION="2.0.0"

echo "╔═══════════════════════════════════════════════╗"
echo "║     Mesh Network Installer v${VERSION}          ║"
echo "╚═══════════════════════════════════════════════╝"

if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root"
   exit 1
fi

echo "📥 Downloading main installer..."
curl -sSL "${REPO_URL}/scripts/mesh-install.sh" -o /tmp/mesh-install.sh
chmod +x /tmp/mesh-install.sh

echo "🚀 Starting installation..."
/tmp/mesh-install.sh
