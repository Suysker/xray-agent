# 协议说明

xray-agent 只使用 Xray-core。协议组合由安装套餐决定，用户可以在菜单中管理账号、分享链接和部分运行参数。

## TLS 套餐

TLS 套餐默认包含：

- `VLESS-TCP TLS Vision`：公开 TCP/443 入口，适合常规 TLS 连接。
- `VLESS-WS TLS`：兼容 WebSocket 客户端和 CDN 场景。
- `VMess-WS TLS`：保留旧客户端兼容，不作为主要推荐协议。
- `VLESS-XHTTP TLS`：适合使用 XHTTP 的客户端。
- `Hysteria2`：Xray-core 内置协议，默认 UDP/443，可选端口跳跃。

TLS 套餐使用用户自己的域名和证书。分享链接优先使用域名，不暴露服务器随机公网 IP。

## Reality 套餐

Reality 套餐默认包含：

- `VLESS-TCP Reality Vision`
- `VLESS-XHTTP Reality`

安装过程中可以选择同时启用 Hysteria2。Hysteria2 仍需要用户自己控制的域名和 TLS 证书，不使用 Reality 目标域名签发证书。

Reality 分享链接会包含 `pbk`、`sid`、`spx`。当当前 Xray-core 支持并且目标站点预检合适时，也会包含 `pqv`。

Reality 的抗量子增强依赖目标站点实际 TLS 行为。脚本会检查证书链长度和 X25519MLKEM768 支持情况；证书链不足 3500 时不会启用 `pqv`。

## Hysteria2

Hysteria2 使用 Xray-core 内置能力，不依赖官方 Hysteria YAML 服务。

- 端口模型：默认 UDP/443；启用端口跳跃后，分享链接会增加 `mport=<端口范围>`。
- 证书域名：默认复用当前 Xray TLS 域名。
- 账号认证：跟随脚本里的 UUID 用户体系。
- 分享格式：`hysteria2://<auth>@<domain>:443/?sni=<domain>#<name>`；启用端口跳跃时会增加类似 `mport=20000-50000` 的参数。
- 带宽参数：按服务端视角填写。服务端上行约等于客户端下载，服务端下行约等于客户端上传；填 `0` 或直接回车表示不写 Brutal 参数，不是自动测速。
- 端口跳跃：需要客户端支持 Hysteria2 多端口格式，并且云安全组和本机防火墙都放行对应 UDP 端口。

如果服务器有多个公网 IP 或复杂 UDP 出口路由，需要确认云防火墙和系统默认路由，避免 UDP 回复源地址不一致。

## XHTTP

XHTTP 会使用脚本生成的路径。TLS 场景下通过你的域名访问；Reality 场景下与 Reality 入口配合使用。

分享链接会包含 `type=xhttp`、`path`、`host`、`mode` 等字段。当前默认 `mode=auto`。

XHTTP 是适合配合 CDN 的 HTTP 类传输。当前 Xray-core 支持 VLESS Encryption 时，脚本会让 XHTTP 使用 Vision flow，并在分享链接和 Mihomo 订阅中同步输出 `flow=xtls-rprx-vision`。如果配置测试不通过，脚本会回退为兼容模式，不会输出与服务端不一致的分享参数。

## 正式版增强能力

脚本会检测当前 Xray-core 是否支持相关命令和字段：

- VLESS Encryption：默认用于无回落的 VLESS WS/XHTTP；XHTTP 会同步 Vision flow。
- REALITY ML-DSA-65：目标站点证书链长度达到 3500 以上时才启用，分享链接输出 `pqv`。
- TLS ECH：当前内核和证书条件支持时启用，分享链接输出 `ech`。
- Hysteria2 QUIC 参数：当前内核支持时启用，不支持时跳过。

部分入口需要兼容浏览器回落或协议分流，脚本会自动选择是否启用 VLESS Encryption，避免生成无法启动的配置。

预览版 Xray-core 中的未发布能力不会作为默认生产配置。需要测试预览版时，请从 core 管理菜单显式选择预览版升级。
