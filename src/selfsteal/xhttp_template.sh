XHTTP_JSON_TEMPLATE='{
  "up": 0,
  "down": 0,
  "total": 0,
  "remark": "xhttp-inbound",
  "enable": true,
  "expiryTime": 0,
  "listen": "/dev/shm/nginx-xhttp.socket,0666",
  "port": 0,
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "<YOUR_USER_UUID>",
        "flow": ""
      }
    ],
    "decryption": "none",
    "fallbacks": []
  },
  "streamSettings": {
    "network": "xhttp",
    "security": "none",
    "sockopt": {
      "tcpFastOpen": true,
      "tcpKeepAliveInterval": 15,
      "tproxy": "off"
    },
    "externalProxy": [
      {
        "forceTls": "tls",
        "dest": "filecloud.rryowa.com",
        "port": 443,
        "remark": "main"
      }
    ],
    "xhttpSettings": {
      "path": "/api/v1/assets/logo.png",
      "host": "filecloud.rryowa.com",
      "mode": "packet-up",
      "scMaxBufferedPosts": 30,
      "extra": {
        "noSSEHeader": true,
        "noGRPCHeader": true,
        "xPaddingBytes": "100-800",
        "xPaddingObfsMode": true,
        "scMaxEachPostBytes": "10000-30000",
        "scMinPostsIntervalMs": "20-30",
        "scStreamUpServerSecs": "45-90",
        "uplinkChunkSize": "2000-8000",
        "sessionPlacement": "header",
        "sessionKey": "X-Session-Id",
        "xmux": {
          "maxConnections": 8,
          "maxConcurrency": 16,
          "hMaxReusableSecs": 300
        }
      }
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"],
    "routeOnly": false
  }
}'
