# Design: VLESS + xHTTP behind Nginx & 3x-ui Database Fix

## Goal
Implement a robust VLESS + xHTTP proxy configuration terminated by Nginx, and fix the 3x-ui database initialization bug where the auto-created client is immediately removed by the panel's traffic manager.

## Proposed Changes

### 1. `selfsteal.sh` (`src/selfsteal/main.sh`)
* **New Option**: Add a `--xhttp` flag to parse and initialize `USE_XHTTP=true`.
* **Nginx Configuration Template**:
  * If `USE_XHTTP` is `true`, write `/etc/nginx/conf.d/selfsteal.conf` to listen directly on port 443 with SSL termination.
  * Add a location block `/xhttp` to proxy pass requests to Xray listening locally on `127.0.0.1:$port` (where `$port` defaults to `47443`).
* **Database Seeding Fix (`setup_default_inbound`)**:
  * Check the value of `USE_XHTTP`.
  * If `true`, configure the inbound protocol as `vless`, transport network as `xhttp`, and security as `none` listening on port `47443`.
  * Execute a multi-statement SQLite insert to add the inbound record and capture its ID with `SELECT last_insert_rowid();`.
  * Insert a corresponding client row in the `client_traffics` table for the auto-created user `admin@$domain` and the new inbound ID. This prevents the 3x-ui daemon from evicting the client.
  * Print the client import link: `vless://$uuid@$domain:443?security=tls&encryption=none&sni=$domain&type=xhttp&mode=auto&host=$domain&path=%2Fxhttp#VLESS-Nginx-XHTTP`.
  * If `false` (default Reality mode), keep the VLESS-Reality on port 443 layout but apply the database `client_traffics` fix so that Reality users are also not evicted.

## Verification Plan

### Automated Tests
* Run `make build` to compile the updated `src/dest/selfsteal.sh`.
* Validate script syntax: `bash -n src/dest/selfsteal.sh`.

### Manual Verification
* Run the installer: `./src/dest/selfsteal.sh --force --domain filecloud.rryowa.com --xhttp install`.
* Query the SQLite database to verify:
  * Inbound exists with correct configurations.
  * `client_traffics` table contains the matching client entry.
* Verify Nginx container binds port 443 and terminates TLS.
* Verify Xray container listens internally on port 47443.
* Test VLESS connection with client link to ensure data flows successfully.
