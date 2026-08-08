{
  "protocol": "freedom",
  "settings": {
    "domainStrategy": "AsIs"
  },
  "streamSettings": {
    "sockopt": {
      "domainStrategy": "UseIP",
      "happyEyeballs": {
        "tryDelayMs": 250,
        "prioritizeIPv6": false,
        "interleave": 1,
        "maxConcurrentTry": 4
      }
    }
  },
  "tag": "IPv4-out"
}
