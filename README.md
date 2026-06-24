# 3x-ui Selfsteal — Stealthy Proxy Deployment Suite

Containerized deployment suite for **VLESS + xHTTP** proxy infrastructure using **Docker**, **Nginx**, and **3x-ui** (Xray-core). Optimized for bypassing Deep Packet Inspection (DPI) censorship, including Russia's TSPU "Siberian" behavioral module (June 2026).

> **Architecture**: Nginx terminates TLS on port 443 and forwards the `/xhttp` location over a Unix socket directly to Xray. Reality is deprecated in favor of xHTTP which disguises proxy traffic as standard HTTP/2 API calls.

---

## 📦 Components

| Script | Purpose |
|---|---|
| `src/sysprep.sh` | System updates, BBR/TCP tuning, swap setup, SSH hardening |
| `src/dest/3x-ui-docker.sh` | Deploys 3x-ui panel in Docker with HTTPS reverse proxy |
| `src/dest/selfsteal.sh` | Deploys Nginx decoy + xHTTP socket routing + auto-configures Xray inbound |
| `src/netbird.sh` | NetBird WireGuard mesh VPN (for domestic/internal links only) |

---

## 🚀 Key Features

- **xHTTP Transport** — Splits proxy traffic into discrete HTTP/2 POST/GET chunks, indistinguishable from REST API traffic. Replaces Reality.
- **Nginx Edge** — Nginx terminates TLS on port 443. Unauthorized scanners see a decoy website. Legitimate clients hit the hidden `/xhttp` path.
- **Unix Socket Routing** — Nginx proxies xHTTP traffic over `/dev/shm/nginx-xhttp.socket` directly to Xray. Zero Docker bridge overhead.
- **Auto-configured Xray Inbound** — On install, `selfsteal` writes the VLESS xHTTP inbound directly into the 3x-ui SQLite database.
- **11 Decoy Templates** — Professional decoy websites downloaded and installed per-template.
- **Anti-Fingerprint Mutation** — Per-install CSS hue rotation and brand name mutation to prevent byte-identical template signatures.
- **Secure Panel Proxy** — 3x-ui panel bound to `127.0.0.1:2053`, exposed via Nginx HTTPS on port 443 at the panel subdomain.
- **Auto-Renewing SSL** — Let's Encrypt certificates via `acme.sh` using TLS-ALPN-01, with cron auto-renewal.

---

## 📁 Directory Structure

```
.
├── src/
│   ├── build.sh                  # Script bundler (inlines source directives)
│   ├── xhttp-client-import.json  # Default xHTTP inbound import template
│   ├── sysprep.sh                # System tuning script
│   ├── netbird.sh                # NetBird mesh VPN script
│   ├── 3x-ui-docker/             # 3x-ui panel source
│   ├── selfsteal/                # Nginx decoy source (modular)
│   ├── common/                   # Shared helpers (logging, docker, firewall)
│   └── dest/                     # Compiled standalone scripts (gitignored)
│       ├── selfsteal.sh
│       └── 3x-ui-docker.sh
├── docs/
│   ├── dpi-research.md           # TSPU "Siberian" block research & workarounds
│   ├── multi-node-setup.md       # Multi-node 3x-ui star topology guide
│   ├── xhttp-bulletproof-config.md  # xHTTP anti-DPI parameter reference
│   ├── testing-guide.md          # Manual test commands
│   └── references/               # Cloned Xray-docs, Xray-examples, 3x-ui source
├── tests/
│   └── run_tests.sh              # Integration test suite
├── Makefile
└── README.md
```

---

## 🛠️ Installation

> [!NOTE]
> All scripts require `root`. Run directly as root or via `make`.

### Step 1 — Build Compiled Scripts
```bash
make build
```

### Step 2 — System Pre-setup (Optional but Recommended)
```bash
make sysprep
```
Sets up swap, BBR congestion control, TCP Fast Open, SSH hardening.

### Step 3 — Deploy 3x-ui Panel
```bash
make 3x-ui ARGS="--secure --domain panel.yourdomain.com --force"
```

| Flag | Description |
|---|---|
| `--secure` | Enable HTTPS reverse proxy for the panel |
| `--domain` | Panel subdomain (must have valid DNS + certificate) |
| `--force` | Skip DNS validation |

Panel access after install: `https://panel.yourdomain.com` (default credentials: `admin` / `admin` — change immediately)

### Step 4 — Deploy Nginx Selfsteal Decoy
```bash
make selfsteal ARGS="--force --domain filecloud.yourdomain.com --template 5"
```

| Flag | Description |
|---|---|
| `--force` | Skip DNS validation and prompts |
| `--domain` | Public domain for the decoy site |
| `--template <1-11>` | Decoy website template number |
| `--ssl-cert` / `--ssl-key` | Use existing certificate instead of ACME |
| `--no-randomize` | Skip per-install template mutation |

On success, the xHTTP inbound is **automatically written** to the 3x-ui database. Copy the printed JSON from the install output and import it into the 3x-ui panel if needed.

---

## 🎨 Decoy Templates

| # | Name | Description |
|---|---|---|
| 1 | 😂 10gag | Meme site |
| 2 | 📁 Convertit | File converter |
| 3 | 🎬 Converter | Video studio converter |
| 4 | ⬇️ Downloader | File downloader |
| 5 | ☁️ FileCloud | Cloud storage |
| 6 | 🎮 Games-site | Retro gaming portal |
| 7 | 🛠️ ModManager | Game mod manager |
| 8 | 🚀 SpeedTest | Internet speedtest |
| 9 | 📺 YouTube | Video hosting with captcha |
| 10 | ⚠️ 503 Error v1 | Maintenance error page |
| 11 | ⚠️ 503 Error v2 | Maintenance error page (alt) |

---

## 🌐 Architecture

```
User Client
    │  VLESS + xHTTP over TLS
    ▼
Nginx (port 443)  ──── decoy site ────▶  Unauthorized Scanner
    │  /xhttp location
    │  grpc_pass → Unix Socket
    ▼
/dev/shm/nginx-xhttp.socket
    │
    ▼
Xray (3x-ui)  ──▶  Internet
```

**Nginx config key directives:**
- `grpc_pass grpc://unix:/dev/shm/nginx-xhttp.socket` — HTTP/2 native passthrough
- `client_max_body_size 0` — prevents Nginx killing large upload streams
- `client_body_timeout 5m` / `grpc_read_timeout 315s` — stream longevity

---

## 🧪 Testing

```bash
make test
```

The integration test suite (`tests/run_tests.sh`) verifies:
1. Docker containers (`nginx-selfsteal`, `3xui_app`) are running
2. SQLite database has the `xhttp-inbound` config and `user-xhttp` client
3. Unix socket `/dev/shm/nginx-xhttp.socket` exists and is live
4. Nginx HTTP/2 POST to `/xhttp` path returns `404` (correct Xray backend signature)
5. Panel HTTPS proxy is reachable
6. **Headless Xray client** opens SOCKS5 tunnel → sends request through VLESS+xHTTP → verifies HTTP 200 roundtrip

---

## 📡 Client Configuration

After install, the panel outputs the importable inbound JSON. Key parameters:

```json
{
  "network": "xhttp",
  "security": "none",
  "xhttpSettings": {
    "path": "/api/v1/assets/logo.png",
    "mode": "packet-up",
    "sessionIDPlacement": "path",
    "enableXmux": true,
    "noSSEHeader": true,
    "noGRPCHeader": true,
    "xPaddingBytes": "100-800"
  }
}
```

> [!IMPORTANT]
> `sessionIDPlacement` is set to `"path"` for compatibility with standard clients (v2rayN, Shadowrocket, etc.) that don't support header-based session IDs on standard link imports.

---

## 📚 Further Reading

- [`docs/dpi-research.md`](docs/dpi-research.md) — TSPU "Siberian" behavioral block analysis and workarounds
- [`docs/xhttp-bulletproof-config.md`](docs/xhttp-bulletproof-config.md) — Full xHTTP anti-DPI parameter reference
- [`docs/multi-node-setup.md`](docs/multi-node-setup.md) — Multi-node star topology with 3x-ui
- [`docs/references/`](docs/references/) — Official Xray-docs and Xray-examples clones
