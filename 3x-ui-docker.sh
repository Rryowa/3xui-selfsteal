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

validate_domain() {
    local domain="$1"
    if [[ "$domain" == */* ]] || [[ "$domain" == *\ * ]]; then
        return 1
    fi
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 1
    fi
    return 0
}

ensure_sqlite3_installed() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        colorized_echo blue "Installing sqlite3 to manage panel settings database..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y sqlite3
        elif command -v yum >/dev/null 2>&1; then
            yum install -y sqlite
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y sqlite
        else
            colorized_echo red "Unable to install sqlite3. Please install it manually."
            return 1
        fi
    fi
    return 0
}

validate_dns() {
    local domain="$1"
    local server_ip="$2"
    
    colorized_echo blue "Checking DNS resolution for $domain..."
    
    # Resolve domain to IP using dig or getent
    local resolved_ip=""
    if command -v dig >/dev/null 2>&1; then
        resolved_ip=$(dig +short "$domain" | tail -n1)
    else
        resolved_ip=$(getent hosts "$domain" | awk '{print $1}')
    fi
    
    if [ -z "$resolved_ip" ]; then
        colorized_echo red "❌ Could not resolve domain $domain"
        return 1
    fi
    
    if [ "$resolved_ip" != "$server_ip" ]; then
        colorized_echo yellow "⚠️  Domain $domain resolves to $resolved_ip, but your server IP is $server_ip."
        read -p "Do you want to proceed anyway? (y/n): " -r dns_confirm
        if [[ ! "$dns_confirm" =~ ^[Yy]$ ]]; then
            return 1
        fi
    else
        colorized_echo green "✅ Domain resolves to server IP successfully."
    fi
    return 0
}

wait_for_db_initialization() {
    local db_file="/opt/3x-ui/db/x-ui.db"
    colorized_echo blue "Waiting for 3x-ui database to initialize..."
    local timeout=15
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if [ -f "$db_file" ]; then
            if sqlite3 "$db_file" "SELECT name FROM sqlite_master WHERE type='table' AND name='settings';" 2>/dev/null | grep -q "settings"; then
                return 0
            fi
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    colorized_echo red "Timeout waiting for database initialization."
    return 1
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
    local ports=(2053)
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

# Stop and remove existing 3xui_app container and volumes to avoid port conflicts and perform clean install
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^3xui_app$'; then
    colorized_echo blue "Stopping and removing existing 3xui_app container and volumes..."
    docker rm -fv 3xui_app >/dev/null 2>&1 || true
fi



# Clean up previous data directory except certificates
if [ -d "/opt/3x-ui" ]; then
    colorized_echo blue "Removing previous database, Caddy config, and backup assets (preserving certificates)..."
    rm -rf /opt/3x-ui/db /opt/3x-ui/backups /opt/3x-ui/docker-compose.yml /opt/3x-ui/caddy
fi

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
    image: ghcr.io/mhsanaei/3x-ui:v2.9.4
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
    # Retrieve public IP dynamically
    public_ip=$(curl -s -4 --connect-timeout 3 ifconfig.me || curl -s -4 --connect-timeout 3 icanhazip.com || ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "YOUR_SERVER_IP")
    
    # Run panel up
    $COMPOSE up -d
    
    # Check if there is an existing configured webPort in DB
    panel_port="2053"
    if [ -f /opt/3x-ui/db/x-ui.db ]; then
        db_port=$(sqlite3 /opt/3x-ui/db/x-ui.db "SELECT value FROM settings WHERE key='webPort';" 2>/dev/null || true)
        if [ -n "$db_port" ]; then
            panel_port="$db_port"
        fi
    fi
    
    colorized_echo green "✅ 3x-ui Docker started successfully!"
    echo
    
    colorized_echo green "────────────────────────────────────────"
    colorized_echo green "💻 Access Details for 3x-ui Panel:"
    colorized_echo green "────────────────────────────────────────"
    colorized_echo green "🔗 URL:      http://${public_ip}:${panel_port}"
    colorized_echo green "👤 Username: admin"
    colorized_echo green "🔑 Password: admin"
    colorized_echo green "────────────────────────────────────────"
    colorized_echo blue "⚠️  IMPORTANT: Please change the default username, password, and port immediately after your first login!"
    colorized_echo blue "ℹ️  NOTE: To secure your panel with HTTPS using Nginx selfsteal, run selfsteal.sh."
    echo
else
    colorized_echo red "Docker not installed. Please install docker first."
    exit 1
fi
