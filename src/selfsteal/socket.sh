# Check if container has /dev/shm volume mounted
check_container_shm_volume() {
    local container_name="$1"
    
    if ! docker inspect "$container_name" >/dev/null 2>&1; then
        return 1
    fi
    
    # Check if /dev/shm is mounted from host
    if docker inspect "$container_name" --format '{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}' 2>/dev/null | grep -q "/dev/shm:/dev/shm"; then
        return 0
    fi
    
    # Also check Binds format
    if docker inspect "$container_name" --format '{{json .HostConfig.Binds}}' 2>/dev/null | grep -q "/dev/shm:/dev/shm"; then
        return 0
    fi
    
    return 1
}

# Detect if 3x-ui was installed by our script
detect_3xui_installation() {
    # Check standard path from 3x-ui-docker.sh
    if [ -f "/opt/3x-ui/docker-compose.yml" ]; then
        echo "/opt/3x-ui"
        return 0
    fi
    
    # Try to find 3xui_app container and its compose file
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^3xui_app$"; then
        # Check common paths
        for path in "/opt/3x-ui" "/root/3x-ui" /home/*/3x-ui; do
            if [ -f "$path/docker-compose.yml" ]; then
                echo "$path"
                return 0
            fi
        done
    fi
    
    return 1
}

# Check if /dev/shm volume is already configured in docker-compose.yml
check_shm_in_compose() {
    local compose_file="$1"
    
    # Check for uncommented /dev/shm mount
    if grep -qE "^[[:space:]]*-[[:space:]]*/dev/shm:/dev/shm" "$compose_file"; then
        echo "active"
        return 0
    fi
    
    # Check for commented /dev/shm mount
    if grep -qE "^[[:space:]]*#.*-[[:space:]]*/dev/shm:/dev/shm" "$compose_file"; then
        echo "commented"
        return 0
    fi
    
    echo "missing"
    return 0
}

# Uncomment /dev/shm volume in docker-compose.yml
uncomment_shm_volume() {
    local compose_file="$1"
    local backup_file="${compose_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Create backup
    cp "$compose_file" "$backup_file"
    log_info "Created backup: $backup_file"
    
    # First, check if 'volumes:' is also commented and uncomment it
    if grep -qE "^[[:space:]]*#[[:space:]]*volumes:" "$compose_file"; then
        sed -i 's|^[[:space:]]*#[[:space:]]*\(volumes:\)|    \1|' "$compose_file"
    fi
    
    # Then uncomment the /dev/shm line
    sed -i 's|^[[:space:]]*#[[:space:]]*\(-[[:space:]]*/dev/shm:/dev/shm.*\)|      \1|' "$compose_file"
    
    # Validate the modified compose file
    if docker compose -f "$compose_file" config >/dev/null 2>&1; then
        log_success "Uncommented /dev/shm volume in docker-compose.yml"
        return 0
    else
        log_error "Failed to validate modified docker-compose.yml, restoring backup"
        mv "$backup_file" "$compose_file"
        return 1
    fi
}

# Add /dev/shm volume to docker-compose.yml
add_shm_volume_to_compose() {
    local compose_file="$1"
    local backup_file="${compose_file}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # First check current state
    local shm_state=$(check_shm_in_compose "$compose_file")
    
    case "$shm_state" in
        "active")
            log_success "/dev/shm volume is already configured"
            return 0
            ;;
        "commented")
            log_info "Found commented /dev/shm volume, uncommenting..."
            uncomment_shm_volume "$compose_file"
            return $?
            ;;
        "missing")
            log_info "Adding /dev/shm volume to docker-compose.yml..."
            ;;
    esac
    
    # Create backup
    cp "$compose_file" "$backup_file"
    log_info "Created backup: $backup_file"
    
    # Check if volumes section exists (uncommented)
    if grep -qE "^[[:space:]]+volumes:" "$compose_file"; then
        # Volumes section exists - add /dev/shm after it
        sed -i '/^[[:space:]]*volumes:/a\      - /dev/shm:/dev/shm' "$compose_file"
    # Check if volumes section exists but commented
    elif grep -qE "^[[:space:]]*#[[:space:]]*volumes:" "$compose_file"; then
        # Uncomment volumes and add /dev/shm
        sed -i 's|^[[:space:]]*#[[:space:]]*\(volumes:\)|\    \1|' "$compose_file"
        sed -i '/^[[:space:]]*volumes:/a\      - /dev/shm:/dev/shm' "$compose_file"
    else
        # No volumes section - add it before network_mode or restart
        if grep -q "^[[:space:]]*network_mode:" "$compose_file"; then
            sed -i '/^[[:space:]]*network_mode:/i\    volumes:\n      - /dev/shm:/dev/shm' "$compose_file"
        elif grep -q "^[[:space:]]*restart:" "$compose_file"; then
            sed -i '/^[[:space:]]*restart:/i\    volumes:\n      - /dev/shm:/dev/shm' "$compose_file"
        else
            # Append at the end of service definition
            echo "    volumes:" >> "$compose_file"
            echo "      - /dev/shm:/dev/shm" >> "$compose_file"
        fi
    fi
    
    # Validate the modified compose file
    if docker compose -f "$compose_file" config >/dev/null 2>&1; then
        log_success "docker-compose.yml updated successfully"
        return 0
    else
        log_error "Failed to validate modified docker-compose.yml, restoring backup"
        mv "$backup_file" "$compose_file"
        return 1
    fi
}

# Configure 3x-ui for socket access
configure_3xui_socket() {
    echo
    echo -e "${CYAN}🔍 Checking Xray/3x-ui Socket Configuration${NC}"
    echo -e "${GRAY}───────────────────────────────────────${NC}"
    
    # Only relevant for socket mode
    if false; then
        echo -e "${GRAY}   ℹ️  TCP mode - socket configuration not needed${NC}"
        return 0
    fi
    
    # Find containers that might need socket access
    local xray_containers=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "3xui_app|xray|marzban" || true)
    
    if [ -z "$xray_containers" ]; then
        echo -e "${GRAY}   ℹ️  No Xray containers detected${NC}"
        echo -e "${GRAY}   When you install Xray, ensure /dev/shm is mounted${NC}"
        return 0
    fi
    
    for container in $xray_containers; do
        echo -e "${GRAY}   Checking container: ${WHITE}$container${NC}"
        
        if check_container_shm_volume "$container"; then
            echo -e "${GREEN}   ✅ $container has /dev/shm mounted${NC}"
            continue
        fi
        
        echo -e "${YELLOW}   ⚠️  $container does NOT have /dev/shm mounted${NC}"
        echo -e "${GRAY}   Socket path: $SOCKET_PATH${NC}"
        echo
        
        # Try to detect if it's our 3x-ui installation
        local xray_path=$(detect_3xui_installation)
        
        if [ -n "$xray_path" ] && [ -f "$xray_path/docker-compose.yml" ]; then
            echo -e "${CYAN}   📦 Detected 3x-ui installation at: $xray_path${NC}"
            
            # Check current state in docker-compose.yml
            local shm_state=$(check_shm_in_compose "$xray_path/docker-compose.yml")
            
            case "$shm_state" in
                "active")
                    echo -e "${GREEN}   ✅ /dev/shm is already configured in docker-compose.yml${NC}"
                    echo -e "${YELLOW}   ⚠️  But container doesn't have it mounted. Needs restart.${NC}"
                    echo
                    echo -e "${CYAN}   Options:${NC}"
                    echo -e "${WHITE}   1)${NC} ${GRAY}Restart container now${NC}"
                    echo -e "${WHITE}   2)${NC} ${GRAY}Skip (restart later)${NC}"
                    echo
                    
                    local choice
                    read -p "$(echo -e "${CYAN}   Select option [1-2]: ${NC}")" choice
                    
                    if [ "$choice" = "1" ]; then
                        echo
                        log_info "Restarting $container..."
                        cd "$xray_path"
                        if docker compose down && docker compose up -d; then
                            log_success "$container restarted"
                            sleep 2
                            if check_container_shm_volume "$container"; then
                                echo -e "${GREEN}   ✅ Verified: /dev/shm is now accessible${NC}"
                            fi
                        else
                            log_error "Failed to restart $container"
                        fi
                        cd - >/dev/null
                    fi
                    continue
                    ;;
                "commented")
                    echo -e "${YELLOW}   ℹ️  /dev/shm volume is configured but commented out${NC}"
                    echo
                    echo -e "${CYAN}   Options:${NC}"
                    echo -e "${WHITE}   1)${NC} ${GRAY}Uncomment and restart automatically${NC}"
                    echo -e "${WHITE}   2)${NC} ${GRAY}Show manual instructions${NC}"
                    echo -e "${WHITE}   3)${NC} ${GRAY}Skip (configure later)${NC}"
                    ;;
                "missing")
                    echo
                    echo -e "${WHITE}   The container '$container' needs access to the socket file.${NC}"
                    echo -e "${WHITE}   To fix this, /dev/shm must be mounted in the container.${NC}"
                    echo
                    echo -e "${CYAN}   Options:${NC}"
                    echo -e "${WHITE}   1)${NC} ${GRAY}Fix automatically (modify docker-compose.yml and restart)${NC}"
                    echo -e "${WHITE}   2)${NC} ${GRAY}Show manual instructions${NC}"
                    echo -e "${WHITE}   3)${NC} ${GRAY}Skip (configure later)${NC}"
                    ;;
            esac
            echo
            
            local choice
            read -p "$(echo -e "${CYAN}   Select option [1-3]: ${NC}")" choice
            
            case "$choice" in
                1)
                    echo
                    log_info "Modifying $xray_path/docker-compose.yml safely via python..."
                    
                    if ! python3 -c 'import yaml' 2>/dev/null; then
                        log_info "Installing PyYAML for safe configuration modification..."
                        apt-get update -qq >/dev/null 2>&1 || true
                        apt-get install -y -qq python3-yaml >/dev/null 2>&1 || true
                    fi
                    
                    if python3 -c 'import sys, yaml; d=yaml.safe_load(open(sys.argv[1])); d.setdefault("services",{}).setdefault("3xui",{}).setdefault("volumes",[]).append("/dev/shm:/dev/shm"); yaml.dump(d, open(sys.argv[1],"w"))' "$xray_path/docker-compose.yml" 2>/dev/null || add_shm_volume_to_compose "$xray_path/docker-compose.yml"; then
                        echo
                        log_info "Restarting $container..."
                        
                        cd "$xray_path"
                        if docker compose down && docker compose up -d; then
                            log_success "$container restarted with /dev/shm mounted"
                            
                            # Verify the fix
                            sleep 2
                            if check_container_shm_volume "$container"; then
                                echo -e "${GREEN}   ✅ Verified: /dev/shm is now accessible${NC}"
                            fi
                        else
                            log_error "Failed to restart $container"
                            echo -e "${YELLOW}   Please restart manually: cd $xray_path && docker compose up -d${NC}"
                        fi
                        cd - >/dev/null
                    fi
                    ;;
                2)
                    echo
                    echo -e "${WHITE}   📋 Manual Instructions:${NC}"
                    echo -e "${GRAY}   ─────────────────────────────────────${NC}"
                    echo -e "${GRAY}   1. Edit docker-compose.yml:${NC}"
                    echo -e "${CYAN}      nano $xray_path/docker-compose.yml${NC}"
                    echo
                    echo -e "${GRAY}   2. Add to the volumes section:${NC}"
                    echo -e "${WHITE}      volumes:${NC}"
                    echo -e "${CYAN}        - /dev/shm:/dev/shm${NC}"
                    echo
                    echo -e "${GRAY}   3. Restart the container:${NC}"
                    echo -e "${CYAN}      cd $xray_path && docker compose down && docker compose up -d${NC}"
                    echo -e "${GRAY}   ─────────────────────────────────────${NC}"
                    ;;
                3|*)
                    echo -e "${GRAY}   Skipped. Remember to configure socket access later.${NC}"
                    ;;
            esac
        else
            # Unknown installation - show generic instructions
            echo -e "${YELLOW}   ⚠️  Could not detect docker-compose.yml location${NC}"
            echo
            echo -e "${WHITE}   To enable socket access, add this volume to your Xray container:${NC}"
            echo -e "${CYAN}      - /dev/shm:/dev/shm${NC}"
            echo
            echo -e "${WHITE}   Then restart the container.${NC}"
        fi
        
        echo
    done
    
    return 0
}
