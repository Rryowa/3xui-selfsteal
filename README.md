# 3x-ui & Nginx Selfsteal Proxy Deployment Suite

Stealthy VPN node deployment infrastructure utilizing **Docker**, **Nginx**, and **3x-ui** (Xray-core) optimized for bypassing Deep Packet Inspection (DPI) censorship.

---

## 📦 Project Components

1. **3x-ui Docker Panel (`3x-ui-docker.sh`)**: Sets up the Xray management web panel in host network mode.
2. **Nginx Selfsteal (`selfsteal.sh`)**: Sets up Nginx as a Reality decoy server and secure reverse proxy.
3. **NetBird VPN (`netbird.sh`)**: Configures encrypted mesh networking via WireGuard.

---

## 🚀 Key Features

* **Reality Masking**: Directs unauthorized probes from port 443 to Nginx via Unix socket `/dev/shm/nginx.sock` or TCP port `47443`.
* **AI-Generated Decoys**: 11 unique website templates used for HTTPS masking.
* **Anti-Fingerprinting**: Automatically mutates template files, CSS colors, HTML headers, and assets per-install to avoid byte-identical signature tracking.
* **Secure Panel Reverse Proxy**: Locks the 3x-ui database `webListen` to `127.0.0.1`. Proxies encrypted admin traffic through Nginx on port `8443` to the panel.
* **Auto-Renewing SSL**: Built-in Let's Encrypt certificates management via `acme.sh` using TLS-ALPN-01 challenge.

---

## 📁 Directory Structure

```
.
├── src/                      # Modular script source files
│   ├── selfsteal/            # Nginx/SSL configuration scripts
│   ├── common/               # Core helpers (Docker, logging, firewall)
│   └── build.sh              # Script builder utility
├── dist/                     # Compiled scripts output
│   └── selfsteal.sh          # Compiled standalone selfsteal script
├── 3x-ui-docker.sh           # 3x-ui deployment script
├── netbird.sh                # NetBird mesh VPN setup script
└── Makefile                  # Project build commands
```

---

## 🛠️ How to Run

### 1. Compile Standalone Script
```bash
make build
```

### 2. Deploy 3x-ui Panel
```bash
sudo bash ./3x-ui-docker.sh
```

### 3. Deploy Nginx Decoy & Panel Proxy (Interactive)
```bash
sudo ./dist/selfsteal.sh install
```
*Alternatively, run in non-interactive force mode:*
```bash
sudo ./dist/selfsteal.sh --force --domain your-domain.com install
```

---

## 🧪 How to Test

### 1. Run Staging Test Install
Uses Let's Encrypt staging environment to bypass API rate limits:
```bash
sudo ./dist/selfsteal.sh --domain your-domain.com --test --force install
```

### 2. Check Service Status
```bash
sudo ./dist/selfsteal.sh status
```

### 3. Verify Panel Proxy (GET)
Verify that Nginx successfully reverse-proxies the panel on port 8443:
```bash
curl -k -s -o /dev/null -w "%{http_code}\n" --resolve your-domain.com:8443:127.0.0.1 https://your-domain.com:8443/
```
*(Note: 3x-ui returns `404` for `HEAD` requests. Avoid curl -I (which sends HEAD).)*

### 4. Verify Docker Socket Mounting
Verify the socket is reachable inside the container:
```bash
docker exec 3xui_app ls -la /dev/shm/nginx.sock
```

---

## ⚙️ Xray Reality Configuration

Add this inbound to your Xray / 3x-ui configuration:

```json
{
  "listen": "0.0.0.0",
  "port": 443,
  "protocol": "vless",
  "settings": {
    "clients": [],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "dest": "/dev/shm/nginx.sock",
      "xver": 1,
      "serverNames": ["your-domain.com"],
      "privateKey": "YOUR_PRIVATE_KEY",
      "shortIds": ["YOUR_SHORT_ID"]
    }
  }
}
```
