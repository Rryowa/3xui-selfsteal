#!/usr/bin/env bash
set -euo pipefail

SCRIPT_VERSION="1.1.0"
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

# Parse command-line arguments
SECURE_PANEL=""
PANEL_DOMAIN=""
PANEL_PORT="8443"
FORCE_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --secure)
            SECURE_PANEL=true
            shift
            ;;
        --no-secure)
            SECURE_PANEL=false
            shift
            ;;
        --domain)
            PANEL_DOMAIN="$2"
            shift 2
            ;;
        --port)
            PANEL_PORT="$2"
            shift 2
            ;;
        --force|-f)
            FORCE_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --secure          Enable HTTPS reverse proxy configuration"
            echo "  --no-secure       Disable HTTPS reverse proxy configuration"
            echo "  --domain <domain> Dedicated domain for the panel"
            echo "  --port <port>     HTTPS port for the panel (default: 8443)"
            echo "  --force, -f       Skip DNS validation"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

detect_os() {
    if [ -f /etc/lsb-release ]; then
        OS=$(lsb_release -si)
    elif [ -f /etc/os-release ]; then
        OS=$(OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"') && echo $OS)
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

# Retrieve public IP dynamically
public_ip=$(curl -s -4 --connect-timeout 3 ifconfig.me || curl -s -4 --connect-timeout 3 icanhazip.com || ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || echo "YOUR_SERVER_IP")

# Ask user if they want to secure the panel if not specified via CLI
if [ -z "$SECURE_PANEL" ]; then
    echo
    colorized_echo blue "🛡️  Panel Domain Masking Configuration"
    echo "Securing your 3x-ui panel with HTTPS on a dedicated domain hides X-ui database web listeners from unauthorized public scanners."
    echo
    read -p "Do you want to secure the panel with a dedicated panel domain and HTTPS? (y/n) [y]: " -r secure_confirm
    secure_confirm=${secure_confirm:-y}
    if [[ "$secure_confirm" =~ ^[Nn]$ ]]; then
        SECURE_PANEL=false
    else
        SECURE_PANEL=true
    fi
fi

if [ "$SECURE_PANEL" = true ]; then
    while [ -z "$PANEL_DOMAIN" ]; do
        read -p "Enter dedicated domain for panel (e.g. panel.example.com): " PANEL_DOMAIN
        if [ -z "$PANEL_DOMAIN" ]; then
            colorized_echo red "Domain cannot be empty!"
        fi
    done
    
    if [ "$FORCE_MODE" != true ]; then
        if ! validate_dns "$PANEL_DOMAIN" "$public_ip"; then
            colorized_echo red "DNS verification failed. Please make sure the domain points to $public_ip."
            read -p "Continue anyway? (y/n) [n]: " -r continue_confirm
            continue_confirm=${continue_confirm:-n}
            if [[ ! "$continue_confirm" =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi

    if [ -z "${PANEL_PORT:-}" ]; then
        read -p "Enter panel HTTPS port [8443]: " input_port
        PANEL_PORT=${input_port:-8443}
    fi
fi

# ACME.sh integration logic
ACME_HOME="/root/.acme.sh"

check_acme_installed() {
    if [ -f "$ACME_HOME/acme.sh" ]; then
        return 0
    fi
    return 1
}

install_acme() {
    colorized_echo blue "Installing acme.sh..."
    local random_email="user$(shuf -i 10000-99999 -n 1)@gmail.com"
    local temp_script="/tmp/acme_install_$$.sh"
    
    if curl -sS --connect-timeout 30 --max-time 60 https://get.acme.sh -o "$temp_script" 2>/dev/null; then
        if [ -s "$temp_script" ]; then
            sh "$temp_script" email="$random_email" >/dev/null 2>&1 || true
        fi
    fi
    rm -f "$temp_script"
    
    if [ -f "$HOME/.acme.sh/acme.sh" ]; then
        ACME_HOME="$HOME/.acme.sh"
    elif [ -f "/root/.acme.sh/acme.sh" ]; then
        ACME_HOME="/root/.acme.sh"
    fi
    
    if check_acme_installed; then
        "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        return 0
    fi
    
    if command -v git >/dev/null 2>&1; then
        local temp_dir="/tmp/acme_git_$$"
        git clone --depth 1 https://github.com/acmesh-official/acme.sh.git "$temp_dir" >/dev/null 2>&1 || true
        if [ -d "$temp_dir" ]; then
            (cd "$temp_dir" && ./acme.sh --install -m "$random_email" >/dev/null 2>&1 || true)
            rm -rf "$temp_dir"
        fi
    fi
    
    if [ -f "$HOME/.acme.sh/acme.sh" ]; then
        ACME_HOME="$HOME/.acme.sh"
    elif [ -f "/root/.acme.sh/acme.sh" ]; then
        ACME_HOME="/root/.acme.sh"
    fi
    
    if check_acme_installed; then
        "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        return 0
    fi
    return 1
}

check_ssl_certificate_status() {
    local domain="$1"
    local ssl_dir="$2"
    local cert_file="$ssl_dir/fullchain.crt"
    
    if [ ! -f "$cert_file" ] || [ ! -f "$ssl_dir/private.key" ]; then
        return 1
    fi
    
    # Verify domain matches certificate (checks CN or SANs)
    if ! openssl x509 -noout -text -in "$cert_file" 2>/dev/null | grep -q -E "CN\s*=\s*${domain}|DNS:${domain}" 2>/dev/null; then
        return 1
    fi
    
    # Get expiration date
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2 || true)
    if [ -z "$expiry_date" ]; then
        return 1
    fi
    
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null || echo "0")
    local now_epoch
    now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    
    if [ "$days_left" -gt 7 ]; then
        return 0
    fi
    return 1
}

issue_ssl_certificate() {
    local domain="$1"
    local ssl_dir="$2"
    
    if check_ssl_certificate_status "$domain" "$ssl_dir"; then
        colorized_echo green "✅ Existing valid SSL certificate found for $domain. Reusing it..."
        return 0
    fi
    
    colorized_echo blue "Requesting Let's Encrypt SSL certificate for $domain..."
    
    if ! check_acme_installed; then
        if ! install_acme; then
            colorized_echo red "❌ Failed to install acme.sh. Cannot configure HTTPS."
            return 1
        fi
    fi
    
    if ! command -v socat >/dev/null 2>&1; then
        colorized_echo blue "Installing socat (required for certificate validation)..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq && apt-get install -y -qq socat >/dev/null 2>&1 || true
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q socat >/dev/null 2>&1 || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q socat >/dev/null 2>&1 || true
        fi
    fi
    
    mkdir -p "$ssl_dir"
    
    local acme_port="8443"
    if [ "$acme_port" = "$PANEL_PORT" ]; then
        acme_port="9443"
    fi
    
    # Set up port redirection 443 -> acme_port
    iptables -t nat -I PREROUTING 1 -p tcp --dport 443 -j REDIRECT --to-port "$acme_port" 2>/dev/null || true
    iptables -t nat -I OUTPUT 1 -p tcp --dport 443 -o lo -j REDIRECT --to-port "$acme_port" 2>/dev/null || true
    
    local exit_code=0
    "$ACME_HOME/acme.sh" --issue \
        -d "$domain" \
        --key-file "$ssl_dir/private.key" \
        --fullchain-file "$ssl_dir/fullchain.crt" \
        --alpn \
        --tlsport "$acme_port" \
        --httpport 65535 \
        --server letsencrypt \
        --force \
        --debug 2 >/tmp/acme_panel_issue.log 2>&1 || exit_code=$?
        
    # Cleanup iptables redirects
    iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-port "$acme_port" 2>/dev/null || true
    iptables -t nat -D OUTPUT -p tcp --dport 443 -o lo -j REDIRECT --to-port "$acme_port" 2>/dev/null || true
    
    if [ $exit_code -eq 0 ] && [ -f "$ssl_dir/private.key" ] && [ -f "$ssl_dir/fullchain.crt" ]; then
        colorized_echo green "✅ SSL Certificate issued and installed successfully!"
        chmod 600 "$ssl_dir/private.key" 2>/dev/null || true
        chmod 644 "$ssl_dir/fullchain.crt" 2>/dev/null || true
        
        # Setup auto-renewal cron wrapper
        local wrapper_script="/opt/3x-ui/acme-renew.sh"
        cat > "$wrapper_script" <<WRAPPER_EOF
#!/usr/bin/env bash
# Auto-generated wrapper for acme.sh renewal
iptables -t nat -I PREROUTING 1 -p tcp --dport 443 -j REDIRECT --to-port "$acme_port" 2>/dev/null || true
iptables -t nat -I OUTPUT 1 -p tcp --dport 443 -o lo -j REDIRECT --to-port "$acme_port" 2>/dev/null || true
"$ACME_HOME/acme.sh" --cron --home "$ACME_HOME" > /dev/null 2>&1
renew_exit=\$?
iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-port "$acme_port" 2>/dev/null || true
iptables -t nat -D OUTPUT -p tcp --dport 443 -o lo -j REDIRECT --to-port "$acme_port" 2>/dev/null || true
if [ \$renew_exit -eq 0 ]; then
    docker restart nginx-panel >/dev/null 2>&1 || true
fi
exit \$renew_exit
WRAPPER_EOF
        chmod 700 "$wrapper_script"
        
        if crontab -l 2>/dev/null | grep -q "3x-ui/acme-renew.sh"; then
            crontab -l 2>/dev/null | grep -v "3x-ui/acme-renew.sh" | crontab - 2>/dev/null || true
        fi
        (crontab -l 2>/dev/null; echo "0 0 * * * $wrapper_script") | crontab -
        return 0
    else
        colorized_echo red "❌ Failed to issue certificate. See /tmp/acme_panel_issue.log for more details."
        return 1
    fi
}

check_ports() {
    local ports=(2053)
    if [ "$SECURE_PANEL" = true ]; then
        ports+=("$PANEL_PORT")
    fi
    
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

# Stop and remove existing containers
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^3xui_app$'; then
    colorized_echo blue "Stopping and removing existing 3xui_app container..."
    docker rm -fv 3xui_app >/dev/null 2>&1 || true
fi

if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^nginx-panel$'; then
    colorized_echo blue "Stopping and removing existing nginx-panel container..."
    docker rm -fv nginx-panel >/dev/null 2>&1 || true
fi

# Clean up previous configuration except certificates
if [ -d "/opt/3x-ui" ]; then
    colorized_echo blue "Cleaning previous 3x-ui files (preserving certificates)..."
    rm -rf /opt/3x-ui/db /opt/3x-ui/backups /opt/3x-ui/docker-compose.yml /opt/3x-ui/nginx.conf /opt/3x-ui/conf.d
fi

check_ports

colorized_echo blue "Installing 3x-ui Docker Edition v$SCRIPT_VERSION..."
mkdir -p /opt/3x-ui/db /opt/3x-ui/cert /opt/3x-ui/backups

# Preserve existing SQLite database if migrating
if [ -f /etc/x-ui/x-ui.db ] && [ ! -f /opt/3x-ui/db/x-ui.db ]; then
    colorized_echo blue "Found existing standalone x-ui database. Copying to Docker volume..."
    cp /etc/x-ui/x-ui.db /opt/3x-ui/db/x-ui.db
fi

# Issue SSL certificate if securing panel
if [ "$SECURE_PANEL" = true ]; then
    if ! issue_ssl_certificate "$PANEL_DOMAIN" "/opt/3x-ui/ssl"; then
        colorized_echo red "Could not secure the panel with SSL. Aborting."
        exit 1
    fi

    # Create Nginx configurations
    cat << 'EOF' > /opt/3x-ui/nginx.conf
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    sendfile on;
    keepalive_timeout 65;
    include /etc/nginx/conf.d/*.conf;
}
EOF

    mkdir -p /opt/3x-ui/conf.d
    # Note: Backend port is resolved dynamically below
fi

# Write initial docker-compose configuration
if [ "$SECURE_PANEL" = true ]; then
    cat << 'DOCKER' > /opt/3x-ui/docker-compose.yml
services:
  3xui:
    image: ghcr.io/mhsanaei/3x-ui:v3.3.1
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

  nginx:
    image: nginx:1.29.3-alpine
    container_name: nginx-panel
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./conf.d:/etc/nginx/conf.d:ro
      - ./ssl:/etc/nginx/ssl:ro
      - ./logs:/var/log/nginx
DOCKER
else
    cat << 'DOCKER' > /opt/3x-ui/docker-compose.yml
services:
  3xui:
    image: ghcr.io/mhsanaei/3x-ui:v3.3.1
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
fi

cd /opt/3x-ui
if command -v docker >/dev/null 2>&1; then
    # Start 3x-ui first to initialize DB
    colorized_echo blue "Starting 3x-ui container..."
    $COMPOSE up -d 3xui
    
    # Wait for DB to initialize
    ensure_sqlite3_installed
    wait_for_db_initialization
    
    panel_port="2053"
    if [ -f /opt/3x-ui/db/x-ui.db ]; then
        db_port=$(sqlite3 /opt/3x-ui/db/x-ui.db "SELECT value FROM settings WHERE key='webPort';" 2>/dev/null || true)
        if [ -n "$db_port" ]; then
            panel_port="$db_port"
        fi
    fi

    if [ "$SECURE_PANEL" = true ]; then
        # Configure local webListen in DB
        colorized_echo blue "Configuring 3x-ui database listener to secure loopback (127.0.0.1)..."
        sqlite3 /opt/3x-ui/db/x-ui.db "DELETE FROM settings WHERE key='webListen'; INSERT INTO settings (key, value) VALUES ('webListen', '127.0.0.1');"
        
        # Write the panel Nginx configuration
        mkdir -p /opt/3x-ui/logs
        cat << EOF > /opt/3x-ui/conf.d/panel.conf
# Panel reverse proxy on non-standard HTTPS port
server {
    listen 0.0.0.0:${PANEL_PORT} ssl http2;
    listen [::]:${PANEL_PORT} ssl http2;
    server_name ${PANEL_DOMAIN};

    ssl_certificate     /etc/nginx/ssl/fullchain.crt;
    ssl_certificate_key /etc/nginx/ssl/private.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # Reverse proxy to 3x-ui panel
    location / {
        proxy_pass http://127.0.0.1:${panel_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket support (required for 3x-ui live terminal)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400s;
    }
}
EOF
        
        # Restart 3x-ui and start Nginx
        colorized_echo blue "Applying changes and starting panel HTTPS proxy..."
        $COMPOSE restart 3xui
        $COMPOSE up -d nginx
        
        colorized_echo green "✅ 3x-ui Docker and Panel proxy started successfully!"
        echo
        colorized_echo green "────────────────────────────────────────"
        colorized_echo green "💻 Access Details for secured 3x-ui Panel:"
        colorized_echo green "────────────────────────────────────────"
        colorized_echo green "🔗 URL:      https://${PANEL_DOMAIN}:${PANEL_PORT}"
        colorized_echo green "👤 Username: admin"
        colorized_echo green "🔑 Password: admin"
        colorized_echo green "────────────────────────────────────────"
        colorized_echo blue "⚠️  IMPORTANT: Please change the default username, password, and port immediately after your first login!"
        colorized_echo blue "ℹ️  NOTE: To secure your Reality proxy, run selfsteal.sh."
        echo
    else
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
        colorized_echo blue "ℹ️  NOTE: To secure your panel with HTTPS using a dedicated domain, re-run 3x-ui-docker.sh and select secure option."
        echo
    fi
else
    colorized_echo red "Docker not installed. Please install docker first."
    exit 1
fi
