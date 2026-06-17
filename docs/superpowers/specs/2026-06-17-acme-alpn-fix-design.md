# Spec: Fix TLS-ALPN-01 SSL Challenge Validation

## Goal
Fix the SSL certificate creation failure during the selfsteal installation. The script currently fails to obtain certificates because it passes both `--standalone` and `--alpn` flags to `acme.sh`, which confuses it into running `http-01` validation over port 80 (resulting in Connection Refused).

## Proposed Changes
We will remove the `--standalone` flag from the `try_args` array in `src/selfsteal/acme.sh`. This will force `acme.sh` to use the intended `tls-alpn-01` challenge.

### src/selfsteal/acme.sh
Modify `_try_issue_cert` (around line 351) to remove `--standalone`:
```diff
         local try_args=(
             --issue
-            --standalone
             -d "$try_domain"
             --key-file "$try_ssl_dir/private.key"
             --fullchain-file "$try_ssl_dir/fullchain.crt"
             --alpn
```

## Verification Plan
1. Compile using `make build`.
2. Run `make run` to trigger the installation script.
3. Verify that `acme.sh` uses `tls-alpn-01` and connects via port 443.
4. Confirm the certificate is successfully obtained.
