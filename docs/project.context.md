# Project Context

## Overview

**Repository:** `DigneZzZ/remnawave-scripts`  
**Purpose:** Enterprise-grade Bash scripts for 3x-ui Panel (Docker), NetBird VPN, and Reality traffic masking management.  
**Target Users:** System administrators deploying VPN/proxy infrastructure on Linux servers.

## Technology Stack

| Component | Technology |
|-----------|------------|
| **Language** | Bash (100%) |
| **Container Runtime** | Docker with Compose v2 plugin |
| **Target OS** | Ubuntu 22.04+, Debian 12+ |
| **Database** | SQLite (built-in 3x-ui) |
| **Web Server** | Caddy / Nginx |

## Core Scripts

| Script | Purpose | CLI Pattern |
|--------|---------|-------------|
| `3x-ui-docker.sh` | 3x-ui Panel installer | `3x-ui-docker.sh` |
| `selfsteal.sh` | Reality masking setup | Interactive menu |
| `netbird.sh` | NetBird VPN installer | `netbird.sh <command> [flags]` |

## Architecture Principles

1. **Idempotency** — Scripts safe to run multiple times
2. **Fail-fast** — `set -Eeuo pipefail` in all scripts
3. **No secrets in code** — All credentials via environment
4. **Bilingual** — EN/RU localization support
5. **Docker Compose v2** — Always `docker compose`, never `docker-compose`

## Key Conventions

### Function Naming
- `*_command()` — CLI entry points
- `*_menu()` — Interactive menus
- `check_*()` — Validation
- `print_*()` — Output formatting

### Version Tracking
```bash
# VERSION=5.8.0          # For grep-based detection
SCRIPT_VERSION="5.8.0"   # Runtime variable
```

### Generated Files
- `/opt/3x-ui/docker-compose.yml` — Container orchestration
- `/opt/3x-ui/db/x-ui.db` — 3x-ui panel database

## Dependencies

**Runtime:**
- bash 4.0+
- curl, wget
- jq
- docker (with compose v2 plugin)

**Development:**
- shellcheck (linting)
- git

## Security Constraints

- No credentials in repository
- All secrets via environment variables or `.env` files
- Credential files must have `600` permissions
- Validate all user input before use

## Related Resources

- [Copilot Instructions](../.github/copilot-instructions.md)
- [Bash Standards](../.github/instructions/bash.instructions.md)
- [Project Memory](project.memory.md)
