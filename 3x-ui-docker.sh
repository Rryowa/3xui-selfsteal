#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="1.0.0"
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

colorized_echo() {
    local color=$1; local text=$2
    case $color in
        "red") printf "\e[91m${text}\e[0m\n" ;;
        "green") printf "\e[92m${text}\e[0m\n" ;;
        "blue") printf "\e[94m${text}\e[0m\n" ;;
        *) echo "${text}" ;;
    esac
}

check_running_as_root() {
    if [ "$(id -u)" != "0" ]; then
        colorized_echo red "This command must be run as root."
        exit 1
    fi
}
check_running_as_root

detect_os() {
    if [ -f /etc/lsb-release ]; then
        OS=$(lsb_release -si)
    elif [ -f /etc/os-release ]; then
        OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
        if [[ "$OS" == "Amazon Linux" ]]; then
            OS="Amazon"
        fi
    elif [ -f /etc/redhat-release ]; then
        OS=$(cat /etc/redhat-release | awk '{print $1}')
    elif [ -f /etc/arch-release ]; then
        OS="Arch"
    else
        colorized_echo red "Unsupported operating system"
        exit 1
    fi
}

detect_compose() {
    if docker compose >/dev/null 2>&1; then
        COMPOSE='docker compose'
    elif docker-compose >/dev/null 2>&1; then
        COMPOSE='docker-compose'
    else
        if [[ "$OS" == "Amazon"* ]]; then
            colorized_echo blue "Docker Compose plugin not found. Attempting manual installation..."
            mkdir -p /usr/libexec/docker/cli-plugins
            curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/libexec/docker/cli-plugins/docker-compose >/dev/null 2>&1
            chmod +x /usr/libexec/docker/cli-plugins/docker-compose
            if docker compose >/dev/null 2>&1; then
                COMPOSE='docker compose'
                colorized_echo green "Docker Compose plugin installed successfully"
            else
                colorized_echo red "Failed to install Docker Compose plugin. Please check your setup."
                exit 1
            fi
        else
            colorized_echo red "docker compose not found"
            exit 1
        fi
    fi
}

detect_os
detect_compose

check_ports() {
    local ports=(80 443 2053)
    local conflict=false
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            colorized_echo red "Port $port is already in use."
            conflict=true
        fi
    done
    if [ "$conflict" = true ]; then
        colorized_echo red "Please stop the conflicting services before installing 3x-ui."
        exit 1
    fi
}
systemctl stop x-ui 2>/dev/null || true
systemctl disable x-ui 2>/dev/null || true

check_ports

colorized_echo blue "Installing 3x-ui Docker Edition v$SCRIPT_VERSION..."

mkdir -p /opt/3x-ui/db /opt/3x-ui/cert /opt/3x-ui/backups

# Preserve existing SQLite database if migrating
if [ -f /etc/x-ui/x-ui.db ] && [ ! -f /opt/3x-ui/db/x-ui.db ]; then
    colorized_echo blue "Found existing standalone x-ui database. Copying to Docker volume..."
    cp /etc/x-ui/x-ui.db /opt/3x-ui/db/x-ui.db
fi

cat << 'DOCKER' > /opt/3x-ui/docker-compose.yml
services:
  3xui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3xui_app
    network_mode: host
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
      - NET_RAW
    tty: true
    volumes:
      - ./db/:/etc/x-ui/
      - ./cert/:/root/cert/
      - /dev/shm:/dev/shm
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
DOCKER

cd /opt/3x-ui
if command -v docker >/dev/null 2>&1; then
    $COMPOSE up -d
    colorized_echo green "✅ 3x-ui Docker started"
else
    colorized_echo red "Docker not installed. Please install docker first."
    exit 1
fi
