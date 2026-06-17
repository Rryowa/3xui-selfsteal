# Unified Research: DPI Evasion & Xray Bridge Architectures (June 2026 Russian Censorship Context)

This document aggregates all researched information, architectural blueprints, technical analyses, and community workarounds regarding current censorship evasion techniques under Russian Deep Packet Inspection (DPI) / TSPU (Technical Means of Countering Threats) as of June 2026.

---

## 1. Project Overview & Architecture
The repository [3xui-selfsteal](file:///root/3xui-selfsteal) is a deployment suite designed to spin up Docker-based VPN and proxy infrastructure. It consists of three primary modules:
1.  **3x-ui Docker Panel ([3x-ui-docker.sh](file:///root/3xui-selfsteal/3x-ui-docker.sh)):** A containerized web interface used to manage Xray inbounds (VLESS, VMess, Trojan, Shadowsocks) and dynamically generate configurations.
2.  **Nginx Selfsteal ([selfsteal.sh](file:///root/3xui-selfsteal/selfsteal.sh)):** Deploys an Nginx web server with professional decoy website templates (mimicking YouTube, speedtests, mod managers) to act as an HTTPS camouflage (decoy destination) on port `47443` or via Unix socket for Xray's Reality protocol.
3.  **NetBird VPN ([netbird.sh](file:///root/3xui-selfsteal/netbird.sh)):** Installs a WireGuard-based mesh VPN to securely connect multiple VPS instances or nodes.
 
### Networking Implementation:
*   Both the 3x-ui and Nginx Selfsteal containers run with `network_mode: "host"`.
*   This bypasses Docker's internal virtual network bridge (`docker0`), allowing both containers to share the host's loopback and network interface.
*   **The Reality Decoy Mechanism:** Xray binds to public port `443`. Legitimate VPN clients present the correct cryptographic key and connect. Active probes, firewalls, or regular internet traffic presenting an incorrect key are silently forwarded internally to `127.0.0.1:47443` (or via Unix socket at `/dev/shm/nginx.sock`), where Nginx serves the decoy site, effectively masking the proxy server.

---

## 2. Why NetBird (WireGuard) Fails in Heavy DPI Environments
While NetBird is useful for creating secure mesh connections between servers outside censored networks, it **fails in heavy DPI zones** (such as Russia) because:
*   The outer layer of the connection crossing the border is standard **UDP WireGuard traffic**.
*   Russian TSPU modules actively identify WireGuard handshakes and discard their packets.
*   Once the NetBird tunnel drops, the internal loopback interfaces (`100.x.x.x`) cannot communicate, breaking any relay.
*   **The Rule of DPI Evasion:** The outermost layer of packets crossing a hostile border must resemble normal HTTPS traffic (`TCP + TLS 1.3 / HTTP/2 / HTTP/3`).

---

## 3. The DPI-Resistant Xray Bridge Architecture
To circumvent border-level DPI without sacrificing performance, network engineers deploy a **two-hop Xray Bridge (Relay)** using different protocols for domestic and international segments.

```mermaid
graph LR
    User[User Client] -- "Domestic Hop (VLESS + TCP + Vision)" --> VPS1[RU VPS (Bridge)]
    VPS1 -- "Border Crossing (VLESS + xHTTP)" --> VPS2[EU VPS (Exit Node)]
    VPS2 --> Internet[Open Internet]
```

### The Logic Behind the Hop Division:
*   **Domestic Hop (User ➔ VPS1):** Since traffic remains inside the country, it is not subjected to border-level filters. It uses **VLESS + TCP + xtls-rpx-vision**, which has minimal CPU overhead and excellent latency.
*   **Cross-Border Hop (VPS1 ➔ VPS2):** This segment crosses the international border, where the heaviest DPI rules reside. It uses **VLESS + xHTTP** (formerly `SplitHTTP`), which chunks TCP/UDP proxy data into discrete HTTP/2 or HTTP/3 request-response streams. To a DPI firewall, this traffic is indistinguishable from standard API calls or browsing activities.
*   **Routing:** The bridge server (VPS1) runs 3x-ui and uses Xray routing rules to bind the incoming `user-inbound` traffic directly to the `vps2-outbound` interface.

---

## 4. Deep-Dive: Browser Dialer vs. NaiveProxy
When standard client-side TLS fingerprints (uTLS) fail, engineers compare two "maximum stealth" approaches.

### A. Browser Dialer (`XRAY_BROWSER_DIALER=1`)
*   **Mechanism:** Rather than trying to emulate browser TLS signatures (which are prone to signature detection discrepancies), Xray spawns a helper page and commands a **real browser** (like Chrome or Firefox) installed on the client machine to make connections using JavaScript (`fetch`/`WebSocket` APIs).
*   **Pros:** Generates a **100% genuine, unblockable TLS fingerprint** on the wire.
*   **Cons:** Extremely resource-heavy; requires keeping a dedicated browser tab open at all times; easily creates **infinite routing loops** if the system-wide VPN client routes browser traffic back into itself.
*   **Verdict:** Impractical for daily use; reserved as a last resort.

### B. NaiveProxy
*   **Mechanism:** NaiveProxy compiles the **actual Chromium network stack (`src/net`)** directly into its binary, using HTTP/2 `CONNECT` tunnels to talk to a Caddy server compiled with the `forwardproxy` plugin.
*   **Pros:** Because it uses Chrome's actual networking stack code, its handshakes, TCP window scaling, and HTTP headers are byte-for-byte identical to Google Chrome. Blocking its signature would mean blocking Chrome itself, which would break the web.
*   **Cons:** Does not support graphical panels like 3x-ui; requires manual server compilation of Caddy; client-side configuration requires raw JSON edits; consumes significant RAM.
*   **Verdict:** The gold standard of single-hop stealth if managed manually.

---

## 5. RKN "Siberian Block" Behavioral Rules (June 2026)
Investigations on Habr (Articles `1047442` and `1044396`) reveal the details of the latest TSPU behavioral module (nicknamed "Siberian"):

### The Logic:
The TSPU does not maintain a static blacklist of target IPs. Instead, it matches traffic against a **logical `AND` (intersection) of three criteria**:
1.  **ASN/Subnet:** Destination IP is in a "suspicious" range (overseas datacenters like Hetzner/OVH, and domestic cloud hosts like Selectel, Yandex.Cloud, Cloud.ru).
2.  **TLS ClientHello Fingerprint:** The connection uses a signature associated with uTLS emulators or standard Go/Rust networking libraries, which fail to mimic browser timing features.
3.  **Parallel Connection Spikes:** The client makes **more than 3 parallel TLS connections** to the exact same SNI in a short window (<350-400 ms or a 60-second window). This is standard for VLESS clients running connection pools.

### The Penalty:
*   Once triggered, the TSPU issues a **120-second silent packet drop (blackhole)** on the `(Client IP, SNI)` pair. 
*   The TCP handshake completes, but the subsequent TLS payloads (like Chrome's ~1800 byte ClientHello) are truncated by the TSPU—it lets the first TCP segment pass, but discards all subsequent segments. The server hangs waiting, leading to `read tcp: i/o timeout` on the client.
*   **The Trap:** If the client tries to immediately change the fingerprint under load, the TSPU issues an **extended 600-second block** across all TLS handshakes to that destination IP.

---

## 6. Infrastructure Outages: Stark Industries & nLighten
Two major European hosting events coincided with the June 2026 blocks but were separate physical incidents:
*   **Stark Industries Solutions Raid (May 22, 2026):** Dutch law enforcement (FIOD) raided physical datacenters in Almere and Amsterdam, seizing 800+ servers associated with Stark, WorkTitans, MIRhosting, and PQHosting over European sanction violations.
*   **nLighten Datacenter Power Cut (June 2, 2026):** nLighten cut power to server racks in Almere rented by MIRhosting. This abruptly knocked out physical virtual servers for popular budget VPS providers (VDSina, McHost, THE.Hosting, GEO.Hosting, UFO.Hosting), which users mistook for RKN blocks.

---

## 7. Verified Workarounds & Evasion Methods

### A. The Chrome CNSA Flag Bypass (For legitimate sites)
For users who cannot open legitimate web resources hosted on Selectel/TimeWeb due to fingerprint blocks:
1.  Open `chrome://flags/` in Chrome.
2.  Search for **Cryptography Compliance (CNSA)** (`#cryptography-compliance-cnsa`) and set it to **Enabled**.
3.  This forces Chrome to prioritize NSA-standard ciphers, reshuffling the ClientHello fingerprint so that the TSPU no longer recognizes it as a blocked "Google Chrome" pattern.

### B. VLESS Client Connection Tuning (Mux / XMUX)
*   Standard VLESS clients open connection pools on start. To avoid triggering the "3 parallel connections" limit, users must enable **Mux** or **XMUX** in their GUI clients (such as sing-box, Nekobox, or v2rayNG).
*   Mux multiplexes all user traffic over a single TCP socket, preventing connection spikes.

### C. 3x-ui v3.x Parameter Issues
*   Upgrading to 3x-ui v3.x has caused immediate blocking for many.
*   **Reason:** v3.x automatically injects two hidden parameters into the Xray configuration: `scMaxEachPostBytes: 1000000` and `scMinPostsIntervalMs: 30`, which trigger the TSPU's fingerprint blacklist.
*   **Solution:** Downgrade to `v2.9.4` or edit the 3x-ui advanced config template to strip these two lines manually.

### D. Blank SNI
*   TSPU rules rely on parsing the Server Name Indication (SNI) string. In configurations where an **empty/blank SNI** can be passed (or where direct routing does not require SNI mapping), the filter rules fail to evaluate the parallel handshake counter, bypassing the block.

---

## 8. The "Sophone Effect" (Софонный Эффект)
A major critique from Russian network engineers (based on Liu Cixin's *The Three-Body Problem*) points out that the TSPU's silent drop mechanism acts as a "Sophone"—it doesn't completely block access but degrades connections and drops random packets, making network states non-reproducible. This halts logical diagnostics: engineers cannot tell if an outage is a routing issue, server bug, DNS problem, or censorship intervention. This severely degrades the overall engineering capabilities and technical school of the sovereign network space.
