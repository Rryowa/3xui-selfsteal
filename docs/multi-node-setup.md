# 3x-ui Multi-Node Setup Guide

This guide details how to set up and manage a centralized **Multi-Node** architecture using 3x-ui (v3.x+). This setup allows you to control multiple exit nodes (VPS instances) from a single Master dashboard.

---

## 1. Multi-Node Topology

In 3x-ui, multi-node configuration relies on a **one-way (Star) topology**. A single panel acts as the controller (Master) and orchestrates one or more remote nodes.

```mermaid
graph TD
    subgraph Star Topology (Correct)
        Master["Master Panel (VPS 1)"] -->|"REST API / Xray gRPC"| NodeA["Remote Node A (VPS 2)"]
        Master -->|"REST API / Xray gRPC"| NodeB["Remote Node B (VPS 3)"]
    end
```

> [!CAUTION]
> ### Circular Sync Anti-Pattern (DO NOT DO THIS)
> Exchanging API keys between servers so that Server A is a node of Server B, **and** Server B is a node of Server A, creates a circular sync loop. This will cause:
> - **State Flipping:** Database entries will continuously fight and overwrite client enabled/disabled states.
> - **Traffic Corruption:** Usage metrics will be double-counted or continuously reset.
> - **Deadlocks:** Concurrent database writes will lock SQLite/Postgres and crash the panels.
>
> ```mermaid
> graph LR
>     ServerA["Server A"] -->|"Adds as Node"| ServerB["Server B"]
>     ServerB -->|"Adds as Node (CRASH LOOP)"| ServerA
>  ```

---

## 2. Step-by-Step Configuration

### Step A: Prerequisites & Installation
Install the same version of 3x-ui on all servers (Master and Node).

```bash
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
```

### Step B: Configure the Remote Node VPS
1. Log in to the remote node's panel (e.g., `http://<node-ip>:2053`).
2. Navigate to **Panel Settings** $\rightarrow$ **Security** (or **Authentication**).
3. Find the **API Token** section, generate a key, and copy it.
4. Open the node's firewall to allow the Master to connect:
   ```bash
   # Allow panel REST API
   ufw allow 2053/tcp
   
   # Allow Xray gRPC API (default is 62789)
   ufw allow 62789/tcp
   ```

### Step C: Register the Node on the Master Panel
1. Log in to your Master panel.
2. In the left sidebar, select **Nodes**.
3. Click the **Add Node** button.
4. Fill in the connection form:

| Field | Description | Recommended Value |
| :--- | :--- | :--- |
| **Node Name** | Descriptive name for the remote server. | `Europe-Germany-Exit` |
| **Address** | Public IP or domain name of the remote node. | `185.xxx.xxx.xxx` |
| **Port** | Port of the remote 3x-ui panel. | `2053` |
| **Key / Token** | API Token copied from Step B. | `YOUR_API_TOKEN_HERE` |
| **Xray API Port** | gRPC port for direct Xray control. | `62789` |
| **Sync Mode** | Sync all inbounds or filter by node. | `all` |

5. Click **Save**. The node status badge will turn green (`Online`) once the initial heartbeat syncs.

---

## 3. High-Scale Deployments: PostgreSQL Backend

For large environments (e.g. dozens of nodes or $>10,000$ active clients), the default local SQLite database (`x-ui.db`) is not recommended due to sync lockups. Switch both panels to a centralized **PostgreSQL** backend.

There is no explicit setting or flag in the 3x-ui configuration that defines a server as a "master" or a "node". Both VPS instances run the exact same 3x-ui codebase and panel software.

Instead, the relationship is defined entirely by who initiates the connection:

The "Master" is simply the panel whose web UI you log into, where you go to the Nodes section, and add the remote server's IP and API token.
The "Node" is the passive remote server that receives REST API requests from the Master.
What happens if two nodes exchange API keys and add each other?
If you add Server B as a node inside Server A, and add Server A as a node inside Server B, they will both attempt to act as Master to each other. This creates a circular sync loop (circular dependency) which will cause severe issues:

## State Flipping (Fighting for Control):
If you enable a client on Server A, but Server B's local database has that client disabled, the two servers will continuously overwrite each other's databases on every sync heartbeat (every few seconds), enabling and disabling the client in a loop.

## Traffic Double-Counting & Corruption:
Both panels will pull and push traffic usage statistics to each other, leading to exponential traffic reporting errors or resetting usage statistics back and forth.

## Database/API Deadlocks:
Because both servers are constantly trying to write to each other's databases via the REST API simultaneously, it can trigger database locks, leading to API timeouts and rendering the panels unresponsive.

## Best Practice:
Always maintain a strict one-way (star) topology. Designate one single server as your primary management panel (Master), and only add remote servers to that master panel. Never add the Master back as a node on the remote worker panels.

Configure this by modifying your Docker Compose environment:

```yaml
services:
  3xui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3xui_app
    environment:
      - XUI_DB_TYPE=postgres
      - XUI_DB_DSN=postgres://db_user:db_pass@your-db-host:5432/xui?sslmode=disable
      - XUI_DB_MAX_OPEN_CONNS=50
      - XUI_DB_MAX_IDLE_CONNS=25
```

---

## 4. Troubleshooting Node Sync

If the node status badge displays offline (red) or synchronization fails:

1. **Verify Firewall Access:** Ensure the Master server's IP is allowed to access ports `2053` and `62789` on the node.
2. **Inspect the Master Logs:** Check the system logs to identify sync errors:
   ```bash
   journalctl -u x-ui -n 100 --no-pager | grep -E "node|sync|heartbeat"
   ```
3. **Verify API Token Validity:** Regenerate the API Token on the node and update it on the Master's Node editing form.
