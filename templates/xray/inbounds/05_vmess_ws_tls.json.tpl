{
  "inbounds": [
    {
      "listen": "${XRAY_INTERNAL_LISTEN_ADDRESS}",
      "port": 31299,
      "protocol": "vmess",
      "tag": "VMessWS",
      "settings": {
        "clients": ${XRAY_CLIENTS_JSON}
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
