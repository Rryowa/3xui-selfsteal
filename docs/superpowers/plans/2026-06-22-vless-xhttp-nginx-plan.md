# VLESS + xHTTP Behind Nginx & DB Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 3x-ui VLESS connection timeouts by introducing a new `--xhttp` mode that configures Nginx-terminated SSL proxying and ensures client traffic tracking records are correctly initialized in the SQLite database.

**Architecture:** We add a `--xhttp` argument to `selfsteal.sh` that switches from direct Reality redirection to an Nginx HTTPS reverse proxy configuration. It creates an Nginx server configuration on port 443 that proxies the `/xhttp` route to a local unencrypted Xray port. It also inserts the necessary matching tracking record into the `client_traffics` table to prevent 3x-ui from evicting the client.

**Tech Stack:** Bash, Nginx, SQLite3, Xray-core, Docker

---

### Task 1: Update CLI Arguments & Help in `src/selfsteal/main.sh`

**Files:**
- Modify: `src/selfsteal/main.sh:90-100` (declare `USE_XHTTP=false`)
- Modify: `src/selfsteal/main.sh:150-165` (add `--xhttp` to help menu)
- Modify: `src/selfsteal/main.sh:248-265` (parse `--xhttp` argument)

- [ ] **Step 1: Declare USE_XHTTP variable**
  Modify lines around 90 in [main.sh](file:///root/3xui-selfsteal/src/selfsteal/main.sh#L90-L95) to declare the boolean variable:
  ```bash
  # Socket Configuration (Nginx only)
  # By default uses Unix socket for better performance
  # Use --tcp flag to switch to TCP port
  USE_SOCKET=true
  SOCKET_PATH="/dev/shm/nginx.sock"
  USE_XHTTP=false
  ```

- [ ] **Step 2: Add flag to the help output**
  Modify lines around 156 in [main.sh](file:///root/3xui-selfsteal/src/selfsteal/main.sh#L156-L161) to document the new option:
  ```bash
  echo -e "${WHITE}Options:${NC}"
  printf "   ${CYAN}%-22s${NC} %s\n" "--socket" "Use Unix socket (default)"
  printf "   ${CYAN}%-22s${NC} %s\n" "--tcp" "Use TCP port instead of socket"
  printf "   ${CYAN}%-22s${NC} %s\n" "--xhttp" "Use VLESS+xHTTP reverse proxy mode (no Reality)"
  ```

- [ ] **Step 3: Add parser rule in argument loop**
  Modify lines around 250 in [main.sh](file:///root/3xui-selfsteal/src/selfsteal/main.sh#L250-L260) to parse the `--xhttp` argument and override `USE_SOCKET`:
  ```bash
          --tcp)
              # Use TCP port instead of Unix socket
              USE_SOCKET=false
              shift
              ;;
          --xhttp)
              # Use VLESS+xHTTP behind Nginx (no Reality)
              USE_XHTTP=true
              USE_SOCKET=false
              shift
              ;;
          --socket)
  ```

- [ ] **Step 4: Verify parsing syntax and build**
  Run: `make build && bash -n src/dest/selfsteal.sh`
  Expected: Builds without errors and bash syntax validation passes.

- [ ] **Step 5: Commit changes**
  ```bash
  git add src/selfsteal/main.sh
  git commit -m "feat: parse --xhttp argument and document in help menu"
  ```

---

### Task 2: Implement Nginx configuration templating for xHTTP reverse proxy

**Files:**
- Modify: `src/selfsteal/main.sh:1058-1065` (add Nginx config generation conditional)

- [ ] **Step 1: Add Nginx reverse proxy configuration generation**
  Modify the site configuration generation logic in [main.sh](file:///root/3xui-selfsteal/src/selfsteal/main.sh#L1058-L1065) to inject the VLESS-xHTTP configuration block when `USE_XHTTP=true`:
  ```bash
      # Create site configuration based on socket, TCP, or xHTTP mode
      if [ "$USE_XHTTP" = true ]; then
          # VLESS-xHTTP reverse proxy configuration
          cat > "$APP_DIR/conf.d/selfsteal.conf" << EOF
  # HTTP server - redirect and ACME challenge
  server {
      listen 80 default_server;
      listen [::]:80 default_server;
      server_name \$domain;
      
      # ACME challenge for Let's Encrypt certificate renewal
      location /.well-known/acme-challenge/ {
          root /var/www/html;
          try_files \\\$uri =404;
      }
      
      # Redirect all other traffic to HTTPS
      location / {
          return 301 https://\\\$host\\\$request_uri;
      }
  }

  # HTTPS server - Nginx on port 443 with TLS termination
  server {
      listen 443 ssl http2;
      listen [::]:443 ssl http2;
      server_name \$domain;

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

      # Logging
      access_log /var/log/nginx/access.log;
      error_log /var/log/nginx/error.log warn;

      # Root directory for decoy site
      root /var/www/html;
      index index.html index.htm;

      # Security headers
      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-XSS-Protection "1; mode=block" always;

      # VLESS-XHTTP routing location block
      location /xhttp {
          proxy_redirect off;
          proxy_pass http://127.0.0.1:\$port;
          proxy_http_version 1.1;
          proxy_set_header Upgrade \\\$http_upgrade;
          proxy_set_header Connection "upgrade";
          proxy_set_header Host \\\$http_host;
          # Show real client IP in Xray
          proxy_set_header X-Real-IP \\\$remote_addr;
          proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;
      }

      # Standard decoy location block
      location / {
          try_files \\\$uri \\\$uri/ /index.html;
      }

      # Cache static files
      location ~* \\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)\$ {
          expires 30d;
          add_header Cache-Control "public, immutable";
      }
  }
  EOF
          log_success "Nginx site configuration created (VLESS-xHTTP reverse proxy)"
      elif [ "$USE_SOCKET" = true ]; then
  ```

- [ ] **Step 2: Verify code structure and compilation**
  Run: `make build && bash -n src/dest/selfsteal.sh`
  Expected: Compiles and checks syntax successfully.

- [ ] **Step 3: Commit changes**
  ```bash
  git add src/selfsteal/main.sh
  git commit -m "feat: implement Nginx conf templating for VLESS-xHTTP proxying"
  ```

---

### Task 3: Update SQLite database initialization to insert tracking row and handle xHTTP inbound settings

**Files:**
- Modify: `src/selfsteal/main.sh:1270-1300` (update inbound JSON and write `client_traffics` row)

- [ ] **Step 1: Rewrite inbound insertion and add user tracking registration**
  Replace the database insertion logic in `setup_default_inbound` at [main.sh](file:///root/3xui-selfsteal/src/selfsteal/main.sh#L1275-L1282) with the conditional inbound setup and multi-statement SQLite transaction:
  ```bash
              local remark="VLESS-REALITY"
              local tag="inbound-443"
              local listen="0.0.0.0"
              local bind_port=443
              local stream_settings_json="{\"network\":\"xhttp\",\"security\":\"reality\",\"externalProxy\":[],\"realitySettings\":{\"show\":false,\"xver\":1,\"dest\":\"/dev/shm/nginx.sock\",\"spiderX\":\"/\",\"serverNames\":[\"$domain\"],\"privateKey\":\"$priv_key\",\"minClient\":\"\",\"maxClient\":\"\",\"maxTimediff\":0,\"shortIds\":[\"$short_id\"]},\"xhttpSettings\":{\"mode\":\"auto\",\"host\":\"\",\"path\":\"/\"}}"
              
              if [ "$USE_XHTTP" = true ]; then
                  remark="VLESS-Nginx-XHTTP"
                  tag="inbound-xhttp"
                  listen="127.0.0.1"
                  bind_port="$port"
                  stream_settings_json="{\"network\":\"xhttp\",\"security\":\"none\",\"externalProxy\":[],\"xhttpSettings\":{\"mode\":\"auto\",\"host\":\"\",\"path\":\"/xhttp\",\"xPaddingBytes\":\"100-1000\",\"scMaxBufferedPosts\":30,\"scStreamUpServerSecs\":\"20-80\"}}"
              fi

              local settings_json="{\"clients\":[{\"id\":\"$uuid\",\"flow\":\"\",\"email\":\"admin@$domain\",\"limitIp\":0,\"totalGB\":0,\"expiryTime\":0}],\"decryption\":\"none\",\"fallbacks\":[]}"
              local sniffing_json="{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"],\"metadataOnly\":false,\"routeOnly\":false}"
              
              # Insert inbound record and retrieve newly created ID
              local inbound_id
              inbound_id=$(sqlite3 "$db_file" "INSERT INTO inbounds (user_id, up, down, total, remark, enable, expiry_time, traffic_reset, last_traffic_reset_time, listen, port, protocol, settings, stream_settings, tag, sniffing, node_id, origin_node_guid) VALUES (0, 0, 0, 0, '$remark', 1, 0, 'never', 0, '$listen', $bind_port, 'vless', '$settings_json', '$stream_settings_json', '$tag', '$sniffing_json', 0, ''); SELECT last_insert_rowid();")
              
              if [ -n "$inbound_id" ] && [[ "$inbound_id" =~ ^[0-9]+$ ]]; then
                  log_info "Updating client_traffics tracking record for inbound ID $inbound_id..."
                  sqlite3 "$db_file" "INSERT INTO client_traffics (inbound_id, enable, email, up, down, expiry_time, total, reset, last_online) VALUES ($inbound_id, 1, 'admin@$domain', 0, 0, 0, 0, 0, 0);"
              else
                  log_warning "Could not retrieve auto-created inbound ID. client_traffics table not updated."
              fi
  ```

- [ ] **Step 2: Update generated configuration link generation**
  Modify the `vless_link` logic at [main.sh](file:///root/3xui-selfsteal/src/selfsteal/main.sh#L1292-L1295):
  ```bash
              # Save link to config directory
              local vless_link
              if [ "$USE_XHTTP" = true ]; then
                  vless_link="vless://$uuid@$domain:443?security=tls&encryption=none&sni=$domain&type=xhttp&mode=auto&host=$domain&path=%2Fxhttp#VLESS-Nginx-XHTTP"
              else
                  vless_link="vless://$uuid@$domain:443?security=reality&encryption=none&sni=$domain&fp=chrome&pbk=$pub_key&sid=$short_id&spiderX=%2F&type=xhttp&mode=auto&host=$domain&path=%2F#VLESS-Reality-Selfsteal"
              fi
              mkdir -p "$APP_DIR"
              echo "$vless_link" > "$APP_DIR/vless.txt"
  ```

- [ ] **Step 3: Verify build and script syntax**
  Run: `make build && bash -n src/dest/selfsteal.sh`
  Expected: Completes without warning or syntax error.

- [ ] **Step 4: Commit database fixes**
  ```bash
  git add src/selfsteal/main.sh
  git commit -m "fix: insert matching client_traffics row and configure VLESS xHTTP settings"
  ```
