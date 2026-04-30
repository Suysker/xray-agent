{
  "inbounds": [
    {
      "listen": "${XRAY_PUBLIC_LISTEN_ADDRESS}",
      "port": 443,
      "protocol": "hysteria",
      "tag": "Hysteria2",
      "settings": {
        "version": 2,
        "clients": ${XRAY_HYSTERIA2_CLIENTS_JSON}
      },
      "streamSettings": {
        "network": "hysteria",
        "security": "tls",
        "tlsSettings": {
          "alpn": ["h3"],
          "minVersion": "1.3",
          "certificates": [{
            "ocspStapling": 3600,
            "certificateFile": "/etc/xray-agent/tls/${XRAY_TLS_DOMAIN}.crt",
            "keyFile": "/etc/xray-agent/tls/${XRAY_TLS_DOMAIN}.key"
          }]
        },
        "hysteriaSettings": {
          "version": 2,
          "udpIdleTimeout": 60,
          "masquerade": {
            "type": "proxy",
            "url": ${XRAY_HYSTERIA2_MASQUERADE_URL_JSON},
            "rewriteHost": true
          }
        }${XRAY_HYSTERIA2_FINALMASK_SUFFIX}
      },
      "sniffing": ${XRAY_SNIFFING_JSON}
    }
  ]
}
