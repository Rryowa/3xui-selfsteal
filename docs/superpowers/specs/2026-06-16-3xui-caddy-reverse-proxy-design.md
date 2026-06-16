# 3x-ui Panel Reverse Proxy with Caddy

This document specifies the design for adding an interactive Caddy reverse proxy configuration to the `3x-ui-docker.sh` panel deployment script.

---

## 1. Requirements & Goal

Currently, the `3x-ui-docker.sh` script deploys the 3x-ui panel without HTTPS encryption or dedicated domain handling. It is also exposed on public interfaces, making it open to scan probes and censorship triggers.

To resolve this:
- We will prompt the user to optionally install a Caddy reverse proxy for their panel.
- Caddy will run in Docker and automatically manage SSL certificates via Let's Encrypt / ZeroSSL.
- To prevent direct public access via HTTP on the raw port (e.g. `2053`), the panel will be configured to bind exclusively to `127.0.0.1` inside the SQLite database.
- Caddy will route the traffic on ports 80/443 directly to the local port on `127.0.0.1`.

---

## 2. Directory Layout & Architecture

Both the 3x-ui panel and the Caddy reverse proxy containers will run in `network_mode: host`. This allows Caddy to communicate with the panel directly via `127.0.0.1` and avoids complex bridge network mapping.

```
/opt/3x-ui/
├── db/
│   └── x-ui.db              # 3x-ui database (settings modified)
├── cert/                    # Panel certificates (if any)
├── backups/                 # Backups
├── docker-compose.yml       # 3x-ui compose configuration
└── caddy/
    ├── docker-compose.yml   # Caddy compose configuration
    ├── Caddyfile            # Caddy routing configuration
    └── .env                 # Caddy environment variables
```

---

## 3. Detailed Component Spec

### A. Main Installer Script Flow (`3x-ui-docker.sh`)
- Normal installation steps run first.
- The script checks if port `80` and `443` are free before prompting.
- The script prompts:
  `Do you want to configure a Caddy reverse proxy with SSL? (y/n): `
- If **Yes**:
  1. Ask for the panel domain (e.g., `panel.example.com`).
  2. Validate the domain format and perform DNS check (ensure it resolves to the server's public IP).
  3. Modify the 3x-ui settings database `/opt/3x-ui/db/x-ui.db` to set `webListen = 127.0.0.1`.
  4. Create `/opt/3x-ui/caddy/` structure: `docker-compose.yml`, `Caddyfile`, and `.env`.
  5. Start Caddy (`docker compose up -d` in `/opt/3x-ui/caddy`).
  6. Restart 3x-ui (`docker compose restart` in `/opt/3x-ui`).
  7. Print connection details pointing to the new HTTPS URL.

### B. SQLite Database Update
To hide the raw port, we will insert or update the `webListen` key in the database:
```bash
sqlite3 /opt/3x-ui/db/x-ui.db "INSERT OR REPLACE INTO settings (key, value) VALUES ('webListen', '127.0.0.1');"
```
*(If sqlite3 is not installed on the host, the script will install it automatically via the system package manager).*

### C. Caddy Files

#### Caddy docker-compose.yml (`/opt/3x-ui/caddy/docker-compose.yml`)
```yaml
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
```

#### Caddyfile (`/opt/3x-ui/caddy/Caddyfile`)
```caddy
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
```

#### Caddy Environment File (`/opt/3x-ui/caddy/.env`)
```ini
PANEL_DOMAIN=panel.example.com
PANEL_PORT=2053
```

---

## 4. Verification Plan

### Automated Checks
- The script should validate domain DNS resolution using `dig` (checking if it resolves to host public IP).
- The script will test port availability for ports `80` and `443` before beginning Caddy installation.

### Manual Verification
- Verify that `ss -tulnp | grep :2053` shows binding ONLY to `127.0.0.1:2053`.
- Verify that accessing `http://YOUR_SERVER_IP:2053` fails.
- Verify that accessing `https://panel.example.com` works and presents the 3x-ui login page with a valid SSL certificate.
