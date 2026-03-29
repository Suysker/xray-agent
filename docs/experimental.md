# experimental

- feature flag 文件：`/etc/xray-agent/feature-flags.env`
- `lib/experimental/finalmask.sh`：Finalmask patch
- `lib/experimental/ech.sh`：ECH patch
- `lib/experimental/vless_encryption.sh`：VLESS Encryption patch
- `lib/experimental/browser_dialer.sh`：browser headers 与本地模式提示
- `lib/experimental/tun.sh`：本地 TUN 模式渲染与进程路由 patch
- `lib/experimental/hysteria2_native.sh`：原生 Hysteria2 渲染与安装流

实验功能通过 `/etc/xray-agent/feature-flags.env` 管理：

- `XRAY_AGENT_ENABLE_FINALMASK`
- `XRAY_AGENT_ENABLE_ECH`
- `XRAY_AGENT_ENABLE_VLESS_ENCRYPTION`
- `XRAY_AGENT_BROWSER_HEADERS`
- `XRAY_AGENT_TRUSTED_X_FORWARDED_FOR`
- `XRAY_AGENT_TUN_PROCESS_NAMES`

说明：

- 默认全部关闭或使用保守默认值
- `XRAY_AGENT_BROWSER_HEADERS` 会实际写入 `08_VLESS_XHTTP_inbounds.json` 的 `xhttpSettings.headers`
- `XRAY_AGENT_TRUSTED_X_FORWARDED_FOR` 会实际 patch 到当前 install profile 渲染出的各个 inbound `streamSettings.sockopt`
- 当前脚本只保证 JSON 渲染与 patch 注入流程
- 启用实验功能后，建议用目标机上的 Xray 二进制再次验证运行时兼容性
