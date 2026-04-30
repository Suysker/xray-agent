# 协议说明

xray-agent 只使用 Xray-core。协议组合由安装套餐决定，用户可以在菜单中管理账号、分享链接和部分运行参数。

## TLS 套餐

TLS 套餐默认包含：

- `VLESS-TCP TLS Vision`：公开 TCP/443 入口，用于 TLS 分流和回落。
- `VLESS-WS TLS`：兼容 WebSocket 客户端和 CDN 场景。
- `VMess-WS TLS`：保留旧客户端兼容，不作为主要推荐协议。
- `VLESS-XHTTP TLS`：经 Nginx 反代到本机 Xray inbound。
- `Hysteria2`：Xray-core 内置协议，占用 UDP/443。

TLS 套餐使用用户自己的域名和证书。分享链接优先使用域名，不暴露服务器随机公网 IP。

## Reality 套餐

Reality 套餐默认包含：

- `VLESS-TCP Reality Vision`
- `VLESS-XHTTP Reality`

安装过程中可以选择同时启用 Hysteria2。Hysteria2 仍需要用户自己控制的域名和 TLS 证书，不使用 Reality 目标域名签发证书。

Reality 分享链接会包含 `pbk`、`sid`、`spx`。当当前 Xray-core 支持并且目标站点预检合适时，也会包含 `pqv`。

## Hysteria2

Hysteria2 使用 Xray-core 内置 `hysteria` inbound，不依赖官方 Hysteria YAML 服务。

- 端口模型：UDP/443。
- 证书域名：默认复用当前 Xray TLS 域名。
- 账号认证：跟随脚本里的 UUID 用户体系。
- 分享格式：`hysteria2://<auth>@<domain>:443/?sni=<domain>#<name>`。
- 带宽参数：只写入服务端配置，不写进分享链接。

如果服务器有多个公网 IP 或复杂 UDP 出口路由，需要确认云防火墙和系统默认路由，避免 UDP 回复源地址不一致。

## XHTTP

XHTTP 默认只写必要的 `path`，其他默认行为交给 Xray-core。TLS 场景下，Nginx 负责公开入口和反代；Reality 场景下，XHTTP 与 Reality 入口共同工作。

分享链接会包含 `type=xhttp`、`path`、`host`、`mode` 等字段。当前默认 `mode=auto`。

## 正式版增强能力

脚本会检测当前 Xray-core 是否支持相关命令和字段：

- VLESS Encryption：默认用于无回落的 VLESS WS/XHTTP。
- REALITY ML-DSA-65：合适时生成服务端 `mldsa65Seed`，分享链接输出 `pqv`。
- TLS ECH：支持时生成 `echServerKeys`，分享链接输出 `ech`。
- Hysteria2 QUIC 参数：使用 `finalmask.quicParams`，不写旧字段。

VLESS TCP TLS 和 VLESS TCP Reality 入口承担分流和回落，必须保持 `encryption=none` 才能被 Xray-core 接受。
