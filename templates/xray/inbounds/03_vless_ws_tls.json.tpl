{
  "inbounds": [
    {
      "listen": "${XRAY_INTERNAL_LISTEN_ADDRESS}",
      "port": 31297,
      "protocol": "vless",
      "tag": "VLESSWS",
      "settings": {
        "clients": ${XRAY_CLIENTS_JSON},
        "decryption": "${XRAY_VLESS_DECRYPTION}"
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
