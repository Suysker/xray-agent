# profiles

核心 profile：

- `server_tls_vision`
- `server_reality_vision`
- `server_tls_ws_vless`
- `server_tls_ws_vmess`
- `server_tls_xhttp`
- `server_reality_xhttp`

扩展 profile：

- `server_hysteria2`
- `local_tun`

兼容说明：

- `server_tls_vision` 安装流仍会联动生成 `server_tls_ws_vless`、`server_tls_ws_vmess` 和 `server_tls_xhttp`
- `server_reality_vision` 安装流仍会联动生成 `server_reality_xhttp`
- 菜单侧保持与 master 脚本的套餐式安装习惯一致

每个 profile 只负责声明：

- 地址来源
- 端口来源
- 传输层
- 安全层
- 路径 / SNI / flow / mode

统一导出器负责将 profile 转成：

- VLESS URL
- Clash Meta 节点
- sing-box outbound
