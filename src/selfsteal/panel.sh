# Helper to configure the panel proxy
configure_panel_proxy() {
    local domain="$1"
    local panel_port="$2"
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: configure_panel_proxy started, domain=$domain, panel_port=$panel_port"
    
    local db_file="/opt/3x-ui/db/x-ui.db"
    if [ -f "$db_file" ]; then
        if command -v sqlite3 >/dev/null 2>&1; then
            # Bind 3x-ui to 127.0.0.1
            log_info "Configuring 3x-ui database to listen only on loopback interface (127.0.0.1)..."
            sqlite3 "$db_file" "DELETE FROM settings WHERE key='webListen'; INSERT INTO settings (key, value) VALUES ('webListen', '127.0.0.1');"
            
            # Restart 3x-ui container to apply change
            if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^3xui_app$'; then
                log_info "Restarting 3xui_app container to apply loopback binding..."
                docker restart 3xui_app >/dev/null 2>&1 || true
            fi
            log_success "3x-ui loopback binding configured"
        else
            log_warning "sqlite3 command not found. Please install sqlite3 to secure the 3x-ui panel listener."
        fi
    else
        log_warning "3x-ui database not found at $db_file. Skipping database loopback configuration."
    fi
}

# Helper to remove the panel proxy Nginx config and restore 3x-ui bindings
remove_panel_proxy() {
    log_info "Removing panel proxy configuration..."
    
    # Remove Nginx panel config
    if [ -f "$APP_DIR/conf.d/panel.conf" ]; then
        rm -f "$APP_DIR/conf.d/panel.conf"
        log_success "Removed Nginx panel config"
        
        # Reload Nginx if container is running
        if docker ps -q -f "name=$CONTAINER_NAME" 2>/dev/null | grep -q .; then
            log_info "Reloading Nginx to apply changes..."
            docker exec "$CONTAINER_NAME" nginx -s reload >/dev/null 2>&1 || true
        fi
    fi
    
    # Restore 3x-ui binding to public
    local db_file="/opt/3x-ui/db/x-ui.db"
    if [ -f "$db_file" ] && command -v sqlite3 >/dev/null 2>&1; then
        log_info "Restoring 3x-ui database listener to public (0.0.0.0)..."
        sqlite3 "$db_file" "DELETE FROM settings WHERE key='webListen'; INSERT INTO settings (key, value) VALUES ('webListen', '0.0.0.0');"
        
        # Restart 3x-ui container
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^3xui_app$'; then
            log_info "Restarting 3xui_app container to apply binding..."
            docker restart 3xui_app >/dev/null 2>&1 || true
        fi
        log_success "3x-ui public binding restored"
    fi
}

# Show status of panel proxy
show_panel_status() {
    local domain="$1"
    local panel_port="$2"
    
    if [ -f "$APP_DIR/conf.d/panel.conf" ]; then
        echo -e "   ${WHITE}Panel Proxy:${NC}       ${GREEN}Enabled${NC}"
        echo -e "   ${WHITE}Panel URL:${NC}         ${BLUE}https://${domain}:${panel_port}${NC}"
        
        local db_file="/opt/3x-ui/db/x-ui.db"
        if [ -f "$db_file" ] && command -v sqlite3 >/dev/null 2>&1; then
            local web_listen
            web_listen=$(sqlite3 "$db_file" "SELECT value FROM settings WHERE key='webListen';" 2>/dev/null | tail -n1 || true)
            if [ "$web_listen" = "127.0.0.1" ]; then
                echo -e "   ${WHITE}3x-ui Bind:${NC}        ${GREEN}Secure (127.0.0.1 only)${NC}"
            else
                echo -e "   ${WHITE}3x-ui Bind:${NC}        ${YELLOW}⚠️  Public ($web_listen)${NC}"
            fi
        fi
    else
        echo -e "   ${WHITE}Panel Proxy:${NC}       ${GRAY}Disabled (HTTP direct or not configured)${NC}"
    fi
}

# Helper to automatically setup default VLESS Reality inbound if no inbounds configured
setup_default_inbound() {
    local domain="$1"
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: setup_default_inbound started, domain=$domain"
    
    local db_file="/opt/3x-ui/db/x-ui.db"
    if [ -f "$db_file" ] && command -v sqlite3 >/dev/null 2>&1; then
        local inbound_count
        inbound_count=$(sqlite3 "$db_file" "SELECT COUNT(*) FROM inbounds;" 2>/dev/null || echo "0")
        
        if [ "$inbound_count" = "0" ] || [ -z "$inbound_count" ]; then
            log_info "No inbounds found in 3x-ui database. Auto-configuring default VLESS Reality inbound..."
            
            # Generate random credentials
            local uuid
            uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
            if [ -z "$uuid" ]; then
                uuid=$(od -x -N 16 /dev/urandom | head -n 1 | awk '{print $2$3"-"$4"-"$5"-"$6"-"$7$8$9}')
            fi
            
            local short_id
            short_id=$(openssl rand -hex 8 2>/dev/null || od -v -An -N 8 -t x1 /dev/urandom | tr -d ' \n')
            
            # Generate Reality keypair via xray container
            local key_output=""
            if docker ps -q -f "name=3xui_app" 2>/dev/null | grep -q .; then
                key_output=$(docker exec 3xui_app bin/xray-linux-amd64 x25519 2>/dev/null || docker exec 3xui_app xray x25519 2>/dev/null || true)
            fi
            
            local priv_key=""
            local pub_key=""
            if [ -n "$key_output" ]; then
                priv_key=$(echo "$key_output" | grep "^PrivateKey:" | awk '{print $NF}')
                pub_key=$(echo "$key_output" | grep -E "^(Password \(PublicKey\)|PublicKey):" | awk '{print $NF}')
            fi
            
            if [ -z "$priv_key" ] || [ -z "$pub_key" ]; then
                log_warning "Could not auto-generate Reality keypair. Skipping default inbound setup."
                log_warning "Try manually: docker exec 3xui_app xray x25519"
                return 0
            fi
            
            # Validate pub_key looks like a valid x25519 base64 key (43-44 chars)
            if [ ${#pub_key} -lt 40 ]; then
                log_warning "Generated PublicKey looks invalid (length=${#pub_key}). Skipping default inbound setup."
                return 0
            fi
            
            local settings_json="{\"clients\":[{\"id\":\"$uuid\",\"flow\":\"xtls-rprx-vision\",\"email\":\"admin@$domain\",\"limitIp\":0,\"totalGB\":0,\"expiryTime\":0}],\"decryption\":\"none\",\"fallbacks\":[]}"
            local stream_settings_json="{\"network\":\"tcp\",\"security\":\"reality\",\"externalProxy\":[],\"realitySettings\":{\"show\":false,\"xver\":1,\"dest\":\"/dev/shm/nginx.sock\",\"spiderX\":\"/\",\"serverNames\":[\"$domain\"],\"privateKey\":\"$priv_key\",\"minClient\":\"\",\"maxClient\":\"\",\"maxTimediff\":0,\"shortIds\":[\"$short_id\"]},\"tcpSettings\":{\"acceptProxyProtocol\":false,\"header\":{\"type\":\"none\"}}}"
            local sniffing_json="{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"],\"metadataOnly\":false,\"routeOnly\":false}"
            
            # Insert inbound record
            sqlite3 "$db_file" "INSERT INTO inbounds (user_id, up, down, total, all_time, remark, enable, expiry_time, traffic_reset, last_traffic_reset_time, listen, port, protocol, settings, stream_settings, tag, sniffing, node_id, origin_node_guid) VALUES (0, 0, 0, 0, 0, 'VLESS-REALITY', 1, 0, 'never', 0, '0.0.0.0', 443, 'vless', '$settings_json', '$stream_settings_json', 'inbound-443', '$sniffing_json', 0, '');"
            
            # Restart 3x-ui container to apply inbound
            if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q '^3xui_app$'; then
                log_info "Restarting 3xui_app container to apply inbound configuration..."
                docker restart 3xui_app >/dev/null 2>&1 || true
            fi
            
            # Save link to config directory
            # NOTE: fp=chrome is REQUIRED for Reality — clients need uTLS fingerprint to construct proper ClientHello.
            #       encryption=none is required by some clients (v2rayN, NekoBox) for VLESS protocol.
            local vless_link="vless://$uuid@$domain:443?security=reality&encryption=none&sni=$domain&fp=chrome&pbk=$pub_key&sid=$short_id&spiderX=%2F&flow=xtls-rprx-vision&type=tcp&headerType=none#VLESS-Reality-Selfsteal"
            mkdir -p "$APP_DIR"
            echo "$vless_link" > "$APP_DIR/vless.txt"
            log_success "Default VLESS Reality inbound auto-configured!"
            
            # Mux reminder: VLESS clients open parallel connection pools by default,
            # which can trigger DPI connection-spike detection. Mux forces single socket.
            log_info "Import the link above into your client (v2rayN, sing-box, Mihomo, NekoBox, v2rayNG)."
            log_info "Enable Mux/XMUX in client settings to force single-socket mode."
        fi
    fi
}

