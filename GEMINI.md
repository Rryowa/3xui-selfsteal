# Project Onboarding & Active DPI Research (GEMINI.md)

This document is compiled as an automated developer onboarding guide and a quick-reference knowledge base. It details what this project is, how it functions, and the technical insights regarding bypass architectures for Deep Packet Inspection (DPI) censorship (specifically targeted at the Russian TSPU restrictions of June 2026).

---

## 1. Project At-a-Glance
This repository is a containerized infrastructure suite designed to deploy stealthy proxy panels and VPN nodes using Docker. 

### Core Components
1.  **3x-ui Docker Panel (`src/dest/3x-ui-docker.sh`):** Installs the `ghcr.io/mhsanaei/3x-ui` panel. This web panel runs Xray-core in the background and dynamically manages inbounds (VLESS, VMess, Trojan, Shadowsocks) stored in a SQLite database (`/opt/3x-ui/db/x-ui.db`).
2.  **Nginx Selfsteal (`src/dest/selfsteal.sh`):** Sets up Nginx as a "Reality" decoy server. It templates professional decoy sites (YouTube, converters, speedtests) to present to unauthorized scanners.
3.  **NetBird mesh VPN (`netbird.sh`):** Sets up an encrypted mesh networking tunnel via WireGuard between server nodes.

### Essential Networking Setup
*   **Host Networking:** Both the 3x-ui and Nginx decoy containers run with `network_mode: "host"`. They share the host system's loopback and network namespaces, bypassing Docker bridge isolations.
*   **Reality Redirection:** Xray binds to public port `443`. Legitimate clients with authentic keys connect. Scanner probes or unauthorized requests are silently redirected internally to `127.0.0.1:47443` or `/dev/shm/nginx.sock`, where Nginx serves the decoy site to camouflage the server.
*   **Nginx Panel Proxy:** Nginx also acts as a secure HTTPS reverse proxy for the 3x-ui web panel, listening on port `8443` and forwarding to local port `2053` (which is secured by binding it to loopback only).
*   **NetBird Limit:** Because NetBird uses standard WireGuard over UDP, it will be blocked or throttled by border-level DPI. Thus, it cannot be used for cross-border links in censored regions.

---

## 2. Running the Project Locally
Run these commands with root privileges to deploy components:

```bash
# 1. Run complete installation sequentially (Recommended)
make install-all

# Alternatively, run components individually:
# - Run system pre-setup and BBR/TCP tuning:    make install-sysprep
# - Deploy 3x-ui Panel Docker container:         make install-3x-ui
# - Deploy Nginx decoy templates (Selfsteal):   make install-selfsteal
# - Deploy NetBird VPN interactive mesh menu:    make install-netbird
```

---

## 3. High-Stealth Evasion: The Xray Bridge Meta
To cross heavily censored borders (e.g. Russia's international gateway), configure an **Xray-to-Xray Bridge** without relying on WireGuard/NetBird:

```
User ➔ [VLESS + TCP + Vision] ➔ Domestic VPS (Bridge) ➔ [VLESS + xHTTP] ➔ Exit VPS (Europe) ➔ Internet
```

1.  **Domestic Hop (User to Domestic VPS):** Uses VLESS + xtls-rpx-vision because it is fast, lightweight, and domestic connections face less DPI sorting.
2.  **Cross-Border Hop (Domestic VPS to Exit VPS):** Uses VLESS + xHTTP. It splits proxy traffic into discrete HTTP/2 or HTTP/3 chunked requests, mimicking REST API or assets downloads, surviving the most aggressive border filters.
3.  **Relay Logic:** Configure the inbound on the Bridge VPS, add a VLESS outbound pointing to the Exit VPS, and map them using Xray's routing rules inside the 3x-ui panel.

---

## 4. Active DPI Research: The "Siberian Block" (June 2026)
Investigations from Russian network forums (such as Habr and ntc.party) confirm the details of the active TSPU behavioral module:

*   **Logical AND Checking:** Blocking triggers when a connection meets three criteria:
    1.  **Suspicious Destination Subnets:** IP belongs to foreign datacenters (Hetzner, OVH, DO) or domestic Russian cloud providers (Selectel, FirstVDS, Yandex.Cloud) used for relays.
    2.  **Fingerprint Match:** Connection uses uTLS Chrome/Safari/iOS signatures, or standard Go/Rust networking fingerprints that do not match live browser timing behaviors.
    3.  **Parallel Connection Spikes:** The client makes **more than 3 parallel TLS connections** to the same SNI in a short window (<350-400 ms).
*   **The Penalty:** If triggered, the TSPU silently truncates the TLS handshake payload. It allows the first TCP segment of Chrome's ClientHello (~1800 bytes) to pass but discards all subsequent segments. The server hangs, resulting in client `i/o timeouts`.
*   **The Trap:** If a client immediately retries or rotates fingerprints under load, the system issues a **600-second extended block** across all TLS handshakes to that destination IP.

---

## 5. Verified DPI Workarounds

### A. Chrome Flag Bypass (CNSA)
If a user cannot load legitimate sites hosted on blocked subnets:
*   Navigate to `chrome://flags/` in Chrome.
*   Enable **Cryptography Compliance (CNSA)** (`#cryptography-compliance-cnsa`).
*   This shifts the cipher sorting to prioritize NSA-compliant suites, altering Chrome's ClientHello signature and bypassing the block.

### B. Blank SNI
*   Leaving the SNI blank or removing it from the TLS handshake bypasses the behavioral counters on some ISPs, since the rule relies on tracking traffic patterns per SNI.

---

## 6. Architectural Rules & Anti-Patterns (Golden Rules)
To prevent recurrent misconfigurations, adhere strictly to these architectural boundaries:

### Rule 1: Never Mix Reality and xHTTP
*   **Anti-Pattern:** Attempting to configure an inbound with `network: xhttp` and `security: reality` on the same port.
*   **Why:** They inherently conflict over port 443 ownership. 
    *   **Reality** requires Xray to bind to port 443 and terminate the TLS handshake itself, proxying unauthorized traffic to Nginx.
    *   **xHTTP** behind Nginx requires Nginx to bind to port 443, terminate TLS, and proxy the `/xhttp` path back to Xray. 

### Rule 2: Nginx xHTTP Reverse Proxy Requires `grpc_pass`
*   **Anti-Pattern:** Using `proxy_pass http://127.0.0.1:port` or `Upgrade: websocket` headers for the `/xhttp` location block.
*   **Why:** xHTTP relies heavily on HTTP/2 multiplexing and chunked streaming. `proxy_pass http://` forces a downgrade to HTTP/1.1, destroying native multiplexing. Fake WebSocket upgrade headers break the stream. 
*   **Fix:** Always use `grpc_pass grpc://` (or `unix:` socket) to natively handle HTTP/2 framing, and disable buffering.
*   **Critical Directives:** Nginx must include `client_max_body_size 0;` (to prevent Nginx from abruptly killing large upload streams) and extended timeouts (`client_body_timeout 5m; grpc_read_timeout 315s;`).

### Rule 3: Do Not Rely on Mux/XMUX for DPI Evasion
*   **Anti-Pattern:** Advising users to simply "Enable Mux/XMUX" in standard VLESS clients to bypass the 3-parallel-connection Siberian Block.
*   **Why:** Outer Mux layers can leak recognizable protocol signatures. 
*   **Fix:** For bulletproof connections, rely on xHTTP's native internal `xmux` properties, randomized chunking (`uplinkChunkSize`, `scMaxEachPostBytes`), and forced artificial delays (`scMinPostsIntervalMs`) as documented in `docs/xhttp-bulletproof-config.md`.
