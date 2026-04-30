{
  "inbounds": [
    {
      "listen": "${XRAY_PUBLIC_LISTEN_ADDRESS}",
      "port": ${XRAY_INBOUND_PORT},
      "protocol": "vless",
      "tag": "${XRAY_INBOUND_TAG}",
      "settings": {
        "clients": ${XRAY_CLIENTS_JSON},
        "decryption": "${XRAY_VLESS_DECRYPTION}",
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
          "target": "${XRAY_REALITY_TARGET}",
          "xver": 0,
          "serverNames": ${XRAY_REALITY_SERVER_NAMES_JSON},
          "privateKey": "${XRAY_REALITY_PRIVATE_KEY}",
          "shortIds": ${XRAY_REALITY_SHORT_IDS_JSON}${XRAY_REALITY_MLDSA65_SEED_JSON_ENTRY}
        },
        "sockopt": ${XRAY_SOCKOPT_JSON}
      },
      "sniffing": ${XRAY_SNIFFING_JSON}
    }
  ]
}
