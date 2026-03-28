{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_INBOUND_PORT},
      "protocol": "hysteria2",
      "tag": "${XRAY_INBOUND_TAG}",
      "settings": {
        "users": ${XRAY_HYSTERIA_USERS_JSON}
      },
      "streamSettings": {
        "network": "hysteria2",
        "security": "tls",
        "tlsSettings": {
          "alpn": ["h3"],
          "certificates": [
            {
              "certificateFile": "/etc/xray-agent/tls/${XRAY_TLS_DOMAIN}.crt",
              "keyFile": "/etc/xray-agent/tls/${XRAY_TLS_DOMAIN}.key"
            }
          ]
        },
        "hysteria2Settings": ${XRAY_HYSTERIA_SETTINGS_JSON},
        "sockopt": ${XRAY_SOCKOPT_JSON}
      },
      "sniffing": ${XRAY_SNIFFING_JSON}
    }
  ]
}
