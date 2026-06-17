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
            sqlite3 "$db_file" "INSERT OR REPLACE INTO settings (key, value) VALUES ('webListen', '127.0.0.1');"
            
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
        sqlite3 "$db_file" "INSERT OR REPLACE INTO settings (key, value) VALUES ('webListen', '0.0.0.0');"
        
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
            web_listen=$(sqlite3 "$db_file" "SELECT value FROM settings WHERE key='webListen';" 2>/dev/null || true)
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
