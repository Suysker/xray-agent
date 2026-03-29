{
  "inbounds": [
    {
      "tag": "${XRAY_INBOUND_TAG}",
      "protocol": "tun",
      "settings": {
        "mtu": ${XRAY_TUN_MTU},
        "autoRoute": false,
        "stack": "system"
      },
      "sniffing": ${XRAY_SNIFFING_JSON}
    }
  ]
}
