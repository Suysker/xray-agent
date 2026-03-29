{
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${XRAY_DOKODEMO_PORT},
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": ${XRAY_TARGET_PORT},
        "network": "raw",
        "followRedirect": false
      },
      "tag": "dokodemo-door-newPort-${XRAY_DOKODEMO_PORT}"
    }
  ]
}
