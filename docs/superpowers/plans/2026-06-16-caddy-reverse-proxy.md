# 3x-ui Panel Caddy Reverse Proxy Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate an interactive Caddy reverse proxy setup into `3x-ui-docker.sh` to secure the 3x-ui panel with HTTPS, bind the panel to `127.0.0.1` (hiding it from the public internet), and serve it via a dedicated domain.

**Architecture:** We will prompt the user during installation to optionally configure Caddy. If enabled, the script will write Caddy Docker files under `/opt/3x-ui/caddy/`, run the Caddy container in host network mode to proxy to `127.0.0.1:PANEL_PORT`, and configure the 3x-ui panel in `x-ui.db` to bind only to local loopback interface.

**Tech Stack:** Bash, Docker, Docker Compose, SQLite3, Caddy

---

### Task 1: Add Caddy installation helper functions

**Files:**
- Modify: `3x-ui-docker.sh`

- [ ] **Step 1: Define `validate_domain` and `check_caddy_ports` functions**

  Add these helper functions to check domain name format and identify conflicts on port 80/443.
  ```bash
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

  check_caddy_ports() {
      local ports=(80 443)
      local conflict=false
      for port in "${ports[@]}"; do
          if ss -tuln | grep -q ":$port "; then
              colorized_echo red "Port $port is already in use."
              conflict=true
          fi
      done
      if [ "$conflict" = true ]; then
          colorized_echo red "Caddy requires ports 80 and 443 to be free for SSL certificates."
          return 1
      fi
      return 0
  }
  ```

- [ ] **Step 2: Define `ensure_sqlite3_installed` function**

  Add helper function to ensure `sqlite3` is available on the host to update the 3x-ui settings database.
  ```bash
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
  ```

- [ ] **Step 3: Define `validate_dns` function**

  Add helper function to check DNS resolution for the panel domain.
  ```bash
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
  ```

---

### Task 2: Implement reverse proxy setup logic

**Files:**
- Modify: `3x-ui-docker.sh`

- [ ] **Step 1: Write `setup_caddy_reverse_proxy` function**

  Add this function to prompt for domain, setup caddy folder structure, and start Caddy.
  ```bash
  setup_caddy_reverse_proxy() {
      local server_ip="$1"
      local panel_port="$2"
      
      echo
      read -p "Do you want to configure a secure Caddy reverse proxy with SSL? (y/n): " -r setup_caddy
      if [[ ! "$setup_caddy" =~ ^[Yy]$ ]]; then
          return 0
      fi
      
      if ! check_caddy_ports; then
          colorized_echo red "Aborting Caddy setup due to port conflicts."
          return 0
      fi
      
      ensure_sqlite3_installed
      
      local panel_domain=""
      while true; do
          read -p "Enter the panel domain (e.g., panel.example.com): " -r input_domain
          panel_domain=$(echo "$input_domain" | sed -e 's|^https\?://||' -e 's|/$||' | xargs)
          if [ -z "$panel_domain" ]; then
              colorized_echo red "Domain cannot be empty."
          elif ! validate_domain "$panel_domain"; then
              colorized_echo red "Invalid domain format. Try again."
          else
              break
          fi
      done
      
      if ! validate_dns "$panel_domain" "$server_ip"; then
          colorized_echo yellow "Skipping Caddy configuration due to DNS validation failure."
          return 0
      fi
      
      colorized_echo blue "Configuring 3x-ui to listen only on local loopback interface..."
      sqlite3 /opt/3x-ui/db/x-ui.db "INSERT OR REPLACE INTO settings (key, value) VALUES ('webListen', '127.0.0.1');"
      
      colorized_echo blue "Creating Caddy configuration files..."
      mkdir -p /opt/3x-ui/caddy
      
      # 1. Write .env
      cat > /opt/3x-ui/caddy/.env << EOF
  PANEL_DOMAIN=$panel_domain
  PANEL_PORT=$panel_port
  EOF
      
      # 2. Write Caddyfile
      cat > /opt/3x-ui/caddy/Caddyfile << 'EOF'
  {
      servers {
          protocols h1 h2 h3
      }
  }

  https://{$PANEL_DOMAIN} {
      encode zstd gzip

      reverse_proxy 127.0.0.1:{$PANEL_PORT} {
          header_up X-Real-IP {remote_host}
          header_up Host {host}
      }

      log {
          output file /var/log/caddy/panel.log {
              roll_size 30mb
              roll_keep 10
              roll_keep_for 720h
          }
      }
  }

  :443 {
      tls internal
      respond 204
  }
  EOF

      # 3. Write docker-compose.yml
      cat > /opt/3x-ui/caddy/docker-compose.yml << 'EOF'
  services:
    caddy:
      image: caddy:2-alpine
      container_name: caddy-3xui
      hostname: caddy
      restart: always
      network_mode: host
      volumes:
        - ./Caddyfile:/etc/caddy/Caddyfile:ro
        - ./logs:/var/log/caddy
        - caddy-ssl-data:/data
      env_file:
        - .env
      logging:
        driver: "json-file"
        options:
          max-size: "10m"
          max-file: "3"

  volumes:
    caddy-ssl-data:
      driver: local
      external: false
      name: caddy-ssl-data
  EOF

      colorized_echo blue "Starting Caddy reverse proxy container..."
      cd /opt/3x-ui/caddy
      docker compose up -d
      
      # Export domain for connection details print
      IS_HTTPS_SECURED=true
      SECURED_DOMAIN="$panel_domain"
  }
  ```

---

### Task 3: Refactor script entry and output blocks

**Files:**
- Modify: `3x-ui-docker.sh`

- [ ] **Step 1: Modify `check_ports` function**

  Update `check_ports` to check only port 2053 (panel port) so that other services on 80/443 do not block the installation if Caddy is not selected.
  ```bash
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
  ```

- [ ] **Step 2: Integrate reverse proxy call and print connection details**

  Modify the setup execution logic to call `setup_caddy_reverse_proxy` after the 3xui container is started, restart 3x-ui if Caddy is setup, and print appropriate connection URLs.
  
  Locate lines containing `$COMPOSE up -d` (around line 136) and replace with:
  ```bash
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
      
      IS_HTTPS_SECURED=false
      SECURED_DOMAIN=""
      
      # Setup Caddy reverse proxy
      setup_caddy_reverse_proxy "$public_ip" "$panel_port"
      
      # If Caddy was configured, restart 3xui to apply the webListen binding
      if [ "$IS_HTTPS_SECURED" = true ]; then
          colorized_echo blue "Restarting 3x-ui panel to apply loopback binding..."
          cd /opt/3x-ui
          $COMPOSE restart
      fi
      
      colorized_echo green "✅ 3x-ui Docker started successfully!"
      echo
      
      colorized_echo green "────────────────────────────────────────"
      colorized_echo green "💻 Access Details for 3x-ui Panel:"
      colorized_echo green "────────────────────────────────────────"
      if [ "$IS_HTTPS_SECURED" = true ]; then
          colorized_echo green "🔗 URL:      https://${SECURED_DOMAIN}"
      else
          colorized_echo green "🔗 URL:      http://${public_ip}:${panel_port}"
      fi
      colorized_echo green "👤 Username: admin"
      colorized_echo green "🔑 Password: admin"
      colorized_echo green "────────────────────────────────────────"
      if [ "$IS_HTTPS_SECURED" = true ]; then
          colorized_echo blue "⚠️  IMPORTANT: Please change the default username and password immediately after your first login!"
      else
          colorized_echo blue "⚠️  IMPORTANT: Please change the default username, password, and port immediately after your first login!"
      fi
      echo
  ```

---

### Task 4: Verification

**Files:**
- Test execution on current system.

- [ ] **Step 1: Test run `3x-ui-docker.sh`**

  Propose and run a simulation or run the modified script directly.
  Verify if loopback binding is correct:
  ```bash
  ss -tulnp | grep :2053
  ```
  Verify Caddy container status:
  ```bash
  docker ps | grep caddy-3xui
  ```
