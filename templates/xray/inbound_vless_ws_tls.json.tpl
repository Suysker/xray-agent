{
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 31297,
      "protocol": "vless",
      "tag": "VLESSWS",
      "settings": {
        "clients": ${XRAY_CLIENTS_JSON},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "acceptProxyProtocol": true,
          "path": "${XRAY_WS_PATH}"
        },
        "sockopt": {
          "tcpFastOpen": true,
          "tcpMptcp": false,
          "tcpNoDelay": false
        }
      },
      "sniffing": ${XRAY_SNIFFING_JSON}
    }
  ]
}
