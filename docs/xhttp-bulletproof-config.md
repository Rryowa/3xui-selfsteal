# Xray xHTTP (SplitHTTP) Bulletproof Configuration Guide

xHTTP (internally implemented as `SplitHTTPConfig` in `XTLS/Xray-core`) is a modern transport protocol designed to disguise proxy traffic by breaking it down into discrete HTTP/2 or HTTP/3 chunked requests. Unlike continuous streams (WebSocket/gRPC) which are highly vulnerable to Traffic Analysis and behavioral Deep Packet Inspection (DPI), xHTTP perfectly mimics standard web API behavior.

## Advanced Configuration Parameters

Based on the actual Golang implementation (`infra/conf/transport_internet.go`), here are the core obfuscation and connection properties needed for a bulletproof connection.

### 1. Timing and Burst Obfuscation
DPI systems (like the Russian TSPU's "Siberian" module) look for connection pools that burst too rapidly, or streams that stay open indefinitely.
*   **`scMinPostsIntervalMs` (e.g. `"10-50"`)**: Forces a random millisecond delay between uplink POST requests. Essential for avoiding behavioral triggers associated with rapid-fire bursts.
*   **`scStreamUpServerSecs` (e.g. `"20-60"`)**: Mimics short-lived API connections by forcing the server stream to close and renegotiate every 20 to 60 seconds. Long-lived HTTP streams are a massive red flag.
*   **`scMaxBufferedPosts` (Integer, e.g. `30`)**: Limits the memory buffer for unsent chunks. 

### 2. Payload Padding
To defeat machine-learning payload size analysis, xHTTP randomizes the packet length.
*   **`xPaddingBytes` (e.g. `"100-1000"`)**: Adds between 100 and 1000 bytes of random padding to each request.
*   **`xPaddingObfsMode` (Boolean: `true`)**: Uses advanced algorithmic hashing to make the padding bytes look mathematically like standard encrypted data rather than simple random noise.
*   **`uplinkChunkSize` & `scMaxEachPostBytes`**: Explicitly randomize the slicing of the uplink payload, ensuring every POST request has a different length.

### 3. Header Suppression
*   **`noSSEHeader: true`**: Suppresses Server-Sent Events headers (`text/event-stream`).
*   **`noGRPCHeader: true`**: Prevents gRPC-like HTTP/2 signatures from leaking in the headers.

### 4. Built-in Multiplexing (XMUX)
Outer multiplexing layers (like standard V2Ray Mux) leak recognizable signatures and open parallel connections that can trigger the TSPU 3-connection limit. xHTTP has built-in multiplexing.
*   **`xmux`**: Configuring `maxConcurrency` and `hMaxReusableSecs` allows xHTTP to recycle HTTP connections natively without exposing the outer Mux protocol.

---

## Recommended Client/Server JSON Configuration

If you are deploying the **Cross-Border Hop** behind Nginx (where Nginx terminates TLS on port 443 and proxies `/xhttp` to the Xray backend), use the following configuration in your 3x-ui Panel or Xray client:

```json
{
  "network": "xhttp",
  "security": "none",
  "xhttpSettings": {
    "mode": "auto",
    "path": "/xhttp",
    "noSSEHeader": true,
    "noGRPCHeader": true,
    "xPaddingBytes": "100-1000",
    "xPaddingObfsMode": true,
    "scMaxEachPostBytes": "5000-15000",
    "scMinPostsIntervalMs": "10-50",
    "scMaxBufferedPosts": 30,
    "scStreamUpServerSecs": "20-60",
    "uplinkChunkSize": "1000-5000",
    "xmux": {
      "maxConcurrency": "8-16",
      "hMaxReusableSecs": "30-120"
    }
  }
}
```

> **Warning:** Both the Client and the Server must be configured with matching obfuscation parameters, otherwise the connection will fail to parse the streams.
