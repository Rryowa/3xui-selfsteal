# 3x-ui & Nginx Selfsteal Proxy Deployment Suite

Stealthy VPN node deployment infrastructure utilizing **Docker**, **Nginx**, and **3x-ui** (Xray-core) optimized for bypassing Deep Packet Inspection (DPI) censorship.

---

## 📦 Project Components

1. **System Pre-setup (`sysprep.sh`)**: Performs system updates, swap setup, time synchronization, SSH hardening, and kernel tuning (BBR, TCP Fast Open, buffer tuning).
2. **3x-ui Docker Panel (`3x-ui-docker.sh`)**: Sets up the Xray management web panel in host network mode (with optional HTTPS reverse proxy).
3. **Nginx Selfsteal (`selfsteal.sh`)**: Sets up Nginx as a Reality decoy server.
4. **NetBird VPN (`netbird.sh`)**: Configures encrypted mesh networking via WireGuard.

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
│   ├── 3x-ui-docker/         # 3x-ui configuration source
│   ├── dest/                 # Compiled standalone scripts (gitignored)
│   │   ├── selfsteal.sh
│   │   └── 3x-ui-docker.sh
│   └── build.sh              # Script builder utility
├── sysprep.sh                # System pre-setup (BBR tuning, swap, updates)
├── netbird.sh                # NetBird mesh VPN setup script
└── Makefile                  # Project build commands
```

---

## 🛠️ How to Run

> [!NOTE]
> All deployment scripts validate that the user is running as `root` firstly. Therefore, you do not need to prepend `sudo` to the commands; run them directly as `root` or using `make`.

### Quick Install (Complete Setup)
To compile, run the system tuner, deploy the 3x-ui panel, and set up Nginx decoy:
```bash
make install-all
```

---

### Step-by-Step Installation

#### 1. Compile Standalone Scripts
```bash
make build
```

#### 2. Pre-setup System (BBR, Swap, Updates)
```bash
make install-sysprep
```

#### 3. Deploy 3x-ui Panel
```bash
make install-3x-ui
```

#### 4. Deploy Nginx Decoy (Interactive)
```bash
make install-selfsteal
```
*Alternatively, run in non-interactive force mode:*
```bash
make install-selfsteal ARGS="--force --domain your-domain.com"
```

---

## 🧪 How to Test

### 1. Run Staging Test Install
Uses Let's Encrypt staging environment to bypass API rate limits:
```bash
./src/dest/selfsteal.sh --domain your-domain.com --test --force install
```

### 2. Check Service Status
```bash
./src/dest/selfsteal.sh status
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
