{
  "inbounds": [
    {
      "listen": "${XRAY_PUBLIC_LISTEN_ADDRESS}",
      "port": ${XRAY_DOKODEMO_PORT},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "${XRAY_INTERNAL_TARGET_ADDRESS}",
        "port": ${XRAY_TARGET_PORT},
        "network": "raw",
        "followRedirect": false
      },
      "tag": "dokodemo-door-newPort-${XRAY_DOKODEMO_PORT}"
    }
  ]
}
