#!/usr/bin/env bash
# ╔════════════════════════════════════════════════════════════════╗
# ║  Selfsteal - Web Server for Reality Traffic Masking           ║
# ║  Supports: Nginx                                              ║
# ║                                                                ║
# ║  Project: gig.ovh                                              ║
# ║  Author:  DigneZzZ (https://github.com/DigneZzZ)               ║
# ║  License: MIT                                                  ║
# ╚════════════════════════════════════════════════════════════════╝
# VERSION=2.9.0

# Capture script directory immediately before any cd commands are executed
ORIGINAL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCRIPT_VERSION="2.9.0"

# Handle @ prefix for consistency with other scripts
if [ $# -gt 0 ] && [ "$1" = "@" ]; then
    shift
fi

# Debug mode - set via --debug flag
DEBUG_MODE=false
SCRIPT_URL="https://raw.githubusercontent.com/dignezzz/remnawave-scripts/main/selfsteal.sh"
UPDATE_URL="$SCRIPT_URL"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            DEBUG_MODE=true
            echo "🔧 DEBUG MODE ENABLED"
            shift
        ;;
        --source)
           if [[ -n "$2" && "$2" =~ selfsteal\.sh$ ]]; then
               SCRIPT_URL="$2"
               shift 2
           else
               echo "Error: --source parameter must be a URL to a selfsteal.sh file."
               exit 1
           fi
        ;;
        *)
            break
        ;;
    esac
done

# Only enable strict mode if not debugging
if [ "$DEBUG_MODE" = true ]; then
    set -u  # Only undefined variables
    # Trap errors to show where they occur
    trap 'echo "❌ ERROR at line $LINENO: $BASH_COMMAND (exit code: $?)"' ERR
else
    set -euo pipefail
fi

# ACME Configuration
# Ensure HOME is set correctly (important for sudo)
[ -z "$HOME" ] && HOME=$(getent passwd "$(id -u)" | cut -d: -f6)
[ "$(id -u)" = "0" ] && HOME="/root"
ACME_HOME="$HOME/.acme.sh"
ACME_INSTALL_URL="https://get.acme.sh"
ACME_PORT=""  # Will be auto-detected or set via --acme-port
ACME_FALLBACK_PORTS=(8443 9443 10443 18443 28443)

# Force mode - skip DNS validation and interactive prompts
FORCE_MODE=false
FORCE_DOMAIN=""
FORCE_PORT=""
FORCE_TEMPLATE=""
PANEL_DOMAIN=""
PANEL_PORT="8443"

# Staging mode for Let's Encrypt (uses staging API to bypass rate limits)
USE_STAGING=false

# Manual SSL certificate paths (for wildcard/custom certs)
MANUAL_SSL_CERT=""
MANUAL_SSL_KEY=""

# Web Server Selection (Nginx only)
WEB_SERVER_CONFIG_FILE="nginx.conf"

# Per-install template mutation (anti-fingerprint) — ENABLED by default.
# Makes each install byte-unique (title/brand/colors/noise) and strips known
# provenance leaks (README, beacons, placeholder manifest). Disable: --no-randomize
RANDOMIZE_TEMPLATE=true

# Socket Configuration (Nginx only)
# By default uses Unix socket for better performance
# Use --tcp flag to switch to TCP port
USE_SOCKET=true
SOCKET_PATH="/dev/shm/nginx.sock"

# Docker Configuration for Nginx decoy
CONTAINER_NAME="nginx-selfsteal"
VOLUME_PREFIX="nginx"
NGINX_VERSION="1.29.3-alpine"

# Paths Configuration (initialized by init_web_server_config)
APP_NAME="selfsteal"
APP_DIR=""
HTML_DIR=""
LOG_FILE="/var/log/selfsteal.log"

# Default Settings
DEFAULT_PORT="9443"

# Template Registry (id:folder:emoji:name)
declare -A TEMPLATE_FOLDERS=(
    ["1"]="10gag"
    ["2"]="convertit"
    ["3"]="converter"
    ["4"]="downloader"
    ["5"]="filecloud"
    ["6"]="games-site"
    ["7"]="modmanager"
    ["8"]="speedtest"
    ["9"]="YouTube"
    ["10"]="503-1"
    ["11"]="503-2"
)

declare -A TEMPLATE_NAMES=(
    ["1"]="😂 10gag - Сайт мемов"
    ["2"]="📁 Convertit - Конвертер файлов"
    ["3"]="🎬 Converter - Видеостудия-конвертер"
    ["4"]="⬇️ Downloader - Даунлоадер"
    ["5"]="☁️ FileCloud - Облачное хранилище"
    ["6"]="🎮 Games-site - Ретро игровой портал"
    ["7"]="🛠️ ModManager - Мод-менеджер для игр"
    ["8"]="🚀 SpeedTest - Спидтест"
    ["9"]="📺 YouTube - Видеохостинг с капчей"
    ["10"]="⚠️ 503 Error - Страница ошибки v1"
    ["11"]="⚠️ 503 Error - Страница ошибки v2"
)

source src/common/logging.sh

source src/common/docker.sh

source src/selfsteal/acme.sh


source src/selfsteal/socket.sh


source src/common/firewall.sh



show_help() {
    local server_name
    server_name="Nginx"
    
    echo -e "${WHITE}$server_name for Reality Selfsteal Management Script v$SCRIPT_VERSION${NC}"
    echo
    echo -e "${WHITE}Usage:${NC}"
    echo -e "  ${CYAN}$APP_NAME${NC} [${GRAY}command${NC}] [${GRAY}options${NC}]"
    echo
    echo -e "${WHITE}Options:${NC}"
    printf "   ${CYAN}%-22s${NC} %s\n" "--install-3xui" "Install official 3x-ui in Docker"
    printf "   ${CYAN}%-22s${NC} %s\n" "--socket" "Use Unix socket (default)"
    printf "   ${CYAN}%-22s${NC} %s\n" "--tcp" "Use TCP port instead of socket"
    printf "   ${CYAN}%-22s${NC} %s\n" "--acme-port <port>" "Custom port for ACME TLS-ALPN"
    printf "   ${CYAN}%-22s${NC} %s\n" "--no-randomize" "Don't mutate templates on install"
    printf "   ${CYAN}%-22s${NC} %s\n" "--test, --staging" "Use Let's Encrypt staging environment"
    echo
    echo -e "${WHITE}Force Install Options:${NC}"
    printf "   ${CYAN}%-22s${NC} %s\n" "--force, -f" "Skip DNS validation and prompts"
    printf "   ${CYAN}%-22s${NC} %s\n" "--domain <domain>" "Domain for installation"
    printf "   ${CYAN}%-22s${NC} %s\n" "--port <port>" "HTTPS port (default: 9443)"
    printf "   ${CYAN}%-22s${NC} %s\n" "--template <1-11>" "Template number to install"
    printf "   ${CYAN}%-22s${NC} %s\n" "--panel-domain <domain>" "Domain for the 3x-ui panel"
    printf "   ${CYAN}%-22s${NC} %s\n" "--panel-port <port>" "Port for the 3x-ui panel (default: 8443)"
    echo
    echo -e "${WHITE}Manual SSL Certificate:${NC}"
    printf "   ${CYAN}%-22s${NC} %s\n" "--ssl-cert <path>" "Path to fullchain certificate"
    printf "   ${CYAN}%-22s${NC} %s\n" "--ssl-key <path>" "Path to private key"
    echo
    echo -e "${WHITE}Commands:${NC}"
    printf "   ${CYAN}%-12s${NC} %s\n" "install" "🚀 Install $server_name for Reality masking"
    printf "   ${CYAN}%-12s${NC} %s\n" "up" "▶️  Start $server_name services"
    printf "   ${CYAN}%-12s${NC} %s\n" "down" "⏹️  Stop $server_name services"
    printf "   ${CYAN}%-12s${NC} %s\n" "restart" "🔄 Restart $server_name services"
    printf "   ${CYAN}%-12s${NC} %s\n" "status" "📊 Show service status"
    printf "   ${CYAN}%-12s${NC} %s\n" "logs" "📝 Show service logs"
    printf "   ${CYAN}%-12s${NC} %s\n" "logs-size" "📊 Show log sizes"
    printf "   ${CYAN}%-12s${NC} %s\n" "clean-logs" "🧹 Clean all logs"
    printf "   ${CYAN}%-12s${NC} %s\n" "edit" "✏️  Edit configuration files"
    printf "   ${CYAN}%-12s${NC} %s\n" "uninstall" "🗑️  Remove installation"
    printf "   ${CYAN}%-12s${NC} %s\n" "template" "🎨 Manage website templates"
    printf "   ${CYAN}%-12s${NC} %s\n" "renew-ssl" "🔐 Renew SSL certificate"
    printf "   ${CYAN}%-12s${NC} %s\n" "menu" "📋 Show interactive menu"
    printf "   ${CYAN}%-12s${NC} %s\n" "update" "🔄 Check for script updates"
    echo
    echo -e "${WHITE}One-liner Install Examples:${NC}"
    echo -e "  ${GRAY}# Install Nginx decoy with auto ACME (interactive)${NC}"
    echo -e "  ${CYAN}$APP_NAME install${NC}"
    echo
    echo -e "  ${GRAY}# Force install with domain (skip prompts)${NC}"
    echo -e "  ${CYAN}$APP_NAME --force --domain reality.example.com install${NC}"
    echo
    echo -e "  ${GRAY}# Force install with custom port and template${NC}"
    echo -e "  ${CYAN}$APP_NAME --force --domain reality.example.com --port 8443 --template 5 install${NC}"
    echo
    echo -e "  ${GRAY}# Install with manual wildcard certificate${NC}"
    echo -e "  ${CYAN}$APP_NAME --force --domain reality.example.com \\${NC}"
    echo -e "  ${CYAN}    --ssl-cert /path/to/fullchain.crt --ssl-key /path/to/private.key install${NC}"
    echo
    echo -e "  ${GRAY}# Install official 3x-ui in Docker${NC}"
    echo -e "  ${CYAN}$APP_NAME --install-3xui${NC}"
    echo
    echo -e "${WHITE}Xray Reality Configuration:${NC}"
    echo -e "  ${GRAY}Socket mode (default):  \"target\": \"/dev/shm/nginx.sock\", \"xver\": 1${NC}"
    echo -e "  ${GRAY}TCP mode:               \"target\": \"127.0.0.1:9443\", \"xver\": 1${NC}"
    echo
    echo -e "${WHITE}For more information, visit:${NC}"
    echo -e "  ${BLUE}https://github.com/DigneZzZ/remnawave-scripts${NC}"
    echo
    echo -e "${GRAY}Project: gig.ovh | Author: DigneZzZ${NC}"
}


# Parse command line arguments
COMMAND=""
ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --version|-v)
            echo "Selfsteal Management Script v$SCRIPT_VERSION"
            exit 0
            ;;
        --acme-port)
            if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                ACME_PORT="$2"
                shift 2
            else
                log_error "--acme-port requires a valid port number"
                exit 1
            fi
            ;;
        --acme-port=*)
            ACME_PORT="${1#*=}"
            if ! [[ "$ACME_PORT" =~ ^[0-9]+$ ]]; then
                log_error "--acme-port requires a valid port number"
                exit 1
            fi
            shift
            ;;
        --debug)
            # Already handled at the top of the script
            shift
            ;;
        --tcp)
            # Use TCP port instead of Unix socket
            USE_SOCKET=false
            shift
            ;;
        --socket)
            # Use Unix socket (default)
            USE_SOCKET=true
            shift
            ;;
        --install-3xui)
            INSTALL_3XUI=true
            shift
            ;;
        --no-randomize|--no-mutate)
            # Disable per-install template mutation (serve templates as downloaded)
            RANDOMIZE_TEMPLATE=false
            shift
            ;;
        --test|--staging)
            # Use Let's Encrypt staging environment
            USE_STAGING=true
            shift
            ;;
        --force|-f)
            # Force mode - skip DNS validation and interactive prompts
            FORCE_MODE=true
            shift
            ;;
        --domain)
            if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
                FORCE_DOMAIN="$2"
                shift 2
            else
                log_error "--domain requires a domain name"
                exit 1
            fi
            ;;
        --panel-domain)
            if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
                PANEL_DOMAIN="$2"
                shift 2
            else
                log_error "--panel-domain requires a domain name"
                exit 1
            fi
            ;;
        --panel-port)
            if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                PANEL_PORT="$2"
                shift 2
            else
                log_error "--panel-port requires a valid port number"
                exit 1
            fi
            ;;
        --domain=*)
            FORCE_DOMAIN="${1#*=}"
            if [ -z "$FORCE_DOMAIN" ]; then
                log_error "--domain requires a domain name"
                exit 1
            fi
            shift
            ;;
        --port)
            if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                FORCE_PORT="$2"
                shift 2
            else
                log_error "--port requires a valid port number"
                exit 1
            fi
            ;;
        --port=*)
            FORCE_PORT="${1#*=}"
            if ! [[ "$FORCE_PORT" =~ ^[0-9]+$ ]]; then
                log_error "--port requires a valid port number"
                exit 1
            fi
            shift
            ;;
        --template)
            if [ -n "$2" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
                FORCE_TEMPLATE="$2"
                shift 2
            else
                log_error "--template requires a template number (1-11)"
                exit 1
            fi
            ;;
        --template=*)
            FORCE_TEMPLATE="${1#*=}"
            if ! [[ "$FORCE_TEMPLATE" =~ ^[0-9]+$ ]]; then
                log_error "--template requires a template number (1-11)"
                exit 1
            fi
            shift
            ;;
        --ssl-cert)
            if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
                MANUAL_SSL_CERT="$2"
                shift 2
            else
                log_error "--ssl-cert requires a path to certificate file"
                exit 1
            fi
            ;;
        --ssl-cert=*)
            MANUAL_SSL_CERT="${1#*=}"
            if [ -z "$MANUAL_SSL_CERT" ]; then
                log_error "--ssl-cert requires a path to certificate file"
                exit 1
            fi
            shift
            ;;
        --ssl-key)
            if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
                MANUAL_SSL_KEY="$2"
                shift 2
            else
                log_error "--ssl-key requires a path to key file"
                exit 1
            fi
            ;;
        --ssl-key=*)
            MANUAL_SSL_KEY="${1#*=}"
            if [ -z "$MANUAL_SSL_KEY" ]; then
                log_error "--ssl-key requires a path to key file"
                exit 1
            fi
            shift
            ;;
        -*)
            log_error "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
        *)
            if [ -z "$COMMAND" ]; then
                COMMAND="$1"
            else
                ARGS+=("$1")
            fi
            shift
            ;;
    esac
done

# Initialize web server configuration based on selection
init_web_server_config() {
    WEB_SERVER="nginx"
    CONTAINER_NAME="nginx-selfsteal"
    VOLUME_PREFIX="nginx"
    APP_DIR="/opt/nginx-selfsteal"
    HTML_DIR="/opt/nginx-selfsteal/html"
    WEB_SERVER_CONFIG_FILE="nginx.conf"
    
    # Ensure variables are exported
    export APP_DIR HTML_DIR CONTAINER_NAME VOLUME_PREFIX WEB_SERVER
}

# Detect existing installation
detect_existing_installation() {
    if [ -d "/opt/nginx-selfsteal" ] && [ -f "/opt/nginx-selfsteal/docker-compose.yml" ]; then
        WEB_SERVER="nginx"
    fi
    init_web_server_config
}

# Initialize config
init_web_server_config
# Fetch IP address with fallback
get_server_ip() {
    local ip
    ip=$(curl -s -4 --connect-timeout 5 ifconfig.io 2>/dev/null) || \
    ip=$(curl -s -4 --connect-timeout 5 icanhazip.com 2>/dev/null) || \
    ip=$(curl -s -4 --connect-timeout 5 ipecho.net/plain 2>/dev/null) || \
    ip="127.0.0.1"
    echo "${ip:-127.0.0.1}"
}
NODE_IP=$(get_server_ip)

# Check if running as root
check_running_as_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check system requirements
# Install Docker using official script
install_docker() {
    log_info "Installing Docker..."
    echo -ne "${CYAN}📦 Installing Docker... ${NC}"
    
    # Run installation silently, capture output for error reporting
    local install_log=$(mktemp)
    if curl -fsSL https://get.docker.com 2>/dev/null | sh >"$install_log" 2>&1; then
        rm -f "$install_log"
        
        # Start and enable Docker service
        if command -v systemctl >/dev/null 2>&1; then
            systemctl start docker >/dev/null 2>&1 || true
            systemctl enable docker >/dev/null 2>&1 || true
        fi
        
        log_success "Docker installed successfully"
        echo -e "${GREEN}Done!${NC}"
        return 0
    else
        echo -e "${RED}Failed!${NC}"
        log_error "Failed to install Docker"
        echo -e "${RED}❌ Installation failed. Error log:${NC}"
        tail -20 "$install_log" 2>/dev/null
        rm -f "$install_log"
        return 1
    fi
}

check_system_requirements() {
    echo -e "${WHITE}🔍 Checking System Requirements${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    echo

    local requirements_met=true

    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Docker is not installed${NC}"
        echo -e "${CYAN}   Installing Docker automatically...${NC}"
        echo
        
        if install_docker; then
            local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
            echo -e "${GREEN}✅ Docker installed: $docker_version${NC}"
        else
            echo -e "${RED}❌ Failed to install Docker${NC}"
            echo -e "${GRAY}   Please install Docker manually: curl -fsSL https://get.docker.com | sh${NC}"
            requirements_met=false
        fi
    else
        local docker_version=$(docker --version | cut -d' ' -f3 | tr -d ',')
        echo -e "${GREEN}✅ Docker installed: $docker_version${NC}"
    fi

    # Check Docker Compose (Docker 20.10+ includes compose as plugin)
    if ! docker compose version >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Docker Compose V2 is not available${NC}"
        echo -e "${GRAY}   Note: Docker Compose V2 is included with modern Docker installations${NC}"
        
        # If Docker was just installed, it should have compose
        if command -v docker >/dev/null 2>&1; then
            echo -e "${GRAY}   Checking again after Docker installation...${NC}"
            sleep 1
            if docker compose version >/dev/null 2>&1; then
                local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
                echo -e "${GREEN}✅ Docker Compose V2: $compose_version${NC}"
            else
                echo -e "${RED}❌ Docker Compose V2 is still not available${NC}"
                requirements_met=false
            fi
        else
            requirements_met=false
        fi
    else
        local compose_version=$(docker compose version --short 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✅ Docker Compose V2: $compose_version${NC}"
    fi

    # Check curl
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}❌ curl is not installed${NC}"
        requirements_met=false
    else
        echo -e "${GREEN}✅ curl is available${NC}"
    fi

    # Check available disk space
    local available_space=$(df / | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [ $available_gb -lt 1 ]; then
        echo -e "${RED}❌ Insufficient disk space: ${available_gb}GB available${NC}"
        requirements_met=false
    else
        echo -e "${GREEN}✅ Sufficient disk space: ${available_gb}GB available${NC}"
    fi

    echo

    if [ "$requirements_met" = false ]; then
        echo -e "${RED}❌ System requirements not met!${NC}"
        return 1
    else
        echo -e "${GREEN}🎉 All system requirements satisfied!${NC}"
        return 0
    fi
}


validate_domain_dns() {
    local domain="$1"
    local server_ip="$2"
    
    echo -e "${WHITE}🔍 Validating DNS Configuration${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    echo
    
    # Check if domain format is valid
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        echo -e "${RED}❌ Invalid domain format!${NC}"
        echo -e "${GRAY}   Domain should be in format: subdomain.domain.com${NC}"
        return 1
    fi
    
    echo -e "${WHITE}📝 Domain:${NC} $domain"
    echo -e "${WHITE}🖥️  Server IP:${NC} $server_ip"
    echo
    
    # Check if dig is available
    if ! command -v dig >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Installing dig utility...${NC}"
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update >/dev/null 2>&1
            apt-get install -y dnsutils >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
            yum install -y bind-utils >/dev/null 2>&1
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y bind-utils >/dev/null 2>&1
        else
            echo -e "${RED}❌ Cannot install dig utility automatically${NC}"
            echo -e "${GRAY}   Please install manually: apt install dnsutils${NC}"
            return 1
        fi
        
        if ! command -v dig >/dev/null 2>&1; then
            echo -e "${RED}❌ Failed to install dig utility${NC}"
            return 1
        fi
        echo -e "${GREEN}✅ dig utility installed${NC}"
        echo
    fi
    
    # Perform DNS lookups
    echo -e "${WHITE}🔍 Checking DNS Records:${NC}"
    echo
    
    # Initialize dns_match to false
    local dns_match="false"
    
    # A record check
    echo -e "${GRAY}   Checking A record...${NC}"
    local a_records=$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
    
    if [ -z "$a_records" ]; then
        echo -e "${RED}   ❌ No A record found${NC}"
        local dns_status="failed"
    else
        echo -e "${GREEN}   ✅ A record found:${NC}"
        while IFS= read -r ip; do
            echo -e "${GRAY}      → $ip${NC}"
            if [ "$ip" = "$server_ip" ]; then
                dns_match="true"
            fi
        done <<< "$a_records"
    fi
    
    # AAAA record check (IPv6)
    echo -e "${GRAY}   Checking AAAA record...${NC}"
    local aaaa_records=$(dig +short AAAA "$domain" 2>/dev/null)
    
    if [ -z "$aaaa_records" ]; then
        echo -e "${GRAY}   ℹ️  No AAAA record found (IPv6)${NC}"
    else
        echo -e "${GREEN}   ✅ AAAA record found:${NC}"
        while IFS= read -r ip; do
            echo -e "${GRAY}      → $ip${NC}"
        done <<< "$aaaa_records"
    fi
    
    # CNAME record check
    echo -e "${GRAY}   Checking CNAME record...${NC}"
    local cname_record=$(dig +short CNAME "$domain" 2>/dev/null)
    
    if [ -n "$cname_record" ]; then
        echo -e "${GREEN}   ✅ CNAME record found:${NC}"
        echo -e "${GRAY}      → $cname_record${NC}"
        
        # Check CNAME target
        echo -e "${GRAY}   Resolving CNAME target...${NC}"
        local cname_a_records=$(dig +short A "$cname_record" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
        
        if [ -n "$cname_a_records" ]; then
            echo -e "${GREEN}   ✅ CNAME target resolved:${NC}"
            while IFS= read -r ip; do
                echo -e "${GRAY}      → $ip${NC}"
                if [ "$ip" = "$server_ip" ]; then
                    dns_match="true"
                fi
            done <<< "$cname_a_records"
        fi
    else
        echo -e "${GRAY}   ℹ️  No CNAME record found${NC}"
    fi
    
    echo
    
    # DNS propagation check with multiple servers
    echo -e "${WHITE}🌐 Checking DNS Propagation:${NC}"
    echo
    
    local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222" "9.9.9.9")
    local propagation_count=0
    
    for dns_server in "${dns_servers[@]}"; do
        echo -e "${GRAY}   Checking via $dns_server...${NC}"
        local remote_a=$(dig @"$dns_server" +short A "$domain" 2>/dev/null | head -1)
        
        if [ -n "$remote_a" ] && [[ "$remote_a" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            if [ "$remote_a" = "$server_ip" ]; then
                echo -e "${GREEN}   ✅ $remote_a (matches server)${NC}"
                ((propagation_count++))
            else
                echo -e "${YELLOW}   ⚠️  $remote_a (different IP)${NC}"
            fi
        else
            echo -e "${RED}   ❌ No response${NC}"
        fi
    done
    
    echo
    
    # Port availability check (только важные для Reality)
    echo -e "${WHITE}🔧 Checking Port Availability:${NC}"
    echo
    
    # Check if port 443 is free (should be free for Xray)
    echo -e "${GRAY}   Checking port 443 availability...${NC}"
    if ss -tlnp | grep -q ":443 "; then
        echo -e "${YELLOW}   ⚠️  Port 443 is occupied${NC}"
        echo -e "${GRAY}      This port will be needed for Xray Reality${NC}"
        local port_info=$(ss -tlnp | grep ":443 " | head -1 | awk '{print $1, $4}')
        echo -e "${GRAY}      Current: $port_info${NC}"
    else
        echo -e "${GREEN}   ✅ Port 443 is available for Xray${NC}"
    fi
    
    # Check if port 80 is free (used for HTTP redirects)
    echo -e "${GRAY}   Checking port 80 availability...${NC}"
    if ss -tlnp | grep -q ":80 "; then
        echo -e "${YELLOW}   ⚠️  Port 80 is occupied${NC}"
        echo -e "${GRAY}      This port will be used for HTTP → HTTPS redirects${NC}"
        local port80_occupied=$(ss -tlnp | grep ":80 " | head -1)
        echo -e "${GRAY}      Current: $port80_occupied${NC}"
    else
        echo -e "${GREEN}   ✅ Port 80 is available for HTTP redirects${NC}"
    fi
    
    echo
    
    # Summary and recommendations
    echo -e "${WHITE}📋 DNS Validation Summary:${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 35))${NC}"
    
    if [ "$dns_match" = "true" ]; then
        echo -e "${GREEN}✅ Domain correctly points to this server${NC}"
        echo -e "${GREEN}✅ DNS propagation: $propagation_count/4 servers${NC}"
        
        if [ "$propagation_count" -ge 2 ]; then
            echo -e "${GREEN}✅ DNS propagation looks good${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  DNS propagation is limited${NC}"
            echo -e "${GRAY}   This might cause issues if needed${NC}"
        fi
    else
        echo -e "${RED}❌ Domain does not point to this server${NC}"
        echo -e "${GRAY}   Expected IP: $server_ip${NC}"
        
        if [ -n "$a_records" ]; then
            echo -e "${GRAY}   Current IPs: $(echo "$a_records" | tr '\n' ' ')${NC}"
        fi
    fi
    
    echo
    echo -e "${WHITE}🔧 Setup Requirements for Reality:${NC}"
    echo -e "${GRAY}   • Domain must point to this server ✓${NC}"
    echo -e "${GRAY}   • Port 443 must be free for Xray ✓${NC}"
    echo -e "${GRAY}   • Port 80 will be used for HTTP → HTTPS redirects${NC}"
    if [ "$USE_SOCKET" = true ]; then
        echo -e "${GRAY}   • Nginx will use Unix socket: $SOCKET_PATH${NC}"
    else
        echo -e "${GRAY}   • Nginx will serve content on internal port${NC}"
    fi
    echo -e "${GRAY}   • Configure Xray Reality AFTER installation${NC}"
    
    echo
    
    # Ask user decision
    if [ "$dns_match" = "true" ] && [ "$propagation_count" -ge 2 ]; then
        echo -e "${GREEN}🎉 DNS validation passed! Ready for installation.${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  DNS validation has warnings.${NC}"
        echo
        read -p "Do you want to continue anyway? [y/N]: " -r continue_anyway
        
        if [[ $continue_anyway =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}⚠️  Continuing with installation despite DNS issues...${NC}"
            return 0
        else
            echo -e "${GRAY}Installation cancelled. Please fix DNS configuration first.${NC}"
            return 1
        fi
    fi
}

# Create Nginx configuration files
create_nginx_config() {
    local domain="$1"
    local port="$2"
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: create_nginx_config started, domain=$domain, port=$port"
    
    # Create .env file
    local connection_mode="socket"
    local connection_target="$SOCKET_PATH"
    if [ "$USE_SOCKET" != true ]; then
        connection_mode="tcp"
        connection_target="127.0.0.1:$port"
    fi
    
    # Determine SSL source
    local ssl_source="ACME (Let's Encrypt)"
    if [ -n "$MANUAL_SSL_CERT" ] && [ -n "$MANUAL_SSL_KEY" ]; then
        ssl_source="Manual (wildcard certificate)"
    fi
    
    cat > "$APP_DIR/.env" << EOF
# Nginx for Reality Selfsteal Configuration
# Web Server: Nginx
# Domain Configuration
SELF_STEAL_DOMAIN=$domain
SELF_STEAL_PORT=$port

# Connection Mode: $connection_mode
# Xray target: $connection_target
# xver: 1 (proxy_protocol v1)

# Generated on $(date)
# Server IP: $NODE_IP
# SSL: $ssl_source
EOF

    log_success ".env file created"
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: Creating SSL directory"
    
    # Create SSL directory
    create_dir_safe "$APP_DIR/ssl" || return 1
    
    # Create HTML directory for webroot (needed for ACME)
    create_dir_safe "$HTML_DIR" || return 1
    create_dir_safe "$HTML_DIR/.well-known/acme-challenge" || return 1
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: Directories created, starting SSL certificate process"
    
    # Obtain SSL certificate via ACME or use manual certificates
    echo
    echo -e "${WHITE}🔐 SSL Certificate Configuration${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    echo
    
    # Check if manual SSL certificates are provided
    if [ -n "$MANUAL_SSL_CERT" ] && [ -n "$MANUAL_SSL_KEY" ]; then
        log_info "Using manual SSL certificates..."
        
        # Validate that files exist
        if [ ! -f "$MANUAL_SSL_CERT" ]; then
            log_error "SSL certificate file not found: $MANUAL_SSL_CERT"
            return 1
        fi
        if [ ! -f "$MANUAL_SSL_KEY" ]; then
            log_error "SSL key file not found: $MANUAL_SSL_KEY"
            return 1
        fi
        
        # Copy certificates to SSL directory
        cp "$MANUAL_SSL_CERT" "$APP_DIR/ssl/fullchain.crt" || {
            log_error "Failed to copy SSL certificate"
            return 1
        }
        cp "$MANUAL_SSL_KEY" "$APP_DIR/ssl/private.key" || {
            log_error "Failed to copy SSL key"
            return 1
        }
        
        # Set proper permissions
        chmod 600 "$APP_DIR/ssl/private.key"
        chmod 644 "$APP_DIR/ssl/fullchain.crt"
        
        log_success "Manual SSL certificates installed"
        
        # Validate certificate matches domain (or is wildcard)
        local cert_domain
        cert_domain=$(openssl x509 -in "$APP_DIR/ssl/fullchain.crt" -noout -subject 2>/dev/null | grep -oP 'CN\s*=\s*\K[^,]+' || true)
        
        if [ -n "$cert_domain" ]; then
            echo -e "${GRAY}   Certificate CN: $cert_domain${NC}"
            
            # Check if it's a wildcard that matches
            if [[ "$cert_domain" == "*."* ]]; then
                local wildcard_base="${cert_domain#\*.}"
                if [[ "$domain" == *".$wildcard_base" ]] || [[ "$domain" == "$wildcard_base" ]]; then
                    log_success "Wildcard certificate matches domain"
                else
                    log_warning "Wildcard certificate may not match domain $domain"
                fi
            elif [ "$cert_domain" != "$domain" ]; then
                log_warning "Certificate CN ($cert_domain) doesn't match domain ($domain)"
            else
                log_success "Certificate matches domain"
            fi
        fi
        
        # Show certificate info
        show_ssl_certificate_info "$APP_DIR/ssl"
    else
        # Use ACME for certificate
        # Pre-check: verify ACME port is available
        local acme_port_check="${ACME_PORT:-8443}"
        log_info "Checking ACME port availability..."
        
        if ss -tlnp 2>/dev/null | grep -q ":$acme_port_check " 2>/dev/null; then
            local blocking_process
            blocking_process=$(ss -tlnp 2>/dev/null | grep ":$acme_port_check " | head -1)
            log_warning "Port $acme_port_check is currently in use!"
            echo -e "${GRAY}   $blocking_process${NC}"
            echo
            echo -e "${WHITE}This may cause certificate issuance to fail.${NC}"
            echo -e "${GRAY}The script will try fallback ports: ${ACME_FALLBACK_PORTS[*]}${NC}"
            echo
        else
            log_success "Port $acme_port_check is available"
        fi
        
        log_info "Obtaining SSL certificate from Let's Encrypt..."
        echo
        
        [ "$DEBUG_MODE" = true ] && echo "DEBUG: Calling issue_ssl_certificate"
        
        # Issue certificate with skip_reload=true since container doesn't exist yet
        if issue_ssl_certificate "$domain" "$APP_DIR/ssl" "true"; then
            log_success "SSL certificate obtained successfully"
            
            # Setup auto-renewal
            setup_ssl_auto_renewal
        else
            log_error "Failed to obtain SSL certificate"
            echo
            echo -e "${WHITE}Troubleshooting:${NC}"
            echo
            echo -e "${YELLOW}   1. Check acme.sh installed:${NC}"
            echo -e "${GRAY}      ls ~/.acme.sh/acme.sh${NC}"
            echo -e "${GRAY}      Fix: curl https://get.acme.sh | sh -s email=my@example.com${NC}"
            echo
            echo -e "${YELLOW}   2. Check DNS:${NC}"
            echo -e "${GRAY}      nslookup $domain${NC}"
            echo -e "${GRAY}      → Should return this server's IP${NC}"
            echo
            echo -e "${YELLOW}   3. Check firewall (port 8443):${NC}"
            echo -e "${GRAY}      ss -tlnp | grep 8443${NC}"
            echo -e "${GRAY}      ufw allow 8443/tcp  OR  iptables -A INPUT -p tcp --dport 8443 -j ACCEPT${NC}"
            echo
            echo -e "${YELLOW}   4. Check if port is in use:${NC}"
            echo -e "${GRAY}      ss -tlnp | grep ':8443'${NC}"
            echo
            
            # In force mode, auto-generate self-signed certificate
            if [ "$FORCE_MODE" = true ]; then
                log_warning "Force mode: generating self-signed certificate..."
                openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                    -keyout "$APP_DIR/ssl/private.key" \
                    -out "$APP_DIR/ssl/fullchain.crt" \
                    -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain" 2>/dev/null || {
                    log_error "Failed to generate self-signed certificate"
                    return 1
                }
                log_warning "Using self-signed certificate (browser warnings expected)"
            else
                read -p "Continue with self-signed certificate (not recommended)? [y/N]: " -r use_selfsigned
                if [[ $use_selfsigned =~ ^[Yy]$ ]]; then
                    log_warning "Generating self-signed certificate as fallback..."
                    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                        -keyout "$APP_DIR/ssl/private.key" \
                        -out "$APP_DIR/ssl/fullchain.crt" \
                        -subj "/C=US/ST=State/L=City/O=Organization/CN=$domain" 2>/dev/null || {
                        log_error "Failed to generate self-signed certificate"
                        return 1
                    }
                    log_warning "Using self-signed certificate (browser warnings expected)"
                else
                    return 1
                fi
            fi
        fi
    fi  # End of SSL certificate configuration (manual vs ACME)
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: SSL certificate process completed, creating docker-compose.yml"

    # Create docker-compose.yml with socket or TCP configuration
    if [ "$USE_SOCKET" = true ]; then
        cat > "$APP_DIR/docker-compose.yml" << EOF
services:
  nginx:
    image: nginx:${NGINX_VERSION}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./conf.d:/etc/nginx/conf.d:ro
      - ${HTML_DIR}:/var/www/html:ro
      - ./logs:/var/log/nginx
      - ./ssl:/etc/nginx/ssl:ro
      - /dev/shm:/dev/shm
    env_file:
      - .env
    network_mode: "host"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
        log_success "docker-compose.yml created (Unix socket mode)"
    else
        cat > "$APP_DIR/docker-compose.yml" << EOF
services:
  nginx:
    image: nginx:${NGINX_VERSION}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./conf.d:/etc/nginx/conf.d:ro
      - ${HTML_DIR}:/var/www/html:ro
      - ./logs:/var/log/nginx
      - ./ssl:/etc/nginx/ssl:ro
    env_file:
      - .env
    network_mode: "host"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
        log_success "docker-compose.yml created (TCP port mode)"
    fi
    
    # Create conf.d directory
    create_dir_safe "$APP_DIR/conf.d" || return 1

    # Create main nginx.conf
    cat > "$APP_DIR/nginx.conf" << 'EOF'
user nginx;
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    log_format proxy_protocol '$proxy_protocol_addr - $remote_user [$time_local] "$request" '
                              '$status $body_bytes_sent "$http_referer" '
                              '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;

    # Performance optimizations
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 1000;
    types_hash_max_size 2048;
    server_tokens off;

    # Buffer optimizations
    client_body_buffer_size 16k;
    client_header_buffer_size 1k;
    client_max_body_size 8m;
    large_client_header_buffers 4 8k;

    # Open file cache for static files
    open_file_cache max=10000 inactive=30s;
    open_file_cache_valid 60s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;

    # Gzip compression (aggressive)
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_buffers 16 8k;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript 
               application/xml application/rss+xml application/atom+xml image/svg+xml
               application/x-javascript application/xhtml+xml application/x-font-ttf
               font/opentype image/x-icon;

    include /etc/nginx/conf.d/*.conf;
}
EOF

    log_success "nginx.conf created"

    # Create site configuration based on socket or TCP mode
    if [ "$USE_SOCKET" = true ]; then
        # Unix socket configuration for Xray Reality
        cat > "$APP_DIR/conf.d/selfsteal.conf" << EOF
# HTTP server - redirect and ACME challenge
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $domain;
    
    # ACME challenge for Let's Encrypt certificate renewal
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri =404;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server via Unix socket with proxy_protocol (for Xray Reality)
# Xray forwards traffic to $SOCKET_PATH with xver: 1 (proxy_protocol v1)
server {
    listen unix:$SOCKET_PATH ssl proxy_protocol http2;
    server_name $domain;

    # SSL Configuration with ACME certificates
    ssl_certificate /etc/nginx/ssl/fullchain.crt;
    ssl_certificate_key /etc/nginx/ssl/private.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # OCSP Stapling (faster TLS handshake)
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    # Logging (proxy_protocol format includes real client IP)
    access_log /var/log/nginx/access.log proxy_protocol;
    error_log /var/log/nginx/error.log warn;

    # Root directory
    root /var/www/html;
    index index.html index.htm;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Cache static files
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF
        log_success "Nginx site configuration created (Unix socket: $SOCKET_PATH)"
        
        # Show Xray configuration hint
        echo
        echo -e "${CYAN}📋 Xray Reality Configuration:${NC}"
        echo -e "${GRAY}───────────────────────────────────────${NC}"
        echo -e "${WHITE}   \"target\": \"$SOCKET_PATH\",${NC}"
        echo -e "${WHITE}   \"xver\": 1${NC}"
        echo -e "${GRAY}───────────────────────────────────────${NC}"
        
    else
        # TCP port configuration
        cat > "$APP_DIR/conf.d/selfsteal.conf" << EOF
# HTTP server - redirect and ACME challenge
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $domain;
    
    # ACME challenge for Let's Encrypt certificate renewal
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri =404;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# HTTPS server with proxy_protocol support (for Reality)
# Port 443 is reserved for Xray - all HTTPS traffic comes via proxy_protocol
server {
    listen 127.0.0.1:$port ssl proxy_protocol http2;
    server_name $domain;

    # SSL Configuration with ACME certificates
    ssl_certificate /etc/nginx/ssl/fullchain.crt;
    ssl_certificate_key /etc/nginx/ssl/private.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # OCSP Stapling (faster TLS handshake)
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 8.8.8.8 valid=300s;
    resolver_timeout 5s;

    # Logging (proxy_protocol format includes real client IP)
    access_log /var/log/nginx/access.log proxy_protocol;
    error_log /var/log/nginx/error.log warn;

    # Root directory
    root /var/www/html;
    index index.html index.htm;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Cache static files
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}

# Fallback server for direct port access (returns 204)
server {
    listen 127.0.0.1:$port ssl default_server;
    server_name _;

    ssl_certificate /etc/nginx/ssl/fullchain.crt;
    ssl_certificate_key /etc/nginx/ssl/private.key;

    return 204;
}
EOF
        log_success "Nginx site configuration created (TCP port: $port)"
        
        # Show Xray configuration hint
        echo
        echo -e "${CYAN}📋 Xray Reality Configuration:${NC}"
        echo -e "${GRAY}───────────────────────────────────────${NC}"
        echo -e "${WHITE}   \"target\": \"127.0.0.1:$port\",${NC}"
        echo -e "${WHITE}   \"xver\": 1${NC}"
        echo -e "${GRAY}───────────────────────────────────────${NC}"
    fi
}

# Install function
install_command() {
    check_running_as_root
    
    # Validate force mode requirements
    if [ "$FORCE_MODE" = true ] && [ -z "$FORCE_DOMAIN" ]; then
        log_error "Force mode requires --domain parameter"
        echo -e "${GRAY}   Example: selfsteal --nginx --force --domain reality.example.com install${NC}"
        return 1
    fi
    
    clear
    local server_display_name
    server_display_name="Nginx"
    
    echo -e "${WHITE}🚀 $server_display_name for Reality Selfsteal Installation${NC} - version: $SCRIPT_VERSION"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo -e "${CYAN}📦 Web Server: $server_display_name${NC}"
    echo
    # Check if already installed
    local existing_install=""
    if [ -d "/opt/nginx-selfsteal" ] && [ -f "/opt/nginx-selfsteal/docker-compose.yml" ]; then
        existing_install="nginx"
    fi
    
    if [ -n "$existing_install" ]; then
        echo -e "${YELLOW}⚠️  Nginx is already installed${NC}"
        
        if [ "$FORCE_MODE" = true ]; then
            log_info "Force mode: reinstalling Nginx..."
            local remove_dir="/opt/nginx-selfsteal"
            (cd "$remove_dir" 2>/dev/null && docker compose down 2>/dev/null) || true
            rm -rf "$remove_dir"
            log_success "Existing installation removed"
        else
            echo
            echo -e "${WHITE}Options:${NC}"
            echo -e "   ${WHITE}1)${NC} ${GRAY}Reinstall Nginx${NC}"
            echo -e "   ${WHITE}2)${NC} ${GRAY}Cancel${NC}"
            
            echo
            read -p "Select option [1-2]: " reinstall_choice
            
            case "$reinstall_choice" in
                1)
                    echo
                    local remove_dir="/opt/nginx-selfsteal"
                    
                    # Check for unexpected files before removal
                    local expected_files="docker-compose.yml|\.env|nginx\.conf|html|logs|ssl|conf\.d"
                    local unexpected_files=$(find "$remove_dir" -maxdepth 1 -type f -o -type d | grep -v "^$remove_dir$" | xargs -I{} basename {} | grep -vE "^($expected_files)$" 2>/dev/null)
                    
                    if [ -n "$unexpected_files" ]; then
                        echo -e "${YELLOW}⚠️  Found unexpected files/folders in $remove_dir:${NC}"
                        echo -e "${GRAY}$(echo "$unexpected_files" | head -10 | sed 's/^/   • /')${NC}"
                        local total_unexpected=$(echo "$unexpected_files" | wc -l | tr -d ' ')
                        if [ "$total_unexpected" -gt 10 ]; then
                            echo -e "${GRAY}   ... and $((total_unexpected - 10)) more${NC}"
                        fi
                        echo
                        echo -e "${WHITE}Options:${NC}"
                        echo -e "   ${WHITE}1)${NC} ${GRAY}Create backup and continue${NC}"
                        echo -e "   ${WHITE}2)${NC} ${GRAY}Delete everything without backup${NC}"
                        echo -e "   ${WHITE}3)${NC} ${GRAY}Cancel installation${NC}"
                        echo
                        read -p "Select option [1-3]: " backup_choice
                        
                        case "$backup_choice" in
                            1)
                                local backup_dir="/opt/selfsteal-backup-$(date +%Y%m%d-%H%M%S)"
                                log_info "Creating backup at $backup_dir..."
                                cp -r "$remove_dir" "$backup_dir"
                                log_success "Backup created: $backup_dir"
                                ;;
                            2)
                                log_warning "Proceeding without backup..."
                                ;;
                            *)
                                echo -e "${GRAY}Installation cancelled${NC}"
                                return 0
                                ;;
                        esac
                    fi
                    
                    log_warning "Removing existing Nginx installation..."
                    (cd "$remove_dir" 2>/dev/null && docker compose down 2>/dev/null) || true
                    rm -rf "$remove_dir"
                    log_success "Existing installation removed"
                    echo
                    ;;
                *)
                    echo -e "${GRAY}Installation cancelled${NC}"
                    return 0
                    ;;
            esac
        fi
    fi

    # Check system requirements
    if ! check_system_requirements; then
        return 1
    fi

    # Install 3x-ui Panel in Docker by default
    install_3xui_docker

    # Collect configuration
    echo -e "${WHITE}📝 Configuration Setup${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    echo

    # Domain configuration
    local domain=""
    local skip_dns_check=false
    
    # Force mode - use provided domain
    if [ "$FORCE_MODE" = true ] && [ -n "$FORCE_DOMAIN" ]; then
        domain="$FORCE_DOMAIN"
        skip_dns_check=true
        log_info "Force mode: using domain $domain"
    else
        echo -e "${WHITE}🌐 Domain Configuration${NC}"
        echo -e "${GRAY}This domain should match your Xray Reality configuration (realitySettings.serverNames)${NC}"
        echo
    
        while [ -z "$domain" ]; do
            read -p "Enter your domain (e.g., reality.example.com): " domain
            if [ -z "$domain" ]; then
                log_error "Domain cannot be empty!"
                continue
            fi
            
            echo
            echo -e "${WHITE}🔍 DNS Validation Options:${NC}"
            echo -e "   ${WHITE}1)${NC} ${GRAY}Validate DNS configuration (recommended)${NC}"
            echo -e "   ${WHITE}2)${NC} ${GRAY}Skip DNS validation (for testing/development)${NC}"
            echo
            
            read -p "Select option [1-2]: " dns_choice
            
            case "$dns_choice" in
                1)
                    echo
                    if ! validate_domain_dns "$domain" "$NODE_IP"; then
                        echo
                        read -p "Try a different domain? [Y/n]: " -r try_again
                        if [[ ! $try_again =~ ^[Nn]$ ]]; then
                            domain=""
                            continue
                        else
                            return 1
                        fi
                    fi
                    ;;
                2)
                    log_warning "Skipping DNS validation..."
                    skip_dns_check=true
                    ;;
                *)
                    log_error "Invalid option!"
                    domain=""
                    continue
                    ;;
            esac
        done
    fi  # End of interactive domain input

    # Port configuration (skip for socket mode)
    local port="$DEFAULT_PORT"
    
    # Force mode - use provided port if specified
    if [ "$FORCE_MODE" = true ] && [ -n "$FORCE_PORT" ]; then
        port="$FORCE_PORT"
        log_info "Force mode: using port $port"
    fi
    
    if [ "$USE_SOCKET" = true ]; then
        # Socket mode - no port needed for Xray communication
        if [ "$FORCE_MODE" != true ]; then
            echo
            echo -e "${WHITE}🔌 Connection Mode: Unix Socket${NC}"
            echo -e "${GRAY}Socket path: $SOCKET_PATH${NC}"
            echo -e "${GRAY}No TCP port configuration needed for Xray communication${NC}"
        fi
    elif [ "$FORCE_MODE" != true ]; then
        echo
        echo -e "${WHITE}🔌 Port Configuration${NC}"
        echo -e "${GRAY}This port should match your Xray Reality configuration (realitySettings.dest)${NC}"
        echo
        
        read -p "Enter HTTPS port (default: $DEFAULT_PORT): " input_port
        if [ -n "$input_port" ]; then
            port="$input_port"
        fi
    fi

    # Validate port
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_error "Invalid port number!"
        return 1
    fi

    # Summary
    echo
    echo -e "${WHITE}📋 Installation Summary${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Web Server:" "$server_display_name"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Domain:" "$domain"
    
    if [ "$USE_SOCKET" = true ]; then
        printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Connection:" "Unix Socket"
        printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Socket Path:" "$SOCKET_PATH"
    else
        printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "HTTPS Port:" "$port"
    fi
    
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Installation Path:" "$APP_DIR"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "HTML Path:" "$HTML_DIR"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Server IP:" "$NODE_IP"
    
    if [ "$skip_dns_check" = true ]; then
        printf "   ${WHITE}%-20s${NC} ${YELLOW}%s${NC}\n" "DNS Validation:" "SKIPPED"
    else
        printf "   ${WHITE}%-20s${NC} ${GREEN}%s${NC}\n" "DNS Validation:" "PASSED"
    fi
    
    # Show manual SSL certificate info if provided
    if [ -n "$MANUAL_SSL_CERT" ] && [ -n "$MANUAL_SSL_KEY" ]; then
        printf "   ${WHITE}%-20s${NC} ${CYAN}%s${NC}\n" "SSL Certificate:" "Manual (wildcard)"
    fi
    
    echo

    # In force mode, skip confirmation
    if [ "$FORCE_MODE" != true ]; then
        read -p "Proceed with installation? [Y/n]: " -r confirm
        if [[ $confirm =~ ^[Nn]$ ]]; then
            echo -e "${GRAY}Installation cancelled${NC}"
            return 0
        fi
    else
        log_info "Force mode: proceeding with installation..."
    fi

    # Create directories
    echo
    echo -e "${WHITE}📁 Creating Directory Structure${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    create_dir_safe "$APP_DIR" || return 1
    create_dir_safe "$HTML_DIR" || return 1
    create_dir_safe "$APP_DIR/logs" || return 1
    
    log_success "Directories created"

    # Create configuration files based on selected web server
    echo
    echo -e "${WHITE}⚙️  Creating Configuration Files${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"

    create_nginx_config "$domain" "$port"
    # Install random template instead of default HTML
    echo
    echo -e "${WHITE}🎨 Installing Template${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 35))${NC}"
    
    # List of available templates
    local templates=("1" "2" "3" "4" "5" "6" "7" "8" "9" "10" "11")
    local template_names=("10gag" "Converter" "Convertit" "Downloader" "FileCloud" "Games-site" "ModManager" "SpeedTest" "YouTube" "503 Error v1" "503 Error v2")
    
    local selected_template=""
    local selected_name=""
    local installed_template=""
    
    # Check if template was specified via --template flag
    if [ -n "$FORCE_TEMPLATE" ]; then
        if [[ "$FORCE_TEMPLATE" =~ ^[1-9]$|^1[01]$ ]]; then
            selected_template="$FORCE_TEMPLATE"
            selected_name="${template_names[$((FORCE_TEMPLATE - 1))]}"
            log_info "Using specified template: $selected_name"
        else
            log_warning "Invalid template number ($FORCE_TEMPLATE), using random"
            local random_index=$((RANDOM % ${#templates[@]}))
            selected_template=${templates[$random_index]}
            selected_name=${template_names[$random_index]}
        fi
    else
        # Select random template
        local random_index=$((RANDOM % ${#templates[@]}))
        selected_template=${templates[$random_index]}
        selected_name=${template_names[$random_index]}
        echo -e "${CYAN}🎲 Selected template: ${selected_name}${NC}"
    fi
    echo
    
    if download_template "$selected_template"; then
        log_success "Template installed successfully"
        installed_template="$selected_name template"
    else
        log_warning "Failed to download template, creating fallback"
        create_default_html
        installed_template="Default template (fallback)"
    fi

    # Install management script
    install_management_script

    # Start services
    echo
    echo -e "${WHITE}🚀 Starting $server_display_name Services${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    
    cd "$APP_DIR"
    
    # Validate configuration
    # Check SSL certificates exist
    if [ ! -f "$APP_DIR/ssl/fullchain.crt" ] || [ ! -f "$APP_DIR/ssl/private.key" ]; then
        log_error "SSL certificates not found!"
        echo -e "${YELLOW}   Missing files in: $APP_DIR/ssl/${NC}"
        echo -e "${GRAY}   Expected: fullchain.crt and private.key${NC}"
        echo
        echo -e "${WHITE}   Possible causes and solutions:${NC}"
        echo
        echo -e "${YELLOW}   1. acme.sh not installed${NC}"
        echo -e "${GRAY}      Check: ls ~/.acme.sh/acme.sh${NC}"
        echo -e "${GRAY}      Fix:   curl https://get.acme.sh | sh -s email=my@example.com${NC}"
        echo
        echo -e "${YELLOW}   2. Port blocked by firewall${NC}"
        echo -e "${GRAY}      Check: ss -tlnp | grep 8443${NC}"
        echo -e "${GRAY}      Fix:   ufw allow 8443/tcp  OR  iptables -A INPUT -p tcp --dport 8443 -j ACCEPT${NC}"
        echo
        echo -e "${YELLOW}   3. DNS not configured${NC}"
        echo -e "${GRAY}      Check: nslookup \$(grep SELF_STEAL_DOMAIN $APP_DIR/.env | cut -d= -f2)${NC}"
        echo -e "${GRAY}      Fix:   Add A record pointing to this server's IP${NC}"
        echo
        echo -e "${YELLOW}   4. Another service using port 8443${NC}"
        echo -e "${GRAY}      Check: ss -tlnp | grep ':8443'${NC}"
        echo -e "${GRAY}      Fix:   Stop the conflicting service or use --acme-port <other_port>${NC}"
        echo
        echo -e "${YELLOW}   5. Let's Encrypt rate limit${NC}"
        echo -e "${GRAY}      Check: Wait 1 hour and try again${NC}"
        echo -e "${GRAY}      Info:  https://letsencrypt.org/docs/rate-limits/${NC}"
        echo
        echo -e "${CYAN}   After fixing the issue, run: $APP_NAME renew-ssl${NC}"
        return 1
    fi
    
    log_info "Validating Nginx configuration..."
    local nginx_validate_rc=0
    validate_nginx_config || nginx_validate_rc=$?
    if [ "$nginx_validate_rc" -eq 0 ]; then
        log_success "Nginx configuration is valid"
    elif [ "$nginx_validate_rc" -eq 2 ]; then
        log_warning "Pre-flight validation skipped (could not pull nginx:${NGINX_VERSION}); continuing — 'docker compose up' will report any real image error"
    else
        log_error "Invalid Nginx configuration"
        echo -e "${YELLOW}💡 Check configuration in: $APP_DIR/conf.d/${NC}"
        return 1
    fi

    # Ensure the runtime image is available (Docker Hub rate-limit / RU-block
    # resilient) so `docker compose up` reuses a local image instead of pulling.
    ensure_runtime_image || log_warning "Could not pre-fetch image; 'docker compose up' will attempt its own pull"
    if docker compose up -d; then
        log_success "$server_display_name services started successfully"
    else
        log_error "Failed to start $server_display_name services"
        return 1
    fi

    # Configure 3x-ui/Xray socket access if needed
    if [ "$USE_SOCKET" = true ]; then
        configure_3xui_socket
    fi

    # Installation complete
    echo
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo -e "${WHITE}🎉 Installation Completed Successfully!${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Web Server:" "$server_display_name"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Domain:" "$domain"
    
    # Show connection mode info for Nginx
    if true; then
        if [ "$USE_SOCKET" = true ]; then
            printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Connection Mode:" "Unix Socket"
            printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Socket Path:" "$SOCKET_PATH"
        else
            printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Connection Mode:" "TCP Port"
            printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "HTTPS Port:" "$port"
        fi
    else
        printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "HTTPS Port:" "$port"
    fi
    
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Installation Path:" "$APP_DIR"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "HTML Content:" "$HTML_DIR"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Installed Template:" "$installed_template"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Management Command:" "$APP_NAME"
    echo
    echo -e "${WHITE}📋 Next Steps:${NC}"
    echo -e "${GRAY}   • Configure your Xray Reality with:${NC}"
    echo -e "${GRAY}     - serverNames: [\"$domain\"]${NC}"
    if [ "$USE_SOCKET" = true ]; then
        echo -e "${CYAN}     - target: \"$SOCKET_PATH\"${NC}"
    else
        echo -e "${CYAN}     - target: \"127.0.0.1:$port\"${NC}"
    fi
    echo -e "${CYAN}     - xver: 1${NC}"
    echo -e "${GRAY}   • Change template: $APP_NAME template${NC}"
    echo -e "${GRAY}   • Customize HTML content in: $HTML_DIR${NC}"
    echo -e "${GRAY}   • Check status: $APP_NAME status${NC}"
    echo -e "${GRAY}   • View logs: $APP_NAME logs${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
}

# Validate Nginx configuration
validate_nginx_config() {
    log_info "Validating Nginx configuration..."

    # Make the image available locally (mirror fallback) before validating.
    ensure_image "nginx:${NGINX_VERSION}" || true

    local out
    if out=$(docker run --rm \
        -v "$APP_DIR/nginx.conf:/etc/nginx/nginx.conf:ro" \
        -v "$APP_DIR/conf.d:/etc/nginx/conf.d:ro" \
        -v "$APP_DIR/ssl:/etc/nginx/ssl:ro" \
        nginx:${NGINX_VERSION} \
        nginx -t 2>&1); then
        return 0
    fi

    # A failed `docker run` due to a pull/registry problem is NOT a config error.
    if echo "$out" | grep -qiE 'pull rate limit|unauthenticated pull|toomanyrequests|error from registry|manifest unknown|manifest for .* not found|not found: manifest|no such host|connection refused|i/o timeout|timeout exceeded|cannot connect to the docker daemon|denied'; then
        echo -e "${YELLOW}⚠️  Could not validate: Docker failed to pull image nginx:${NGINX_VERSION}${NC}"
        echo -e "${GRAY}   This is NOT an nginx config error (Docker Hub rate limit / block).${NC}"
        return 2
    fi

    echo "$out" | tail -20
    return 1
}


show_current_template_info() {
    echo -e "${WHITE}📄 Current Template Information${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 35))${NC}"
    echo
    
    if [ ! -d "$HTML_DIR" ] || [ ! "$(ls -A "$HTML_DIR" 2>/dev/null)" ]; then
        echo -e "${GRAY}   No template installed${NC}"
        return
    fi
    
    # Проверить наличие основных файлов
    if [ -f "$HTML_DIR/index.html" ]; then
        local title=$(grep -o '<title>[^<]*</title>' "$HTML_DIR/index.html" 2>/dev/null | sed 's/<title>\|<\/title>//g' | head -1)
        local meta_comment=$(grep -o '<!-- [a-f0-9]\{16\} -->' "$HTML_DIR/index.html" 2>/dev/null | head -1)
        local file_count=$(find "$HTML_DIR" -type f | wc -l)
        local total_size=$(du -sh "$HTML_DIR" 2>/dev/null | cut -f1)
        
        echo -e "${WHITE}   Title:${NC} ${GRAY}${title:-"Unknown"}${NC}"
        echo -e "${WHITE}   Files:${NC} ${GRAY}$file_count${NC}"
        echo -e "${WHITE}   Size:${NC} ${GRAY}$total_size${NC}"
        echo -e "${WHITE}   Path:${NC} ${GRAY}$HTML_DIR${NC}"
        
        if [ -n "$meta_comment" ]; then
            echo -e "${WHITE}   ID:${NC} ${GRAY}$meta_comment${NC}"
        fi
        
        # Показать последнее изменение
        local last_modified=$(stat -c %y "$HTML_DIR/index.html" 2>/dev/null | cut -d' ' -f1)
        if [ -n "$last_modified" ]; then
            echo -e "${WHITE}   Modified:${NC} ${GRAY}$last_modified${NC}"
        fi
    else
        echo -e "${GRAY}   Custom or unknown template${NC}"
        echo -e "${WHITE}   Path:${NC} ${GRAY}$HTML_DIR${NC}"
    fi
    echo
}

# ============================================
# Template Mutation (anti-fingerprint)
# ============================================
# Makes every install byte-unique and slightly different in appearance so the
# served decoy does NOT match the public sni-templates repo by hash/title/
# structure, and strips known provenance leaks. Safe for the minified
# React/Vite SPA shells most templates ship as: it never renames CSS classes
# or reorders DOM (that would break the bundles) — uniqueness comes from
# title/brand/meta/manifest changes, a per-install CSS hue rotation, byte
# noise, cache-busters and a freshly generated favicon.
randomize_template() {
    local dir="$1"
    [ -d "$dir" ] || return 0

    # --- helpers ---------------------------------------------------------
    _rt_hex() {  # _rt_hex N -> N random bytes as lowercase hex
        local n="${1:-4}"
        if command -v openssl >/dev/null 2>&1; then
            openssl rand -hex "$n" 2>/dev/null && return 0
        fi
        head -c "$n" /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n' && return 0
        echo "$RANDOM$RANDOM$RANDOM"
    }
    _rt_pick() { local a=("$@"); echo "${a[RANDOM % ${#a[@]}]}"; }

    log_info "Mutating template for per-install uniqueness (anti-fingerprint)..."

    # --- 1. strip provenance / non-asset leaks --------------------------
    # README.md ships the SmallPoppa source URLs + wget instructions; .map
    # files leak original sources; markdown/license are never served content.
    find "$dir" -type f \( -iname '*.md' -o -iname '*.markdown' \
        -o -iname 'LICENSE' -o -iname 'LICENSE.*' -o -iname '*.map' \
        -o -iname '.gitignore' -o -iname '.gitattributes' \) -delete 2>/dev/null || true

    # --- 2. per-install identity ----------------------------------------
    local adjs=(Swift Bright Lumen Nimbus Vivid Prime Atlas Pulse Nova Quartz Onyx Vertex Cobalt Ember Drift Solace Zephyr Apex Halcyon Meridian Aero Cedar Indigo Mistral)
    local nouns=(Cloud Vault Hub Forge Works Studio Labs Stream Desk Space Grid Port Wave Loop Stack Nest Spark Core Pixel Harbor Bay Field Crest Point)
    local brand; brand="$(_rt_pick "${adjs[@]}") $(_rt_pick "${nouns[@]}")"
    local short="${brand%% *}"
    local tails=("$brand" "$brand — $(_rt_pick Home Dashboard Portal Online Service Cloud Center Access)" "$short · $(_rt_pick Files Media Tools Hub Suite)")
    local new_title; new_title="$(_rt_pick "${tails[@]}")"
    local descs=("Fast, simple and secure." "Your files, anywhere you go." "Built for speed and privacy." "Reliable service, every day." "Modern tools that just work." "Simple. Fast. Yours.")
    local new_desc; new_desc="$(_rt_pick "${descs[@]}")"

    # per-install color rotation: shift UI hue, counter-rotate media so photos
    # stay correct. One injected <style> recolors any template, SPA or static.
    local deg=$(( (RANDOM % 300) + 30 ))   # 30..329 degrees
    local sat=$(( (RANDOM % 30) + 90 ))    # 90..119 percent
    local cssv; cssv="$(_rt_hex 3)"

    # --- 3. mutate HTML files -------------------------------------------
    local f
    while IFS= read -r -d '' f; do
        sed -i "s#<title>[^<]*</title>#<title>${new_title}</title>#" "$f" 2>/dev/null || true
        sed -i "s#MyWebSite#${brand}#g; s#MySite#${short}#g" "$f" 2>/dev/null || true
        sed -i "s#\(name=[\"']description[\"'][^>]*content=\)[\"'][^\"']*[\"']#\1\"${new_desc}\"#Ig" "$f" 2>/dev/null || true
        # drop external Google Fonts (off-box fetch + breaks if blocked in RU); system fonts take over
        sed -i "/fonts\.googleapis\.com/d; /fonts\.gstatic\.com/d" "$f" 2>/dev/null || true
        # neutralize phone-home IP beacon -> same-origin 404 -> existing fallback text
        sed -i "s#https\?://api\.ipify\.org[^\"')]*#/_s/ip#g" "$f" 2>/dev/null || true
        # fix the broken default Vite favicon reference
        sed -i "s#/vite\.svg#/favicon.svg#g" "$f" 2>/dev/null || true
        # cache-buster on local css/js refs (changes hash + request pattern)
        sed -i -E "s#((href|src)=\"[^\"]*\.(css|js))(\?[^\"]*)?\"#\1?v=${cssv}\"#g" "$f" 2>/dev/null || true
        # per-install color shift + byte noise, injected into <head>
        sed -i "s#</head>#<style>html{filter:hue-rotate(${deg}deg) saturate(${sat}%)}img,picture,video,svg,canvas{filter:hue-rotate(-${deg}deg)}</style><!-- $(_rt_hex 6) --></head>#I" "$f" 2>/dev/null || true
    done < <(find "$dir" -type f -iname '*.html' -print0 2>/dev/null)

    # --- 4. mutate css/js: kill phone-home beacons + byte noise ---------
    # The api.ipify.org beacon lives inside the minified JS bundle, not the
    # HTML, so it must be neutralized here. Replaced with a same-origin path:
    # the SPA fallback returns index.html, JSON parse fails, and the template's
    # own .catch() shows its "IP unknown" text — no off-box request is made.
    while IFS= read -r -d '' f; do
        sed -i "s#https\?://api\.ipify\.org[^\"')]*#/_s/ip#g" "$f" 2>/dev/null || true
        printf '\n/* %s */\n' "$(_rt_hex 6)" >> "$f" 2>/dev/null || true
    done < <(find "$dir" -type f \( -iname '*.css' -o -iname '*.js' \) -print0 2>/dev/null)

    # --- 5. clean random favicon (also removes svgjs.dev generator marker) -
    local hue=$(( RANDOM % 360 ))
    cat > "$dir/favicon.svg" <<SVG 2>/dev/null || true
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="14" fill="hsl(${hue},68%,50%)"/><circle cx="32" cy="32" r="13" fill="hsl($(( (hue + 45) % 360 )),72%,90%)"/></svg>
SVG

    # --- 6. fix placeholder manifest brand ------------------------------
    while IFS= read -r -d '' f; do
        sed -i "s#MyWebSite#${brand}#g; s#MySite#${short}#g" "$f" 2>/dev/null || true
    done < <(find "$dir" -type f \( -iname '*.webmanifest' -o -iname 'manifest.json' \) -print0 2>/dev/null)

    log_success "Template mutated — brand: ${brand}, hue +${deg}° (unique per install)"
    return 0
}

download_template() {
    local template_type="$1"
    local template_folder=""
    local template_name=""
    
    # Получаем данные из регистра
    if [[ -n "${TEMPLATE_FOLDERS[$template_type]:-}" ]]; then
        template_folder="${TEMPLATE_FOLDERS[$template_type]}"
        template_name="${TEMPLATE_NAMES[$template_type]}"
    else
        log_error "Unknown template type: $template_type"
        return 1
    fi
    
    echo -e "${WHITE}🎨 Downloading Template: $template_name${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo
    
    # Создаем директорию
    create_dir_safe "$HTML_DIR" || return 1
    rm -rf "${HTML_DIR:?}"/* 2>/dev/null || true
    cd "$HTML_DIR" || return 1
    
    # Пробуем разные методы загрузки
    if download_via_git "$template_folder"; then
        [ "${RANDOMIZE_TEMPLATE:-true}" = true ] && randomize_template "$HTML_DIR"
        setup_file_permissions
        return 0
    fi
    
    if download_via_api "$template_folder"; then
        [ "${RANDOMIZE_TEMPLATE:-true}" = true ] && randomize_template "$HTML_DIR"
        setup_file_permissions
        return 0
    fi
    
    if download_via_curl_fallback "$template_folder"; then
        [ "${RANDOMIZE_TEMPLATE:-true}" = true ] && randomize_template "$HTML_DIR"
        setup_file_permissions
        return 0
    fi
    
    log_error "Failed to download any files"
    log_warning "Creating fallback template..."
    create_fallback_html "$template_name"
    return 1
}

# Download via git sparse-checkout
download_via_git() {
    local template_folder="$1"
    
    if ! command -v git >/dev/null 2>&1; then
        return 1
    fi
    
    echo -e "${WHITE}📦 Using Git for download...${NC}"
    
    local temp_dir="/tmp/selfsteal-template-$$"
    create_dir_safe "$temp_dir" || return 1
    
    if ! git clone --filter=blob:none --sparse "https://github.com/DigneZzZ/remnawave-scripts.git" "$temp_dir" 2>/dev/null; then
        rm -rf "$temp_dir"
        return 1
    fi
    
    cd "$temp_dir" || { rm -rf "$temp_dir"; return 1; }
    git sparse-checkout set "sni-templates/$template_folder" 2>/dev/null
    
    local source_path="$temp_dir/sni-templates/$template_folder"
    if [ -d "$source_path" ] && cp -r "$source_path"/* "$HTML_DIR/" 2>/dev/null; then
        local files_copied
        files_copied=$(find "$HTML_DIR" -type f | wc -l)
        log_success "Template files copied: $files_copied files"
        rm -rf "$temp_dir"
        show_download_summary "$files_copied" "${TEMPLATE_NAMES[$1]:-Template}"
        return 0
    fi
    
    rm -rf "$temp_dir"
    return 1
}

# Download via GitHub API
download_via_api() {
    local template_folder="$1"
    
    if ! command -v wget >/dev/null 2>&1; then
        return 1
    fi
    
    echo -e "${WHITE}📦 Using wget for recursive download...${NC}"
    
    local api_url="https://api.github.com/repos/DigneZzZ/remnawave-scripts/git/trees/main?recursive=1"
    local tree_data
    tree_data=$(curl -s "$api_url" 2>/dev/null)
    
    if [ -z "$tree_data" ] || ! echo "$tree_data" | grep -q '"path"'; then
        return 1
    fi
    
    log_success "Repository structure retrieved"
    echo -e "${WHITE}📥 Downloading files...${NC}"
    
    local template_files
    template_files=$(echo "$tree_data" | grep -o '"path":[^,]*' | sed 's/"path":"//' | sed 's/"//' | grep "^sni-templates/$template_folder/")
    
    local files_downloaded=0
    
    if [ -n "$template_files" ]; then
        while IFS= read -r file_path; do
            [ -z "$file_path" ] && continue
            
            local relative_path="${file_path#sni-templates/$template_folder/}"
            local file_url="https://raw.githubusercontent.com/DigneZzZ/remnawave-scripts/main/$file_path"
            
            local file_dir
            file_dir=$(dirname "$relative_path")
            [ "$file_dir" != "." ] && create_dir_safe "$file_dir"
            
            if wget -q "$file_url" -O "$relative_path" 2>/dev/null; then
                echo -e "${GREEN}   ✅ $relative_path${NC}"
                ((files_downloaded++))
            fi
        done <<< "$template_files"
        
        if [ $files_downloaded -gt 0 ]; then
            show_download_summary "$files_downloaded" "${TEMPLATE_NAMES[$1]:-Template}"
            return 0
        fi
    fi
    
    return 1
}

# Fallback download via curl
download_via_curl_fallback() {
    local template_folder="$1"
    
    echo -e "${WHITE}📦 Using curl fallback method...${NC}"
    
    local base_url="https://raw.githubusercontent.com/DigneZzZ/remnawave-scripts/main/sni-templates/$template_folder"
    local common_files=("index.html" "favicon.ico" "favicon.svg" "site.webmanifest" "apple-touch-icon.png" "favicon-96x96.png")
    local asset_files=("assets/style.css" "assets/script.js" "assets/main.js")
    
    local files_downloaded=0
    
    echo -e "${WHITE}📥 Downloading common files...${NC}"
    
    for file in "${common_files[@]}"; do
        local url="$base_url/$file"
        if curl -fsSL "$url" -o "$file" 2>/dev/null; then
            echo -e "${GREEN}   ✅ $file${NC}"
            ((files_downloaded++))
        fi
    done
    
    create_dir_safe "assets"
    echo -e "${WHITE}📁 Downloading assets...${NC}"
    
    for file in "${asset_files[@]}"; do
        local url="$base_url/$file"
        local filename
        filename=$(basename "$file")
        if curl -fsSL "$url" -o "assets/$filename" 2>/dev/null; then
            echo -e "${GREEN}   ✅ assets/$filename${NC}"
            ((files_downloaded++))
        fi
    done
    
    if [ $files_downloaded -gt 0 ]; then
        show_download_summary "$files_downloaded" "${TEMPLATE_NAMES[$1]:-Template}"
        return 0
    fi
    
    return 1
}

# Функция для установки правильных прав доступа
setup_file_permissions() {
    echo -e "${WHITE}🔒 Setting up file permissions...${NC}"
    
    # Устанавливаем права на файлы
    chmod -R 644 "$HTML_DIR"/* 2>/dev/null || true
    
    # Устанавливаем права на директории
    find "$HTML_DIR" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    # Устанавливаем владельца (если возможно)
    chown -R www-data:www-data "$HTML_DIR" 2>/dev/null || true
    
    echo -e "${GREEN}✅ File permissions configured${NC}"
}

# Функция для показа итогов скачивания
show_download_summary() {
    local files_count="$1"
    local template_name="$2"
    
    echo
    echo -e "${WHITE}📊 Download Summary:${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 25))${NC}"
    printf "   ${WHITE}%-20s${NC} ${GREEN}%d${NC}\n" "Files downloaded:" "$files_count"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Template:" "$template_name"
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Location:" "$HTML_DIR"
    
    # Показать размер
    local total_size=$(du -sh "$HTML_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
    printf "   ${WHITE}%-20s${NC} ${GRAY}%s${NC}\n" "Total size:" "$total_size"
    
    echo
    echo -e "${GREEN}✅ Template downloaded successfully${NC}"
}

# Fallback функция для создания базового HTML если скачивание не удалось
create_fallback_html() {
    local template_name="$1"
    
    cat > "index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$template_name</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
        }
        .container {
            text-align: center;
            max-width: 600px;
            padding: 2rem;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        p {
            font-size: 1.2rem;
            opacity: 0.9;
            margin-bottom: 2rem;
        }
        .status {
            background: rgba(255,255,255,0.1);
            padding: 1rem 2rem;
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 Service Ready</h1>
        <p>$template_name template is now active</p>
        <div class="status">
            <p>✅ System Online</p>
        </div>
    </div>
</body>
</html>
EOF
}

# Create default HTML content for initial installation
create_default_html() {
    echo -e "${WHITE}🌐 Creating Default Website${NC}"
    
    cat > "$HTML_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 500px;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        p {
            color: #666;
            line-height: 1.6;
            margin-bottom: 15px;
        }
        .status {
            display: inline-block;
            background: #4CAF50;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 14px;
            margin-top: 20px;
        }
        .info {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            margin-top: 20px;
            border-left: 4px solid #667eea;
        }
        .info h3 {
            color: #333;
            margin-bottom: 10px;
        }
        .command {
            background: #2d3748;
            color: #e2e8f0;
            padding: 10px;
            border-radius: 4px;
            font-family: monospace;
            margin: 10px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🌐 Nginx</h1>
        <p>Nginx server is running correctly and ready to serve your content.</p>
        <div class="status">✅ Service Active</div>
        <div class="info">
            <h3>🎨 Ready for Templates</h3>
            <p>Use the template manager to install website templates:</p>
            <div class="command"> template</div>
            
        </div>
    </div>
</body>
</html>
EOF

    # Create 404 page
    cat > "$HTML_DIR/404.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 - Page Not Found</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            margin: 0;
            padding: 40px;
            background: #f5f5f5;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            text-align: center;
            max-width: 500px;
        }
        h1 {
            color: #e74c3c;
            font-size: 4rem;
            margin-bottom: 20px;
        }
        h2 {
            color: #333;
            margin-bottom: 15px;
        }
        p {
            color: #666;
            line-height: 1.6;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>404</h1>        <h2>Page Not Found</h2>
        <p>The page you are looking for does not exist.</p>
    </div>
</body>
</html>
EOF
    echo -e "${GREEN}✅ Default HTML content created${NC}"
}

# Function to show template options (dynamically generated from registry)
show_template_options() {
    echo -e "${WHITE}🎨 Website Template Options${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 35))${NC}"
    echo
    echo -e "${WHITE}Select template type:${NC}"
    
    # Dynamically list templates from registry
    for i in $(seq 1 11); do
        local name="${TEMPLATE_NAMES[$i]:-}"
        if [ -n "$name" ]; then
            printf "   ${WHITE}%-3s${NC} ${CYAN}%s${NC}\n" "$i)" "$name"
        fi
    done
    
    echo
    echo -e "   ${WHITE}v)${NC} ${GRAY}📄 View Current Template${NC}"
    echo -e "   ${WHITE}k)${NC} ${GRAY}📝 Keep Current Template${NC}"
    echo -e "   ${WHITE}r)${NC} ${GRAY}🎲 Random Template${NC}"
    echo
    echo -e "   ${GRAY}0)${NC} ${GRAY}⬅️  Cancel${NC}"
    echo
}

# Apply template with optional restart
apply_template_and_restart() {
    local template_id="$1"
    local template_name="${TEMPLATE_NAMES[$template_id]:-Template}"
    
    echo
    if download_template "$template_id"; then
        log_success "$template_name downloaded successfully!"
        echo
        maybe_restart_webserver
    else
        log_error "Failed to download template: $template_name"
    fi
    read -p "Press Enter to continue..."
}

# Check if web server is running and offer restart
maybe_restart_webserver() {
    local running_services
    running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
    
    local server_name
    server_name="Nginx"
    
    if [ "$running_services" -gt 0 ]; then
        read -p "Restart $server_name to apply changes? [Y/n]: " -r restart_server
        if [[ ! $restart_server =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}🔄 Restarting $server_name...${NC}"
            cd "$APP_DIR" && docker compose restart
            log_success "$server_name restarted"
        fi
    fi
}

# Template management command
template_command() {
    check_running_as_root
    
    if ! docker --version >/dev/null 2>&1; then
        log_error "Docker is not available"
        return 1
    fi

    if [ ! -d "$APP_DIR" ]; then
        log_error "Web server is not installed. Run '$APP_NAME install' first."
        return 1
    fi

    local server_name
    server_name="Nginx"

    local running_services
    running_services=$(cd "$APP_DIR" && docker compose ps -q 2>/dev/null | wc -l || echo "0")
    
    if [ "$running_services" -gt 0 ]; then
        log_warning "$server_name is currently running"
        echo -e "${GRAY}   Template changes will be applied immediately${NC}"
        echo
        read -p "Continue with template download? [Y/n]: " -r continue_template
        if [[ $continue_template =~ ^[Nn]$ ]]; then
            return 0
        fi
    fi
    
    while true; do
        clear
        show_template_options
        
        read -p "Select template option [0-11, v, k, r]: " choice
        
        case "$choice" in
            [1-9]|10|11)
                # Check if template exists in registry
                if [[ -n "${TEMPLATE_NAMES[$choice]:-}" ]]; then
                    apply_template_and_restart "$choice"
                else
                    log_error "Invalid template number!"
                    sleep 1
                fi
                ;;
            v|V)
                echo
                show_current_template_info
                read -p "Press Enter to continue..."
                ;;
            k|K)
                echo -e "${GRAY}Current template preserved${NC}"
                read -p "Press Enter to continue..."
                ;;
            r|R)
                # Random template
                local random_id=$((RANDOM % 11 + 1))
                echo -e "${CYAN}🎲 Randomly selected: ${TEMPLATE_NAMES[$random_id]}${NC}"
                apply_template_and_restart "$random_id"
                ;;
            0)
                return 0
                ;;
            *)
                log_error "Invalid option!"
                sleep 1
                ;;
        esac
    done
}




install_management_script() {
    log_info "Installing Management Script"
    
    local script_path=""
    local target_path="/usr/local/bin/$APP_NAME"
    
    # Проверим, не является ли источник тем же файлом, что и целевой
    if [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "@" ]; then
        local source_real_path
        local target_real_path
        source_real_path=$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")
        target_real_path=$(realpath "$target_path" 2>/dev/null || readlink -f "$target_path" 2>/dev/null || echo "$target_path")
        
        if [ "$source_real_path" = "$target_real_path" ]; then
            log_success "Management script already installed: $target_path"
            return 0
        fi
        
        script_path="$0"
    else
        local temp_script="/tmp/selfsteal-install.sh"
        if curl -fsSL "$UPDATE_URL" -o "$temp_script" 2>/dev/null; then
            script_path="$temp_script"
            echo -e "${GRAY}📥 Downloaded script from remote source${NC}"
        else
            log_warning "Could not install management script automatically"
            echo -e "${GRAY}   You can download it manually from: $UPDATE_URL${NC}"
            return 1
        fi
    fi
    
    if [ -f "$script_path" ]; then
        if cp "$script_path" "$target_path" 2>/dev/null; then
            chmod +x "$target_path"
            log_success "Management script installed: $target_path"
        else
            log_warning "Management script installation skipped (already exists)"
        fi
        
        if [ "$script_path" = "/tmp/selfsteal-install.sh" ]; then
            rm -f "$script_path"
        fi
    else
        log_error "Failed to install management script"
        return 1
    fi
}
# Service management functions
up_command() {
    check_running_as_root
    
    if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
        log_error "Web server is not installed. Run '$APP_NAME install' first."
        return 1
    fi
    
    local server_name
    server_name="Nginx"
    
    log_info "Starting $server_name Services"
    cd "$APP_DIR" || return 1

    ensure_runtime_image || log_warning "Could not pre-fetch image; 'docker compose up' will attempt its own pull"
    if docker compose up -d; then
        log_success "$server_name services started successfully"
    else
        log_error "Failed to start $server_name services"
        return 1
    fi
}

down_command() {
    check_running_as_root
    
    if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
        log_warning "Web server is not installed"
        return 0
    fi
    
    local server_name
    server_name="Nginx"
    
    log_info "Stopping $server_name Services"
    cd "$APP_DIR" || return 1
    
    if docker compose down; then
        log_success "$server_name services stopped successfully"
    else
        log_error "Failed to stop $server_name services"
        return 1
    fi
}

restart_command() {
    check_running_as_root
    
    local server_name
    server_name="Nginx"
    read -p "Validate Nginx config before restart? [Y/n]: " -r validate_choice
    if [[ ! $validate_choice =~ ^[Nn]$ ]]; then
        local nginx_validate_rc=0
        validate_nginx_config || nginx_validate_rc=$?
        if [ "$nginx_validate_rc" -eq 1 ]; then
            return 1
        elif [ "$nginx_validate_rc" -eq 2 ]; then
            log_warning "Validation skipped (could not pull nginx:${NGINX_VERSION}); restarting anyway"
        fi
    fi

    log_info "Restarting $server_name Services"
    down_command
    sleep 2
    up_command
}

status_command() {
    if [ ! -d "$APP_DIR" ]; then
        log_error "Nginx not installed"
        return 1
    fi

    local server_name
    server_name="Nginx"

    echo -e "${WHITE}📊 $server_name Service Status${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    echo

    cd "$APP_DIR" || return 1
    
    # Получаем статус контейнера
    local container_status
    local running_count
    local total_count
    local actual_status
    
    container_status=$(docker compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null)
    running_count=$(docker compose ps -q --status running 2>/dev/null | wc -l)
    total_count=$(docker compose ps -q 2>/dev/null | wc -l)
    actual_status=$(docker compose ps --format "{{.State}}" 2>/dev/null | head -1)
    
    case "$actual_status" in
        "running")
            log_success "Status: Running"
            echo -e "${GREEN}✅ All services are running ($running_count/$total_count)${NC}"
            ;;
        "restarting")
            log_warning "Status: Restarting (Error)"
            log_error "Service is failing and restarting ($running_count/$total_count)"
            echo -e "${YELLOW}🔧 Action needed: Check logs for errors${NC}"
            ;;
        "")
            log_error "Status: Not running"
            echo -e "${RED}❌ No services found${NC}"
            ;;
        *)
            log_error "Status: $actual_status"
            echo -e "${RED}❌ Services not running ($running_count/$total_count)${NC}"
            ;;
    esac

    echo
    echo -e "${WHITE}📋 Container Details:${NC}"
    if [ -n "$container_status" ]; then
        echo "$container_status"
    else
        echo -e "${GRAY}No containers found${NC}"
    fi

    # Показать рекомендации при проблемах
    if [ "$actual_status" = "restarting" ]; then
        echo
        echo -e "${YELLOW}🔧 Troubleshooting:${NC}"
        echo -e "${GRAY}   1. Check logs: $APP_NAME logs${NC}"
        echo -e "${GRAY}   2. Validate config: $APP_NAME edit${NC}"
        echo -e "${GRAY}   3. Restart services: $APP_NAME restart${NC}"
    fi
    
    # Show configuration summary
    echo
    echo -e "${WHITE}⚙️  Configuration:${NC}"
    
    local domain=""
    local port=""
    local connection_mode=""
    
    if [ -f "$APP_DIR/.env" ]; then
        domain=$(grep "SELF_STEAL_DOMAIN=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2 || true)
        port=$(grep "SELF_STEAL_PORT=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2 || true)
        connection_mode=$(grep "Connection Mode:" "$APP_DIR/.env" 2>/dev/null | cut -d':' -f2 | tr -d ' ' || true)
    fi
    
    printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Web Server:" "$server_name"
    printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Domain:" "${domain:-N/A}"
    
    # Show connection mode for Nginx
    if true; then
        if [ "$connection_mode" = "socket" ] || [ -z "$connection_mode" ]; then
            printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Connection:" "Unix Socket"
            printf "   ${WHITE}%-15s${NC} ${CYAN}%s${NC}\n" "Xray target:" "$SOCKET_PATH"
        else
            printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Connection:" "TCP Port"
            printf "   ${WHITE}%-15s${NC} ${CYAN}%s${NC}\n" "Xray target:" "127.0.0.1:${port:-9443}"
        fi
    else
        printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "HTTPS Port:" "${port:-9443}"
    fi
    printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "HTML Path:" "$HTML_DIR"
    printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Script Version:" "v$SCRIPT_VERSION"
    
    # Show SSL certificate info for Nginx
    if [ "$WEB_SERVER" = "nginx" ] && [ -f "$APP_DIR/ssl/fullchain.crt" ]; then
        echo
        show_ssl_certificate_info "$APP_DIR/ssl"
    fi
}

logs_command() {
    if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
        log_error "Nginx is not installed"
        return 1
    fi
    
    local server_name
    server_name="Nginx"
    
    echo -e "${WHITE}📝 $server_name Logs${NC}"
    echo -e "${GRAY}Press Ctrl+C to exit${NC}"
    echo
    
    cd "$APP_DIR" || return 1
    docker compose logs -f
}


# Clean logs function
# Renew SSL certificate command
renew_ssl_command() {
    check_running_as_root
    
    if [ ! -d "$APP_DIR" ]; then
        log_error "Nginx is not installed"
        return 1
    fi
    
    echo -e "${WHITE}🔐 SSL Certificate Renewal${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 35))${NC}"
    echo
    
    # Show current certificate info
    if [ -f "$APP_DIR/ssl/fullchain.crt" ]; then
        show_ssl_certificate_info "$APP_DIR/ssl"
        echo
    fi
    
    # Check if acme.sh is installed
    if ! check_acme_installed; then
        log_error "acme.sh is not installed"
        echo -e "${GRAY}   Certificate was likely generated as self-signed${NC}"
        echo
        
        # Offer to get a proper certificate
        read -p "Would you like to obtain a Let's Encrypt certificate now? [Y/n]: " -r get_cert
        if [[ ! $get_cert =~ ^[Nn]$ ]]; then
            # Get domain from config
            local domain
            domain=$(grep "SELF_STEAL_DOMAIN=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2)
            
            if [ -z "$domain" ]; then
                log_error "Could not determine domain from configuration"
                return 1
            fi
            
            # Install acme.sh and get certificate
            if install_acme; then
                # Pre-check: verify ACME port is available
                local acme_port_check="${ACME_PORT:-8443}"
                log_info "Checking ACME port availability..."
                
                if ss -tlnp 2>/dev/null | grep -q ":$acme_port_check " 2>/dev/null; then
                    local blocking_process
                    blocking_process=$(ss -tlnp 2>/dev/null | grep ":$acme_port_check " | head -1)
                    log_warning "Port $acme_port_check is currently in use!"
                    echo -e "${GRAY}   $blocking_process${NC}"
                    echo -e "${GRAY}The script will try fallback ports: ${ACME_FALLBACK_PORTS[*]}${NC}"
                    echo
                else
                    log_success "Port $acme_port_check is available"
                fi
                
                log_info "Stopping Nginx for certificate issuance..."
                cd "$APP_DIR" && docker compose stop
                
                if issue_ssl_certificate "$domain" "$APP_DIR/ssl" "false"; then
                    log_success "Certificate obtained successfully"
                    setup_ssl_auto_renewal
                    
                    log_info "Starting Nginx..."
                    cd "$APP_DIR" && docker compose up -d
                    
                    echo
                    log_success "SSL certificate has been updated!"
                else
                    log_error "Failed to obtain certificate"
                    
                    log_info "Restarting Nginx with existing certificate..."
                    cd "$APP_DIR" && docker compose up -d
                    return 1
                fi
            fi
        fi
        return 0
    fi
    
    # Get domain from config
    local domain
    domain=$(grep "SELF_STEAL_DOMAIN=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2)
    
    if [ -z "$domain" ]; then
        log_error "Could not determine domain from configuration"
        return 1
    fi
    
    # Check certificate status
    local status
    status=$(check_ssl_certificate_status "$APP_DIR/ssl")
    
    echo -e "${WHITE}Options:${NC}"
    echo -e "   ${WHITE}1)${NC} ${GRAY}Check and renew if needed (automatic)${NC}"
    echo -e "   ${WHITE}2)${NC} ${GRAY}Force renewal${NC}"
    echo -e "   ${WHITE}3)${NC} ${GRAY}Cancel${NC}"
    echo
    
    read -p "Select option [1-3]: " -r renew_choice
    
    case "$renew_choice" in
        1)
            echo
            log_info "Checking certificate renewal..."
            
            if renew_ssl_certificates; then
                # Reload Nginx to pick up any renewed certificates
                log_info "Reloading Nginx configuration..."
                docker exec "$CONTAINER_NAME" nginx -s reload 2>/dev/null || true
                
                echo
                log_success "Certificate renewal check completed"
                
                # Show updated status
                echo
                show_ssl_certificate_info "$APP_DIR/ssl"
            fi
            ;;
        2)
            echo
            log_warning "Forcing certificate renewal..."
            
            # Pre-check: verify ACME port is available
            local acme_port_check="${ACME_PORT:-8443}"
            log_info "Checking ACME port availability..."
            
            if ss -tlnp 2>/dev/null | grep -q ":$acme_port_check " 2>/dev/null; then
                local blocking_process
                blocking_process=$(ss -tlnp 2>/dev/null | grep ":$acme_port_check " | head -1)
                log_warning "Port $acme_port_check is currently in use!"
                echo -e "${GRAY}   $blocking_process${NC}"
                echo -e "${GRAY}The script will try fallback ports: ${ACME_FALLBACK_PORTS[*]}${NC}"
                echo
            else
                log_success "Port $acme_port_check is available"
            fi
            
            log_info "Stopping Nginx for certificate renewal..."
            
            cd "$APP_DIR" && docker compose stop
            
            # Get the saved TLS port from acme.sh domain config for iptables redirect
            local acme_tls_port
            acme_tls_port=$(get_acme_tls_port "$domain")
            
            # Setup iptables redirect before renewal
            setup_acme_port_redirect "$acme_tls_port"
            
            local renew_ok=false
            if "$ACME_HOME/acme.sh" --renew -d "$domain" --force 2>&1; then
                # Re-install certificate
                "$ACME_HOME/acme.sh" --install-cert -d "$domain" \
                    --key-file "$APP_DIR/ssl/private.key" \
                    --fullchain-file "$APP_DIR/ssl/fullchain.crt" \
                    --reloadcmd "docker exec $CONTAINER_NAME nginx -s reload 2>/dev/null || true" 2>&1
                
                log_success "Certificate renewed successfully"
                renew_ok=true
            else
                log_warning "Renewal encountered issues (may not be due for renewal yet)"
            fi
            
            # Cleanup iptables redirect
            cleanup_acme_port_redirect "$acme_tls_port"
            
            log_info "Starting Nginx..."
            cd "$APP_DIR" && docker compose up -d
            
            echo
            show_ssl_certificate_info "$APP_DIR/ssl"
            ;;
        *)
            echo -e "${GRAY}Renewal cancelled${NC}"
            ;;
    esac
}

clean_logs_command() {
    check_running_as_root
    
    if [ ! -d "$APP_DIR" ]; then
        log_error "Nginx is not installed"
        return 1
    fi
    
    local server_name
    server_name="Nginx"
    
    echo -e "${WHITE}🧹 Cleaning $server_name Logs${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 25))${NC}"
    echo
    
    # Show current log sizes
    echo -e "${WHITE}📊 Current log sizes:${NC}"
    
    # Docker logs
    local docker_logs_size
    docker_logs_size=$(docker logs "$CONTAINER_NAME" 2>&1 | wc -c 2>/dev/null || echo "0")
    docker_logs_size=$((docker_logs_size / 1024))
    echo -e "${GRAY}   Docker logs: ${WHITE}${docker_logs_size}KB${NC}"
    
    # Server access logs
    local server_logs_path="$APP_DIR/logs"
    if [ -d "$server_logs_path" ]; then
        local server_logs_size
        server_logs_size=$(du -sk "$server_logs_path" 2>/dev/null | cut -f1 || echo "0")
        echo -e "${GRAY}   $server_name logs: ${WHITE}${server_logs_size}KB${NC}"
    fi
    
    echo
    read -p "Clean all logs? [y/N]: " -r clean_choice
    
    if [[ $clean_choice =~ ^[Yy]$ ]]; then
        log_info "Cleaning logs..."
        
        # Clean Docker logs by recreating container
        if docker ps -q -f "name=$CONTAINER_NAME" >/dev/null 2>&1; then
            echo -e "${GRAY}   Stopping $server_name...${NC}"
            cd "$APP_DIR" && docker compose stop
            
            echo -e "${GRAY}   Removing container to clear logs...${NC}"
            docker rm "$CONTAINER_NAME" 2>/dev/null || true
            
            echo -e "${GRAY}   Starting $server_name...${NC}"
            cd "$APP_DIR" && docker compose up -d
        fi
        
        # Clean server internal logs
        if [ -d "$server_logs_path" ]; then
            echo -e "${GRAY}   Cleaning $server_name access logs...${NC}"
            rm -rf "${server_logs_path:?}"/* 2>/dev/null || true
        fi
        
        log_success "Logs cleaned successfully"
    else
        echo -e "${GRAY}Log cleanup cancelled${NC}"
    fi
}

# Show log sizes function
logs_size_command() {
    check_running_as_root
    
    if [ ! -d "$APP_DIR" ]; then
        log_error "Nginx is not installed"
        return 1
    fi
    
    local server_name
    server_name="Nginx"
    
    echo -e "${WHITE}📊 $server_name Log Sizes${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 25))${NC}"
    echo
    
    # Docker logs
    local docker_logs_size
    if docker ps -q -f "name=$CONTAINER_NAME" >/dev/null 2>&1; then
        docker_logs_size=$(docker logs "$CONTAINER_NAME" 2>&1 | wc -c 2>/dev/null || echo "0")
        docker_logs_size=$((docker_logs_size / 1024))
        echo -e "${WHITE}📋 Docker logs:${NC} ${GRAY}${docker_logs_size}KB${NC}"
    else
        echo -e "${WHITE}📋 Docker logs:${NC} ${GRAY}Container not running${NC}"
    fi
    
    # Logs directory
    if [ -d "$APP_DIR/logs" ]; then
        local logs_dir_size
        logs_dir_size=$(du -sk "$APP_DIR/logs" 2>/dev/null | cut -f1 || echo "0")
        echo -e "${WHITE}📁 Logs directory:${NC} ${GRAY}${logs_dir_size}KB${NC}"
        
        # List individual log files
        local log_files
        log_files=$(find "$APP_DIR/logs" -name "*.log*" -type f 2>/dev/null)
        if [ -n "$log_files" ]; then
            echo -e "${GRAY}   Log files:${NC}"
            while IFS= read -r log_file; do
                local file_size
                file_size=$(du -k "$log_file" 2>/dev/null | cut -f1 || echo "0")
                local file_name
                file_name=$(basename "$log_file")
                echo -e "${GRAY}   - $file_name: ${file_size}KB${NC}"
            done <<< "$log_files"
        fi
    fi
    
    echo
    echo -e "${GRAY}💡 Tip: Use '$APP_NAME clean-logs' to clean all logs${NC}"
    echo
}

stop_services() {
    if [ -f "$APP_DIR/docker-compose.yml" ]; then
        cd "$APP_DIR" || return
        docker compose down 2>/dev/null || true
    fi
}

uninstall_command() {
    check_running_as_root
    
    local server_name
    server_name="Nginx"
    
    echo -e "${WHITE}🗑️  $server_name Uninstallation${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    echo
    
    if [ ! -d "$APP_DIR" ]; then
        log_warning "$server_name is not installed"
        return 0
    fi
    
    log_warning "This will completely remove $server_name and all data!"
    echo
    read -p "Are you sure you want to continue? [y/N]: " -r confirm
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${GRAY}Uninstallation cancelled${NC}"
        return 0
    fi
    
    echo
    log_info "Stopping services..."
    stop_services
    
    log_info "Removing files..."
    rm -rf "${APP_DIR:?}"
    
    log_info "Removing management script..."
    rm -f "/usr/local/bin/$APP_NAME"
    
    log_success "$server_name uninstalled successfully"
    echo
    echo -e "${GRAY}Note: HTML content in $HTML_DIR was preserved${NC}"
}

edit_command() {
    check_running_as_root
    
    if [ ! -d "$APP_DIR" ]; then
        log_error "Nginx is not installed"
        return 1
    fi
    
    local server_name
    server_name="Nginx"
    
    echo -e "${WHITE}📝 Edit $server_name Configuration Files${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 30))${NC}"
    echo
    
    echo -e "${WHITE}Select file to edit:${NC}"
    echo -e "   ${WHITE}1)${NC} ${GRAY}.env file (domain and port settings)${NC}"
    echo -e "   ${WHITE}2)${NC} ${GRAY}nginx.conf (main Nginx configuration)${NC}"
    echo -e "   ${WHITE}3)${NC} ${GRAY}selfsteal.conf (site configuration)${NC}"
    echo -e "   ${WHITE}4)${NC} ${GRAY}docker-compose.yml (Docker configuration)${NC}"
    echo -e "   ${WHITE}0)${NC} ${GRAY}Cancel${NC}"
    echo
    
    read -p "Select option [0-4]: " choice
    
    case "$choice" in
        1)
            ${EDITOR:-nano} "$APP_DIR/.env"
            log_warning "Restart $server_name to apply changes: $APP_NAME restart"
            ;;
        2)
            ${EDITOR:-nano} "$APP_DIR/nginx.conf"
            read -p "Validate Nginx config after editing? [Y/n]: " -r validate_choice
            if [[ ! $validate_choice =~ ^[Nn]$ ]]; then
                validate_nginx_config || true
            fi
            log_warning "Restart $server_name to apply changes: $APP_NAME restart"
            ;;
        3)
            ${EDITOR:-nano} "$APP_DIR/conf.d/selfsteal.conf"
            read -p "Validate Nginx config after editing? [Y/n]: " -r validate_choice
            if [[ ! $validate_choice =~ ^[Nn]$ ]]; then
                validate_nginx_config || true
            fi
            log_warning "Restart $server_name to apply changes: $APP_NAME restart"
            ;;
        4)
            ${EDITOR:-nano} "$APP_DIR/docker-compose.yml"
            log_warning "Restart $server_name to apply changes: $APP_NAME restart"
            ;;
        0)
            echo -e "${GRAY}Cancelled${NC}"
            ;;
        *)
            log_error "Invalid option"
            ;;
    esac
}




check_for_updates() {
    echo -e "${WHITE}🔍 Checking for updates...${NC}"
    
    # Check if curl is available
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  curl not available, cannot check for updates${NC}"
        return 1
    fi
    
    # Get latest version from GitHub script
    echo -e "${WHITE}📝 Fetching latest script version...${NC}"
    local remote_script_version
    remote_script_version=$(curl -s "$UPDATE_URL" 2>/dev/null | grep "^SCRIPT_VERSION=" | cut -d'"' -f2)
    
    if [ -z "$remote_script_version" ]; then
        echo -e "${YELLOW}⚠️  Unable to fetch latest version${NC}"
        return 1
    fi
    
    echo -e "${WHITE}📝 Current version: ${GRAY}v$SCRIPT_VERSION${NC}"
    echo -e "${WHITE}📦 Latest version:  ${GRAY}v$remote_script_version${NC}"
    echo
    
    # Compare versions
    if [ "$SCRIPT_VERSION" = "$remote_script_version" ]; then
        echo -e "${GREEN}✅ You are running the latest version${NC}"
        return 0
    else
        echo -e "${YELLOW}🔄 A new version is available!${NC}"
        echo
        
        # Try to get changelog/release info if available
        echo -e "${WHITE}What's new in v$remote_script_version:${NC}"
        echo -e "${GRAY}• Bug fixes and improvements${NC}"
        echo -e "${GRAY}• Enhanced stability${NC}"
        echo -e "${GRAY}• Updated features${NC}"
        
        echo
        read -p "Would you like to update now? [Y/n]: " -r update_choice
        
        if [[ ! $update_choice =~ ^[Nn]$ ]]; then
            update_script
        else
            echo -e "${GRAY}Update skipped${NC}"
        fi
    fi
}

# Update script function
update_script() {
    echo -e "${WHITE}🔄 Updating script...${NC}"
    
    # Create backup
    local backup_file="/tmp/selfsteal-backup-$(date +%Y%m%d_%H%M%S).sh"
    if cp "$0" "$backup_file" 2>/dev/null; then
        echo -e "${GRAY}💾 Backup created: $backup_file${NC}"
    fi
    
    # Download new version
    local temp_file="/tmp/selfsteal-update-$$.sh"
    
    if curl -fsSL "$UPDATE_URL" -o "$temp_file" 2>/dev/null; then
        # Verify downloaded file
        if [ -s "$temp_file" ] && head -1 "$temp_file" | grep -q "#!/"; then
            # Get new version from downloaded script
            local new_version=$(grep "^SCRIPT_VERSION=" "$temp_file" | cut -d'"' -f2)
            
            # Check if running as root for system-wide update
            if [ "$EUID" -eq 0 ]; then
                # Update system installation
                if [ -f "/usr/local/bin/$APP_NAME" ]; then
                    cp "$temp_file" "/usr/local/bin/$APP_NAME"
                    chmod +x "/usr/local/bin/$APP_NAME"
                    echo -e "${GREEN}✅ System script updated successfully${NC}"
                fi
                
                # Update current script if different location
                if [ "$0" != "/usr/local/bin/$APP_NAME" ]; then
                    cp "$temp_file" "$0"
                    chmod +x "$0"
                    echo -e "${GREEN}✅ Current script updated successfully${NC}"
                fi
            else
                # User-level update
                cp "$temp_file" "$0"
                chmod +x "$0"
                echo -e "${GREEN}✅ Script updated successfully${NC}"
                echo -e "${YELLOW}💡 Run with sudo to update system-wide installation${NC}"
            fi
            
            rm -f "$temp_file"
            
            echo
            echo -e "${WHITE}🎉 Update completed!${NC}"
            echo -e "${WHITE}📝 Updated to version: ${GRAY}v$new_version${NC}"
            echo -e "${GRAY}Please restart the script to use the new version${NC}"
            echo
            
            read -p "Restart script now? [Y/n]: " -r restart_choice
            if [[ ! $restart_choice =~ ^[Nn]$ ]]; then
                echo -e "${GRAY}Restarting...${NC}"
                exec "$0" "$@"
            fi
        else
            echo -e "${RED}❌ Downloaded file appears to be corrupted${NC}"
            rm -f "$temp_file"
            return 1
        fi
    else
        echo -e "${RED}❌ Failed to download update${NC}"
        rm -f "$temp_file"
        return 1
    fi
}

# Auto-update check (silent)
check_for_updates_silent() {
    # Simple silent check for updates
    if command -v curl >/dev/null 2>&1; then
        local remote_script_version
        remote_script_version=$(timeout 5 curl -s "$UPDATE_URL" 2>/dev/null | grep "^SCRIPT_VERSION=" | cut -d'"' -f2 2>/dev/null)
        
        if [ -n "$remote_script_version" ] && [ "$SCRIPT_VERSION" != "$remote_script_version" ]; then
            echo -e "${YELLOW}💡 Update available: v$remote_script_version (current: v$SCRIPT_VERSION)${NC}"
            echo -e "${GRAY}   Run '$APP_NAME update' to update${NC}"
            echo
        fi
    fi 2>/dev/null || true  # Suppress any errors completely
}

# Manual update command
update_command() {
    check_running_as_root
    check_for_updates
}

# Guide and instructions command
guide_command() {
    clear
    echo -e "${WHITE}📖 Selfsteal Setup Guide${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 50))${NC}"
    echo

    # 3x-ui Docker installation instruction info
    echo -e "${BLUE}📦 3x-ui Installation:${NC}"
    echo -e "${GRAY}To install the official 3x-ui panel in Docker, run:${NC}"
    echo -e "  ${CYAN}$APP_NAME --install-3xui${NC}"
    echo -e "${GRAY}This installs the panel in a Docker container (3xui_app) listening on port 2053.${NC}"
    echo

    # Get current configuration
    local domain=""
    local port=""
    local connection_mode=""
    local xray_target=""
    
    if [ -f "$APP_DIR/.env" ]; then
        domain=$(grep "SELF_STEAL_DOMAIN=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2 || true)
        port=$(grep "SELF_STEAL_PORT=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2 || true)
        connection_mode=$(grep "Connection Mode:" "$APP_DIR/.env" 2>/dev/null | cut -d':' -f2 | tr -d ' ' || true)
    fi
    
    # Determine xray_target based on web server and connection mode
    local xver_value=0
    if true; then
        xver_value=1
        if [ "$connection_mode" = "socket" ] || [ -z "$connection_mode" ]; then
            xray_target="$SOCKET_PATH"
        else
            xray_target="127.0.0.1:${port:-9443}"
        fi
    else
        xver_value=0
        xray_target="127.0.0.1:${port:-9443}"
    fi

    local server_name
    server_name="Nginx"

    echo -e "${BLUE}🎯 What is Selfsteal?${NC}"
    echo -e "${GRAY}Selfsteal is a $server_name-based front-end for Xray Reality protocol that provides:"
    echo -e "${GRAY}• Traffic masking with legitimate-looking websites"
    echo -e "${GRAY}• SSL/TLS termination and certificate management"
    echo -e "${GRAY}• Multiple website templates for better camouflage"
    echo -e "${GRAY}• Easy integration with Xray Reality servers${NC}"
    echo

    echo -e "${BLUE}🔧 How it works:${NC}"
    if [ "$connection_mode" != "tcp" ]; then
        echo -e "${GRAY}1. Nginx listens on Unix Socket ($SOCKET_PATH)"
    else
        echo -e "${GRAY}1. Nginx runs on internal port (127.0.0.1:${port:-9443})"
    fi
    echo -e "${GRAY}2. Xray Reality forwards traffic via proxy_protocol (xver: 1)"
    echo -e "${GRAY}3. Regular users see a normal website"
    echo -e "${GRAY}4. VPN clients connect through Reality protocol${NC}"
    echo

    if [ -n "$domain" ]; then
        echo -e "${GREEN}✅ Your Current Configuration:${NC}"
        echo -e "${WHITE}   Web Server:${NC} ${CYAN}$server_name${NC}"
        echo -e "${WHITE}   Domain:${NC} ${CYAN}$domain${NC}"
        if [ "$connection_mode" != "tcp" ]; then
            echo -e "${WHITE}   Connection:${NC} ${CYAN}Unix Socket${NC}"
            echo -e "${WHITE}   Xray target:${NC} ${CYAN}$SOCKET_PATH${NC}"
        else
            echo -e "${WHITE}   Connection:${NC} ${CYAN}TCP Port${NC}"
            echo -e "${WHITE}   Xray target:${NC} ${CYAN}127.0.0.1:$port${NC}"
        fi
        echo
    else
        echo -e "${YELLOW}⚠️  Selfsteal not configured yet. Run installation first!${NC}"
        echo
    fi

    echo -e "${BLUE}📋 Xray Reality Configuration Example:${NC}"
    echo -e "${GRAY}Copy this template and customize it for your Xray server:${NC}"
    echo

    # Try to get X25519 private key from 3xui_app container
    local private_key=""
    local key_generated=false
    
    # Try docker exec if 3xui_app is running, with retries for boot
    if docker ps -q -f "name=3xui_app" 2>/dev/null | grep -q .; then
        local xray_output
        local retries=5
        while [ $retries -gt 0 ]; do
            xray_output=$(docker exec 3xui_app /app/bin/xray-linux-amd64 x25519 2>/dev/null) || true
            if [ -n "$xray_output" ]; then
                private_key=$(echo "$xray_output" | grep "PrivateKey:" | awk '{print $2}' || true)
                if [ -n "$private_key" ]; then
                    key_generated=true
                    break
                fi
            fi
            sleep 2
            retries=$((retries - 1))
        done
    fi
    
    # Use placeholder if 3xui_app not available
    if [ "$key_generated" = false ]; then
        private_key="YOUR_PRIVATE_KEY_HERE"
        echo -e "${YELLOW}💡 3x-ui container not running. Generate keys with:${NC}"
        echo -e "${GRAY}   docker exec 3xui_app /app/bin/xray-linux-amd64 x25519${NC}"
        echo
    fi

    echo -e "${WHITE}{
    \"inbounds\": [
        {
            \"tag\": \"VLESS_REALITY_SELFSTEAL\",
            \"port\": 443,
            \"protocol\": \"vless\",
            \"settings\": {
                \"clients\": [],
                \"decryption\": \"none\"
            },
            \"sniffing\": {
                \"enabled\": true,
                \"destOverride\": [\"http\", \"tls\", \"quic\"]
            },
            \"streamSettings\": {
                \"network\": \"raw\",
                \"security\": \"reality\",
                \"realitySettings\": {
                    \"show\": false,
                    \"xver\": $xver_value,
                    \"target\": \"${xray_target}\",
                    \"spiderX\": \"/\",
                    \"shortIds\": [\"\"],
                    \"privateKey\": \"$private_key\",
                    \"serverNames\": [\"${domain:-reality.example.com}\"]
                }
            }
        }
    ]
}${NC}"

    echo
    echo -e "${YELLOW}🔑 Replace the following values:${NC}"
    echo -e "${GRAY}• ${WHITE}clients[]${GRAY} - Add your client configurations with UUIDs${NC}"
    echo -e "${GRAY}• ${WHITE}shortIds${GRAY} - Add your Reality short IDs${NC}"
    if [ "$key_generated" = false ]; then
        echo -e "${GRAY}• ${WHITE}privateKey${GRAY} - Generate with: ${WHITE}docker exec 3xui_app /app/bin/xray-linux-amd64 x25519${NC}"
    fi
    if [ -z "$domain" ]; then
        echo -e "${GRAY}• ${WHITE}serverNames${GRAY} - Your actual domain${NC}"
    fi
    echo
    
    echo -e "${WHITE}   xver: 1${NC} - proxy_protocol version (Nginx requires xver: 1)"
    echo -e "${WHITE}   target: ${xray_target}${NC}"
    echo

    if [ "$key_generated" = false ]; then
        echo -e "${BLUE}🔐 Generate Reality Keys${NC}"
        echo -e "${GRAY}Run: ${WHITE}docker exec 3xui_app /app/bin/xray-linux-amd64 x25519${NC}"
        echo -e "${GRAY}Use ${WHITE}PrivateKey${GRAY} in server config, ${WHITE}PublicKey${GRAY} in client config${NC}"
        echo
    fi

    echo -e "${BLUE}📱 Client Configuration Tips:${NC}"
    echo -e "${GRAY}For client apps (v2rayN, v2rayNG, etc.):${NC}"
    echo -e "${WHITE}• Protocol:${NC} VLESS"
    echo -e "${WHITE}• Security:${NC} Reality"
    echo -e "${WHITE}• Server:${NC} ${domain:-your-domain.com}"
    echo -e "${WHITE}• Port:${NC} 443"
    echo -e "${WHITE}• Flow:${NC} xtls-rprx-vision"
    echo -e "${WHITE}• SNI:${NC} ${domain:-your-domain.com}"
    echo

    echo -e "${BLUE}🔍 Testing Your Setup:${NC}"
    echo -e "${GRAY}1. Check if $server_name is running:${NC}"
    echo -e "${CYAN}   selfsteal status${NC}"
    echo
    echo -e "${GRAY}2. Verify website loads in browser:${NC}"
    echo -e "${CYAN}   https://${domain:-your-domain.com}${NC}"
    echo
    echo -e "${GRAY}3. Test Xray Reality connection:${NC}"
    echo -e "${CYAN}   Use your VPN client with the configuration above${NC}"
    echo

    echo -e "${BLUE}🛠️  Troubleshooting:${NC}"
    echo -e "${GRAY}• ${WHITE}Connection refused:${GRAY} Check if $server_name is running (selfsteal status)${NC}"
    echo -e "${GRAY}• ${WHITE}SSL certificate errors:${GRAY} Verify DNS points to your server${NC}"
    if [ "$WEB_SERVER" = "nginx" ] && [ "$connection_mode" != "tcp" ]; then
        echo -e "${GRAY}• ${WHITE}Reality not working:${GRAY} Check socket exists: ls -la $SOCKET_PATH${NC}"
    else
        echo -e "${GRAY}• ${WHITE}Reality not working:${GRAY} Check port ${port:-9443} is listening${NC}"
    fi
    echo -e "${GRAY}• ${WHITE}Website not loading:${GRAY} Try changing templates (selfsteal template)${NC}"
    echo

    echo -e "${GREEN}💡 Pro Tips:${NC}"
    echo -e "${GRAY}• Use different website templates to avoid detection${NC}"
    echo -e "${GRAY}• Keep your domain's DNS properly configured${NC}"
    echo -e "${GRAY}• Monitor logs regularly for any issues${NC}"
    echo -e "${GRAY}• Update both web server and Xray regularly${NC}"
    echo


    echo -e "${YELLOW}📚 Additional Resources:${NC}"
    echo -e "${GRAY}• Xray Documentation: ${CYAN}https://xtls.github.io/${NC}"
    echo -e "${GRAY}• Reality Protocol Guide: ${CYAN}https://github.com/XTLS/REALITY${NC}"
    echo
}

main_menu() {
    # Auto-check for updates on first run
    check_for_updates_silent
    
    local server_name
    server_name="Nginx"
    
    while true; do
        clear
        echo -e "${WHITE}🔗 $server_name for Reality Selfsteal${NC}"
        echo -e "${GRAY}Management System v$SCRIPT_VERSION${NC}"
        echo -e "${CYAN}Project: gig.ovh | Author: DigneZzZ${NC}"
        echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
        echo


        local menu_status="Not installed"
        local status_color="$GRAY"
        local domain=""
        local port=""
        
        if [ -d "$APP_DIR" ]; then
            if [ -f "$APP_DIR/.env" ]; then
                domain=$(grep "SELF_STEAL_DOMAIN=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2)
                port=$(grep "SELF_STEAL_PORT=" "$APP_DIR/.env" 2>/dev/null | cut -d'=' -f2)
            fi
            
            cd "$APP_DIR"
            local container_state=$(docker compose ps --format "{{.State}}" 2>/dev/null | head -1)
            
            case "$container_state" in
                "running")
                    menu_status="Running"
                    status_color="$GREEN"
                    ;;
                "restarting")
                    menu_status="Error (Restarting)"
                    status_color="$YELLOW"
                    ;;
                "exited"|"stopped")
                    menu_status="Stopped"
                    status_color="$RED"
                    ;;
                "paused")
                    menu_status="Paused"
                    status_color="$YELLOW"
                    ;;
                *)
                    if [ -f "$APP_DIR/docker-compose.yml" ]; then
                        menu_status="Not running"
                        status_color="$RED"
                    else
                        menu_status="Not installed"
                        status_color="$GRAY"
                    fi
                    ;;
            esac
        fi
        
        case "$menu_status" in
            "Running")
                echo -e "${status_color}✅ Status: $menu_status${NC}"
                ;;
            "Error (Restarting)")
                echo -e "${status_color}⚠️  Status: $menu_status${NC}"
                ;;
            "Stopped"|"Not running")
                echo -e "${status_color}❌ Status: $menu_status${NC}"
                ;;
            "Paused")
                echo -e "${status_color}⏸️  Status: $menu_status${NC}"
                ;;
            *)
                echo -e "${status_color}📦 Status: $menu_status${NC}"
                ;;
        esac
        
        printf "   ${WHITE}%-10s${NC} ${GRAY}%s${NC}\n" "Server:" "$server_name"
        if [ -n "$domain" ]; then
            printf "   ${WHITE}%-10s${NC} ${GRAY}%s${NC}\n" "Domain:" "$domain"
        fi
        if [ -n "$port" ]; then
            printf "   ${WHITE}%-10s${NC} ${GRAY}%s${NC}\n" "Port:" "$port"
        fi
        
        if [ "$menu_status" = "Error (Restarting)" ]; then
            echo
            echo -e "${YELLOW}⚠️  Service is experiencing issues!${NC}"
            echo -e "${GRAY}   Recommended: Check logs (option 7) or restart services (option 4)${NC}"
        fi
        
        echo
        echo -e "${WHITE}📋 Available Operations:${NC}"
        echo

        echo -e "${WHITE}🔧 Service Management:${NC}"
        echo -e "   ${WHITE}1)${NC} 🚀 Install $server_name"
        echo -e "   ${WHITE}2)${NC} ▶️  Start services"
        echo -e "   ${WHITE}3)${NC} ⏹️  Stop services"
        echo -e "   ${WHITE}4)${NC} 🔄 Restart services"
        echo -e "   ${WHITE}5)${NC} 📊 Service status"
        echo

        echo -e "${WHITE}🎨 Website Management:${NC}"
        echo -e "   ${WHITE}6)${NC} 🎨 Website templates"
        echo -e "   ${WHITE}7)${NC} 📖 Setup guide & examples"
        echo

        echo -e "${WHITE}📝 Logs & Monitoring:${NC}"
        echo -e "   ${WHITE}8)${NC} 📝 View logs"
        echo -e "   ${WHITE}9)${NC} 📊 Log sizes"
        echo -e "   ${WHITE}10)${NC} 🧹 Clean logs"
        echo -e "   ${WHITE}11)${NC} ✏️  Edit configuration"
        
        # Show SSL renewal option only for Nginx
        if true; then
            echo -e "   ${WHITE}12)${NC} 🔐 Renew SSL certificate"
        fi
        echo

        echo -e "${WHITE}🗑️  Maintenance:${NC}"
        echo -e "   ${WHITE}13)${NC} 🗑️  Uninstall $server_name"
        echo -e "   ${WHITE}14)${NC} 🔄 Check for updates"
        echo
        echo -e "   ${GRAY}0)${NC} ⬅️  Exit"
        echo
        case "$menu_status" in
            "Not installed")
                echo -e "${BLUE}💡 Tip: Start with option 1 to install $server_name${NC}"
                ;;
            "Stopped"|"Not running")
                echo -e "${BLUE}💡 Tip: Use option 2 to start services${NC}"
                ;;
            "Error (Restarting)")
                echo -e "${BLUE}💡 Tip: Check logs (8) to diagnose issues${NC}"
                ;;
            "Running")
                echo -e "${BLUE}💡 Tip: Use option 6 to customize website templates${NC}"
                ;;
        esac

        read -p "$(echo -e "${WHITE}Select option [0-14]:${NC} ")" choice

        case "$choice" in
            1) install_command; read -p "Press Enter to continue..." ;;
            2) up_command; read -p "Press Enter to continue..." ;;
            3) down_command; read -p "Press Enter to continue..." ;;
            4) restart_command; read -p "Press Enter to continue..." ;;
            5) status_command; read -p "Press Enter to continue..." ;;
            6) template_command ;;
            7) guide_command; read -p "Press Enter to continue..." ;;
            8) logs_command; read -p "Press Enter to continue..." ;;
            9) logs_size_command; read -p "Press Enter to continue..." ;;
            10) clean_logs_command; read -p "Press Enter to continue..." ;;
            11) edit_command; read -p "Press Enter to continue..." ;;
            12) 
                renew_ssl_command
                read -p "Press Enter to continue..."
                ;;
            13) uninstall_command; read -p "Press Enter to continue..." ;;
            14) update_command; read -p "Press Enter to continue..." ;;
            0) clear; exit 0 ;;
            *) 
                echo -e "${RED}❌ Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

install_3xui_docker() {
    check_running_as_root
    log_info "Installing official 3x-ui Panel in Docker..."
    
    # Check if Docker is installed
    if ! command -v docker >/dev/null 2>&1; then
        install_docker || { log_error "Docker is required but could not be installed."; exit 1; }
    fi
    
    local XUI_DIR="/opt/3x-ui"
    create_dir_safe "$XUI_DIR"
    
    # Check for a cloned 3x-ui repository in common locations
    local SCRIPT_DIR="$ORIGINAL_SCRIPT_DIR"
    
    local source_repo=""
    for loc in "$SCRIPT_DIR/3x-ui" "$SCRIPT_DIR/../3x-ui" "$(pwd)/3x-ui" "/root/3x-ui"; do
        if [ -d "$loc" ] && [ -f "$loc/Dockerfile" ]; then
            source_repo="$loc"
            break
        fi
    done
    
    if [ -n "$source_repo" ]; then
        log_info "Found cloned 3x-ui repository at: $source_repo"
        log_info "Copying source files to $XUI_DIR/src..."
        rm -rf "$XUI_DIR/src"
        mkdir -p "$XUI_DIR/src"
        cp -r "$source_repo/." "$XUI_DIR/src/"
        
        # Create docker-compose.yml to build from source
        cat > "$XUI_DIR/docker-compose.yml" << 'EOF'
services:
  3xui:
    build:
      context: ./src
      dockerfile: Dockerfile
    container_name: 3xui_app
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ./db/:/etc/x-ui/
      - ./cert/:/root/cert/
      - /dev/shm:/dev/shm
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
    network_mode: "host"
    restart: unless-stopped
EOF
    else
        log_info "Cloned 3x-ui repository not found. Falling back to official ghcr.io image..."
        # Create docker-compose.yml to pull pre-built image
        cat > "$XUI_DIR/docker-compose.yml" << 'EOF'
services:
  3xui:
    image: ghcr.io/mhsanaei/3x-ui:v2.9.4
    container_name: 3xui_app
    cap_add:
      - NET_ADMIN
      - NET_RAW
    volumes:
      - ./db/:/etc/x-ui/
      - ./cert/:/root/cert/
      - /dev/shm:/dev/shm
    environment:
      XRAY_VMESS_AEAD_FORCED: "false"
      XUI_ENABLE_FAIL2BAN: "true"
    network_mode: "host"
    restart: unless-stopped
EOF
    fi
    
    log_info "Starting 3x-ui container..."
    cd "$XUI_DIR"
    if docker compose up -d; then
        log_success "3x-ui Docker container started successfully. Access it at port 2053."
    else
        log_error "Failed to start 3x-ui Docker container"
        exit 1
    fi
    cd - >/dev/null
}

if [ "${INSTALL_3XUI:-false}" = true ]; then
    install_3xui_docker
    exit 0
fi

# Auto-detect existing installation if server wasn't specified via command line
# This allows running commands on existing installation
if [ "$COMMAND" != "install" ]; then
    detect_existing_installation
fi

# Main execution
case "$COMMAND" in
    install) install_command ;;
    up) up_command ;;
    down) down_command ;;
    restart) restart_command ;;
    status) status_command ;;
    logs) logs_command ;;
    logs-size) logs_size_command ;;
    clean-logs) clean_logs_command ;;
    edit) edit_command ;;
    uninstall) uninstall_command ;;
    template) template_command ;;
    renew-ssl) renew_ssl_command ;;
    guide) guide_command ;;
    menu) main_menu ;;
    update) update_command ;;
    check-update) update_command ;;
    help) show_help ;;
    --version|-v) echo "Selfsteal Management Script v$SCRIPT_VERSION" ;;
    --help|-h) show_help ;;
    "") 
        # For menu mode, try to detect existing installation
        detect_existing_installation
        main_menu 
        ;;
    *) 
        echo -e "${RED}❌ Unknown command: $COMMAND${NC}"
        echo "Use '$APP_NAME --help' for usage information."
        exit 1
        ;;
esac

