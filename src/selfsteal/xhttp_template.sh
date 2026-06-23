XHTTP_JSON_TEMPLATE='{
  "up": 0,
  "down": 0,
  "total": 0,
  "remark": "xhttp-inbound",
  "enable": true,
  "expiryTime": 0,
  "listen": "/dev/shm/nginx-xhttp.socket,0666",
  "port": 443,
  "shareAddrStrategy": "custom",
  "shareAddr": "filecloud.rryowa.com",
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "<YOUR_USER_UUID>",
        "email": "user-xhttp",
        "subId": "userrxhttpsubid1",
        "enable": true,
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
      "tproxy": "off",
      "tcpcongestion": "bbr",
      "tcpKeepAliveIdle": 15,
      "tcpMaxSeg": 1440,
      "tcpUserTimeout": 10000
    },
    "xhttpSettings": {
      "enableXmux": true,
      "path": "/api/v1/assets/logo.png",
      "host": "filecloud.rryowa.com",
      "mode": "packet-up",
      "scMaxBufferedPosts": 30,
      "noSSEHeader": true,
      "noGRPCHeader": true,
      "xPaddingBytes": "100-800",
      "xPaddingObfsMode": true,
      "scMaxEachPostBytes": "10000-30000",
      "scMinPostsIntervalMs": "20-30",
      "scStreamUpServerSecs": "45-90",
      "uplinkChunkSize": 4000,
      "sessionIDPlacement": "header",
      "sessionIDKey": "X-Session-Id",
      "xmux": {
        "maxConcurrency": "16",
        "hMaxReusableSecs": "300"
      }
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"],
    "routeOnly": false
  }
}'
