#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0;0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 1. Environment checks
log_info "Checking Docker containers..."
if ! docker ps --format '{{.Names}}' | grep -q "^nginx-selfsteal$"; then
    log_fail "nginx-selfsteal container is not running!"
fi
if ! docker ps --format '{{.Names}}' | grep -q "^3xui_app$"; then
    log_fail "3xui_app container is not running!"
fi
log_pass "Docker containers are active"

# Get Domain from environment
DOMAIN=""
if [ -f /opt/nginx-selfsteal/.env ]; then
    DOMAIN=$(grep -oP 'SELF_STEAL_DOMAIN=\K.+' /opt/nginx-selfsteal/.env || true)
fi
if [ -z "$DOMAIN" ]; then
    log_warn "Could not read domain from /opt/nginx-selfsteal/.env, checking host file..."
    if [ -f /opt/nginx-selfsteal/conf.d/selfsteal.conf ]; then
        DOMAIN=$(grep -oP 'server_name \K[^;]+' /opt/nginx-selfsteal/conf.d/selfsteal.conf | head -n1 || true)
    fi
fi
if [ -z "$DOMAIN" ]; then
    DOMAIN="localhost"
fi
log_info "Using domain: $DOMAIN"

# 2. Database validation
DB_PATH="/opt/3x-ui/db/x-ui.db"
log_info "Validating SQLite database at $DB_PATH..."
if [ ! -f "$DB_PATH" ]; then
    log_fail "3x-ui database not found at $DB_PATH!"
fi

# Query settings and clients
inbound_exists=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM inbounds WHERE remark='xhttp-inbound';" 2>/dev/null || echo "0")
if [ "$inbound_exists" -eq "0" ]; then
    log_fail "VLESS xhttp-inbound remark not found in SQLite Database!"
fi

client_exists=$(sqlite3 "$DB_PATH" "SELECT count(*) FROM clients WHERE email='user-xhttp';" 2>/dev/null || echo "0")
if [ "$client_exists" -eq "0" ]; then
    log_fail "user-xhttp client email not found in SQLite Database!"
fi

log_pass "SQLite database configuration matches expected schema"

# 3. Unix Socket Verification
SOCKET_PATH="/dev/shm/nginx-xhttp.socket"
log_info "Verifying Unix Socket at $SOCKET_PATH..."
if [ ! -S "$SOCKET_PATH" ]; then
    log_fail "Unix Socket file not found or not a socket at $SOCKET_PATH!"
fi

# Check write permission for nginx user (or general permissions)
socket_perms=$(stat -c "%a" "$SOCKET_PATH" 2>/dev/null || echo "000")
if [ "$socket_perms" != "777" ] && [ "$socket_perms" != "666" ]; then
    log_warn "Socket permissions are $socket_perms, expected 666 or 777"
fi
log_pass "Unix Socket is online"

# 4. Local loopback network edge routing check
log_info "Validating Nginx Edge proxy routing (HTTP/2 curl test)..."
http_code=$(curl -k -s -o /dev/null -w "%{http_code}\n" \
  --http2 -X POST \
  -H "Host: $DOMAIN" \
  -H "X-Session-Id: autotest-session" \
  https://127.0.0.1/api/v1/assets/logo.png \
  --resolve "$DOMAIN:443:127.0.0.1")

# An unauthenticated raw POST to Xray's xHTTP inbound returns 404 Not Found.
# If Xray is stopped, it returns 502. If Nginx route fails to decoy, it returns 200.
# Therefore, 404 is the correct signature showing active routing to the Xray backend.
if [ "$http_code" -ne "404" ]; then
    log_fail "Nginx Edge HTTP/2 route check failed! Response code: $http_code (expected 404)"
fi
log_pass "Nginx Edge HTTP/2 route routing to socket returns HTTP 404 (Success signature)"

# 5. Panel secure reverse proxy check
PANEL_CONF="/opt/nginx-selfsteal/conf.d/panel.conf"
if [ -f "$PANEL_CONF" ]; then
    PANEL_DOMAIN=$(grep -oP 'server_name\s+\K[^;]+' "$PANEL_CONF" | head -n1 || true)
    PANEL_PORT=$(grep -oP 'listen\s+\K[0-9]+' "$PANEL_CONF" | head -n1 || true)
    if [ -n "$PANEL_DOMAIN" ] && [ -n "$PANEL_PORT" ]; then
        log_info "Validating Secure Panel access ($PANEL_DOMAIN:$PANEL_PORT)..."
        panel_code=$(curl -k -s -o /dev/null -w "%{http_code}\n" \
          --resolve "$PANEL_DOMAIN:$PANEL_PORT:127.0.0.1" \
          "https://$PANEL_DOMAIN:$PANEL_PORT/")
        
        # 3x-ui returns 302 (redirect to login), 200, or 404 (HEAD or unauthenticated GET)
        if [ "$panel_code" -ne "404" ] && [ "$panel_code" -ne "302" ] && [ "$panel_code" -ne "200" ] && [ "$panel_code" -ne "301" ]; then
            log_fail "Panel secure proxy checks failed! Response code: $panel_code"
        fi
        log_pass "Secure Panel proxy on $PANEL_DOMAIN:$PANEL_PORT is online and reachable"
    else
        log_warn "Panel proxy domain/port not found in panel.conf, skipping panel check"
    fi
else
    log_info "No panel.conf found, skipping panel check"
fi

# 6. Headless Xray Client Proxy Loopback Test
log_info "Starting Headless Xray Client Run (Real proxy tunnel verification)..."
CLIENT_CONFIG_PATH="/dev/shm/xhttp-client-test.json"
CLIENT_LOG_PATH="/tmp/xray-client.log"

# Extract UUID from DB
UUID=$(sqlite3 "$DB_PATH" "SELECT uuid FROM clients WHERE email='user-xhttp';" 2>/dev/null || true)
if [ -z "$UUID" ]; then
    log_fail "Could not retrieve user UUID for headless client test!"
fi

# Extract Certificate Fingerprint
CERT_PATH="/opt/nginx-selfsteal/ssl/fullchain.crt"
if [ ! -f "$CERT_PATH" ]; then
    log_fail "SSL Certificate not found at $CERT_PATH for fingerprint check!"
fi
FINGERPRINT=$(openssl x509 -noout -fingerprint -sha256 -in "$CERT_PATH" | cut -d= -f2 || true)
if [ -z "$FINGERPRINT" ]; then
    log_fail "Could not calculate certificate fingerprint!"
fi

# Write dynamic client config
cat > "$CLIENT_CONFIG_PATH" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "port": 10808,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "userLevel": 0
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "127.0.0.1",
            "port": 443,
            "users": [
              {
                "id": "$UUID",
                "encryption": "none",
                "level": 0
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "$DOMAIN",
          "pinnedPeerCertSha256": "$FINGERPRINT"
        },
        "xhttpSettings": {
          "enableXmux": true,
          "path": "/api/v1/assets/logo.png",
          "host": "$DOMAIN",
          "mode": "packet-up",
          "noSSEHeader": true,
          "noGRPCHeader": true,
          "xPaddingBytes": "100-800",
          "xPaddingObfsMode": true,
          "scMaxEachPostBytes": "10000-30000",
          "scMinPostsIntervalMs": "20-30",
          "scStreamUpServerSecs": "45-90",
          "uplinkChunkSize": 4000,
          "sessionIDPlacement": "header",
          "sessionIDKey": "X-Session-Id",
          "xmux": {
            "maxConcurrency": "16",
            "hMaxReusableSecs": 300
          }
        }
      }
    }
  ]
}
EOF

# Stop any pre-existing test client instance
docker exec 3xui_app pkill -f "$CLIENT_CONFIG_PATH" >/dev/null 2>&1 || true

# Start background client xray in 3xui_app container
docker exec 3xui_app /app/bin/xray-linux-amd64 run -c "$CLIENT_CONFIG_PATH" > "$CLIENT_LOG_PATH" 2>&1 &
sleep 2

# Verify SOCKS5 port is active on host
if ! ss -tlnp 2>/dev/null | grep -q ":10808 "; then
    cat "$CLIENT_LOG_PATH"
    docker exec 3xui_app pkill -f "$CLIENT_CONFIG_PATH" >/dev/null 2>&1 || true
    rm -f "$CLIENT_CONFIG_PATH"
    log_fail "Headless Xray client failed to bind SOCKS port 10808!"
fi

# Send connection request through the SOCKS tunnel back to local decoy server
proxy_code=$(curl -k -s -o /dev/null -w "%{http_code}\n" \
  -x socks5h://127.0.0.1:10808 \
  "https://$DOMAIN/index.html")

# Cleanup background client
docker exec 3xui_app pkill -f "$CLIENT_CONFIG_PATH" >/dev/null 2>&1 || true
rm -f "$CLIENT_CONFIG_PATH"

if [ "$proxy_code" -ne "200" ]; then
    log_fail "Headless Client Proxy Tunnel test failed! Response: $proxy_code (expected 200)"
fi
log_pass "Headless Client Proxy Tunnel verification succeeded (Roundtrip HTTP 200)"

echo
log_pass "ALL INTEGRATION TESTS PASSED SUCCESSFULLY!"
