# Fix TLS-ALPN-01 SSL Challenge Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct `acme.sh` arguments by removing the redundant `--standalone` flag to allow standalone ALPN challenge.

**Architecture:** Edit `src/selfsteal/acme.sh` where `try_args` is constructed. Rebuild with Makefile. Re-run installer to verify.

**Tech Stack:** Bash

---

### Task 1: Modify acme.sh arguments

**Files:**
- Modify: `src/selfsteal/acme.sh`

- [ ] **Step 1: Edit `src/selfsteal/acme.sh` to remove `--standalone` from `try_args`**

Remove the `--standalone` array element from the `try_args` declaration (around line 351).

Before:
```bash
        local try_args=(
            --issue
            --standalone
            -d "$try_domain"
            --key-file "$try_ssl_dir/private.key"
            --fullchain-file "$try_ssl_dir/fullchain.crt"
            --alpn
            --tlsport "$try_port"
            --httpport 65535
            --server letsencrypt
            --force
            --debug 2
        )
```

After:
```bash
        local try_args=(
            --issue
            -d "$try_domain"
            --key-file "$try_ssl_dir/private.key"
            --fullchain-file "$try_ssl_dir/fullchain.crt"
            --alpn
            --tlsport "$try_port"
            --httpport 65535
            --server letsencrypt
            --force
            --debug 2
        )
```

- [ ] **Step 2: Compile changes**

Run: `make build`
Expected output:
```
Building selfsteal.sh...
```

- [ ] **Step 3: Commit**

```bash
git add src/selfsteal/acme.sh
git commit -m "fix: remove redundant --standalone flag from acme.sh arguments"
```

---

### Task 2: Verify validation flow

**Files:**
- Test: Run installer

- [ ] **Step 1: Start installer in test mode**

Run: `make run`
Input domain `filecloud3.rryowa.com` (pointing to this server).
Input choice `1` for DNS validation.
Proceed with installation.

- [ ] **Step 2: Verify ACME challenge triggers tls-alpn-01**

Check output to ensure it prints:
```
ℹ️  Requesting SSL certificate for filecloud3.rryowa.com...
ℹ️  Issuing certificate via TLS-ALPN on port 8443...
```
And verifies successfully using `tls-alpn-01` challenge without triggering `http-01` or port 80.
