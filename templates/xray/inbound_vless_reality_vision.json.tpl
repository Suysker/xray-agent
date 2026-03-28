{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_INBOUND_PORT},
      "protocol": "vless",
      "tag": "${XRAY_INBOUND_TAG}",
      "settings": {
        "clients": ${XRAY_CLIENTS_JSON},
        "decryption": "none",
        "fallbacks": ${XRAY_FALLBACKS_JSON}
      },
      "streamSettings": {
        "network": "raw",
        "rawSettings": {
          "acceptProxyProtocol": ${XRAY_ACCEPT_PROXY_PROTOCOL}
        },
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${XRAY_REALITY_DEST}",
          "xver": 0,
          "serverNames": ${XRAY_REALITY_SERVER_NAMES_JSON},
          "privateKey": "${XRAY_REALITY_PRIVATE_KEY}",
          "publicKey": "${XRAY_REALITY_PUBLIC_KEY}",
          "shortIds": ${XRAY_REALITY_SHORT_IDS_JSON}
        },
        "sockopt": ${XRAY_SOCKOPT_JSON}
      },
      "sniffing": ${XRAY_SNIFFING_JSON}
    }
  ]
}
