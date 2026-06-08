# 3x-ui and VPN Deploy Scripts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Shell](https://img.shields.io/badge/language-Bash-blue.svg)](#)
[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](#)

![remnawave-script](remnawave-script.webp)

> **TL;DR:** One-liner scripts to deploy and manage **3x-ui Panel (Docker)**, **NetBird VPN**, and **Reality traffic masking (Selfsteal)** via Docker. Includes UNIX socket sharing, ACME.sh certificates, and randomized static decoy sites.

---

## 🚀 Quick Start

```bash
# 3x-ui Panel (Docker Edition)
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/3x-ui-docker.sh)

# Reality Selfsteal (Decoy server)
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh) @ install
```

---

## 📦 What's Included

| Script | Purpose | Install Command |
|--------|---------|----------------|
| **3x-ui-docker.sh** | 3x-ui Panel installer | `3x-ui-docker.sh` |
| **selfsteal.sh** | Reality traffic masking | `selfsteal <command>` |
| **netbird.sh** | NetBird VPN installer | `netbird.sh <command>` |

**Key features across all scripts:** auto-updates, interactive menus, Docker Compose v2, UNIX socket sharing.

---

## ⚡ 3x-ui Docker Panel

Installer for **3x-ui** Docker Edition with host network mode and UNIX socket support.

### Installation

```bash
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/3x-ui-docker.sh)
```

### Highlights

- **SQLite Database Preservation** — automatically migrates and preserves existing standalone x-ui database if found at `/etc/x-ui/x-ui.db`.
- **UNIX Socket Configuration** — mounts `/dev/shm` to share Unix sockets with Nginx Selfsteal container for stealthy proxying.
- **Port Conflict Checks** — verifies port availability (`80`, `443`, `2053`) before launching container.

<details>
<summary><b>📂 File Structure</b></summary>

```text
/opt/3x-ui/
├── docker-compose.yml
├── db/                   # SQLite database
├── cert/                 # Certificates
└── backups/              # Backups
```

</details>

---

## 🎭 Caddy Selfsteal (Reality Masking)

Deploy Caddy as a **Reality traffic masking** solution with professional website templates for HTTPS camouflage.

### Installation

```bash
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh) @ install
```

### Commands

| Command | Description |
|---------|-------------|
| `install` / `uninstall` | Install or remove |
| `up` / `down` / `restart` | Service lifecycle |
| `status` / `logs` | Status & logs |
| `template` | Manage website templates |
| `edit` | Edit Caddyfile |
| `guide` | Reality integration guide |
| `update` | Update script |

### Templates

8 pre-built website templates: `10gag`, `converter`, `downloader`, `filecloud`, `games-site`, `modmanager`, `speedtest`, `YouTube`.

```bash
selfsteal template list              # List templates
selfsteal template install converter # Install template
```

> 🛡️ **v2.8.0:** every template is uniquified per install (no byte-identical fingerprint) and provenance leaks are stripped. HTTP/3 is **off by default** — enable with `--h3`; disable mutation with `--no-randomize`. See [README-selfsteal.md](README-selfsteal.md).

**Xray Reality config:**
```json
{ "realitySettings": { "dest": "127.0.0.1:9443", "serverNames": ["your-domain.com"] } }
```

<details>
<summary><b>📂 File Structure</b></summary>

```text
/opt/caddy/
├── .env, docker-compose.yml, Caddyfile
├── logs/
└── html/           # Template content
    ├── index.html, 404.html
    └── assets/

/usr/local/bin/selfsteal
```

</details>

---

## ⚙️ System Requirements

| | Minimum | Recommended |
|---|---------|-------------|
| **CPU** | 1 core | 2+ cores |
| **RAM** | 512 MB | 2 GB+ |
| **Storage** | 2 GB | 10 GB+ SSD |
| **Network** | Stable | 100 Mbps+ |

**OS:** Ubuntu 18.04+, Debian 10+, CentOS 7+, AlmaLinux 8+, Fedora 32+, Arch, openSUSE 15+

**Dependencies** (auto-installed): Docker Engine, Docker Compose V2, curl, openssl, jq, tar/gzip

---

## 🔐 Security

- Services bind to `127.0.0.1` by default
- Auto-generated DB credentials, JWT secrets, API tokens
- UFW/firewalld guidance during setup
- SSL/TLS via Caddy with DNS validation

<details>
<summary><b>🔒 Production Hardening</b></summary>

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow from trusted_ip to any port panel_port
sudo ufw enable
```

</details>

---

## 📊 Monitoring & Logs

```bash
selfsteal status   # Service status
selfsteal logs     # Real-time logs
docker stats       # Resource usage
```

<details>
<summary><b>📋 Log Locations</b></summary>

| Component | Path |
|-----------|------|
| 3x-ui Panel | `/opt/3x-ui/backups/` |
| Caddy / Nginx | `/opt/caddy/logs/` or `/opt/nginx-selfsteal/logs/` |

Log rotation: 50MB max, 5 files kept, compressed automatically.

</details>

---

## 🧩 Other Scripts

This repository also includes additional utility scripts for network management and VPN setup.

### 🐦 NetBird — VPN Installer

Quick installer for [NetBird](https://netbird.io/) mesh VPN. Supports CLI, cloud-init, interactive menu, and Ansible modes.

```bash
# CLI installation
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/netbird.sh) install --key YOUR-SETUP-KEY

# Auto-install for cloud-init / provisioning
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/netbird.sh) init --key YOUR-SETUP-KEY

# Interactive menu
bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/netbird.sh) menu
```

Key features: one-liner install, SSH access between peers (`--ssh`), auto-firewall setup (UFW/firewalld), Ansible-friendly mode.

📖 Full documentation: [README-netbird.md](./README-netbird.md)

---

## 🤝 Contributing

1. Fork → branch → make changes → test → PR
2. Follow existing code style, test on multiple distros
3. Check [existing issues](https://github.com/DigneZzZ/remnawave-scripts/issues) before reporting bugs

---

## 📜 License

[MIT License](./LICENSE) — free for commercial and private use.

---

<div align="center">

**⭐ Star this project if you find it useful!**

[Report Bug](https://github.com/DigneZzZ/remnawave-scripts/issues) · [Request Feature](https://github.com/DigneZzZ/remnawave-scripts/issues) · [Community: gig.ovh](https://gig.ovh)

</div>
