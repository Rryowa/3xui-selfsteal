# Check if acme.sh is installed
check_acme_installed() {
    if [ -f "$ACME_HOME/acme.sh" ]; then
        return 0
    fi
    return 1
}

# Install acme.sh
install_acme() {
    log_info "Installing acme.sh..."
    
    # Disable exit on error and pipefail for this function
    set +e
    set +o pipefail 2>/dev/null || true
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: Starting install_acme, ACME_HOME=$ACME_HOME"
    
    # Check for required dependencies
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required for acme.sh installation"
        set -e
        set -o pipefail 2>/dev/null || true
        return 1
    fi
    
    # Check if already installed
    if [ -f "$ACME_HOME/acme.sh" ]; then
        log_success "acme.sh is already installed"
        "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        set -e
        set -o pipefail 2>/dev/null || true
        return 0
    fi
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: acme.sh not found at $ACME_HOME/acme.sh"
    
    # Generate random email for registration
    local random_email="user$(shuf -i 10000-99999 -n 1)@gmail.com"
    
    echo -e "${GRAY}   Email: $random_email${NC}"
    echo -e "${GRAY}   Downloading and installing acme.sh...${NC}"
    
    # Download script first, then execute (more reliable than pipe)
    local temp_script="/tmp/acme_install_$$.sh"
    local install_output=""
    local install_exit_code=0
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: Downloading from https://get.acme.sh to $temp_script"
    
    if curl -sS --connect-timeout 30 --max-time 60 https://get.acme.sh -o "$temp_script" 2>/dev/null; then
        if [ -s "$temp_script" ]; then
            echo -e "${GRAY}   Running acme.sh installer...${NC}"
            [ "$DEBUG_MODE" = true ] && echo "DEBUG: Script size: $(wc -c < "$temp_script") bytes"
            
            install_output=$(sh "$temp_script" email="$random_email" 2>&1) || install_exit_code=$?
            echo -e "${GRAY}   Installer finished with code: $install_exit_code${NC}"
            
            [ "$DEBUG_MODE" = true ] && echo "DEBUG: Install output:"
            [ "$DEBUG_MODE" = true ] && echo "$install_output"
        else
            echo -e "${YELLOW}   Downloaded script is empty${NC}"
        fi
    else
        echo -e "${YELLOW}   Failed to download from get.acme.sh${NC}"
    fi
    rm -f "$temp_script"
    
    # Note: Don't source .bashrc directly - it contains 'return' for non-interactive shells
    # which would terminate the entire script. Instead, just search for acme.sh in known paths.
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: Checking for acme.sh at $ACME_HOME/acme.sh"
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: HOME=$HOME"
    [ "$DEBUG_MODE" = true ] && { ls -la "$ACME_HOME/" 2>/dev/null || echo "DEBUG: $ACME_HOME does not exist"; }
    
    # Check multiple possible locations
    local acme_found=false
    for acme_path in "$ACME_HOME/acme.sh" "$HOME/.acme.sh/acme.sh" "/root/.acme.sh/acme.sh"; do
        [ "$DEBUG_MODE" = true ] && echo "DEBUG: Checking $acme_path"
        if [ -f "$acme_path" ]; then
            ACME_HOME=$(dirname "$acme_path")
            acme_found=true
            [ "$DEBUG_MODE" = true ] && echo "DEBUG: Found at $acme_path, setting ACME_HOME=$ACME_HOME"
            break
        fi
    done
    
    if [ "$acme_found" = true ]; then
        log_success "acme.sh installed successfully"
        
        # Set default CA to Let's Encrypt
        "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
        
        [ "$DEBUG_MODE" = false ] && set -e
        [ "$DEBUG_MODE" = false ] && set -o pipefail 2>/dev/null || true
        return 0
    fi
    
    # If first method failed, try git clone method
    log_warning "First method failed, trying git clone method..."
    
    if command -v git >/dev/null 2>&1; then
        local temp_dir="/tmp/acme_git_$$"
        rm -rf "$temp_dir"
        
        echo -e "${GRAY}   Cloning acme.sh repository...${NC}"
        if git clone --depth 1 https://github.com/acmesh-official/acme.sh.git "$temp_dir" 2>/dev/null; then
            cd "$temp_dir" || true
            echo -e "${GRAY}   Running installer from git...${NC}"
            install_output=$(./acme.sh --install -m "$random_email" 2>&1) || install_exit_code=$?
            echo -e "${GRAY}   Git installer finished with code: $install_exit_code${NC}"
            [ "$DEBUG_MODE" = true ] && echo "DEBUG: Git install output: $install_output"
            cd - >/dev/null || true
            rm -rf "$temp_dir"
            
            # Note: Don't source .bashrc - it would terminate the script
            # Just search for acme.sh in known paths below.
            
            # Check again in multiple locations
            for acme_path in "$ACME_HOME/acme.sh" "$HOME/.acme.sh/acme.sh" "/root/.acme.sh/acme.sh"; do
                if [ -f "$acme_path" ]; then
                    ACME_HOME=$(dirname "$acme_path")
                    log_success "acme.sh installed successfully via git"
                    "$ACME_HOME/acme.sh" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true
                    [ "$DEBUG_MODE" = false ] && set -e
                    [ "$DEBUG_MODE" = false ] && set -o pipefail 2>/dev/null || true
                    return 0
                fi
            done
        else
            echo -e "${YELLOW}   Git clone failed${NC}"
        fi
        rm -rf "$temp_dir"
    else
        echo -e "${YELLOW}   Git not available for fallback${NC}"
    fi
    
    log_error "Failed to install acme.sh"
    if [ -n "${install_output:-}" ]; then
        echo -e "${YELLOW}Installation output:${NC}"
        echo "$install_output" | tail -20
    fi
    [ "$DEBUG_MODE" = false ] && set -e
    [ "$DEBUG_MODE" = false ] && set -o pipefail 2>/dev/null || true
    return 1
}

# Find available port for ACME TLS-ALPN challenge
find_available_acme_port() {
    # If port was explicitly set via --acme-port, use it
    if [ -n "$ACME_PORT" ]; then
        echo "$ACME_PORT"
        return 0
    fi
    
    # Try fallback ports
    for port in "${ACME_FALLBACK_PORTS[@]}"; do
        if ! ss -tlnp 2>/dev/null | grep -q ":$port " 2>/dev/null; then
            echo "$port"
            return 0
        fi
    done
    
    # No available port found - return empty string but success
    echo ""
    return 0
}

# Helper: setup iptables redirect from 443 to acme_port (TLS-ALPN-01 requires port 443)
setup_acme_port_redirect() {
    local target_port="$1"
    if [ "$target_port" != "443" ]; then
        log_info "Setting up port redirect 443 → $target_port for TLS-ALPN challenge..."
        iptables -t nat -I PREROUTING 1 -p tcp --dport 443 -j REDIRECT --to-port "$target_port" 2>/dev/null || true
        iptables -t nat -I OUTPUT 1 -p tcp --dport 443 -o lo -j REDIRECT --to-port "$target_port" 2>/dev/null || true
    fi
}

# Helper: remove iptables redirect
cleanup_acme_port_redirect() {
    local target_port="$1"
    if [ "$target_port" != "443" ]; then
        iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-port "$target_port" 2>/dev/null || true
        iptables -t nat -D OUTPUT -p tcp --dport 443 -o lo -j REDIRECT --to-port "$target_port" 2>/dev/null || true
    fi
}

# Helper: read Le_TLSPort from acme.sh domain config
get_acme_tls_port() {
    local domain="$1"
    local acme_home="${ACME_HOME:-$HOME/.acme.sh}"
    local domain_conf="$acme_home/${domain}/${domain}.conf"
    
    if [ -f "$domain_conf" ]; then
        local saved_port
        saved_port=$(grep "^Le_TLSPort=" "$domain_conf" 2>/dev/null | cut -d"'" -f2 | tr -d '"')
        if [ -n "$saved_port" ]; then
            echo "$saved_port"
            return 0
        fi
    fi
    
    # Fallback to ACME_PORT or default
    echo "${ACME_PORT:-443}"
    return 0
}

# Issue SSL certificate for domain using TLS-ALPN
issue_ssl_certificate() {
    local domain="$1"
    local ssl_dir="$2"
    local skip_reload="${3:-false}"  # Skip reload command during initial install
    
    log_info "Requesting SSL certificate for $domain..."
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: issue_ssl_certificate started"
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: domain=$domain, ssl_dir=$ssl_dir, skip_reload=$skip_reload"
    
    # Disable exit on error and pipefail for this function
    set +e
    set +o pipefail 2>/dev/null || true
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: Checking if acme.sh is installed"
    
    # Ensure acme.sh is installed
    if ! check_acme_installed; then
        [ "$DEBUG_MODE" = true ] && echo "DEBUG: acme.sh not installed, calling install_acme"
        if ! install_acme; then
            [ "$DEBUG_MODE" = true ] && echo "DEBUG: install_acme FAILED"
            [ "$DEBUG_MODE" = false ] && set -e
            [ "$DEBUG_MODE" = false ] && set -o pipefail 2>/dev/null || true
            return 1
        fi
        [ "$DEBUG_MODE" = true ] && echo "DEBUG: install_acme completed successfully"
    else
        [ "$DEBUG_MODE" = true ] && echo "DEBUG: acme.sh already installed at $ACME_HOME"
    fi
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: Checking for socat"
    
    # Install socat if not available (required for standalone mode)
    if ! command -v socat >/dev/null 2>&1; then
        log_info "Installing socat (required for certificate validation)..."
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq && apt-get install -y -qq socat >/dev/null 2>&1 || true
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q socat >/dev/null 2>&1 || true
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q socat >/dev/null 2>&1 || true
        elif command -v apk >/dev/null 2>&1; then
            apk add --quiet socat >/dev/null 2>&1 || true
        fi
        
        if command -v socat >/dev/null 2>&1; then
            log_success "socat installed"
        else
            log_error "Failed to install socat"
            [ "$DEBUG_MODE" = false ] && set -e
            [ "$DEBUG_MODE" = false ] && set -o pipefail 2>/dev/null || true
            return 1
        fi
    fi
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: Creating SSL directory: $ssl_dir"
    
    # Create SSL directory
    if ! create_dir_safe "$ssl_dir"; then
        [ "$DEBUG_MODE" = false ] && set -e
        [ "$DEBUG_MODE" = false ] && set -o pipefail 2>/dev/null || true
        return 1
    fi
    
    [ "$DEBUG_MODE" = true ] && echo "DEBUG: Finding available ACME port"
    
    # Find available port for ACME
    local acme_port
    acme_port=$(find_available_acme_port)
    
    if [ -z "$acme_port" ]; then
        log_error "No available port found for ACME TLS-ALPN challenge"
        echo -e "${YELLOW}All fallback ports are in use: ${ACME_FALLBACK_PORTS[*]}${NC}"
        echo -e "${GRAY}You can specify a custom port with: --acme-port <port>${NC}"
        echo
        
        # Show what's using the ports
        echo -e "${WHITE}Port usage:${NC}"
        for port in "${ACME_FALLBACK_PORTS[@]}"; do
            local process_info
            process_info=$(ss -tlnp 2>/dev/null | grep ":$port " | head -1)
            if [ -n "$process_info" ]; then
                echo -e "${RED}   Port $port: IN USE${NC}"
                echo -e "${GRAY}   $process_info${NC}"
            else
                echo -e "${GREEN}   Port $port: Available${NC}"
            fi
        done
        echo
        
        # Ask user for custom port
        read -p "Enter custom port for ACME (or press Enter to cancel): " -r custom_port
        if [ -n "$custom_port" ] && [[ "$custom_port" =~ ^[0-9]+$ ]]; then
            if ss -tlnp 2>/dev/null | grep -q ":$custom_port "; then
                log_error "Port $custom_port is also in use"
                return 1
            fi
            acme_port="$custom_port"
        else
            return 1
        fi
    fi
    
    # Check if the selected port needs firewall opening
    if ! check_firewall_port "$acme_port"; then
        echo
        echo -e "${YELLOW}⚠️  Firewall may be blocking port $acme_port${NC}"
        echo -ne "${CYAN}Continue anyway? [y/N]: ${NC}"
        read -r continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            log_info "Please open port $acme_port in firewall and try again"
            return 1
        fi
    fi
    
    # Prepare reload command - skip during initial install when container doesn't exist yet
    local reload_cmd=""
    if [ "$skip_reload" != "true" ] && docker ps -q -f "name=$CONTAINER_NAME" 2>/dev/null | grep -q .; then
        reload_cmd="docker exec $CONTAINER_NAME nginx -s reload 2>/dev/null || true"
    fi
    
    # Helper: attempt certificate issuance on a given port
    _try_issue_cert() {
        local try_port="$1"
        local try_domain="$2"
        local try_ssl_dir="$3"
        local try_reload_cmd="$4"
        
        log_info "Issuing certificate via TLS-ALPN on port $try_port..."
        echo -e "${GRAY}This may take a minute...${NC}"
        
        local try_args=(
            --issue
            --standalone
            -d "$try_domain"
            --key-file "$try_ssl_dir/private.key"
            --fullchain-file "$try_ssl_dir/fullchain.crt"
            --alpn
            --tlsport "$try_port"
            --httpport 65535
            --server letsencrypt
            --force
            --debug 2
        )
        
        if [ -n "$try_reload_cmd" ]; then
            try_args+=(--reloadcmd "$try_reload_cmd")
        fi
        
        # Setup iptables redirect: Let's Encrypt connects to 443, redirect to acme_port
        setup_acme_port_redirect "$try_port"
        
        local try_output
        local try_exit_code
        try_output=$("$ACME_HOME/acme.sh" "${try_args[@]}" 2>&1) && try_exit_code=0 || try_exit_code=$?
        
        # Always cleanup iptables redirect
        cleanup_acme_port_redirect "$try_port"
        
        if [ $try_exit_code -eq 0 ] && [ -f "$try_ssl_dir/private.key" ] && [ -f "$try_ssl_dir/fullchain.crt" ]; then
            log_success "Certificate issued and installed successfully (port $try_port)"
            chmod 600 "$try_ssl_dir/private.key" 2>/dev/null || true
            chmod 644 "$try_ssl_dir/fullchain.crt" 2>/dev/null || true
            return 0
        elif [ $try_exit_code -eq 0 ]; then
            log_error "acme.sh reported success but certificate files were not created"
            echo -e "${YELLOW}Expected files:${NC}"
            echo -e "  Key:  $try_ssl_dir/private.key"
            echo -e "  Cert: $try_ssl_dir/fullchain.crt"
            echo -e "${YELLOW}ACME output (last 30 lines):${NC}"
            echo "$try_output" | tail -30
            return 1
        else
            log_error "Failed to issue certificate on port $try_port (exit code: $try_exit_code)"
            echo -e "${YELLOW}ACME output:${NC}"
            echo "$try_output" | tail -30
            return 1
        fi
    }
    
    # Try primary port
    if _try_issue_cert "$acme_port" "$domain" "$ssl_dir" "$reload_cmd"; then
        set -e
        set -o pipefail
        return 0
    fi
    
    # Try fallback ports if primary port wasn't explicitly set
    if [ -z "$ACME_PORT" ]; then
        local tried_port="$acme_port"
        for fallback_port in "${ACME_FALLBACK_PORTS[@]}"; do
            if [ "$fallback_port" = "$tried_port" ]; then
                continue
            fi
            if ! ss -tlnp 2>/dev/null | grep -q ":$fallback_port " 2>/dev/null; then
                echo
                log_warning "Trying fallback port $fallback_port..."
                
                if _try_issue_cert "$fallback_port" "$domain" "$ssl_dir" "$reload_cmd"; then
                    set -e
                    set -o pipefail
                    return 0
                fi
            fi
        done
    fi
    
    set -e
    set -o pipefail
    return 1
}

# Renew SSL certificates
renew_ssl_certificates() {
    log_info "Checking for certificate renewal..."
    
    if ! check_acme_installed; then
        log_warning "acme.sh not installed, skipping renewal"
        return 1
    fi
    
    # Collect all unique TLS ports from acme.sh domain configs for iptables redirect
    local tls_ports=()
    local acme_home="${ACME_HOME:-$HOME/.acme.sh}"
    for domain_conf in "$acme_home"/*/[!.]*.conf; do
        [ -f "$domain_conf" ] || continue
        local saved_port
        saved_port=$(grep "^Le_TLSPort=" "$domain_conf" 2>/dev/null | cut -d"'" -f2 | tr -d '"')
        if [ -n "$saved_port" ] && [ "$saved_port" != "443" ]; then
            # Add to array if not already present
            local already=false
            for p in "${tls_ports[@]}"; do
                [ "$p" = "$saved_port" ] && { already=true; break; }
            done
            [ "$already" = false ] && tls_ports+=("$saved_port")
        fi
    done
    
    # Setup iptables redirects for all non-443 TLS ports
    for port in "${tls_ports[@]}"; do
        setup_acme_port_redirect "$port"
    done
    
    local renew_result=0
    if "$ACME_HOME/acme.sh" --cron --home "$ACME_HOME" 2>&1; then
        log_success "Certificate renewal check completed"
    else
        log_warning "Certificate renewal encountered issues"
        renew_result=1
    fi
    
    # Cleanup iptables redirects
    for port in "${tls_ports[@]}"; do
        cleanup_acme_port_redirect "$port"
    done
    
    return $renew_result
}

# Setup auto-renewal cron job
setup_ssl_auto_renewal() {
    log_info "Setting up auto-renewal for SSL certificates..."
    
    if ! check_acme_installed; then
        log_warning "acme.sh not installed, skipping auto-renewal setup"
        return 1
    fi
    
    # Create renewal wrapper script that handles iptables redirect for non-443 TLS ports
    local wrapper_script="$APP_DIR/acme-renew.sh"
    cat > "$wrapper_script" <<'WRAPPER_EOF'
#!/usr/bin/env bash
# Auto-generated wrapper for acme.sh renewal with iptables redirect support
# TLS-ALPN-01 requires Let's Encrypt to connect to port 443.
# When acme.sh uses --tlsport (non-443), iptables REDIRECT is needed.

set -e

ACME_HOME="__ACME_HOME__"

# Collect all TLS ports from domain configs
tls_ports=()
for domain_conf in "$ACME_HOME"/*/[!.]*.conf; do
    [ -f "$domain_conf" ] || continue
    saved_port=$(grep "^Le_TLSPort=" "$domain_conf" 2>/dev/null | cut -d"'" -f2 | tr -d '"')
    if [ -n "$saved_port" ] && [ "$saved_port" != "443" ]; then
        already=false
        for p in "${tls_ports[@]}"; do
            [ "$p" = "$saved_port" ] && { already=true; break; }
        done
        [ "$already" = false ] && tls_ports+=("$saved_port")
    fi
done

# Setup iptables redirects
for port in "${tls_ports[@]}"; do
    iptables -t nat -I PREROUTING 1 -p tcp --dport 443 -j REDIRECT --to-port "$port" 2>/dev/null || true
    iptables -t nat -I OUTPUT 1 -p tcp --dport 443 -o lo -j REDIRECT --to-port "$port" 2>/dev/null || true
done

# Run acme.sh cron
"$ACME_HOME/acme.sh" --cron --home "$ACME_HOME" > /dev/null 2>&1
renew_exit=$?

# Cleanup iptables redirects
for port in "${tls_ports[@]}"; do
    iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-port "$port" 2>/dev/null || true
    iptables -t nat -D OUTPUT -p tcp --dport 443 -o lo -j REDIRECT --to-port "$port" 2>/dev/null || true
done

exit $renew_exit
WRAPPER_EOF
    
    # Replace placeholder with actual ACME_HOME path
    sed -i "s|__ACME_HOME__|$ACME_HOME|g" "$wrapper_script"
    chmod 700 "$wrapper_script"
    
    # Remove any existing acme.sh cron entries (both direct and wrapper)
    if crontab -l 2>/dev/null | grep -q "acme"; then
        crontab -l 2>/dev/null | grep -v "acme" | crontab - 2>/dev/null || true
    fi
    
    # Setup cron with wrapper script
    log_info "Configuring cron job for auto-renewal..."
    (crontab -l 2>/dev/null; echo "0 0 * * * $wrapper_script") | crontab -
    log_success "Auto-renewal cron job configured (with iptables redirect support)"
    
    return 0
}

# Check certificate expiration
check_ssl_certificate_status() {
    local ssl_dir="$1"
    local cert_file="$ssl_dir/fullchain.crt"
    
    if [ ! -f "$cert_file" ]; then
        echo "not_found"
        return 1
    fi
    
    # Get expiration date
    local expiry_date
    expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
    
    if [ -z "$expiry_date" ]; then
        echo "invalid"
        return 1
    fi
    
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry_date" +%s 2>/dev/null)
    local now_epoch
    now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
    
    if [ "$days_left" -lt 0 ]; then
        echo "expired"
    elif [ "$days_left" -lt 7 ]; then
        echo "expiring_soon:$days_left"
    elif [ "$days_left" -lt 30 ]; then
        echo "warning:$days_left"
    else
        echo "valid:$days_left"
    fi
    
    return 0
}

# Display SSL certificate info
show_ssl_certificate_info() {
    local ssl_dir="$1"
    local cert_file="$ssl_dir/fullchain.crt"
    
    if [ ! -f "$cert_file" ]; then
        log_warning "Certificate file not found: $cert_file"
        return 1
    fi
    
    echo -e "${WHITE}🔐 SSL Certificate Information${NC}"
    echo -e "${GRAY}$(printf '─%.0s' $(seq 1 40))${NC}"
    
    # Get certificate details
    local subject
    subject=$(openssl x509 -subject -noout -in "$cert_file" 2>/dev/null | sed 's/subject=//')
    local issuer
    issuer=$(openssl x509 -issuer -noout -in "$cert_file" 2>/dev/null | sed 's/issuer=//')
    local expiry
    expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | sed 's/notAfter=//')
    local start
    start=$(openssl x509 -startdate -noout -in "$cert_file" 2>/dev/null | sed 's/notBefore=//')
    
    printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Subject:" "$subject"
    printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Issuer:" "$issuer"
    printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Valid From:" "$start"
    printf "   ${WHITE}%-15s${NC} ${GRAY}%s${NC}\n" "Valid Until:" "$expiry"
    
    # Check status
    local status
    status=$(check_ssl_certificate_status "$ssl_dir")
    
    case "$status" in
        valid:*)
            local days="${status#valid:}"
            echo -e "   ${WHITE}Status:${NC}         ${GREEN}✅ Valid ($days days remaining)${NC}"
            ;;
        warning:*)
            local days="${status#warning:}"
            echo -e "   ${WHITE}Status:${NC}         ${YELLOW}⚠️  Renewal recommended ($days days remaining)${NC}"
            ;;
        expiring_soon:*)
            local days="${status#expiring_soon:}"
            echo -e "   ${WHITE}Status:${NC}         ${RED}🔴 Expiring soon! ($days days remaining)${NC}"
            ;;
        expired)
            echo -e "   ${WHITE}Status:${NC}         ${RED}❌ EXPIRED${NC}"
            ;;
        *)
            echo -e "   ${WHITE}Status:${NC}         ${YELLOW}⚠️  Unknown${NC}"
            ;;
    esac
    
    echo
}
