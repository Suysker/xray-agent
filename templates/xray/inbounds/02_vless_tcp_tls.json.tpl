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
        "security": "tls",
        "tlsSettings": {
          "alpn": ["http/1.1", "h2"],
          "rejectUnknownSni": true,
          "minVersion": "1.2",
          "certificates": [{
            "ocspStapling": 3600,
            "certificateFile": "/etc/xray-agent/tls/${XRAY_TLS_DOMAIN}.crt",
            "keyFile": "/etc/xray-agent/tls/${XRAY_TLS_DOMAIN}.key"
          }]${XRAY_TLS_ECH_SERVER_KEYS_JSON_ENTRY}
        },
        "sockopt": ${XRAY_SOCKOPT_JSON}
      },
      "sniffing": ${XRAY_SNIFFING_JSON}
    }
  ]
}
