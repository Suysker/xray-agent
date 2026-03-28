# config-matrix

| profile | transport | security | status |
| --- | --- | --- | --- |
| server_tls_vision | raw/tcp | tls | stable |
| server_reality_vision | raw/tcp | reality | stable |
| server_tls_ws_vless | ws | tls | stable |
| server_tls_ws_vmess | ws | tls | stable |
| server_tls_xhttp | xhttp | tls | stable |
| server_reality_xhttp | xhttp | reality | stable |
| server_hysteria2 | hysteria2 | tls | experimental |
| local_tun | tun | none | experimental |

兼容能力：

- TLS 套餐仍然同时生成 `VLESS TCP + VLESS WS + VMess WS + XHTTP`
- Reality 套餐仍然生成 `VLESS TCP + XHTTP`
- WARP 分流、黑名单、IPv6 分流、sniffing、sockopt 继续保留为运行时管理能力

feature patch：

- Finalmask：默认关闭，可对 REALITY / XHTTP / Hysteria2 注入
- TLS ECH：默认关闭，仅对 TLS 线路注入
- VLESS Encryption：默认关闭，作为实验字段预留
- Browser Headers：默认开启为 `chrome`
- trustedXForwardedFor：默认来源 `127.0.0.1`
