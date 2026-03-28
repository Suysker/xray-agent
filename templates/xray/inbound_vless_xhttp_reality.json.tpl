{
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": ${XRAY_INBOUND_PORT},
      "protocol": "vless",
      "tag": "${XRAY_INBOUND_TAG}",
      "settings": {
        "clients": ${XRAY_CLIENTS_JSON},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "${XRAY_XHTTP_PATH}",
          "mode": "${XRAY_XHTTP_MODE}",
          "headers": ${XRAY_XHTTP_HEADERS_JSON}
        },
        "sockopt": ${XRAY_SOCKOPT_JSON}
      },
      "sniffing": ${XRAY_SNIFFING_JSON}
    }
  ]
}
