# Verified Example: `x-ui-pro` xHTTP Architecture

**Source:** [https://github.com/mozaroc/x-ui-pro](https://github.com/mozaroc/x-ui-pro)
**Significance:** This is a highly popular, real-world verified installation script that demonstrates how to properly route xHTTP traffic through Nginx into Xray via Unix sockets.

## Key Architectural Decisions

1.  **Nginx `grpc_pass`:** They use `grpc_pass` instead of `proxy_pass` to maintain the HTTP/2 stream integrity.
2.  **Unix Sockets over TCP:** They bind Xray to a Unix socket (`/dev/shm/uds2023.sock`) instead of a TCP port (`127.0.0.1:port`) for higher performance and lower latency.
3.  **Mode `packet-up`:** They use `"mode": "packet-up"` in the `xhttpSettings` which is highly recommended for compatibility with various CDNs and reverse proxies.
4.  **Long Timeouts:** Nginx uses a `1h` (1 hour) timeout for `grpc_read_timeout` to prevent stream dropping.

## 1. Nginx Location Block

```nginx
location /secret-xhttp-path {
    grpc_pass grpc://unix:/dev/shm/uds2023.sock;
    grpc_buffer_size         16k;
    grpc_socket_keepalive    on;
    grpc_read_timeout        1h;
    grpc_send_timeout        1h;
    grpc_set_header Connection         "";
    grpc_set_header X-Forwarded-For    $proxy_add_x_forwarded_for;
    grpc_set_header X-Forwarded-Proto  $scheme;
    grpc_set_header X-Forwarded-Port   $server_port;
    grpc_set_header Host               $host;
    grpc_set_header X-Forwarded-Host   $host;
}
```

## 2. Xray (3x-ui) Inbound Configuration

*   **Listen:** `/dev/shm/uds2023.sock,0666`
*   **Port:** `0` (Since it's a socket)
*   **Protocol:** `vless`

**Stream Settings JSON:**
```json
{
  "network": "xhttp",
  "security": "none",
  "xhttpSettings": {
    "path": "/secret-xhttp-path",
    "host": "your-domain.com",
    "headers": {},
    "scMaxBufferedPosts": 30,
    "scMaxEachPostBytes": "1000000",
    "noSSEHeader": false,
    "xPaddingBytes": "100-1000",
    "mode": "packet-up"
  },
  "sockopt": {
    "acceptProxyProtocol": false,
    "tcpFastOpen": true,
    "tcpNoDelay": true,
    "domainStrategy": "UseIP"
  }
}
```
