# Check if port is open in firewall
check_firewall_port() {
    local port="$1"
    local firewall_issues=""
    
    # Check UFW
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        if ! ufw status | grep -qE "^$port(/tcp)?\s+ALLOW"; then
            firewall_issues="ufw"
            log_warning "UFW is active and port $port may be blocked"
            log_info "To open: ufw allow $port/tcp"
        fi
    fi
    
    # Check firewalld
    if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        if ! firewall-cmd --list-ports 2>/dev/null | grep -qE "$port/tcp"; then
            [ -n "$firewall_issues" ] && firewall_issues="$firewall_issues, "
            firewall_issues="${firewall_issues}firewalld"
            log_warning "firewalld is active and port $port may be blocked"
            log_info "To open: firewall-cmd --add-port=$port/tcp --permanent && firewall-cmd --reload"
        fi
    fi
    
    # Check iptables (basic check)
    if command -v iptables >/dev/null 2>&1; then
        if iptables -L INPUT -n 2>/dev/null | grep -q "DROP\|REJECT"; then
            if ! iptables -L INPUT -n 2>/dev/null | grep -qE "dpt:$port\s+.*ACCEPT"; then
                [ -n "$firewall_issues" ] && firewall_issues="$firewall_issues, "
                firewall_issues="${firewall_issues}iptables"
                log_warning "iptables may be blocking port $port"
                log_info "To open: iptables -I INPUT -p tcp --dport $port -j ACCEPT"
            fi
        fi
    fi
    
    if [ -n "$firewall_issues" ]; then
        return 1
    fi
    return 0
}
