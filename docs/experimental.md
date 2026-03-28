# experimental

实验功能通过 `/etc/xray-agent/feature-flags.env` 管理：

- `XRAY_AGENT_ENABLE_FINALMASK`
- `XRAY_AGENT_ENABLE_ECH`
- `XRAY_AGENT_ENABLE_VLESS_ENCRYPTION`
- `XRAY_AGENT_BROWSER_HEADERS`
- `XRAY_AGENT_TRUSTED_X_FORWARDED_FOR`
- `XRAY_AGENT_TUN_PROCESS_NAMES`

说明：

- 默认全部关闭或使用保守默认值
- 当前脚本只保证 JSON 渲染与 patch 注入流程
- 启用实验功能后，建议用目标机上的 Xray 二进制再次验证运行时兼容性
