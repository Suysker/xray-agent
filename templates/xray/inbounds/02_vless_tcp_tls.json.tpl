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
        "security": "tls",
        "tlsSettings": {
          "alpn": ["http/1.1", "h2"],
          "rejectUnknownSni": true,
          "minVersion": "1.2",
          "certificates": [{
            "ocspStapling": 3600,
            "certificateFile": "/etc/xray-agent/tls/${XRAY_TLS_DOMAIN}.crt",
            "keyFile": "/etc/xray-agent/tls/${XRAY_TLS_DOMAIN}.key"
          }]
        },
        "sockopt": ${XRAY_SOCKOPT_JSON}
      },
      "sniffing": ${XRAY_SNIFFING_JSON}
    }
  ]
}
