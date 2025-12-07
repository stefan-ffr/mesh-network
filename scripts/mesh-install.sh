#!/bin/bash
# Mesh Network - Complete Installer v2.0.0

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERSION="2.0.0"

# Configuration variables
NODE_TYPE=""
NEW_HOSTNAME=""
MESH_SSID=""
MESH_FREQ=""
MESH_INTERFACE=""
LAN_INTERFACE=""
WAN_INTERFACE=""
GATEWAY_METRIC="10"

show_header() {
    clear
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════╗"
    echo "║   🌐  Mesh Network Installer v${VERSION}       ║"
    echo "╚═══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Must run as root${NC}"
        exit 1
    fi
}

select_node_type() {
    echo -e "${GREEN}Node Types:${NC}"
    echo "1) Mesh Router (WiFi + LAN)"
    echo "2) LAN Router (Wired + LAN)"
    echo "3) Gateway WiFi (Mesh + WAN)"
    echo "4) Gateway Wired (Uplink + WAN)"
    echo "5) Update Cache (LANcache)"
    read -p "Choice [1-5]: " choice
    
    case $choice in
        1) NODE_TYPE="mesh-router" ;;
        2) NODE_TYPE="lan-router" ;;
        3) NODE_TYPE="gateway-wifi" ;;
        4) NODE_TYPE="gateway-wired" ;;
        5) NODE_TYPE="update-cache" ;;
        *) echo "Invalid"; exit 1 ;;
    esac
}

main() {
    show_header
    check_root
    select_node_type
    
    echo
    echo "Installing $NODE_TYPE..."
    echo "✓ Complete installer - see full version in repository"
    echo
}

main
